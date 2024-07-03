// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {TimelockControllerUpgradeable} from "openzeppelin-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {IVotes} from "openzeppelin/governance/utils/IVotes.sol";
import {TransparentUpgradeableProxy} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {ERC20VotesUpgradeable} from "openzeppelin-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {IGovernor} from "openzeppelin/governance/IGovernor.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {BaseGovernorDeployer} from "script/BaseGovernorDeployer.sol";
import {SubmitUpgradeProposalScript} from "script/SubmitUpgradeProposalScript.s.sol";
import {SetupNewGovernors} from "test/helpers/SetupNewGovernors.sol";
import {L2ArbitrumGovernorV2, GovernorCountingFractionalUpgradeable} from "src/L2ArbitrumGovernorV2.sol";
import {TimelockRolesUpgrader} from "src/gov-action-contracts/TimelockRolesUpgrader.sol";
import {ProposalHelper, Proposal} from "test/helpers/ProposalHelper.sol";

// ----------------------------------------------------------------------------------------------------------------- //
// Test Suite Base - Shared values, setup, helpers, and virtual methods needed by concrete test contracts
// ----------------------------------------------------------------------------------------------------------------- //

abstract contract L2ArbitrumGovernorV2Test is SetupNewGovernors {
  // state
  L2ArbitrumGovernorV2 governor;
  TimelockControllerUpgradeable timelock;
  address PROXY_ADMIN_CONTRACT;
  ERC20Mock mockToken;
  ERC20VotesUpgradeable arbitrumToken;

  // helper contracts
  ProposalHelper proposalHelper;
  BaseGovernorDeployer proxyDeployer;

  function setUp() public virtual override {
    super.setUp();

    // State that both core and treasury governors can use
    arbitrumToken = ERC20VotesUpgradeable(L2_ARB_TOKEN_ADDRESS);
    mockToken = new ERC20Mock();
    proposalHelper = new ProposalHelper();
  }

  function _getMajorDelegate(uint256 _actorSeed) public view returns (address) {
    return _majorDelegates[_actorSeed % _majorDelegates.length];
  }

  function _proposeRealisticProposal(uint256 _proposalSeed) internal virtual returns (Proposal memory);

  function _proposeTestProposal()
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
    description = "Test";

    vm.prank(_getMajorDelegate(1));
    _proposalId = governor.propose(targets, values, calldatas, description);
  }

  function _voteForProposal(uint256 _proposalId, VoteType _voteType) internal {
    for (uint256 i; i < _majorDelegates.length; i++) {
      vm.prank(_majorDelegates[i]);
      governor.castVote(_proposalId, uint8(_voteType));
    }
  }

  function _skipToPostUpgrade() internal {
    (
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldatas,
      string memory _description,
      uint256 _proposalId
    ) = submitUpgradeProposalScript.run(address(timelockRolesUpgrader));

    vm.roll(vm.getBlockNumber() + currentCoreGovernor.votingDelay() + 1);
    assertEq(uint256(currentCoreGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Active));

    // Vote
    for (uint256 i; i < _majorDelegates.length; i++) {
      vm.prank(_majorDelegates[i]);
      currentCoreGovernor.castVote(_proposalId, uint8(VoteType.For));
    }

    // Success
    vm.roll(vm.getBlockNumber() + currentCoreGovernor.votingPeriod() + 1);
    assertEq(uint256(currentCoreGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Succeeded));

    // Queue
    currentCoreGovernor.queue(_targets, _values, _calldatas, keccak256(bytes(_description)));
    assertEq(uint256(currentCoreGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Queued));
    vm.warp(vm.getBlockTimestamp() + currentCoreTimelock.getMinDelay() + 1);

    // Execute
    currentCoreGovernor.execute(_targets, _values, _calldatas, keccak256(bytes(_description)));
    assertEq(uint256(currentCoreGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Executed));
  }
}

// ----------------------------------------------------------------------------------------------------------------- //
// Core Governor Base - An extended base test suite helping us test proposals relevant to Core Governor
// ----------------------------------------------------------------------------------------------------------------- //

