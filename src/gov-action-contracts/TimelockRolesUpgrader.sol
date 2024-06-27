// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

import {TimelockControllerUpgradeable} from "openzeppelin-upgradeable/governance/TimelockControllerUpgradeable.sol";

contract TimelockRolesUpgrader {
  address public immutable CORE_TIMELOCK;
  address public immutable CURRENT_CORE_GOVERNOR;
  address public immutable NEW_CORE_GOVERNOR;
  address public immutable TREASURY_TIMELOCK;
  address public immutable CURRENT_TREASURY_GOVERNOR;
  address public immutable NEW_TREASURY_GOVERNOR;

  constructor(
    address _coreTimelock,
    address _currentCoreGovernor,
    address _newCoreGovernor,
    address _treasuryTimelock,
    address _currentTreasuryGovernor,
    address _newTreasuryGovernor
  ) {
    if (
      _coreTimelock == address(0) || _currentCoreGovernor == address(0) || _newCoreGovernor == address(0)
        || _treasuryTimelock == address(0) || _currentTreasuryGovernor == address(0) || _newTreasuryGovernor == address(0)
    ) {
      revert("TimelockRolesUpgrader: zero address");
    }
    CORE_TIMELOCK = _coreTimelock;
    TREASURY_TIMELOCK = _treasuryTimelock;
    CURRENT_CORE_GOVERNOR = _currentCoreGovernor;
    NEW_CORE_GOVERNOR = _newCoreGovernor;
    CURRENT_TREASURY_GOVERNOR = _currentTreasuryGovernor;
    NEW_TREASURY_GOVERNOR = _newTreasuryGovernor;
  }

  function perform() external {
    _swapGovernorsOnTimelock(CORE_TIMELOCK, CURRENT_CORE_GOVERNOR, NEW_CORE_GOVERNOR);
    _swapGovernorsOnTimelock(TREASURY_TIMELOCK, CURRENT_TREASURY_GOVERNOR, NEW_TREASURY_GOVERNOR);
  }

  function _swapGovernorsOnTimelock(address _timelock, address _oldGovernor, address _newGovernor) private {
    _grantRole(_timelock, _newGovernor, keccak256("PROPOSER_ROLE"));
    _grantRole(_timelock, _newGovernor, keccak256("CANCELLER_ROLE"));
    _revokeRole(_timelock, _oldGovernor, keccak256("PROPOSER_ROLE"));
    _revokeRole(_timelock, _oldGovernor, keccak256("CANCELLER_ROLE"));

    // Check roles were changed
    TimelockControllerUpgradeable timelock = TimelockControllerUpgradeable(payable(_timelock));
    require(timelock.hasRole(keccak256("PROPOSER_ROLE"), _newGovernor), "Adder role not granted");
    require(timelock.hasRole(keccak256("CANCELLER_ROLE"), _newGovernor), "Replacer role not granted");
    require(!timelock.hasRole(keccak256("PROPOSER_ROLE"), _oldGovernor), "Rotator role not granted");
    require(!timelock.hasRole(keccak256("CANCELLER_ROLE"), _oldGovernor), "Remover role not granted");
  }

  function _grantRole(address _timelock, address _governor, bytes32 _role) private {
    TimelockControllerUpgradeable(payable(_timelock)).grantRole(_role, address(_governor));
  }

  function _revokeRole(address _timelock, address _governor, bytes32 _role) private {
    TimelockControllerUpgradeable(payable(_timelock)).revokeRole(_role, address(_governor));
  }
}
