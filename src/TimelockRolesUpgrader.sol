// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

import {TimelockControllerUpgradeable} from "openzeppelin-upgradeable/governance/TimelockControllerUpgradeable.sol";

contract TimelockRolesUpgrader {
  function upgradeRoles(address _timelock, address _currentGovernor, address _newGovernor) public {
    // Grant new Governor Proposer role
    grantRole(_timelock, _newGovernor, keccak256("PROPOSER_ROLE"));

    // Grant new Governor Canceller role
    grantRole(_timelock, _newGovernor, keccak256("CANCELLER_ROLE"));

    // Revoke current Governor's Proposer role
    revokeRole(_timelock, _currentGovernor, keccak256("PROPOSER_ROLE"));

    // Revoke current Governor's Canceller role
    revokeRole(_timelock, _currentGovernor, keccak256("CANCELLER_ROLE"));
  }

  function grantRole(address _timelock, address _governor, bytes32 _role) public {
    TimelockControllerUpgradeable(payable(_timelock)).grantRole(_role, address(_governor));
  }

  function revokeRole(address _timelock, address _governor, bytes32 _role) public {
    TimelockControllerUpgradeable(payable(_timelock)).revokeRole(_role, address(_governor));
  }
}
