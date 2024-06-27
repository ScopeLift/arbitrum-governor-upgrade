// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {L2ArbitrumGovernorV2Test} from "test/L2ArbitrumGovernorV2.t.sol";
import {SubmitUpgradeProposal} from "script/SubmitUpgradeProposal.s.sol";
import {TimelockControllerUpgradeable} from "openzeppelin-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {GovernorUpgradeable} from "openzeppelin-upgradeable/governance/GovernorUpgradeable.sol";
import {IGovernor} from "openzeppelin-contracts/contracts/governance/IGovernor.sol";
import {BaseGovernorDeployer} from "script/BaseGovernorDeployer.sol";
import {DeployCoreGovernor} from "script/DeployCoreGovernor.s.sol";
import {DeployTreasuryGovernor} from "script/DeployTreasuryGovernor.s.sol";
// import {AccessControlUpgradeable} from "openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import {TimelockRolesUpgrader} from "src/gov-action-contracts/TimelockRolesUpgrader.sol";

abstract contract SubmitUpgradeProposalTest is L2ArbitrumGovernorV2Test {
  SubmitUpgradeProposal submitUpgradeProposal;
  GovernorUpgradeable currentGovernor;
  TimelockControllerUpgradeable currentTimelock;

  enum VoteType {
    Against,
    For,
    Abstain
  }

  function _currentGovernorAddress() internal pure virtual returns (address);
  function _currentTimelockAddress() internal pure virtual returns (address);

  function setUp() public override {
    super.setUp();
    submitUpgradeProposal = new SubmitUpgradeProposal();
    currentGovernor = GovernorUpgradeable(payable(_currentGovernorAddress()));
    currentTimelock = TimelockControllerUpgradeable(payable(_currentTimelockAddress()));
  }

  function test_SuccessfullyExecuteUpgradeProposal() public {
    // Propose
    (
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldatas,
      string memory _description,
      uint256 _proposalId
    ) = submitUpgradeProposal.proposeUpgradeAndReturnCalldata(
      _currentTimelockAddress(), _currentGovernorAddress(), address(governor)
    );
    assertEq(uint256(currentGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Pending));
    vm.roll(vm.getBlockNumber() + currentGovernor.votingDelay() + 1);
    assertEq(uint256(currentGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Active));

    // Vote
    for (uint256 i; i < _majorDelegates.length; i++) {
      vm.prank(_majorDelegates[i]);
      currentGovernor.castVote(_proposalId, uint8(VoteType.For));
    }

    // Success
    vm.roll(vm.getBlockNumber() + governor.votingPeriod() + 1);
    assertEq(uint256(currentGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Succeeded));

    // Queue
    currentGovernor.queue(_targets, _values, _calldatas, keccak256(bytes(_description)));
    assertEq(uint256(currentGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Queued));
    vm.warp(vm.getBlockTimestamp() + currentTimelock.getMinDelay() + 1);

    // Execute
    // TODO: Update _calldatas to work with sendTxToL1.
    currentGovernor.execute(_targets, _values, _calldatas, keccak256(bytes(_description)));
    assertEq(uint256(currentGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Executed));
  }

  function test_ExecuteUpgradeUsingUpgradeExecutor() public {
    TimelockRolesUpgrader timelockRolesUpgrader = new TimelockRolesUpgrader(
      ARBITRUM_CORE_GOVERNOR_TIMELOCK,
      ARBITRUM_CORE_GOVERNOR,
      address(governor),
      ARBITRUM_TREASURY_GOVERNOR_TIMELOCK,
      ARBITRUM_TREASURY_GOVERNOR,
      address(governor)
    );

    address target = address(timelockRolesUpgrader);
    bytes memory data = abi.encodeWithSelector(timelockRolesUpgrader.perform.selector);

    vm.prank(SECURITY_COUNCIL_9);
    IUpgradeExecutor(UPGRADE_EXECUTOR).execute(target, data);

    assertEq(currentTimelock.hasRole(keccak256("PROPOSER_ROLE"), address(governor)), true);
    assertEq(currentTimelock.hasRole(keccak256("CANCELLER_ROLE"), address(governor)), true);
    assertEq(currentTimelock.hasRole(keccak256("PROPOSER_ROLE"), _currentGovernorAddress()), false);
    assertEq(currentTimelock.hasRole(keccak256("CANCELLER_ROLE"), _currentGovernorAddress()), false);
  }

  function createProposal(
    address l1TimelockAddr,
    string memory proposalDescription,
    address oneOffUpgradeAddr,
    address arbOneInboxAddr,
    address upgradeExecutorAddr
  ) public returns (bytes memory) {
    address retryableTicketMagic = RETRYABLE_TICKET_MAGIC;
    // uint256 minDelay = IL1Timelock(l1TimelockAddr).getMinDelay();
    uint256 minDelay = 259_200; // TODO: Update to use getMinDelay() when it's available

    // the data to call the upgrade executor with
    // it tells the upgrade executor how to call the upgrade contract, and what calldata to provide to it
    bytes memory upgradeExecutorCallData = abi.encodeWithSelector(
      IUpgradeExecutor.execute.selector,
      oneOffUpgradeAddr,
      abi.encodeWithSelector(TimelockRolesUpgrader.perform.selector)
    );

    // the data provided to call the l1 timelock with
    // specifies how to create a retryable ticket, which will then be used to call the upgrade executor with the
    // data created from the step above
    bytes memory l1TimelockData = abi.encodeWithSelector(
      IL1Timelock.schedule.selector,
      retryableTicketMagic, // tells the l1 timelock that we want to make a retryable, instead of an l1 upgrade
      0, // ignored for l2 upgrades
      abi.encode( // these are the retryable data params
        arbOneInboxAddr, // the inbox we want to use, should be arb one or nova inbox
        upgradeExecutorAddr, // the upgrade executor on the l2 network
        0, // no value in this upgrade
        0, // max gas - will be filled in when the retryable is actually executed
        0, // max fee per gas - will be filled in when the retryable is actually executed
        upgradeExecutorCallData // call data created in the previous step
      ),
      bytes32(0), // no predecessor
      keccak256(abi.encodePacked(proposalDescription)), // prop description
      minDelay // delay for this proposal
    );

    // the data provided to the L2 Arbitrum Governor in the propose() method
    // the target will be the ArbSys address on Arb One
    bytes memory proposal = abi.encodeWithSelector(
      IArbSys.sendTxToL1.selector, // the execution of the proposal will create an L2->L1 cross chain message
      l1TimelockAddr, // the target of the cross chain message is the L1 timelock
      l1TimelockData // call the l1 timelock with the data created in the previous step
    );
    return proposal;
  }

  function test_formulateProposalCalldata() public {
    TimelockRolesUpgrader timelockRolesUpgrader = new TimelockRolesUpgrader(
      ARBITRUM_CORE_GOVERNOR_TIMELOCK,
      ARBITRUM_CORE_GOVERNOR,
      address(governor),
      ARBITRUM_TREASURY_GOVERNOR_TIMELOCK,
      ARBITRUM_TREASURY_GOVERNOR,
      address(governor)
    );

    bytes memory proposalCalldata = createProposal(
      L1_TIMELOCK,
      "Upgrade Governor Timelock Roles",
      address(timelockRolesUpgrader),
      ARB_ONE_DELAYED_INBOX,
      UPGRADE_EXECUTOR
    );
    console2.log("proposalCalldata is:");
    console2.logBytes(proposalCalldata);
  }
}

