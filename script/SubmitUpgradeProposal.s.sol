// SPDX-License-Identifier: AGPL-3.0-only
// slither-disable-start reentrancy-benign

pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {SharedGovernorConstants} from "script/SharedGovernorConstants.sol";
import {GovernorUpgradeable} from "openzeppelin-upgradeable/governance/GovernorUpgradeable.sol";
import {AccessControlUpgradeable} from "openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";

contract SubmitUpgradeProposal is Script, SharedGovernorConstants {
  address PROPOSER = 0x1B686eE8E31c5959D9F5BBd8122a58682788eeaD; // L2Beat

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
    targets = new address[](1);
    values = new uint256[](1);
    calldatas = new bytes[](1);
    description = "Upgrade timelock roles";

    targets[0] = ARB_SYS;
    // TODO: Write the calldata for the ArbSys.sendTxToL1 call
    calldatas[0] = abi.encodeWithSelector(ArbSys.sendTxToL1.selector, abi.encodeWithSelector("TODO"));

    vm.startBroadcast(PROPOSER);
    _proposalId = GovernorUpgradeable(payable(_currentGovernor)).propose(targets, values, calldatas, description);
    vm.stopBroadcast();
  }
}

interface ArbSys {
  function sendTxToL1(address destination, bytes memory calldataData) external payable;
}
