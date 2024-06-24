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
import {ERC20VotesUpgradeable} from "openzeppelin-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {IGovernor} from "openzeppelin/governance/IGovernor.sol";

// ----------------------------------------------------------------------------------------------------------------- //
// Test Suite Base - Shared values, setup, helpers, and virtual methods needed by concrete test contracts
// ----------------------------------------------------------------------------------------------------------------- //

abstract contract L2ArbitrumGovernorV2Test is Test, SharedGovernorConstants {
  uint256 constant FORK_BLOCK = 220_819_857; // Arbitrary recent block
  /// @dev Proxy admin contract deployed in construction of TransparentUpgradeableProxy -- getter is internal, so we
  /// hardcode the address below
  address constant PROXY_ADMIN_CONTRACT = 0x740f24A3cbF1fbA1226C6018511F96d1055ce961; // Proxy Admin Contract Address
  L2ArbitrumGovernorV2 governor;
  BaseGovernorDeployer proxyDeployer;
  ERC20VotesUpgradeable arbitrumToken;
  ERC20Mock mockToken;

  // Each concrete test suite returns the appropriate concrete deploy script which will be exercised in setup
  function _createGovernorDeployer() internal virtual returns (BaseGovernorDeployer);

  function setUp() public virtual {
    vm.createSelectFork(
      vm.envOr("ARBITRUM_ONE_RPC_URL", string("Please set ARBITRUM_ONE_RPC_URL in your .env file")), FORK_BLOCK
    );

    DeployImplementation _implementationDeployer = new DeployImplementation();
    _implementationDeployer.setUp();
    address _implementation = address(_implementationDeployer.run());
    arbitrumToken = ERC20VotesUpgradeable(ARB_TOKEN_ADDRESS);
    mockToken = new ERC20Mock();

    proxyDeployer = _createGovernorDeployer();
    proxyDeployer.setUp();
    governor = proxyDeployer.run(_implementation);
  }

  function _getMajorDelegate(uint256 _actorSeed) public pure returns (address) {
    address[] memory _majorDelegates = new address[](4);
    _majorDelegates[0] = 0x1B686eE8E31c5959D9F5BBd8122a58682788eeaD; // L2BEAT
    _majorDelegates[1] = 0xF4B0556B9B6F53E00A1FDD2b0478Ce841991D8fA; // olimpio
    _majorDelegates[2] = 0x11cd09a0c5B1dc674615783b0772a9bFD53e3A8F; // Gauntlet
    _majorDelegates[3] = 0xB933AEe47C438f22DE0747D57fc239FE37878Dd1; // Wintermute
    return _majorDelegates[_actorSeed % _majorDelegates.length];
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
    assertEq(address(arbitrumToken), address(ARB_TOKEN_ADDRESS));
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
    vm.assume(_actor != GOVERNOR_OWNER && _actor != PROXY_ADMIN_CONTRACT);
    _numerator = bound(_numerator, 1, governor.quorumDenominator());
    vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, _actor));
    vm.prank(_actor);
    governor.relay(address(governor), 0, abi.encodeWithSelector(governor.updateQuorumNumerator.selector, _numerator));
  }
}

