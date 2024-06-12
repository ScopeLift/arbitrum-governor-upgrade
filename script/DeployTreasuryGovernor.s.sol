// SPDX-License-Identifier: AGPL-3.0-only
// slither-disable-start reentrancy-benign

pragma solidity 0.8.26;

import {BaseGovernorDeployer} from "script/BaseGovernorDeployer.sol";

// Concrete deployment script for the Arbitrum L2 Core Governor.
contract DeployTreasuryGovernor is BaseGovernorDeployer {
  function NAME() public pure override returns (string memory) {
    return "Treasury L2ArbitrumGovernor";
  }

  function TIMELOCK_ADDRESS() public pure override returns (address payable) {
    return payable(0xbFc1FECa8B09A5c5D3EFfE7429eBE24b9c09EF58);
  }

  function QUORUM_NUMERATOR() public pure override returns (uint256) {
    return 300;
  }
}