abstract contract CoreGovernorBase is L2ArbitrumGovernorV2Test {
  function setUp() public virtual override {
    super.setUp();
    /// Proxy admin contract deployed in construction of TransparentUpgradeableProxy -- getter is internal so we
    /// hardcode the address
    PROXY_ADMIN_CONTRACT = 0x740f24A3cbF1fbA1226C6018511F96d1055ce961;
    governor = newCoreGovernor;
    timelock = currentCoreTimelock;
    proxyDeployer = proxyCoreGovernorDeployer;
  }

  function _proposeRealisticProposal(uint256 _proposalSeed) internal override returns (Proposal memory) {
    Proposal[] memory _proposals = new Proposal[](1);

    // one type of realistic proposal would be to use ArbSys to do something via L2 UpgradeExecutor
    MockOneOffUpgrader _oneOffUpgrader = new MockOneOffUpgrader();
    _proposals[0] = proposalHelper.createL2ArbSysProposal(
      "Realistic core proposal", address(_oneOffUpgrader), L1_TIMELOCK_MIN_DELAY, governor, _getMajorDelegate(1)
    );

    return _proposals[_proposalSeed % _proposals.length];
  }
}

// ----------------------------------------------------------------------------------------------------------------- //
// Treasury Governor Base - An extended base test suite helping us test proposals relevant to Treasury Governor
// ----------------------------------------------------------------------------------------------------------------- //

