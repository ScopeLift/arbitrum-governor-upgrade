// SPDX-License-Identifier: UNLICENSED
// slither-disable-start reentrancy-benign

pragma solidity 0.8.26;

import {BaseDeployer} from "script/BaseDeployer.sol";
import {SharedGovernorConstants} from "script/SharedGovernorConstants.sol";
import {L2ArbitrumGovernorV2} from "src/L2ArbitrumGovernorV2.sol";
import {TransparentUpgradeableProxy} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TimelockControllerUpgradeable} from "openzeppelin-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {IVotes} from "openzeppelin/governance/utils/IVotes.sol";

// This base deployer contract is meant to be inherited by each concrete script written to deploy a specific governor,
// namely the Treasury Governor and Core Governor. It includes the base deployment logic, shared constants, and
// defines the virtual methods for values which must be provided by each concrete implementation.
abstract contract BaseGovernorDeployer is BaseDeployer, SharedGovernorConstants {
  // Virtual methods returning initialization parameters that must be implemented by
  // each concrete deploy script.
  function NAME() public virtual returns (string memory);
  function TIMELOCK_ADDRESS() public virtual returns (address payable);
  function QUORUM_NUMERATOR() public virtual returns (uint256);

  function run(address _implementation) public returns (L2ArbitrumGovernorV2 _governor) {
    vm.startBroadcast(deployerPrivateKey);
    TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(_implementation, PROXY_OWNER, "");
    _governor = L2ArbitrumGovernorV2(payable(address(_proxy)));
    _governor.initialize(
      NAME(),
      INITIAL_VOTING_DELAY,
      INITIAL_VOTING_PERIOD,
      INITIAL_PROPOSAL_THRESHOLD,
      IVotes(ARB_TOKEN_ADDRESS),
      TimelockControllerUpgradeable(TIMELOCK_ADDRESS()),
      QUORUM_NUMERATOR(),
      INITIAL_VOTE_EXTENSION,
      PROXY_OWNER // TODO: verify this is the same as the proxy admin
    );
    vm.stopBroadcast();
  }
}
