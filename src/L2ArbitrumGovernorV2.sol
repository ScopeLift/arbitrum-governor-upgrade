// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {GovernorUpgradeable} from "openzeppelin-upgradeable/governance/GovernorUpgradeable.sol";
import {GovernorSettingsUpgradeable} from
  "openzeppelin-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import {GovernorCountingFractionalUpgradeable} from
  "src/lib/governance/extensions/GovernorCountingFractionalUpgradeable.sol";
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
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract L2ArbitrumGovernorV2 is
  Initializable,
  GovernorSettingsUpgradeable,
  GovernorCountingFractionalUpgradeable,
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
    __GovernorCountingFractional_init();
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

  /// @notice Allows the owner to make calls from the governor
  /// @dev    We want the owner to be able to upgrade settings and parameters on this Governor
  ///         however we can't use onlyGovernance as it requires calls originate from the governor
  ///         contract. The normal flow for onlyGovernance to work is to call execute on the governor
  ///         which will then call out to the _executor(), which will then call back in to the governor to set
  ///         a parameter. At the point of setting the parameter onlyGovernance is checked, and this includes
  ///         a check this call originated in the execute() function. The purpose of this is an added
  ///         safety measure that ensure that all calls originate at the governor, and if second entrypoint is
  ///         added to the _executor() contract, that new entrypoint will not be able to pass the onlyGovernance check.
  ///         You can read more about this in the comments on onlyGovernance()
  ///         This flow doesn't work for Arbitrum governance as we require an proposal on L2 to first
  ///         be relayed to L1, and then back again to L2 before calling into the governor to update
  ///         settings. This means that updating settings can't be done in a single transaction.
  ///         There are two potential solutions to this problem:
  ///         1.  Use a more persistent record that a specific upgrade is taking place. This adds
  ///             a lot of complexity, as we have multiple layers of calldata wrapping each other to
  ///             define the multiple transactions that occur in a round-trip upgrade. So safely recording
  ///             execution of the would be difficult and brittle.
  ///         2.  Override this protection and just ensure elsewhere that the executor only has the
  ///             the correct entrypoints and access control. We've gone for this option.
  ///         By overriding the relay function we allow the executor to make any call originating
  ///         from the governor, and by setting the _executor() to be the governor itself we can use the
  ///         relay function to call back into the governor to update settings e.g:
  ///
  ///         l2ArbitrumGovernor.relay(
  ///             address(l2ArbitrumGovernor),
  ///             0,
  ///             abi.encodeWithSelector(l2ArbitrumGovernor.updateQuorumNumerator.selector, 4)
  ///         );
  function relay(address target, uint256 value, bytes calldata data) external payable virtual override onlyOwner {
    Address.functionCallWithValue(target, data, value);
  }

  /// @notice returns l2 executor address; used internally for onlyGovernance check
  function _executor()
    internal
    view
    override(GovernorTimelockControlUpgradeable, GovernorUpgradeable)
    returns (address)
  {
    return address(this);
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