abstract contract TreasuryGovernorBase is L2ArbitrumGovernorV2Test {
  function setUp() public virtual override {
    super.setUp();
    // Proxy admin contract deployed in construction of TransparentUpgradeableProxy -- getter is internal so we hardcode
    // the address
    PROXY_ADMIN_CONTRACT = 0xD3fe9b9cc02F23B3e3b43CF80700d8C7cf178339;
    governor = newTreasuryGovernor;
    timelock = currentTreasuryTimelock;
    proxyDeployer = proxyTreasuryGovernorDeployer;
  }

  function _proposeRealisticProposal(uint256 _proposalSeed) internal override returns (Proposal memory) {
    Proposal[] memory _proposals = new Proposal[](2);

    _proposals[0] = proposalHelper.createTreasuryProposalForSingleTransfer(
      L2_ARB_TOKEN_ADDRESS, address(0x1), 1_000_000 ether, governor, _getMajorDelegate(1)
    );

    // https://www.tally.xyz/gov/arbitrum/proposal/79183200449169085571205208154003416944507585311666453826890708127615057369177
    _proposals[1] = proposalHelper.createTreasuryProposalForSingleTransfer(
      L2_ARB_TOKEN_ADDRESS,
      address(0x544cBe6698E2e3b676C76097305bBa588dEfB13A),
      1_900_000_000_000_000_000_000_000,
      governor,
      _getMajorDelegate(1)
    );

    return _proposals[_proposalSeed % _proposals.length];
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
    assertEq(address(arbitrumToken), address(L2_ARB_TOKEN_ADDRESS));
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
  error GovernorInsufficientProposerVotes(address proposer, uint256 votes, uint256 threshold);
  error GovernorUnexpectedProposalState(uint256 proposalId, ProposalState current, bytes32 expectedStates);

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

  function testFuzz_CreatesProposalAndEmitsEvent(uint256 _actorSeed) public {
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

  function testFuzz_RevertIf_ThresholdNotMet(
    address _actor,
    MockOneOffUpgrader _oneOffUpgrader,
    string memory _description
  ) public {
    uint256 _actorVotes = arbitrumToken.getPastVotes(_actor, vm.getBlockNumber() - 1);
    vm.assume(_actorVotes < governor.proposalThreshold());
    vm.assume(_actor != PROXY_ADMIN_CONTRACT);

    vm.expectRevert(
      abi.encodeWithSelector(
        GovernorInsufficientProposerVotes.selector, _actor, _actorVotes, governor.proposalThreshold()
      )
    );
    proposalHelper.createL2ArbSysProposal(
      _description, address(_oneOffUpgrader), L1_TIMELOCK_MIN_DELAY, governor, _actor
    );
  }

  function testFuzz_RevertIf_ProposalAlreadyCreated(
    uint256 _actorSeed,
    MockOneOffUpgrader _oneOffUpgrader,
    string memory _description
  ) public {
    Proposal memory _proposal = proposalHelper.createL2ArbSysProposal(
      _description, address(_oneOffUpgrader), L1_TIMELOCK_MIN_DELAY, governor, _getMajorDelegate(_actorSeed)
    );

    vm.expectRevert(
      abi.encodeWithSelector(GovernorUnexpectedProposalState.selector, _proposal.proposalId, ProposalState.Pending, 0)
    );

    proposalHelper.createL2ArbSysProposal(
      _description, address(_oneOffUpgrader), L1_TIMELOCK_MIN_DELAY, governor, _getMajorDelegate(_actorSeed)
    );
    vm.stopPrank();
  }
}

abstract contract CastVote is L2ArbitrumGovernorV2Test {
  function testFuzz_ProposalVoteSuccess(uint256 _proposalSeed) public {
    Proposal memory _proposal = _proposeRealisticProposal(_proposalSeed);
    vm.roll(vm.getBlockNumber() + governor.votingDelay() + 1);

    vm.roll(vm.getBlockNumber() + governor.votingDelay() + 1);
    assertEq(uint256(governor.state(_proposal.proposalId)), uint256(IGovernor.ProposalState.Active));

    // Vote For
    for (uint256 i; i < _majorDelegates.length; i++) {
      vm.prank(_majorDelegates[i]);
      governor.castVote(_proposal.proposalId, uint8(VoteType.For));
    }

    vm.roll(vm.getBlockNumber() + governor.votingPeriod() + 1);
    vm.assertEq(uint256(governor.state(_proposal.proposalId)), uint256(ProposalState.Succeeded));
  }

  function testFuzz_ProposalVoteDefeat(uint256 _proposalSeed) public {
    Proposal memory _proposal = _proposeRealisticProposal(_proposalSeed);

    vm.roll(vm.getBlockNumber() + governor.votingDelay() + 1);
    assertEq(uint256(governor.state(_proposal.proposalId)), uint256(ProposalState.Active));

    // Vote Against
    for (uint256 i; i < _majorDelegates.length; i++) {
      vm.prank(_majorDelegates[i]);
      governor.castVote(_proposal.proposalId, uint8(VoteType.Against));
    }

    vm.roll(vm.getBlockNumber() + governor.votingPeriod() + 1);
    vm.assertEq(uint256(governor.state(_proposal.proposalId)), uint256(ProposalState.Defeated));
  }
}

abstract contract CastVoteWithReasonAndParams is L2ArbitrumGovernorV2Test {
  function testFuzz_CorrectlyVotesViaNominalVote(uint256 _proposalSeed, uint256 _delegateSeed, uint256 _voteSeed)
    public
  {
    Proposal memory _proposal = _proposeRealisticProposal(_proposalSeed);
    vm.roll(vm.getBlockNumber() + governor.votingDelay() + 1);

    address _delegate = _getMajorDelegate(_delegateSeed);
    uint8 _support = uint8(_voteSeed % 3);
    uint256 _votes = governor.getVotes(_delegate, vm.getBlockNumber() - 1);
    assertGt(_votes, 0);

    vm.prank(_delegate);
    bytes memory _params = "";
    governor.castVoteWithReasonAndParams(_proposal.proposalId, _support, "MyReason", _params);

    (uint256 _againstVotesCast, uint256 _forVotesCast, uint256 _abstainVotesCast) =
      governor.proposalVotes(_proposal.proposalId);

    assertEq(_againstVotesCast, _support == 0 ? _votes : 0);
    assertEq(_forVotesCast, _support == 1 ? _votes : 0);
    assertEq(_abstainVotesCast, _support == 2 ? _votes : 0);
  }

  function testFuzz_RevertIf_DelegateVotesTwiceViaNominalVote(
    uint256 _proposalSeed,
    uint256 _delegateSeed,
    uint256 _voteSeed
  ) public {
    Proposal memory _proposal = _proposeRealisticProposal(_proposalSeed);
    vm.roll(vm.getBlockNumber() + governor.votingDelay() + 1);

    address _delegate = _getMajorDelegate(_delegateSeed);
    uint8 _support = uint8(_voteSeed % 3);
    uint256 _votes = governor.getVotes(_delegate, vm.getBlockNumber() - 1);
    assertGt(_votes, 0);

    vm.startPrank(_delegate);
    bytes memory _params = "";
    governor.castVoteWithReasonAndParams(_proposal.proposalId, _support, "MyReason", _params);

    vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorAlreadyCastVote.selector, _delegate));
    governor.castVoteWithReasonAndParams(_proposal.proposalId, _support, "MyReason", _params);
    vm.stopPrank();
  }

  function testFuzz_CastCorrectVotesViaFlexibleVoting(
    uint256 _proposalSeed,
    uint256 _actorSeed,
    uint256 _forVotes,
    uint256 _againstVotes,
    uint256 _abstainVotes
  ) public {
    _skipToPostUpgrade();
    Proposal memory _proposal = _proposeRealisticProposal(_proposalSeed);
    vm.roll(vm.getBlockNumber() + governor.votingDelay() + 1);

    address _delegate = _getMajorDelegate(_actorSeed);
    uint256 _votes = governor.getVotes(_delegate, vm.getBlockNumber() - 1);
    _forVotes = bound(_forVotes, 0, _votes);
    _againstVotes = bound(_againstVotes, 0, _votes - _forVotes);
    _abstainVotes = bound(_abstainVotes, 0, _votes - _forVotes - _againstVotes);

    vm.prank(_delegate);
    bytes memory _params = abi.encodePacked(uint128(_againstVotes), uint128(_forVotes), uint128(_abstainVotes));
    governor.castVoteWithReasonAndParams(_proposal.proposalId, VOTE_TYPE_FRACTIONAL, "MyReason", _params);

    (uint256 _againstVotesCast, uint256 _forVotesCast, uint256 _abstainVotesCast) =
      governor.proposalVotes(_proposal.proposalId);

    assertEq(_againstVotesCast, _againstVotes);
    assertEq(_forVotesCast, _forVotes);
    assertEq(_abstainVotesCast, _abstainVotes);
  }

  function testFuzz_CorrectlyVotesTwiceViaFlexibleVoting(
    uint256 _proposalSeed,
    uint256 _actorSeed,
    uint256 _firstVote,
    uint256 _secondVote,
    uint256 _forVotes,
    uint256 _againstVotes,
    uint256 _abstainVotes
  ) public {
    _skipToPostUpgrade();
    Proposal memory _proposal = _proposeRealisticProposal(_proposalSeed);
    vm.roll(vm.getBlockNumber() + governor.votingDelay() + 1);

    address _delegate = _getMajorDelegate(_actorSeed);
    uint256 _votes = governor.getVotes(_delegate, vm.getBlockNumber() - 1);
    _firstVote = bound(_firstVote, 0, _votes - 1);
    _forVotes = bound(_forVotes, 0, _firstVote);
    _againstVotes = bound(_againstVotes, 0, _firstVote - _forVotes);
    _abstainVotes = bound(_abstainVotes, 0, _firstVote - _forVotes - _againstVotes);

    {
      vm.prank(_delegate);
      bytes memory _params = abi.encodePacked(uint128(_againstVotes), uint128(_forVotes), uint128(_abstainVotes));
      governor.castVoteWithReasonAndParams(_proposal.proposalId, VOTE_TYPE_FRACTIONAL, "MyReason", _params);

      (uint256 _againstVotesCast, uint256 _forVotesCast, uint256 _abstainVotesCast) =
        governor.proposalVotes(_proposal.proposalId);

      assertEq(_againstVotesCast, _againstVotes);
      assertEq(_forVotesCast, _forVotes);
      assertEq(_abstainVotesCast, _abstainVotes);
    }
    _secondVote = bound(_secondVote, 0, _votes - _firstVote);
    uint256 _forFirstVote = _forVotes;
    _forVotes = bound(uint256(keccak256(abi.encode(_forVotes))), 0, _secondVote);
    uint256 _againstFirstVote = _againstVotes;
    _againstVotes = bound(uint256(keccak256(abi.encode(_againstVotes))), 0, _secondVote - _forVotes);
    uint256 _abstainFirstVote = _abstainVotes;
    _abstainVotes = bound(uint256(keccak256(abi.encode(_abstainVotes))), 0, _secondVote - _forVotes - _againstVotes);

    {
      bytes memory _params = abi.encodePacked(uint128(_againstVotes), uint128(_forVotes), uint128(_abstainVotes));

      vm.prank(_delegate);
      governor.castVoteWithReasonAndParams(_proposal.proposalId, VOTE_TYPE_FRACTIONAL, "MyReason", _params);
    }
    (uint256 _againstVotesCast2, uint256 _forVotesCast2, uint256 _abstainVotesCast2) =
      governor.proposalVotes(_proposal.proposalId);

    assertEq(_againstVotesCast2, _againstFirstVote + _againstVotes);
    assertEq(_forVotesCast2, _forFirstVote + _forVotes);
    assertEq(_abstainVotesCast2, _abstainFirstVote + _abstainVotes);
  }

  // fails if voting with weight > totalWeight
  function testFuzz_RevertIf_VoteWeightGreaterThanTotalWeightViaFlexibleVoting(
    uint256 _proposalSeed,
    uint256 _actorSeed,
    uint256 _forVotes,
    uint256 _againstVotes,
    uint256 _abstainVotes,
    uint256 _sumOfVotes
  ) public {
    _skipToPostUpgrade();
    Proposal memory _proposal = _proposeRealisticProposal(_proposalSeed);
    vm.roll(vm.getBlockNumber() + governor.votingDelay() + 1);

    address _delegate = _getMajorDelegate(_actorSeed);
    uint256 _votes = governor.getVotes(_delegate, vm.getBlockNumber() - 1);
    _sumOfVotes = bound(_sumOfVotes, _votes + 1, _votes * 2);
    _forVotes = bound(_forVotes, 0, _sumOfVotes);
    _againstVotes = bound(_againstVotes, 0, _sumOfVotes - _forVotes);
    _abstainVotes = _sumOfVotes - _forVotes - _againstVotes;

    bytes memory _params = abi.encodePacked(uint128(_againstVotes), uint128(_forVotes), uint128(_abstainVotes));
    vm.expectRevert(
      abi.encodeWithSelector(
        GovernorCountingFractionalUpgradeable.GovernorExceedRemainingWeight.selector, _delegate, _sumOfVotes, _votes
      )
    );
    vm.prank(_delegate);
    governor.castVoteWithReasonAndParams(_proposal.proposalId, VOTE_TYPE_FRACTIONAL, "MyReason", _params);
  }

  // fails if voting twice with (first votes + second votes) > totalWeight
  function testFuzz_RevertIf_VotingWeightGreaterThanTwoVotesViaFlexibleVoting(
    uint256 _proposalSeed,
    uint256 _actorSeed,
    uint256 _firstVote,
    uint256 _secondVote,
    uint256 _forVotes,
    uint256 _againstVotes,
    uint256 _abstainVotes
  ) public {
    _skipToPostUpgrade();
    Proposal memory _proposal = _proposeRealisticProposal(_proposalSeed);
    vm.roll(vm.getBlockNumber() + governor.votingDelay() + 1);

    address _delegate = _getMajorDelegate(_actorSeed);
    uint256 _votes = governor.getVotes(_delegate, vm.getBlockNumber() - 1);
    _firstVote = bound(_firstVote, 0, _votes - 1);
    _forVotes = bound(_forVotes, 0, _firstVote);
    _againstVotes = bound(_againstVotes, 0, _firstVote - _forVotes);
    _abstainVotes = bound(_abstainVotes, 0, _firstVote - _forVotes - _againstVotes);

    {
      vm.prank(_delegate);
      bytes memory _params = abi.encodePacked(uint128(_againstVotes), uint128(_forVotes), uint128(_abstainVotes));
      governor.castVoteWithReasonAndParams(_proposal.proposalId, VOTE_TYPE_FRACTIONAL, "MyReason", _params);

      (uint256 _againstVotesCast, uint256 _forVotesCast, uint256 _abstainVotesCast) =
        governor.proposalVotes(_proposal.proposalId);

      assertEq(_againstVotesCast, _againstVotes);
      assertEq(_forVotesCast, _forVotes);
      assertEq(_abstainVotesCast, _abstainVotes);
    }
    uint256 _firstVoteTotal = _forVotes + _againstVotes + _abstainVotes;
    _secondVote = bound(_secondVote, _votes - _firstVoteTotal + 1, _votes * 2);
    _forVotes = bound(uint256(keccak256(abi.encode(_forVotes))), 0, _secondVote);
    _againstVotes = bound(uint256(keccak256(abi.encode(_againstVotes))), 0, _secondVote - _forVotes);
    _abstainVotes = _secondVote - _forVotes - _againstVotes;

    {
      bytes memory _params = abi.encodePacked(uint128(_againstVotes), uint128(_forVotes), uint128(_abstainVotes));

      vm.prank(_delegate);
      vm.expectRevert(
        abi.encodeWithSelector(
          GovernorCountingFractionalUpgradeable.GovernorExceedRemainingWeight.selector,
          _delegate,
          _secondVote,
          _votes - _firstVoteTotal
        )
      );
      governor.castVoteWithReasonAndParams(_proposal.proposalId, VOTE_TYPE_FRACTIONAL, "MyReason", _params);
    }
  }

  // vote first with flexible, second with nominal should pass
  function testFuzz_CastFractionalVotesThenNominalVotesViaFlexibleVoting(
    uint256 _proposalSeed,
    uint256 _actorSeed,
    uint256 _forVotes,
    uint256 _againstVotes,
    uint256 _abstainVotes,
    uint256 _voteSeed
  ) public {
    _skipToPostUpgrade();
    Proposal memory _proposal = _proposeRealisticProposal(_proposalSeed);
    vm.roll(vm.getBlockNumber() + governor.votingDelay() + 1);

    address _delegate = _getMajorDelegate(_actorSeed);
    uint256 _votes = governor.getVotes(_delegate, vm.getBlockNumber() - 1);
    _forVotes = bound(_forVotes, 0, _votes - 1);
    _againstVotes = bound(_againstVotes, 0, _votes - 1 - _forVotes);
    _abstainVotes = bound(_abstainVotes, 0, _votes - 1 - _forVotes - _againstVotes);

    vm.prank(_delegate);
    bytes memory _params = abi.encodePacked(uint128(_againstVotes), uint128(_forVotes), uint128(_abstainVotes));
    governor.castVoteWithReasonAndParams(_proposal.proposalId, VOTE_TYPE_FRACTIONAL, "MyReason", _params);

    (uint256 _againstVotesCast, uint256 _forVotesCast, uint256 _abstainVotesCast) =
      governor.proposalVotes(_proposal.proposalId);

    assertEq(_againstVotesCast, _againstVotes);
    assertEq(_forVotesCast, _forVotes);
    assertEq(_abstainVotesCast, _abstainVotes);

    // Nominal Votes
    uint8 _support = uint8(_voteSeed % 3);
    vm.prank(_delegate);
    _params = "";
    governor.castVoteWithReasonAndParams(_proposal.proposalId, _support, "MyReason", _params);

    (_againstVotesCast, _forVotesCast, _abstainVotesCast) = governor.proposalVotes(_proposal.proposalId);
    assertEq(_againstVotesCast, _support == 0 ? _votes - _forVotes - _abstainVotes : _againstVotes);
    assertEq(_forVotesCast, _support == 1 ? _votes - _againstVotes - _abstainVotes : _forVotes);
    assertEq(_abstainVotesCast, _support == 2 ? _votes - _againstVotes - _forVotes : _abstainVotes);
  }

  function testFuzz_ProposalSucceedsAfterFractionalVotes(uint256 _proposalSeed) public {
    _skipToPostUpgrade();
    Proposal memory _proposal = _proposeRealisticProposal(_proposalSeed);
    vm.roll(vm.getBlockNumber() + governor.votingDelay() + 1);

    uint256 _totalForVotes;
    for (uint256 i; i < _majorDelegates.length; i++) {
      address _delegate = _majorDelegates[i];
      uint256 _votes = governor.getVotes(_delegate, vm.getBlockNumber() - 1);
      uint256 _forVotes = _votes;
      uint256 _againstVotes = 0;
      uint256 _abstainVotes = 0;

      vm.prank(_delegate);
      bytes memory _params = abi.encodePacked(uint128(_againstVotes), uint128(_forVotes), uint128(_abstainVotes));
      governor.castVoteWithReasonAndParams(_proposal.proposalId, VOTE_TYPE_FRACTIONAL, "MyReason", _params);
      _totalForVotes += _forVotes;
    }

    (uint256 _againstVotesCast, uint256 _forVotesCast, uint256 _abstainVotesCast) =
      governor.proposalVotes(_proposal.proposalId);
    assertEq(_forVotesCast, _totalForVotes);
    assertEq(_againstVotesCast, 0);
    assertEq(_abstainVotesCast, 0);

    vm.roll(vm.getBlockNumber() + governor.votingPeriod() + 1);
    assertEq(uint8(governor.state(_proposal.proposalId)), uint8(ProposalState.Succeeded));
  }

  // should move a proposal to succeeded via only flexible voting
  function testFuzz_ProposalFailsAfterFractionalVotes(uint256 _proposalSeed) public {
    _skipToPostUpgrade();
    Proposal memory _proposal = _proposeRealisticProposal(_proposalSeed);
    vm.roll(vm.getBlockNumber() + governor.votingDelay() + 1);

    uint256 _totalAgainstVotes;
    for (uint256 i; i < _majorDelegates.length; i++) {
      address _delegate = _majorDelegates[i];
      uint256 _votes = governor.getVotes(_delegate, vm.getBlockNumber() - 1);
      uint256 _forVotes = 0;
      uint256 _againstVotes = _votes;
      uint256 _abstainVotes = 0;

      vm.prank(_delegate);
      bytes memory _params = abi.encodePacked(uint128(_againstVotes), uint128(_forVotes), uint128(_abstainVotes));
      governor.castVoteWithReasonAndParams(_proposal.proposalId, VOTE_TYPE_FRACTIONAL, "MyReason", _params);
      _totalAgainstVotes += _againstVotes;
    }

    (uint256 _againstVotesCast, uint256 _forVotesCast, uint256 _abstainVotesCast) =
      governor.proposalVotes(_proposal.proposalId);
    assertEq(_forVotesCast, 0);
    assertEq(_againstVotesCast, _totalAgainstVotes);
    assertEq(_abstainVotesCast, 0);

    vm.roll(vm.getBlockNumber() + governor.votingPeriod() + 1);
    assertEq(uint8(governor.state(_proposal.proposalId)), uint8(ProposalState.Defeated));
  }
}

