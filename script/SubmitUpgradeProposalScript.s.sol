// SPDX-License-Identifier: AGPL-3.0-only
// slither-disable-start reentrancy-benign

pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {SharedGovernorConstants} from "script/SharedGovernorConstants.sol";
import {GovernorUpgradeable} from "openzeppelin-upgradeable/governance/GovernorUpgradeable.sol";
import {CreateL2ArbSysProposal} from "script/helpers/CreateL2ArbSysProposal.sol";

contract SubmitUpgradeProposalScript is Script, SharedGovernorConstants, CreateL2ArbSysProposal {
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
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldatas,
      string memory _description,
      uint256 _proposalId
    )
  {
    _description = "Upgrade timelock roles";
    (_targets, _values, _calldatas) = createL2ArbSysProposal(_description, _timelockRolesUpgrader, minDelay);

    vm.startBroadcast(PROPOSER);
    _proposalId = GovernorUpgradeable(payable(L2_CORE_GOVERNOR)).propose(_targets, _values, _calldatas, _description);
    vm.stopBroadcast();
  }
}