interface IUpgradeExecutor {
  function execute(address to, bytes calldata data) external payable;
}

interface IL1Timelock {
  // function RETRYABLE_TICKET_MAGIC() external returns (address) {
  //   return RETRYABLE_TICKET_MAGIC;
  // }

  function schedule(
    address target,
    uint256 value,
    bytes calldata data,
    bytes32 predecessor,
    bytes32 salt,
    uint256 delay
  ) external;
  function getMinDelay() external view returns (uint256);
}

interface IArbSys {
  function sendTxToL1(address destination, bytes calldata data) external payable returns (uint256);
}

interface IL2ArbitrumGovernor {
  function propose(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    string memory description
  ) external returns (uint256);
}

contract CoreGovernorUpgrade is SubmitUpgradeProposalTest {
  function _createGovernorDeployer() internal override returns (BaseGovernorDeployer) {
    return new DeployCoreGovernor();
  }

  function _currentGovernorAddress() internal pure override returns (address) {
    return ARBITRUM_CORE_GOVERNOR;
  }

  function _currentTimelockAddress() internal pure override returns (address) {
    return ARBITRUM_CORE_GOVERNOR_TIMELOCK;
  }
}

contract TreasuryGovernorUpgrade is SubmitUpgradeProposalTest {
  function _createGovernorDeployer() internal override returns (BaseGovernorDeployer) {
    return new DeployTreasuryGovernor();
  }

  function _currentGovernorAddress() internal pure override returns (address) {
    return ARBITRUM_TREASURY_GOVERNOR;
  }

  function _currentTimelockAddress() internal pure override returns (address) {
    return ARBITRUM_TREASURY_GOVERNOR_TIMELOCK;
  }
}