abstract contract Queue is L2ArbitrumGovernorV2Test {
  function testFuzz_QueuesAWinningProposalAfterUpgrade(uint256 _proposalSeed) public {
    _skipToPostUpgrade();
    Proposal memory _proposal = _proposeRealisticProposal(_proposalSeed);
    vm.roll(vm.getBlockNumber() + governor.votingDelay() + 1);

    _voteForProposal(_proposal.proposalId, VoteType.For);
    vm.roll(vm.getBlockNumber() + governor.votingPeriod() + 1);

    governor.queue(_proposal.targets, _proposal.values, _proposal.calldatas, keccak256(bytes(_proposal.description)));
    vm.assertEq(uint256(governor.state(_proposal.proposalId)), uint256(ProposalState.Queued));
  }

  function testFuzz_RevertIf_QueuesAWinningProposalBeforeUpgrade(uint256 _proposalSeed) public {
    Proposal memory _proposal = _proposeRealisticProposal(_proposalSeed);
    vm.roll(vm.getBlockNumber() + governor.votingDelay() + 1);

    _voteForProposal(_proposal.proposalId, VoteType.For);
    vm.roll(vm.getBlockNumber() + governor.votingPeriod() + 1);

    vm.expectRevert(
      abi.encodePacked(
        "AccessControl: account ",
        Strings.toHexString(uint160(address(governor)), 20),
        " is missing role ",
        Strings.toHexString(uint256(TIMELOCK_PROPOSER_ROLE), 32)
      )
    );
    governor.queue(_proposal.targets, _proposal.values, _proposal.calldatas, keccak256(bytes(_proposal.description)));
  }
}

