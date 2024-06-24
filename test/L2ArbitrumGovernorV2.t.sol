// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {SharedGovernorConstants} from "script/SharedGovernorConstants.sol";
import {DeployImplementation} from "script/DeployImplementation.s.sol";
import {BaseGovernorDeployer} from "script/BaseGovernorDeployer.sol";
import {DeployCoreGovernor} from "script/DeployCoreGovernor.s.sol";
import {DeployTreasuryGovernor} from "script/DeployTreasuryGovernor.s.sol";
import {L2ArbitrumGovernorV2} from "src/L2ArbitrumGovernorV2.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {TimelockControllerUpgradeable} from "openzeppelin-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {IVotes} from "openzeppelin/governance/utils/IVotes.sol";
import {TransparentUpgradeableProxy} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

// ----------------------------------------------------------------------------------------------------------------- //
// Test Suite Base - Shared values, setup, helpers, and virtual methods needed by concrete test contracts
// ----------------------------------------------------------------------------------------------------------------- //

abstract contract L2ArbitrumGovernorV2Test is Test, SharedGovernorConstants {
  uint256 constant FORK_BLOCK = 220_819_857; // Arbitrary recent block
  address constant proxyAdminContract = 0x740f24A3cbF1fbA1226C6018511F96d1055ce961; // Proxy Admin Contract Address
  L2ArbitrumGovernorV2 governor;
  BaseGovernorDeployer proxyDeployer;
  ERC20Mock mockToken;

  // Each concrete test suite returns the appropriate concrete deploy script which will be exercised in setup
  function _createGovernorDeployer() internal virtual returns (BaseGovernorDeployer);

  function setUp() public {
    vm.createSelectFork(
      vm.envOr("ARBITRUM_ONE_RPC_URL", string("Please set ARBITRUM_ONE_RPC_URL in your .env file")), FORK_BLOCK
    );

    DeployImplementation _implementationDeployer = new DeployImplementation();
    _implementationDeployer.setUp();
    address _implementation = address(_implementationDeployer.run());
    mockToken = new ERC20Mock();

    proxyDeployer = _createGovernorDeployer();
    proxyDeployer.setUp();
    governor = proxyDeployer.run(_implementation);
  }
}

// ----------------------------------------------------------------------------------------------------------------- //
// Abstract Test Suite - Write generic integration tests for both Governors
// ----------------------------------------------------------------------------------------------------------------- //

abstract contract Initialize is L2ArbitrumGovernorV2Test {
  function test_ConfiguresTheParametersDuringInitialization() public {
    assertEq(governor.name(), proxyDeployer.NAME());
    assertEq(governor.votingDelay(), INITIAL_VOTING_DELAY);
    assertEq(governor.votingPeriod(), INITIAL_VOTING_PERIOD);
    assertEq(governor.proposalThreshold(), INITIAL_PROPOSAL_THRESHOLD);
    assertEq(address(governor.token()), address(ARB_TOKEN_ADDRESS));
    assertEq(address(governor.timelock()), proxyDeployer.TIMELOCK_ADDRESS());
    assertEq(governor.lateQuorumVoteExtension(), INITIAL_VOTE_EXTENSION);
    assertEq(governor.owner(), GOVERNOR_OWNER);
  }

  function test_RevertIf_InitializerIsCalledASecondTime() public {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    governor.initialize(
      "TEST", 1, 1, 1, IVotes(address(0x1)), TimelockControllerUpgradeable(payable(address(0x1))), 1, 1, address(0x1)
    );
  }
}

abstract contract Relay is L2ArbitrumGovernorV2Test {
  error OwnableUnauthorizedAccount(address actor);

  function testFuzz_CanRelayUpdateQuorumNumerator(uint256 _numerator) public {
    _numerator = bound(_numerator, 1, governor.quorumDenominator());
    vm.prank(GOVERNOR_OWNER);
    governor.relay(address(governor), 0, abi.encodeWithSelector(governor.updateQuorumNumerator.selector, _numerator));
    assertEq(governor.quorumNumerator(), _numerator);
  }

  function testFuzz_CanRelayUpdateTimelock(TimelockControllerUpgradeable _timelock) public {
    vm.prank(GOVERNOR_OWNER);
    governor.relay(address(governor), 0, abi.encodeWithSelector(governor.updateTimelock.selector, _timelock));
    assertEq(governor.timelock(), address(_timelock));
  }

  function testFuzz_CanRelaySetVotingDelay(uint48 _newVotingDelay) public {
    vm.prank(GOVERNOR_OWNER);
    governor.relay(address(governor), 0, abi.encodeWithSelector(governor.setVotingDelay.selector, _newVotingDelay));
    assertEq(governor.votingDelay(), _newVotingDelay);
  }

  function testFuzz_CanRelaySetVotingPeriod(uint32 _newVotingPeriod) public {
    vm.assume(_newVotingPeriod != 0);
    vm.prank(GOVERNOR_OWNER);
    governor.relay(address(governor), 0, abi.encodeWithSelector(governor.setVotingPeriod.selector, _newVotingPeriod));
    assertEq(governor.votingPeriod(), _newVotingPeriod);
  }

  function testFuzz_CanRelaySetProposalThreshold(uint256 _newProposalThreshold) public {
    vm.prank(GOVERNOR_OWNER);
    governor.relay(
      address(governor), 0, abi.encodeWithSelector(governor.setProposalThreshold.selector, _newProposalThreshold)
    );
    assertEq(governor.proposalThreshold(), _newProposalThreshold);
  }

  function testFuzz_CanRelayTokenTransfer(address _to, uint256 _amount) public {
    vm.assume(_to != address(0));
    mockToken.mint(address(governor), _amount);
    vm.prank(GOVERNOR_OWNER);
    governor.relay(address(mockToken), 0, abi.encodeWithSelector(mockToken.transfer.selector, _to, _amount));
    assertEq(mockToken.balanceOf(_to), _amount);
  }

  function testFuzz_RevertIf_NotOwner(address _actor, uint256 _numerator) public {
    vm.assume(_actor != GOVERNOR_OWNER && _actor != proxyAdminContract);
    _numerator = bound(_numerator, 1, governor.quorumDenominator());
    vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, _actor));
    vm.prank(_actor);
    governor.relay(address(governor), 0, abi.encodeWithSelector(governor.updateQuorumNumerator.selector, _numerator));
  }
}

// ----------------------------------------------------------------------------------------------------------------- //
// Concrete Test Contracts - Inherit from each abstract test and implement concrete methods for Core & Treasury case
// ----------------------------------------------------------------------------------------------------------------- //

contract CoreGovernorInitialize is Initialize {
  function _createGovernorDeployer() internal override returns (BaseGovernorDeployer) {
    return new DeployCoreGovernor();
  }
}

contract CoreGovernorRelay is Relay {
  function _createGovernorDeployer() internal override returns (BaseGovernorDeployer) {
    return new DeployCoreGovernor();
  }
}

contract TreasuryGovernorInitialize is Initialize {
  function _createGovernorDeployer() internal override returns (BaseGovernorDeployer) {
    return new DeployTreasuryGovernor();
  }
}

contract TreasuryGovernorRelay is Relay {
  function _createGovernorDeployer() internal override returns (BaseGovernorDeployer) {
    return new DeployTreasuryGovernor();
  }
}
