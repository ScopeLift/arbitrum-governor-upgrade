// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {GovernorUpgradeable} from "openzeppelin-upgradeable/governance/GovernorUpgradeable.sol";
import {GovernorSettingsUpgradeable} from
  "openzeppelin-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import {GovernorCountingSimpleUpgradeable} from
  "openzeppelin-upgradeable/governance/extensions/GovernorCountingSimpleUpgradeable.sol";
import {GovernorTimelockControlUpgradeable} from
  "openzeppelin-upgradeable/governance/extensions/GovernorTimelockControlUpgradeable.sol";
import {GovernorVotesQuorumFractionUpgradeable} from
  "openzeppelin-upgradeable/governance/extensions/GovernorVotesQuorumFractionUpgradeable.sol";
import {GovernorPreventLateQuorumUpgradeable} from
  "openzeppelin-upgradeable/governance/extensions/GovernorPreventLateQuorumUpgradeable.sol";
import {GovernorVotesUpgradeable} from "openzeppelin-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import {TimelockControllerUpgradeable} from "openzeppelin-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {IVotes} from "openzeppelin/governance/utils/IVotes.sol";

contract L2ArbitrumGovernorV2 is
  Initializable,
  GovernorSettingsUpgradeable,
  GovernorCountingSimpleUpgradeable,
  GovernorVotesUpgradeable,
  GovernorTimelockControlUpgradeable,
  GovernorVotesQuorumFractionUpgradeable,
  GovernorPreventLateQuorumUpgradeable,
  OwnableUpgradeable
{
  constructor() {
    _disableInitializers();
  }

  function initialize(
    string memory _name,
    uint48 _initialVotingDelay,
    uint32 _initialVotingPeriod,
    uint256 _initialProposalThreshold,
    IVotes _arbAddress,
    TimelockControllerUpgradeable _timelockAddress,
    uint256 _quorumNumeratorValue,
    uint48 _initialVoteExtension,
    address _initialOwner
  ) public initializer {
    __Governor_init(_name);
    __GovernorSettings_init(_initialVotingDelay, _initialVotingPeriod, _initialProposalThreshold);
    __GovernorCountingSimple_init();
    __GovernorVotes_init(_arbAddress);
    __GovernorTimelockControl_init(_timelockAddress);
    __GovernorVotesQuorumFraction_init(_quorumNumeratorValue);
    __GovernorPreventLateQuorum_init(_initialVoteExtension);
    __Ownable_init(_initialOwner);
  }

  /// @inheritdoc GovernorVotesQuorumFractionUpgradeable
  function quorumDenominator() public pure override(GovernorVotesQuorumFractionUpgradeable) returns (uint256) {
    // update to 10k to allow for higher precision
    return 10_000;
  }

  function proposalDeadline(uint256 _proposalId)
    public
    view
    virtual
    override(GovernorPreventLateQuorumUpgradeable, GovernorUpgradeable)
    returns (uint256)
  {
    return GovernorPreventLateQuorumUpgradeable.proposalDeadline(_proposalId);
  }

  function proposalNeedsQueuing(uint256 _proposalId)
    public
    view
    virtual
    override(GovernorTimelockControlUpgradeable, GovernorUpgradeable)
    returns (bool)
  {
    return GovernorTimelockControlUpgradeable.proposalNeedsQueuing(_proposalId);
  }

  function proposalThreshold()
    public
    view
    virtual
    override(GovernorSettingsUpgradeable, GovernorUpgradeable)
    returns (uint256)
  {
    return GovernorSettingsUpgradeable.proposalThreshold();
  }

  function state(uint256 _proposalId)
    public
    view
    virtual
    override(GovernorTimelockControlUpgradeable, GovernorUpgradeable)
    returns (ProposalState)
  {
    return GovernorTimelockControlUpgradeable.state(_proposalId);
  }

  function _castVote(uint256 _proposalId, address _account, uint8 _support, string memory _reason, bytes memory _params)
    internal
    virtual
    override(GovernorPreventLateQuorumUpgradeable, GovernorUpgradeable)
    returns (uint256)
  {
    return GovernorPreventLateQuorumUpgradeable._castVote(_proposalId, _account, _support, _reason, _params);
  }

  function _cancel(
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    bytes32 _descriptionHash
  ) internal virtual override(GovernorTimelockControlUpgradeable, GovernorUpgradeable) returns (uint256) {
    return GovernorTimelockControlUpgradeable._cancel(_targets, _values, _calldatas, _descriptionHash);
  }

  function _queueOperations(
    uint256 _proposalId,
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    bytes32 _descriptionHash
  ) internal virtual override(GovernorTimelockControlUpgradeable, GovernorUpgradeable) returns (uint48) {
    return
      GovernorTimelockControlUpgradeable._queueOperations(_proposalId, _targets, _values, _calldatas, _descriptionHash);
  }

  function _executor()
    internal
    view
    virtual
    override(GovernorTimelockControlUpgradeable, GovernorUpgradeable)
    returns (address)
  {
    return GovernorTimelockControlUpgradeable._executor();
  }

  function _executeOperations(
    uint256 _proposalId,
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    bytes32 _descriptionHash
  ) internal virtual override(GovernorTimelockControlUpgradeable, GovernorUpgradeable) {
    return GovernorTimelockControlUpgradeable._executeOperations(
      _proposalId, _targets, _values, _calldatas, _descriptionHash
    );
  }
}