abstract contract Execute is L2ArbitrumGovernorV2Test {
  function testFuzz_ExecutesAQueuedProposalAfterUpgrade(uint256 _proposalSeed) public {
    _skipToPostUpgrade();

    // Propose
    Proposal memory _proposal = _proposeRealisticProposal(_proposalSeed);
    vm.roll(vm.getBlockNumber() + governor.votingDelay() + 1);

    // Vote
    _voteForProposal(_proposal.proposalId, VoteType.For);
    vm.roll(vm.getBlockNumber() + governor.votingPeriod() + 1);

    // Queue
    governor.queue(_proposal.targets, _proposal.values, _proposal.calldatas, keccak256(bytes(_proposal.description)));
    vm.warp(vm.getBlockTimestamp() + timelock.getMinDelay() + 1);

    // Execute
    governor.execute(_proposal.targets, _proposal.values, _proposal.calldatas, keccak256(bytes(_proposal.description)));
    assertEq(uint256(governor.state(_proposal.proposalId)), uint256(IGovernor.ProposalState.Executed));
  }
}

abstract contract Cancel is L2ArbitrumGovernorV2Test {
  event ProposalCanceled(uint256 proposalId);

  error GovernorOnlyProposer(address proposer);
  error ProposalNotPending(IGovernor.ProposalState state);

  function testFuzz_CancelsPendingProposal(uint256 _actorSeed) public virtual {
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

  function testFuzz_RevertIf_NotProposer(uint256 _actorSeed, address _actor) public {
    address _proposer = _getMajorDelegate(_actorSeed);
    vm.assume(_actor != _proposer && _actor != PROXY_ADMIN_CONTRACT);
    address[] memory targets = new address[](1);
    uint256[] memory values = new uint256[](1);
    bytes[] memory calldatas = new bytes[](1);
    string memory description = "Test";

    vm.prank(_proposer);
    governor.propose(targets, values, calldatas, description);

    vm.prank(address(_actor));
    vm.expectRevert(abi.encodeWithSelector(GovernorOnlyProposer.selector, _actor));
    governor.cancel(targets, values, calldatas, keccak256(bytes(description)));
  }

  function testFuzz_RevertIf_ProposalIsActive(uint256 _actorSeed) public {
    address[] memory targets = new address[](1);
    uint256[] memory values = new uint256[](1);
    bytes[] memory calldatas = new bytes[](1);
    string memory description = "Test";
    address _actor = _getMajorDelegate(_actorSeed);

    vm.prank(_actor);
    uint256 proposalId = governor.propose(targets, values, calldatas, description);
    vm.roll(vm.getBlockNumber() + governor.votingDelay() + 1);

    vm.prank(_actor);
    vm.expectRevert(abi.encodeWithSelector(ProposalNotPending.selector, IGovernor.ProposalState.Active));
    governor.cancel(targets, values, calldatas, keccak256(bytes(description)));
    assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));
  }
}

