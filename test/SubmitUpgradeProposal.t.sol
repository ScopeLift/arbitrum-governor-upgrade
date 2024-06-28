// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {L2ArbitrumGovernorV2Test} from "test/L2ArbitrumGovernorV2.t.sol";
import {SubmitUpgradeProposalScript} from "script/SubmitUpgradeProposalScript.s.sol";
import {TimelockControllerUpgradeable} from "openzeppelin-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {GovernorUpgradeable} from "openzeppelin-upgradeable/governance/GovernorUpgradeable.sol";
import {IGovernor} from "openzeppelin-contracts/contracts/governance/IGovernor.sol";
import {BaseGovernorDeployer} from "script/BaseGovernorDeployer.sol";
import {DeployCoreGovernor} from "script/DeployCoreGovernor.s.sol";
import {DeployTreasuryGovernor} from "script/DeployTreasuryGovernor.s.sol";
import {DeployImplementation} from "script/DeployImplementation.s.sol";
import {TimelockRolesUpgrader} from "src/gov-action-contracts/TimelockRolesUpgrader.sol";
import {L2ArbitrumGovernorV2} from "src/L2ArbitrumGovernorV2.sol";
import {SharedGovernorConstants} from "script/SharedGovernorConstants.sol";
import {SetupNewGovernors} from "test/helpers/SetupNewGovernors.sol";

contract SubmitUpgradeProposalTest is SetupNewGovernors {
  function test_SuccessfullyExecuteUpgradeProposal() public {
    // Propose
    (
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldatas,
      string memory _description,
      uint256 _proposalId
    ) = submitUpgradeProposalScript.run(
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
