// SPDX-License-Identifier: AGPL-3.0-only
// slither-disable-start reentrancy-benign

pragma solidity 0.8.26;

import {BaseDeployer} from "script/BaseDeployer.sol";
import {TimelockRolesUpgrader} from "src/gov-action-contracts/TimelockRolesUpgrader.sol";
import {SharedGovernorConstants} from "script/SharedGovernorConstants.sol";

contract DeployTimelockRolesUpgrader is BaseDeployer, SharedGovernorConstants {
  function run(address _newCoreGovernor, address _newTreasuryGovernor)
    public
    returns (TimelockRolesUpgrader timelockRolesUpgrader)
  {
    vm.startBroadcast(deployerPrivateKey);
    timelockRolesUpgrader = new TimelockRolesUpgrader(
      ARBITRUM_CORE_GOVERNOR_TIMELOCK,
      ARBITRUM_CORE_GOVERNOR,
      _newCoreGovernor,
      ARBITRUM_TREASURY_GOVERNOR_TIMELOCK,
      ARBITRUM_TREASURY_GOVERNOR,
      _newTreasuryGovernor
    );
    vm.stopBroadcast();
  }
}
