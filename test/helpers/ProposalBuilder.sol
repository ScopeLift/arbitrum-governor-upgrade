// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

contract ProposalBuilder {
  address[] private _targets;
  uint256[] private _values;
  bytes[] private _calldatas;

  function add(address _target, uint256 _value, bytes memory _calldata) public {
    _targets.push(_target);
    _values.push(_value);
    _calldatas.push(_calldata);
  }

  function targets() public view returns (address[] memory) {
    return _targets;
  }

  function values() public view returns (uint256[] memory) {
    return _values;
  }

  function calldatas() public view returns (bytes[] memory) {
    return _calldatas;
  }
}
