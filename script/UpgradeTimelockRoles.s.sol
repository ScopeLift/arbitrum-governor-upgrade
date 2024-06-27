// SPDX-License-Identifier: AGPL-3.0-only
// slither-disable-start reentrancy-benign

pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {SharedGovernorConstants} from "script/SharedGovernorConstants.sol";
import {GovernorUpgradeable} from "openzeppelin-upgradeable/governance/GovernorUpgradeable.sol";
import {AccessControlUpgradeable} from "openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";

contract UpgradeTimelockRoles is Script, SharedGovernorConstants {
  address PROPOSER = 0x1B686eE8E31c5959D9F5BBd8122a58682788eeaD; // L2Beat

  function proposeUpgrade(address _timelock, address _currentGovernor, address _newGovernor)
    public
    returns (uint256 _proposalId)
  {
    address[] memory targets = new address[](1);
    uint256[] memory values = new uint256[](1);
    bytes[] memory calldatas = new bytes[](1);
    string memory description = "Upgrade Proposer Roles";

    // Grant new Governor Proposer role
    targets[0] = address(_timelock);
    calldatas[0] = abi.encodeWithSelector(
      AccessControlUpgradeable.grantRole.selector, keccak256("PROPOSER_ROLE"), address(_newGovernor)
    );

    // Grant new Governor Canceller role
    targets[1] = address(_timelock);
    calldatas[1] = abi.encodeWithSelector(
      AccessControlUpgradeable.grantRole.selector, keccak256("CANCELLER_ROLE"), address(_newGovernor)
    );

    // Revoke current Governor's Proposer role
    targets[2] = address(_timelock);
    calldatas[2] = abi.encodeWithSelector(
      AccessControlUpgradeable.revokeRole.selector, keccak256("PROPOSER_ROLE"), address(_currentGovernor)
    );

    // Revoke current Governor's Canceller role
    targets[3] = address(_timelock);
    calldatas[3] = abi.encodeWithSelector(
      AccessControlUpgradeable.revokeRole.selector, keccak256("CANCELLER_ROLE"), address(_currentGovernor)
    );

    vm.startBroadcast(PROPOSER);
    _proposalId = GovernorUpgradeable(payable(_currentGovernor)).propose(targets, values, calldatas, description);
    vm.stopBroadcast();
  }

  function proposeUpgradeAndReturnCalldata(address _timelock, address _currentGovernor, address _newGovernor)
    public
    returns (
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description,
      uint256 _proposalId
    )
  {
    targets = new address[](4);
    values = new uint256[](4);
    calldatas = new bytes[](4);
    description = "Upgrade Proposer Roles";

    // Grant new Governor Proposer role
    targets[0] = address(_timelock);
    calldatas[0] = abi.encodeWithSelector(
      AccessControlUpgradeable.grantRole.selector, keccak256("PROPOSER_ROLE"), address(_newGovernor)
    );

    // Grant new Governor Canceller role
    targets[1] = address(_timelock);
    calldatas[1] = abi.encodeWithSelector(
      AccessControlUpgradeable.grantRole.selector, keccak256("CANCELLER_ROLE"), address(_newGovernor)
    );

    // Revoke current Governor's Proposer role
    targets[2] = address(_timelock);
    calldatas[2] = abi.encodeWithSelector(
      AccessControlUpgradeable.revokeRole.selector, keccak256("PROPOSER_ROLE"), address(_currentGovernor)
    );

    // Revoke current Governor's Canceller role
    targets[3] = address(_timelock);
    calldatas[3] = abi.encodeWithSelector(
      AccessControlUpgradeable.revokeRole.selector, keccak256("CANCELLER_ROLE"), address(_currentGovernor)
    );

    vm.startBroadcast(PROPOSER);
    _proposalId = GovernorUpgradeable(payable(_currentGovernor)).propose(targets, values, calldatas, description);
    vm.stopBroadcast();
  }
}