contract MockOneOffUpgrader {
  function perform() public pure {}
}

// ----------------------------------------------------------------------------------------------------------------- //
// Concrete Test Contracts - Inherit from each abstract test and implement concrete methods for Core & Treasury case
// ----------------------------------------------------------------------------------------------------------------- //

contract CoreGovernorInitialize is CoreGovernorBase, Initialize {
  function setUp() public override(L2ArbitrumGovernorV2Test, CoreGovernorBase) {
    super.setUp();
  }
}

contract CoreGovernorRelay is CoreGovernorBase, Relay {
  function setUp() public override(L2ArbitrumGovernorV2Test, CoreGovernorBase) {
    super.setUp();
  }
}

contract CoreGovernorQuorum is CoreGovernorBase, Quorum {
  function setUp() public override(L2ArbitrumGovernorV2Test, CoreGovernorBase) {
    super.setUp();
  }
}

contract CoreGovernorPropose is CoreGovernorBase, Propose {
  function setUp() public override(L2ArbitrumGovernorV2Test, CoreGovernorBase) {
    super.setUp();
  }
}

contract CoreGovernorCastVote is CoreGovernorBase, CastVote {
  function setUp() public override(L2ArbitrumGovernorV2Test, CoreGovernorBase) {
    super.setUp();
  }
}

