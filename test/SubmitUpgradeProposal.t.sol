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
import {AccessControlUpgradeable} from "openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import {TimelockRolesUpgrader} from "src/TimelockRolesUpgrader.sol";

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
    // currentGovernor.execute(_targets, _values, _calldatas, keccak256(bytes(_description)));
    // assertEq(uint256(currentGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Executed));
  }

  function test_ExecuteUpgradeUsingUpgradeExecutor() public {
    TimelockRolesUpgrader timelockRolesUpgrader = new TimelockRolesUpgrader();

    address target = address(timelockRolesUpgrader);
    bytes memory data = abi.encodeWithSelector(
      timelockRolesUpgrader.upgradeRoles.selector,
      _currentTimelockAddress(),
      _currentGovernorAddress(),
      address(governor)
    );

    vm.prank(SECURITY_COUNCIL_9);
    IUpgradeExecutor(UPGRADE_EXECUTOR).execute(target, data);

    assertEq(currentTimelock.hasRole(keccak256("PROPOSER_ROLE"), address(governor)), true);
    assertEq(currentTimelock.hasRole(keccak256("CANCELLER_ROLE"), address(governor)), true);
    assertEq(currentTimelock.hasRole(keccak256("PROPOSER_ROLE"), _currentGovernorAddress()), false);
    assertEq(currentTimelock.hasRole(keccak256("CANCELLER_ROLE"), _currentGovernorAddress()), false);
  }
}

interface IUpgradeExecutor {
  function execute(address upgrade, bytes memory upgradeCalldata) external payable;
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
