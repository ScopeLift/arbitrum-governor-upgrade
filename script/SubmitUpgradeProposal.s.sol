// SPDX-License-Identifier: AGPL-3.0-only
// slither-disable-start reentrancy-benign

pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {SharedGovernorConstants} from "script/SharedGovernorConstants.sol";
import {GovernorUpgradeable} from "openzeppelin-upgradeable/governance/GovernorUpgradeable.sol";
import {AccessControlUpgradeable} from "openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";

contract SubmitUpgradeProposal is Script, SharedGovernorConstants {
  // TODO: Update `PROPOSER` to script msg.sender who will subtmit the proposal.
  address PROPOSER = 0x1B686eE8E31c5959D9F5BBd8122a58682788eeaD; // L2Beat
  // TODO: Update `minDelay` to latest getMinDelay() from L1Timelock.
  uint256 minDelay = 259_200;

  function run(address _timelockRolesUpgrader) public {
    proposeUpgradeAndReturnCalldata(_timelockRolesUpgrader);
  }

  function proposeUpgradeAndReturnCalldata(address _timelockRolesUpgrader)
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
    bytes memory proposalCalldata =
      createProposal(L1_TIMELOCK, description, _timelockRolesUpgrader, ARB_ONE_DELAYED_INBOX, UPGRADE_EXECUTOR);
    calldatas[0] = proposalCalldata;

    vm.startBroadcast(PROPOSER);
    _proposalId = GovernorUpgradeable(payable(ARBITRUM_CORE_GOVERNOR)).propose(targets, values, calldatas, description);
    vm.stopBroadcast();
  }

  function createProposal(
    address l1TimelockAddr,
    string memory proposalDescription,
    address oneOffUpgradeAddr,
    address arbOneInboxAddr,
    address upgradeExecutorAddr
  ) internal view returns (bytes memory) {
    address retryableTicketMagic = RETRYABLE_TICKET_MAGIC;

    // the data to call the upgrade executor with
    // it tells the upgrade executor how to call the upgrade contract, and what calldata to provide to it
    bytes memory upgradeExecutorCallData = abi.encodeWithSelector(
      IUpgradeExecutor.execute.selector,
      oneOffUpgradeAddr,
      abi.encodeWithSelector(ITimelockRolesUpgrader.perform.selector)
    );

    // the data provided to call the l1 timelock with
    // specifies how to create a retryable ticket, which will then be used to call the upgrade executor with the
    // data created from the step above
    bytes memory l1TimelockData = abi.encodeWithSelector(
      IL1Timelock.schedule.selector,
      retryableTicketMagic, // tells the l1 timelock that we want to make a retryable, instead of an l1 upgrade
      0, // ignored for l2 upgrades
      abi.encode( // these are the retryable data params
        arbOneInboxAddr, // the inbox we want to use, should be arb one or nova inbox
        upgradeExecutorAddr, // the upgrade executor on the l2 network
        0, // no value in this upgrade
        0, // max gas - will be filled in when the retryable is actually executed
        0, // max fee per gas - will be filled in when the retryable is actually executed
        upgradeExecutorCallData // call data created in the previous step
      ),
      bytes32(0), // no predecessor
      keccak256(abi.encodePacked(proposalDescription)), // prop description
      minDelay // delay for this proposal
    );

    // the data provided to the L2 Arbitrum Governor in the propose() method
    // the target will be the ArbSys address on Arb One
    bytes memory proposalCalldata = abi.encodeWithSelector(
      IArbSys.sendTxToL1.selector, // the execution of the proposal will create an L2->L1 cross chain message
      l1TimelockAddr, // the target of the cross chain message is the L1 timelock
      l1TimelockData // call the l1 timelock with the data created in the previous step
    );
    return proposalCalldata;
  }
}

interface IUpgradeExecutor {
  function execute(address to, bytes calldata data) external payable;
}

interface IL1Timelock {
  function schedule(
    address target,
    uint256 value,
    bytes calldata data,
    bytes32 predecessor,
    bytes32 salt,
    uint256 delay
  ) external;
  function getMinDelay() external view returns (uint256);
}

interface IArbSys {
  function sendTxToL1(address destination, bytes calldata data) external payable returns (uint256);
}

interface IL2ArbitrumGovernor {
  function propose(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    string memory description
  ) external returns (uint256);
}

interface ITimelockRolesUpgrader {
  function perform() external;
}