abstract contract Quorum is L2ArbitrumGovernorV2Test {
  function setUp() public override {
    super.setUp();
    _setQuorumNumerator(3000); // 30% quorum
    vm.roll(vm.getBlockNumber() + 1);
  }

  function _setQuorumNumerator(uint256 _numerator) internal {
    vm.prank(address(governor));
    governor.updateQuorumNumerator(_numerator);
  }

  function _getMajorTokenHolder(uint256 _actorSeed) internal pure returns (address) {
    address[] memory _majorTokenHolders = new address[](4);
    _majorTokenHolders[0] = 0x62383739D68Dd0F844103Db8dFb05a7EdED5BBE6;
    _majorTokenHolders[1] = 0xF977814e90dA44bFA03b6295A0616a897441aceC;
    _majorTokenHolders[2] = 0xf7F468B184A48f6ca37EeFFE12733Ee1c16B6E26;
    _majorTokenHolders[3] = 0x1190CEA3e2c8727218768bFb990C3228aA06dfA9;
    return _majorTokenHolders[_actorSeed % _majorTokenHolders.length];
  }

  function testFuzz_ReturnsCorrectQuorum(uint256 _numerator, uint256 _pastBlockNumber) public {
    _numerator = bound(_numerator, 1, governor.quorumDenominator());
    _setQuorumNumerator(_numerator);
    vm.roll(vm.getBlockNumber() + 1);
    _pastBlockNumber = bound(_pastBlockNumber, 1, vm.getBlockNumber() - 1);

    uint256 tokenPastTotalSupply = arbitrumToken.getPastTotalSupply(_pastBlockNumber);
    uint256 excludeAddressVotes = arbitrumToken.getPastVotes(governor.EXCLUDE_ADDRESS(), _pastBlockNumber);
    uint256 expectedQuorum = (tokenPastTotalSupply - excludeAddressVotes) * governor.quorumNumerator(_pastBlockNumber)
      / governor.quorumDenominator();
    vm.assertEq(governor.quorum(_pastBlockNumber), expectedQuorum);
  }

  function testFuzz_ReturnsCorrectQuorumAfterDelegatingToExcludeAddress(uint256 _numerator, uint256 _actorSeed) public {
    // Set a random numerator
    _numerator = bound(_numerator, 1, governor.quorumDenominator());
    _setQuorumNumerator(_numerator);
    vm.roll(vm.getBlockNumber() + 1);

    // Keep track of the previous quorum and exclude address votes
    uint256 previousQuorum = governor.quorum(vm.getBlockNumber() - 1);
    uint256 previousExcludeAddressVotes =
      arbitrumToken.getPastVotes(governor.EXCLUDE_ADDRESS(), vm.getBlockNumber() - 1);

    // Delegate a major token holder's balance to the exclude address
    address _actor = _getMajorTokenHolder(_actorSeed);
    vm.startPrank(_actor);
    arbitrumToken.delegate(governor.EXCLUDE_ADDRESS());
    vm.stopPrank();
    vm.roll(vm.getBlockNumber() + 1);

    uint256 previousBlock = vm.getBlockNumber() - 1;
    uint256 tokenPastTotalSupply = arbitrumToken.getPastTotalSupply(previousBlock);
    uint256 excludeAddressVotes = arbitrumToken.getPastVotes(governor.EXCLUDE_ADDRESS(), previousBlock);
    uint256 expectedQuorum = (tokenPastTotalSupply - excludeAddressVotes) * governor.quorumNumerator(previousBlock)
      / governor.quorumDenominator();

    vm.assertEq(governor.quorum(previousBlock), expectedQuorum);
    // Exclude address votes should increase by the actor's balance
    vm.assertEq(
      arbitrumToken.getPastVotes(governor.EXCLUDE_ADDRESS(), previousBlock),
      previousExcludeAddressVotes + arbitrumToken.balanceOf(_actor)
    );
    // Quorum should decrease
    vm.assertGt(previousQuorum, expectedQuorum);
  }
}

abstract contract Propose is L2ArbitrumGovernorV2Test {
  event ProposalCreated(
    uint256 proposalId,
    address proposer,
    address[] targets,
    uint256[] values,
    string[] signatures,
    bytes[] calldatas,
    uint256 voteStart,
    uint256 voteEnd,
    string description
  );

  function testFuzz_Propose(uint256 _actorSeed) public {
    // Proposal parameters
    address[] memory targets = new address[](1);
    uint256[] memory values = new uint256[](1);
    bytes[] memory calldatas = new bytes[](1);
    string[] memory signatures = new string[](1);
    uint256 voteStart = vm.getBlockNumber() + governor.votingDelay();
    uint256 voteEnd = voteStart + governor.votingPeriod();
    string memory description = "Test";

    uint256 proposalId = governor.hashProposal(targets, values, calldatas, keccak256(bytes(description)));
    address _actor = _getMajorDelegate(_actorSeed);
    vm.prank(_actor);
    vm.expectEmit();
    emit ProposalCreated(proposalId, _actor, targets, values, signatures, calldatas, voteStart, voteEnd, description);
    governor.propose(targets, values, calldatas, description);

    assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));
  }
}

abstract contract Cancel is L2ArbitrumGovernorV2Test {
  event ProposalCanceled(uint256 proposalId);

  function testFuzz_CancelProposalAfterSucceedingButBeforeQueuing(uint256 _actorSeed) public virtual {
    address[] memory targets = new address[](1);
    uint256[] memory values = new uint256[](1);
    bytes[] memory calldatas = new bytes[](1);
    string memory description = "Test";

    address _actor = _getMajorDelegate(_actorSeed);
    vm.prank(_actor);
    uint256 proposalId = governor.propose(targets, values, calldatas, description);

    assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));
    vm.prank(address(_actor));
    governor.cancel(targets, values, calldatas, keccak256(bytes(description)));
    assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Canceled));
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

contract CoreGovernorQuorum is Quorum {
  function _createGovernorDeployer() internal override returns (BaseGovernorDeployer) {
    return new DeployCoreGovernor();
  }
}

contract CoreGovernorPropose is Propose {
  function _createGovernorDeployer() internal override returns (BaseGovernorDeployer) {
    return new DeployCoreGovernor();
  }
}

contract CoreGovernorCancel is Cancel {
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

contract TreasuryGovernorQuorum is Quorum {
  function _createGovernorDeployer() internal override returns (BaseGovernorDeployer) {
    return new DeployTreasuryGovernor();
  }
}

contract TreasuryGovernorPropose is Propose {
  function _createGovernorDeployer() internal override returns (BaseGovernorDeployer) {
    return new DeployTreasuryGovernor();
  }
}

contract TreasuryGovernorCancel is Cancel {
  function _createGovernorDeployer() internal override returns (BaseGovernorDeployer) {
    return new DeployTreasuryGovernor();
  }
}
