// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {L2ArbitrumGovernorV2Test} from "test/L2ArbitrumGovernorV2.t.sol";
import {UpgradeTimelockRoles} from "script/UpgradeTimelockRoles.s.sol";
import {TimelockControllerUpgradeable} from "openzeppelin-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {GovernorUpgradeable} from "openzeppelin-upgradeable/governance/GovernorUpgradeable.sol";
import {IGovernor} from "openzeppelin-contracts/contracts/governance/IGovernor.sol";
import {BaseGovernorDeployer} from "script/BaseGovernorDeployer.sol";
import {DeployCoreGovernor} from "script/DeployCoreGovernor.s.sol";
import {DeployTreasuryGovernor} from "script/DeployTreasuryGovernor.s.sol";
import {AccessControlUpgradeable} from "openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";

abstract contract UpgradeTimelockRolesTest is L2ArbitrumGovernorV2Test {
  UpgradeTimelockRoles upgradeTimelockRoles;
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
    upgradeTimelockRoles = new UpgradeTimelockRoles();
    currentGovernor = GovernorUpgradeable(payable(_currentGovernorAddress()));
    currentTimelock = TimelockControllerUpgradeable(payable(_currentTimelockAddress()));
  }

  function test_SuccessfullyExecuteUpgradeProposal() public {
    (
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldatas,
      string memory _description,
      uint256 _proposalId
    ) = upgradeTimelockRoles.proposeUpgradeAndReturnCalldata(
      _currentTimelockAddress(), _currentGovernorAddress(), address(governor)
    );
    assertEq(uint256(currentGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Pending));
    vm.roll(vm.getBlockNumber() + currentGovernor.votingDelay() + 1);
    assertEq(uint256(currentGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Active));

    for (uint256 i; i < _majorDelegates.length; i++) {
      vm.prank(_majorDelegates[i]);
      currentGovernor.castVote(_proposalId, uint8(VoteType.For));
    }

    vm.roll(vm.getBlockNumber() + governor.votingPeriod() + 1);
    assertEq(uint256(currentGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Succeeded));

    currentGovernor.queue(_targets, _values, _calldatas, keccak256(bytes(_description)));
    assertEq(uint256(currentGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Queued));
    vm.warp(vm.getBlockTimestamp() + currentTimelock.getMinDelay() + 1);

    vm.assertEq(
      currentTimelock.hasRole(keccak256("TIMELOCK_ADMIN_ROLE"), address(0xCF57572261c7c2BCF21ffD220ea7d1a27D40A827)),
      true
    );

    currentGovernor.execute(_targets, _values, _calldatas, keccak256(bytes(_description)));
    assertEq(uint256(currentGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Executed));
  }

  function test_ExecuteUsingUpgradeExecutor() public {
    address upgradeExecutor = 0xCF57572261c7c2BCF21ffD220ea7d1a27D40A827; // Executor
    MyContract myContract = new MyContract();
    address target = address(myContract);
    bytes memory data = abi.encodeWithSelector(myContract.upgradeRoles.selector, address(governor));

    // address target = address(0x34d45e99f7D8c45ed05B5cA72D54bbD1fb3F98f0);
    // bytes memory data = abi.encodeWithSelector(TimelockControllerUpgradeable.grantRole.selector, address(governor));
    vm.prank(0x423552c0F05baCCac5Bfa91C6dCF1dc53a0A1641); // Security Council
    IUpgradeExecutor(upgradeExecutor).execute(target, data);
  }
}

interface IUpgradeExecutor {
  function execute(address upgrade, bytes memory upgradeCalldata) external payable;
}

contract MyContract {
  function upgradeRoles(address _governor) public {
    TimelockControllerUpgradeable(payable(0x34d45e99f7D8c45ed05B5cA72D54bbD1fb3F98f0)).grantRole(
      keccak256("CANCELLER_ROLE"), address(_governor)
    );
  }
}

contract CoreGovernorUpgrade is UpgradeTimelockRolesTest {
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

contract TreasuryGovernorUpgrade is UpgradeTimelockRolesTest {
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