contract CoreGovernorHasVoted is CoreGovernorBase, CastVoteWithReasonAndParams {
  function setUp() public override(L2ArbitrumGovernorV2Test, CoreGovernorBase) {
    super.setUp();
  }
}

contract CoverGovernorQueue is CoreGovernorBase, Queue {
  function setUp() public override(L2ArbitrumGovernorV2Test, CoreGovernorBase) {
    super.setUp();
  }
}

contract CoreGovernorCancel is CoreGovernorBase, Cancel {
  function setUp() public override(L2ArbitrumGovernorV2Test, CoreGovernorBase) {
    super.setUp();
  }
}

contract CoreGovernorExecute is CoreGovernorBase, Execute {
  function setUp() public override(L2ArbitrumGovernorV2Test, CoreGovernorBase) {
    super.setUp();
  }
}

contract TreasuryGovernorInitialize is TreasuryGovernorBase, Initialize {
  function setUp() public override(L2ArbitrumGovernorV2Test, TreasuryGovernorBase) {
    super.setUp();
  }
}

contract TreasuryGovernorRelay is TreasuryGovernorBase, Relay {
  function setUp() public override(L2ArbitrumGovernorV2Test, TreasuryGovernorBase) {
    super.setUp();
  }
}

contract TreasuryGovernorQuorum is TreasuryGovernorBase, Quorum {
  function setUp() public override(L2ArbitrumGovernorV2Test, TreasuryGovernorBase) {
    super.setUp();
  }
}

