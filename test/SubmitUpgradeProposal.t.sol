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
import {TimelockRolesUpgrader} from "src/gov-action-contracts/TimelockRolesUpgrader.sol";
import {L2ArbitrumGovernorV2} from "src/L2ArbitrumGovernorV2.sol";
import {SharedGovernorConstants} from "script/SharedGovernorConstants.sol";
import {DeployImplementation} from "script/DeployImplementation.s.sol";

contract SubmitUpgradeProposalTest is SharedGovernorConstants, Test {
  uint256 constant FORK_BLOCK = 220_819_857; // Arbitrary recent block
  /// @dev Proxy admin contract deployed in construction of TransparentUpgradeableProxy -- getter is internal, so we
  /// hardcode the address below
  address constant PROXY_ADMIN_CONTRACT = 0x740f24A3cbF1fbA1226C6018511F96d1055ce961; // Proxy Admin Contract Address

  SubmitUpgradeProposal submitUpgradeProposal;
  BaseGovernorDeployer proxyCoreGovernorDeployer;
  BaseGovernorDeployer proxyTreasuryGovernorDeployer;

  // Current governors and timelocks
  GovernorUpgradeable currentCoreGovernor;
  TimelockControllerUpgradeable currentCoreTimelock;
  GovernorUpgradeable currentTreasuryGovernor;
  TimelockControllerUpgradeable currentTreasuryTimelock;

  // New governors
  L2ArbitrumGovernorV2 newCoreGovernor;
  L2ArbitrumGovernorV2 newTreasuryGovernor;

  enum VoteType {
    Against,
    For,
    Abstain
  }

  function setUp() public {
    vm.createSelectFork(
      vm.envOr("ARBITRUM_ONE_RPC_URL", string("Please set ARBITRUM_ONE_RPC_URL in your .env file")), FORK_BLOCK
    );

    submitUpgradeProposal = new SubmitUpgradeProposal();

    // Deploy Governor implementation contract
    DeployImplementation _implementationDeployer = new DeployImplementation();
    _implementationDeployer.setUp();
    address _implementation = address(_implementationDeployer.run());

    proxyCoreGovernorDeployer = new DeployCoreGovernor();
    proxyTreasuryGovernorDeployer = new DeployTreasuryGovernor();
    proxyCoreGovernorDeployer.setUp();
    proxyTreasuryGovernorDeployer.setUp();

    // Deploy Governor proxy contracts
    newCoreGovernor = proxyCoreGovernorDeployer.run(_implementation);
    newTreasuryGovernor = proxyTreasuryGovernorDeployer.run(_implementation);

    // Current governors and timelocks
    currentCoreGovernor = GovernorUpgradeable(payable(ARBITRUM_CORE_GOVERNOR));
    currentCoreTimelock = TimelockControllerUpgradeable(payable(ARBITRUM_CORE_GOVERNOR_TIMELOCK));
    currentTreasuryGovernor = GovernorUpgradeable(payable(ARBITRUM_TREASURY_GOVERNOR));
    currentTreasuryTimelock = TimelockControllerUpgradeable(payable(ARBITRUM_TREASURY_GOVERNOR_TIMELOCK));

    // Deploy a mock ArbSys contract at ARB_SYS
    MockArbSys mockArbSys = new MockArbSys();
    bytes memory code = address(mockArbSys).code;
    vm.etch(ARB_SYS, code);
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
      ARBITRUM_CORE_GOVERNOR //maybe also the treasury governor to use in createProposal
    );
    assertEq(uint256(currentCoreGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Pending));
    vm.roll(vm.getBlockNumber() + currentCoreGovernor.votingDelay() + 1);
    assertEq(uint256(currentCoreGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Active));

    // Vote
    for (uint256 i; i < _majorDelegates.length; i++) {
      vm.prank(_majorDelegates[i]);
      currentCoreGovernor.castVote(_proposalId, uint8(VoteType.For));
    }

    // Success
    vm.roll(vm.getBlockNumber() + currentCoreGovernor.votingPeriod() + 1);
    assertEq(uint256(currentCoreGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Succeeded));

    // Queue
    currentCoreGovernor.queue(_targets, _values, _calldatas, keccak256(bytes(_description)));
    assertEq(uint256(currentCoreGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Queued));
    vm.warp(vm.getBlockTimestamp() + currentCoreTimelock.getMinDelay() + 1);

    // Execute
    currentCoreGovernor.execute(_targets, _values, _calldatas, keccak256(bytes(_description)));
    assertEq(uint256(currentCoreGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Executed));
  }

  function test_ExecuteUpgradeUsingUpgradeExecutor() public {
    TimelockRolesUpgrader timelockRolesUpgrader = new TimelockRolesUpgrader(
      ARBITRUM_CORE_GOVERNOR_TIMELOCK,
      ARBITRUM_CORE_GOVERNOR,
      address(newCoreGovernor),
      ARBITRUM_TREASURY_GOVERNOR_TIMELOCK,
      ARBITRUM_TREASURY_GOVERNOR,
      address(newTreasuryGovernor)
    );

    address target = address(timelockRolesUpgrader);
    bytes memory data = abi.encodeWithSelector(timelockRolesUpgrader.perform.selector);

    vm.prank(SECURITY_COUNCIL_9);
    IUpgradeExecutor(UPGRADE_EXECUTOR).execute(target, data);

    assertEq(currentCoreTimelock.hasRole(keccak256("PROPOSER_ROLE"), address(newCoreGovernor)), true);
    assertEq(currentCoreTimelock.hasRole(keccak256("CANCELLER_ROLE"), address(newCoreGovernor)), true);
    assertEq(currentCoreTimelock.hasRole(keccak256("PROPOSER_ROLE"), ARBITRUM_CORE_GOVERNOR), false);
    assertEq(currentCoreTimelock.hasRole(keccak256("CANCELLER_ROLE"), ARBITRUM_CORE_GOVERNOR), false);

    assertEq(currentTreasuryTimelock.hasRole(keccak256("PROPOSER_ROLE"), address(newTreasuryGovernor)), true);
    assertEq(currentTreasuryTimelock.hasRole(keccak256("CANCELLER_ROLE"), address(newTreasuryGovernor)), true);
    assertEq(currentTreasuryTimelock.hasRole(keccak256("PROPOSER_ROLE"), ARBITRUM_TREASURY_GOVERNOR), false);
    assertEq(currentTreasuryTimelock.hasRole(keccak256("CANCELLER_ROLE"), ARBITRUM_TREASURY_GOVERNOR), false);
  }
}

interface IUpgradeExecutor {
  function execute(address to, bytes calldata data) external payable;
}

contract MockArbSys {
  function sendTxToL1(address _l1Target, bytes calldata _data) external {}
}
