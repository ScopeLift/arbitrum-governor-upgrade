// SPDX-License-Identifier: AGPL-3.0-only
// slither-disable-start reentrancy-benign

pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {SharedGovernorConstants} from "script/SharedGovernorConstants.sol";
import {GovernorUpgradeable} from "openzeppelin-upgradeable/governance/GovernorUpgradeable.sol";
import {AccessControlUpgradeable} from "openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import {CreateProposalCalldata} from "script/helpers/CreateProposalCalldata.sol";

contract SubmitUpgradeProposalScript is Script, SharedGovernorConstants, CreateProposalCalldata {
  // TODO: Update `PROPOSER` to script msg.sender who will submit the proposal.
  address PROPOSER = 0x1B686eE8E31c5959D9F5BBd8122a58682788eeaD; // L2Beat
  // TODO: Update `minDelay` to latest getMinDelay() from L1Timelock.
  uint256 minDelay = 259_200;

  function run(address _timelockRolesUpgrader)
    public
    returns (
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description,
      uint256 _proposalId
    )
  {
    return proposeUpgrade(_timelockRolesUpgrader);
  }

  function proposeUpgrade(address _timelockRolesUpgrader)
    internal
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
    bytes memory proposalCalldata = _createProposal(description, _timelockRolesUpgrader, minDelay);
    calldatas[0] = proposalCalldata;

    vm.startBroadcast(PROPOSER);
    _proposalId = GovernorUpgradeable(payable(ARBITRUM_CORE_GOVERNOR)).propose(targets, values, calldatas, description);
    vm.stopBroadcast();
  }
}
