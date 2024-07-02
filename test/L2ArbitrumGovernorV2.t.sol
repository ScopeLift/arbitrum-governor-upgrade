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
import {CreateProposal} from "script/helpers/CreateProposal.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {TimelockRolesUpgrader} from "src/gov-action-contracts/TimelockRolesUpgrader.sol";
import {SubmitUpgradeProposalScript} from "script/SubmitUpgradeProposalScript.s.sol";
import {SetupNewGovernors} from "test/helpers/SetupNewGovernors.sol";

// import {ProposalBuilder} from "test/helpers/ProposalBuilder.sol";

// ----------------------------------------------------------------------------------------------------------------- //
// Test Suite Base - Shared values, setup, helpers, and virtual methods needed by concrete test contracts
// ----------------------------------------------------------------------------------------------------------------- //

struct Proposal {
  address[] targets;
  uint256[] values;
  bytes[] calldatas;
  string description;
}

abstract contract L2ArbitrumGovernorV2Test is SetupNewGovernors {
  /// @dev Proxy admin contract deployed in construction of TransparentUpgradeableProxy
  address PROXY_ADMIN_CONTRACT;
  L2ArbitrumGovernorV2 governor;
  TimelockControllerUpgradeable timelock;
  BaseGovernorDeployer proxyDeployer;
  ERC20VotesUpgradeable arbitrumToken;
  ERC20Mock mockToken;
  CreateProposal createProposalHelper;

  function setUp() public virtual override {
    super.setUp();
    createProposalHelper = new CreateProposal();
    arbitrumToken = ERC20VotesUpgradeable(ARB_TOKEN_ADDRESS);
    mockToken = new ERC20Mock();
  }

  function _getMajorDelegate(uint256 _actorSeed) public view returns (address) {
    return _majorDelegates[_actorSeed % _majorDelegates.length];
  }

  function _proposeRealisticProposal(uint256 _randomSeed)
    internal
    virtual
    returns (
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldatas,
      string memory _description,
      uint256 _proposalId
    );

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

abstract contract CoreGovernorTest is L2ArbitrumGovernorV2Test {
  function setUp() public virtual override {
    super.setUp();
    /// Proxy admin contract deployed in construction of TransparentUpgradeableProxy -- getter is internal so we
    /// hardcode the address
    PROXY_ADMIN_CONTRACT = 0x740f24A3cbF1fbA1226C6018511F96d1055ce961;
    governor = newCoreGovernor;
    timelock = currentCoreTimelock;
    proxyDeployer = proxyCoreGovernorDeployer;
  }

  function _proposeRealisticProposal(uint256 _randomSeed)
    internal
    override
    returns (
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldatas,
      string memory _description,
      uint256 _proposalId
    )
  {
    Proposal[] memory _proposals = new Proposal[](2);
    uint256 _switch = _randomSeed % _proposals.length;
    if (_switch == 0) {
      // one type of realistic proposal would be to use ArbSys to do something via L2 UpgradeExecutor
    } else if (_switch == 1) {
      // another type of realistic proposal would be to use ArbSys to do something on L1 UpgradeExecutor
    }
  }
}

abstract contract TreasuryGovernorTest is L2ArbitrumGovernorV2Test {
  function setUp() public virtual override {
    super.setUp();
    // Proxy admin contract deployed in construction of TransparentUpgradeableProxy -- getter is internal so we hardcode
    // the address
    PROXY_ADMIN_CONTRACT = 0xD3fe9b9cc02F23B3e3b43CF80700d8C7cf178339;
    governor = newTreasuryGovernor;
    timelock = currentTreasuryTimelock;
    proxyDeployer = proxyTreasuryGovernorDeployer;
  }

  function _proposeRealisticProposal(uint256 _randomSeed)
    internal
    override
    returns (
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldatas,
      string memory _description,
      uint256 _proposalId
    )
  {
    Proposal[] memory _proposals = new Proposal[](2);
    uint256 _switch = _randomSeed % _proposals.length;
    if (_switch == 0) {
      // one type of realistic proposal would be to use ArbSys to do something via L2 UpgradeExecutor
    } else if (_switch == 1) {
      // another type of realistic proposal would be to use ArbSys to do something on L1 UpgradeExecutor
    }
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

    (address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas) =
      createProposalHelper.createCoreProposal(_description, address(_oneOffUpgrader), L1_TIMELOCK_MIN_DELAY);

    vm.startPrank(_actor);
    vm.expectRevert(
      abi.encodeWithSelector(
        GovernorInsufficientProposerVotes.selector, _actor, _actorVotes, governor.proposalThreshold()
      )
    );
    governor.propose(_targets, _values, _calldatas, _description);
    vm.stopPrank();
  }

  function testFuzz_RevertIf_ProposalAlreadyCreated(
    uint256 _actorSeed,
    MockOneOffUpgrader _oneOffUpgrader,
    string memory _description
  ) public {
    (address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas) =
      createProposalHelper.createCoreProposal(_description, address(_oneOffUpgrader), L1_TIMELOCK_MIN_DELAY);
    uint256 _proposalId = governor.hashProposal(_targets, _values, _calldatas, keccak256(bytes(_description)));

    vm.startPrank(_getMajorDelegate(_actorSeed));
    governor.propose(_targets, _values, _calldatas, _description);
    vm.expectRevert(
      abi.encodeWithSelector(GovernorUnexpectedProposalState.selector, _proposalId, ProposalState.Pending, 0)
    );
    governor.propose(_targets, _values, _calldatas, _description);
    vm.stopPrank();
  }
}

abstract contract CastVoteOnCoreGovernor is L2ArbitrumGovernorV2Test {
  function _proposeACoreProposal(uint256 _actorSeed, address _oneOffUpgrader, string memory _description)
    internal
    returns (uint256 _proposalId)
  {
    (address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas) =
      createProposalHelper.createCoreProposal(_description, _oneOffUpgrader, L1_TIMELOCK_MIN_DELAY);

    vm.startPrank(_getMajorDelegate(_actorSeed));
    _proposalId = governor.propose(_targets, _values, _calldatas, _description);
    vm.stopPrank();
  }

  function testFuzz_ProposalVoteSuccess(
    uint256 _actorSeed,
    MockOneOffUpgrader _oneOffUpgrader,
    string memory _description
  ) public {
    uint256 _proposalId = _proposeACoreProposal(_actorSeed, address(_oneOffUpgrader), _description);

    vm.roll(vm.getBlockNumber() + governor.votingDelay() + 1);
    assertEq(uint256(governor.state(_proposalId)), uint256(IGovernor.ProposalState.Active));

    // Vote For
    for (uint256 i; i < _majorDelegates.length; i++) {
      vm.prank(_majorDelegates[i]);
      governor.castVote(_proposalId, uint8(VoteType.For));
    }

    vm.roll(vm.getBlockNumber() + governor.votingPeriod() + 1);
    vm.assertEq(uint256(governor.state(_proposalId)), uint256(ProposalState.Succeeded));
  }

  function testFuzz_ProposalVoteDefeat(
    uint256 _actorSeed,
    MockOneOffUpgrader _oneOffUpgrader,
    string memory _description
  ) public {
    uint256 _proposalId = _proposeACoreProposal(_actorSeed, address(_oneOffUpgrader), _description);

    vm.roll(vm.getBlockNumber() + governor.votingDelay() + 1);
    assertEq(uint256(governor.state(_proposalId)), uint256(ProposalState.Active));

    // Vote Against
    for (uint256 i; i < _majorDelegates.length; i++) {
      vm.prank(_majorDelegates[i]);
      governor.castVote(_proposalId, uint8(VoteType.Against));
    }

    vm.roll(vm.getBlockNumber() + governor.votingPeriod() + 1);
    vm.assertEq(uint256(governor.state(_proposalId)), uint256(ProposalState.Defeated));
  }
}

abstract contract CastVoteOnTreasuryGovernor is L2ArbitrumGovernorV2Test {
  function _proposeATreasuryProposal(uint256 _actorSeed, address _to, uint256 _amount)
    internal
    returns (uint256 _proposalId)
  {
    _amount = bound(_amount, 0, arbitrumToken.balanceOf(DAO_TREASURY));
    string memory _description = "Transfer to random address";
    (address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas) =
      createProposalHelper.createTreasuryProposalForSingleTransfer(ARB_TOKEN_ADDRESS, _to, _amount);

    vm.startPrank(_getMajorDelegate(_actorSeed));
    _proposalId = governor.propose(_targets, _values, _calldatas, _description);
    vm.stopPrank();
  }

  function testFuzz_ProposalVoteSuccess(uint256 _actorSeed, address _to, uint256 _amount) public {
    uint256 _proposalId = _proposeATreasuryProposal(_actorSeed, _to, _amount);

    vm.roll(vm.getBlockNumber() + governor.votingDelay() + 1);
    assertEq(uint256(governor.state(_proposalId)), uint256(ProposalState.Active));

    // Vote For
    for (uint256 i; i < _majorDelegates.length; i++) {
      vm.prank(_majorDelegates[i]);
      governor.castVote(_proposalId, uint8(VoteType.For));
    }

    vm.roll(vm.getBlockNumber() + governor.votingPeriod() + 1);
    vm.assertEq(uint256(governor.state(_proposalId)), uint256(ProposalState.Succeeded));
  }

  function testFuzz_ProposalVoteDefeat(uint256 _actorSeed, address _to, uint256 _amount) public {
    uint256 _proposalId = _proposeATreasuryProposal(_actorSeed, _to, _amount);

    vm.roll(vm.getBlockNumber() + governor.votingDelay() + 1);
    assertEq(uint256(governor.state(_proposalId)), uint256(ProposalState.Active));

    // Vote Against
    for (uint256 i; i < _majorDelegates.length; i++) {
      vm.prank(_majorDelegates[i]);
      governor.castVote(_proposalId, uint8(VoteType.Against));
    }

    vm.roll(vm.getBlockNumber() + governor.votingPeriod() + 1);
    vm.assertEq(uint256(governor.state(_proposalId)), uint256(ProposalState.Defeated));
  }
}

abstract contract Queue is L2ArbitrumGovernorV2Test {
  function test_QueuesAWinningProposalAfterUpgrade() public {
    _skipToPostUpgrade();
    (
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description,
      uint256 _proposalId
    ) = _proposeTestProposal();
    vm.roll(vm.getBlockNumber() + governor.votingDelay() + 1);

    _voteForProposal(_proposalId, VoteType.For);
    vm.roll(vm.getBlockNumber() + governor.votingPeriod() + 1);

    governor.queue(targets, values, calldatas, keccak256(bytes(description)));
    vm.assertEq(uint256(governor.state(_proposalId)), uint256(ProposalState.Queued));
  }

  function test_RevertIf_QueuesAWinningProposalBeforeUpgrade() public {
    (
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description,
      uint256 _proposalId
    ) = _proposeTestProposal();
    vm.roll(vm.getBlockNumber() + governor.votingDelay() + 1);

    _voteForProposal(_proposalId, VoteType.For);
    vm.roll(vm.getBlockNumber() + governor.votingPeriod() + 1);

    vm.expectRevert(
      abi.encodePacked(
        "AccessControl: account ",
        Strings.toHexString(uint160(address(governor)), 20),
        " is missing role ",
        Strings.toHexString(uint256(PROPOSER_ROLE), 32)
      )
    );
    governor.queue(targets, values, calldatas, keccak256(bytes(description)));
  }
}

abstract contract Execute is L2ArbitrumGovernorV2Test {
  function test_ExecutesAQueuedProposalAfterUpgrade() public {
    _skipToPostUpgrade();

    // Propose
    (
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldatas,
      string memory _description,
      uint256 _proposalId
    ) = _proposeTestProposal();
    vm.roll(vm.getBlockNumber() + governor.votingDelay() + 1);

    // Vote
    _voteForProposal(_proposalId, VoteType.For);
    vm.roll(vm.getBlockNumber() + governor.votingPeriod() + 1);

    // Queue
    governor.queue(_targets, _values, _calldatas, keccak256(bytes(_description)));
    vm.warp(vm.getBlockTimestamp() + timelock.getMinDelay() + 1);

    // Execute
    governor.execute(_targets, _values, _calldatas, keccak256(bytes(_description)));
    assertEq(uint256(governor.state(_proposalId)), uint256(IGovernor.ProposalState.Executed));
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

contract CoreGovernorInitialize is CoreGovernorTest, Initialize {
  function setUp() public override(L2ArbitrumGovernorV2Test, CoreGovernorTest) {
    super.setUp();
  }
}

contract CoreGovernorRelay is CoreGovernorTest, Relay {
  function setUp() public override(L2ArbitrumGovernorV2Test, CoreGovernorTest) {
    super.setUp();
  }
}

contract CoreGovernorQuorum is CoreGovernorTest, Quorum {
  function setUp() public override(L2ArbitrumGovernorV2Test, CoreGovernorTest) {
    super.setUp();
  }
}

contract CoreGovernorPropose is CoreGovernorTest, Propose {
  function setUp() public override(L2ArbitrumGovernorV2Test, CoreGovernorTest) {
    super.setUp();
  }
}

contract CoreGovernorCastVote is CoreGovernorTest, CastVoteOnCoreGovernor {
  function setUp() public override(L2ArbitrumGovernorV2Test, CoreGovernorTest) {
    super.setUp();
  }
}

contract CoverGovernorQueue is CoreGovernorTest, Queue {
  function setUp() public override(L2ArbitrumGovernorV2Test, CoreGovernorTest) {
    super.setUp();
  }
}

contract CoreGovernorCancel is CoreGovernorTest, Cancel {
  function setUp() public override(L2ArbitrumGovernorV2Test, CoreGovernorTest) {
    super.setUp();
  }
}

contract CoreGovernorExecute is CoreGovernorTest, Execute {
  function setUp() public override(L2ArbitrumGovernorV2Test, CoreGovernorTest) {
    super.setUp();
  }
}

contract TreasuryGovernorInitialize is TreasuryGovernorTest, Initialize {
  function setUp() public override(L2ArbitrumGovernorV2Test, TreasuryGovernorTest) {
    super.setUp();
  }
}

contract TreasuryGovernorRelay is TreasuryGovernorTest, Relay {
  function setUp() public override(L2ArbitrumGovernorV2Test, TreasuryGovernorTest) {
    super.setUp();
  }
}

contract TreasuryGovernorQuorum is TreasuryGovernorTest, Quorum {
  function setUp() public override(L2ArbitrumGovernorV2Test, TreasuryGovernorTest) {
    super.setUp();
  }
}

contract TreasuryGovernorPropose is TreasuryGovernorTest, Propose {
  function setUp() public override(L2ArbitrumGovernorV2Test, TreasuryGovernorTest) {
    super.setUp();
  }
}

contract TreasuryGovernorVote is TreasuryGovernorTest, CastVoteOnTreasuryGovernor {
  function setUp() public override(L2ArbitrumGovernorV2Test, TreasuryGovernorTest) {
    super.setUp();
  }
}

contract TreasuryGovernorQueue is TreasuryGovernorTest, Queue {
  function setUp() public override(L2ArbitrumGovernorV2Test, TreasuryGovernorTest) {
    super.setUp();
  }
}

contract TreasuryGovernorExecute is TreasuryGovernorTest, Execute {
  function setUp() public override(L2ArbitrumGovernorV2Test, TreasuryGovernorTest) {
    super.setUp();
  }
}

contract TreasuryGovernorCancel is TreasuryGovernorTest, Cancel {
  function setUp() public override(L2ArbitrumGovernorV2Test, TreasuryGovernorTest) {
    super.setUp();
  }
}
