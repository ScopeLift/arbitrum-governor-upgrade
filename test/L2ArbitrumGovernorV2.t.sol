// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {L2ArbitrumGovernorV2} from "src/L2ArbitrumGovernorV2.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {TransparentUpgradeableProxy} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

contract L2ArbitrumGovernorV2Test is Test {
  uint256 constant FORK_BLOCK = 220_819_857; // Arbitrary recent block
  address proxyOwner = makeAddr("Proxy Owner");
  L2ArbitrumGovernorV2 governor;

  function setUp() public {
    vm.createSelectFork(
      vm.envOr("ARBITRUM_ONE_RPC_URL", string("Please set ARBITRUM_ONE_RPC_URL in your .env file")), FORK_BLOCK
    );
    address _implementation = address(new L2ArbitrumGovernorV2());
    TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(_implementation, proxyOwner, "");
    governor = L2ArbitrumGovernorV2(payable(address(_proxy)));
    governor.initialize();
  }
}

contract Initialize is L2ArbitrumGovernorV2Test {
  function test_RevertIf_InitializerIsCalledASecondTime() public {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    governor.initialize();
  }
}
