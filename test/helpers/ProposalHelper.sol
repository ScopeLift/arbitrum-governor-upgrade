// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {CreateL2ArbSysProposal, IFixedDelegateErc20Wallet} from "script/helpers/CreateL2ArbSysProposal.sol";
import {L2ArbitrumGovernorV2} from "src/L2ArbitrumGovernorV2.sol";

struct Proposal {
  address[] targets;
  uint256[] values;
  bytes[] calldatas;
  string description;
  uint256 proposalId;
}

contract ProposalHelper is CreateL2ArbSysProposal, Test {
  function createL2ArbSysProposal(
    string memory _proposalDescription,
    address _oneOffUpgradeAddr,
    uint256 _minDelay,
    L2ArbitrumGovernorV2 _governor,
    address _proposer
  ) public returns (Proposal memory) {
    (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
      createL2ArbSysProposal(_proposalDescription, _oneOffUpgradeAddr, _minDelay);
    vm.prank(_proposer);
    uint256 _proposalId = _governor.propose(targets, values, calldatas, _proposalDescription);
    return Proposal(targets, values, calldatas, _proposalDescription, _proposalId);
  }

  function createTreasuryProposalForSingleTransfer(
    address _token,
    address _to,
    uint256 _amount,
    L2ArbitrumGovernorV2 _governor,
    address _proposer
  ) public returns (Proposal memory) {
    address[] memory targets = new address[](1);
    uint256[] memory values = new uint256[](1);
    bytes[] memory calldatas = new bytes[](1);

    targets[0] = L2_ARB_TREASURY_FIXED_DELEGATE;
    bytes memory transferCalldata =
      abi.encodeWithSelector(IFixedDelegateErc20Wallet.transfer.selector, _token, _to, _amount);
    calldatas[0] = transferCalldata;
    string memory _proposalDescription = "treasury proposal";
    vm.prank(_proposer);
    uint256 _proposalId = _governor.propose(targets, values, calldatas, _proposalDescription);
    return Proposal(targets, values, calldatas, _proposalDescription, _proposalId);
  }
}
