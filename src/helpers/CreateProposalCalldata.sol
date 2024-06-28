// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

import {SharedGovernorConstants} from "script/SharedGovernorConstants.sol";

contract CreateProposalCalldata is SharedGovernorConstants {
  function createProposal(string memory _proposalDescription, address _oneOffUpgradeAddr, uint256 _minDelay)
    internal
    view
    returns (bytes memory)
  {
    address retryableTicketMagic = RETRYABLE_TICKET_MAGIC;

    // the data to call the upgrade executor with
    // it tells the upgrade executor how to call the upgrade contract, and what calldata to provide to it
    bytes memory upgradeExecutorCallData = abi.encodeWithSelector(
      IUpgradeExecutor.execute.selector,
      _oneOffUpgradeAddr,
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
        ARB_ONE_DELAYED_INBOX, // the inbox we want to use, should be arb one or nova inbox
        UPGRADE_EXECUTOR, // the upgrade executor on the l2 network
        0, // no value in this upgrade
        0, // max gas - will be filled in when the retryable is actually executed
        0, // max fee per gas - will be filled in when the retryable is actually executed
        upgradeExecutorCallData // call data created in the previous step
      ),
      bytes32(0), // no predecessor
      keccak256(abi.encodePacked(_proposalDescription)), // prop description
      _minDelay // delay for this proposal
    );

    // the data provided to the L2 Arbitrum Governor in the propose() method
    // the target will be the ArbSys address on Arb One
    bytes memory proposalCalldata = abi.encodeWithSelector(
      IArbSys.sendTxToL1.selector, // the execution of the proposal will create an L2->L1 cross chain message
      L1_TIMELOCK, // the target of the cross chain message is the L1 timelock
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
