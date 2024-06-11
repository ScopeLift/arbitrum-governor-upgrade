// SPDX-License-Identifier: UNLICENSED
// slither-disable-start reentrancy-benign

pragma solidity 0.8.26;

import {BaseGovernorDeployer} from "script/BaseGovernorDeployer.sol";

// Concrete deployment script for the Arbitrum L2 Core Governor.
contract DeployCoreGovernor is BaseGovernorDeployer {
  function NAME() public pure override returns (string memory) {
    return "Core L2ArbitrumGovernor";
  }

  function TIMELOCK_ADDRESS() public pure override returns (address payable) {
    return payable(0x34d45e99f7D8c45ed05B5cA72D54bbD1fb3F98f0);
  }

  function QUORUM_NUMERATOR() public pure override returns (uint256) {
    return 500;
  }
}