contract TreasuryGovernorPropose is TreasuryGovernorBase, Propose {
  function setUp() public override(L2ArbitrumGovernorV2Test, TreasuryGovernorBase) {
    super.setUp();
  }
}

contract TreasuryGovernorCastVote is TreasuryGovernorBase, CastVote {
  function setUp() public override(L2ArbitrumGovernorV2Test, TreasuryGovernorBase) {
    super.setUp();
  }
}

contract TreasuryGovernorHasVoted is TreasuryGovernorBase, CastVoteWithReasonAndParams {
  function setUp() public override(L2ArbitrumGovernorV2Test, TreasuryGovernorBase) {
    super.setUp();
  }
}

contract TreasuryGovernorQueue is TreasuryGovernorBase, Queue {
  function setUp() public override(L2ArbitrumGovernorV2Test, TreasuryGovernorBase) {
    super.setUp();
  }
}

contract TreasuryGovernorExecute is TreasuryGovernorBase, Execute {
  function setUp() public override(L2ArbitrumGovernorV2Test, TreasuryGovernorBase) {
    super.setUp();
  }
}

contract TreasuryGovernorCancel is TreasuryGovernorBase, Cancel {
  function setUp() public override(L2ArbitrumGovernorV2Test, TreasuryGovernorBase) {
    super.setUp();
  }
}
