// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {SubmitUpgradeProposalScript} from "script/SubmitUpgradeProposalScript.s.sol";
import {TimelockControllerUpgradeable} from "openzeppelin-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {GovernorUpgradeable} from "openzeppelin-upgradeable/governance/GovernorUpgradeable.sol";
import {BaseGovernorDeployer} from "script/BaseGovernorDeployer.sol";
import {DeployCoreGovernor} from "script/DeployCoreGovernor.s.sol";
import {DeployTreasuryGovernor} from "script/DeployTreasuryGovernor.s.sol";
import {L2ArbitrumGovernorV2} from "src/L2ArbitrumGovernorV2.sol";
import {DeployImplementation} from "script/DeployImplementation.s.sol";
import {SharedGovernorConstants} from "script/SharedGovernorConstants.sol";

abstract contract SetupNewGovernors is SharedGovernorConstants, Test {
  uint256 constant FORK_BLOCK = 220_819_857; // Arbitrary recent block

  SubmitUpgradeProposalScript submitUpgradeProposalScript;
  BaseGovernorDeployer proxyCoreGovernorDeployer;
  BaseGovernorDeployer proxyTreasuryGovernorDeployer;

  // Current governors and timelocks
  GovernorUpgradeable currentCoreGovernor;
  TimelockControllerUpgradeable currentCoreTimelock;
  GovernorUpgradeable currentTreasuryGovernor;
  TimelockControllerUpgradeable currentTreasuryTimelock;

  // New governors
  L2ArbitrumGovernorV2 newCoreGovernor;
  L2ArbitrumGovernorV2 newTreasuryGovernor;

  enum VoteType {
    Against,
    For,
    Abstain
  }

  function setUp() public virtual {
    vm.createSelectFork(
      vm.envOr("ARBITRUM_ONE_RPC_URL", string("Please set ARBITRUM_ONE_RPC_URL in your .env file")), FORK_BLOCK
    );
    submitUpgradeProposalScript = new SubmitUpgradeProposalScript();

    // Deploy Governor implementation contract
    DeployImplementation _implementationDeployer = new DeployImplementation();
    _implementationDeployer.setUp();
    address _implementation = address(_implementationDeployer.run());

    proxyCoreGovernorDeployer = new DeployCoreGovernor();
    proxyTreasuryGovernorDeployer = new DeployTreasuryGovernor();
    proxyCoreGovernorDeployer.setUp();
    proxyTreasuryGovernorDeployer.setUp();

    // Deploy Governor proxy contracts
    newCoreGovernor = proxyCoreGovernorDeployer.run(_implementation);
    newTreasuryGovernor = proxyTreasuryGovernorDeployer.run(_implementation);

    // Current governors and timelocks
    currentCoreGovernor = GovernorUpgradeable(payable(ARBITRUM_CORE_GOVERNOR));
    currentCoreTimelock = TimelockControllerUpgradeable(payable(ARBITRUM_CORE_GOVERNOR_TIMELOCK));
    currentTreasuryGovernor = GovernorUpgradeable(payable(ARBITRUM_TREASURY_GOVERNOR));
    currentTreasuryTimelock = TimelockControllerUpgradeable(payable(ARBITRUM_TREASURY_GOVERNOR_TIMELOCK));

    // Deploy a mock ArbSys contract at ARB_SYS
    vm.allowCheatcodes(address(ARB_SYS));
    MockArbSys mockArbSys = new MockArbSys();
    bytes memory code = address(mockArbSys).code;
    vm.etch(ARB_SYS, code);
  }
}

contract MockArbSys is SharedGovernorConstants, Test {
  function sendTxToL1(address _l1Target, bytes calldata _data) external {
    // (address _l1Timelock, bytes memory _l1TimelockCalldata) = abi.decode(_data[:4], (address, bytes));

    (
      address _retryableTicketMagic,
      uint256 _ignored,
      bytes memory _retryableData,
      bytes32 _predecessor,
      bytes32 _description,
      uint256 _minDelay
    ) = abi.decode(_data[4:], (address, uint256, bytes, bytes32, bytes32, uint256));
    console2.log("retryableData");
    console2.logBytes(_retryableData);
    (
      address _arbOneDelayedInbox,
      address _upgradeExecutor,
      uint256 _value,
      uint256 _maxGas,
      uint256 _maxFeePerGas,
      bytes memory _upgradeExecutorCallData
    ) = this.decodeRetryableData(_retryableData);
    // (address _oneOffUpgradeAddress, bytes memory _upgradeExecutorCallData) =
    // this.decodeRetryableData(_retryableData);
    vm.prank(SECURITY_COUNCIL_9);
    address(UPGRADE_EXECUTOR).call(_upgradeExecutorCallData);
  }

  function decodeRetryableData(bytes calldata _retryableData)
    public
    returns (address, address, uint256, uint256, uint256, bytes memory)
  {
    (
      address _arbOneDelayedInbox,
      address _upgradeExecutor,
      uint256 _value,
      uint256 _maxGas,
      uint256 _maxFeePerGas,
      bytes memory _upgradeExecutorCallData
    ) = abi.decode(_retryableData, (address, address, uint256, uint256, uint256, bytes));
    // (address _oneOffUpgradeAddress, bytes memory _upgradeExecutorCallData) =
    //   abi.decode(_retryableData, (address, bytes));
    // return (_oneOffUpgradeAddress, _upgradeExecutorCallData);
    return (_arbOneDelayedInbox, _upgradeExecutor, _value, _maxGas, _maxFeePerGas, _upgradeExecutorCallData);
  }
}

interface IUpgradeExecutor {
  function execute(address to, bytes calldata data) external payable;
}
