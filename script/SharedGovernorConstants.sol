// SPDX-License-Identifier: AGPL-3.0-only
// slither-disable-start reentrancy-benign

pragma solidity 0.8.26;

// Inheritable extension holding governor deployment constants that are shared between the Core Governor and the
// Treasury Governor. These should be carefully checked and reviewed before final deployment.
contract SharedGovernorConstants {
  address public constant PROXY_ADMIN = address(0x123);
  address public constant GOVERNOR_OWNER = 0xCF57572261c7c2BCF21ffD220ea7d1a27D40A827; // Arb One Upgrade Executor
  address public constant ARB_TOKEN_ADDRESS = 0x912CE59144191C1204E64559FE8253a0e49E6548;

  // These values match the current production values for both governors. Note that they are expressed in L1 blocks,
  // with an assumed 12 second block time, because on Arbitrum, block.number returns the number of the L1.
  uint48 public constant INITIAL_VOTING_DELAY = 21_600; // 3 days
  uint32 public constant INITIAL_VOTING_PERIOD = 100_800; // 14 days
  uint48 public constant INITIAL_VOTE_EXTENSION = 14_400; // 2 days

  // This value matches the current production value for both governors. 1M Arb in raw decimals.
  uint256 public constant INITIAL_PROPOSAL_THRESHOLD = 1_000_000_000_000_000_000_000_000;
}
