// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

// import {SharedGovernorConstants} from "script/SharedGovernorConstants.sol";
import {CreateL2ArbSysProposal} from "script/helpers/CreateL2ArbSysProposal.sol";

contract ProposalHelper is CreateL2ArbSysProposal {
  struct Proposal {
    address[] targets;
    uint256[] values;
    bytes[] calldatas;
    string description;
    uint256 proposalId;
  }

  // function createProposal(

  // )

  function createCoreProposal(
    string memory _proposalDescription,
    address _oneOffUpgradeAddr,
    uint256 _minDelay,
    address _proposer
  ) public pure returns (Proposal memory) {
    address[] memory targets = new address[](1);
    uint256[] memory values = new uint256[](1);
    bytes[] memory calldatas = new bytes[](1);

    targets[0] = ARB_SYS;
    calldatas[0] = createProposalCalldata(_proposalDescription, _oneOffUpgradeAddr, _minDelay);
  }

  function createTreasuryProposalForSingleTransfer(address _token, address _to, uint256 _amount)
    public
    pure
    returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
  {
    targets = new address[](1);
    values = new uint256[](1);
    calldatas = new bytes[](1);

    targets[0] = DAO_TREASURY;
    bytes memory transferCalldata =
      abi.encodeWithSelector(IFixedDelegateErc20Wallet.transfer.selector, _token, _to, _amount);
    calldatas[0] = transferCalldata;
  }
}
