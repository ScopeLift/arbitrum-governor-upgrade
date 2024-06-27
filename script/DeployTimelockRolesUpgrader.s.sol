// SPDX-License-Identifier: AGPL-3.0-only
// slither-disable-start reentrancy-benign

pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {TimelockRolesUpgrader} from "src/TimelockRolesUpgrader.sol";

// Basic shared infrastructure for all deploy scripts
contract BaseDeployer is Script {
  uint256 deployerPrivateKey;

  function setUp() public {
    deployerPrivateKey =
      vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
  }

  function run() public returns (TimelockRolesUpgrader timelockRolesUpgrader) {
    vm.startBroadcast(deployerPrivateKey);
    timelockRolesUpgrader = new TimelockRolesUpgrader();
    vm.stopBroadcast();
  }
}
