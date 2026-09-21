// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {DeployComposer} from "script/deploy/DeployComposer.s.sol";
import {ConfigReader, CommonContracts, VaultDeployConfig, VaultEntry} from "script/lib/ConfigReader.sol";

contract DeployComposerPersistenceHarness is DeployComposer {
    function seed(VaultDeployConfig memory config, string memory rawJson) external {
        vaultConfig = config;
        rawVaultConfigJson = rawJson;
    }

    function applyOverridesAndSnapshot() external {
        _applyCommonOverrides(vaultConfig.deployChainId);
        snapshotCommon();
    }

    function setRelayer(address newRelayer) external {
        vaultConfig.common.cctpRelayer = newRelayer;
    }

    function writeOutput() external {
        writeDeploymentOutput();
    }

    function writeCommon() external {
        writeCommonConfigIfChanged();
    }

    function overlayOutput() external returns (bool) {
        return overlayDeploymentOutput();
    }

    function requireExistingDeploymentsForMsig() external view {
        _requireExistingDeploymentsForMsig();
    }

    function relayer() external view returns (address) {
        return vaultConfig.common.cctpRelayer;
    }

    function composer() external view returns (address) {
        return vaultConfig.vaults[0].composer;
    }

    function share() external view returns (address) {
        return vaultConfig.contracts.share;
    }

    function vaultAddress() external view returns (address) {
        return vaultConfig.vaults[0].addr;
    }
}

contract DeployComposerPersistenceTest is Test {
    uint256 internal constant OUTPUT_CHAIN_ID = 999_999_995;
    uint256 internal constant OVERLAY_CHAIN_ID = 999_999_994;
    uint256 internal constant COMMON_CHAIN_ID = 999_999_993;
    uint256 internal constant MSIG_CHAIN_ID = 999_999_992;
    string internal constant OUTPUT_SYMBOL = "W3OUTPUT";
    string internal constant OVERLAY_SYMBOL = "W3OVERLAY";
    string internal constant COMMON_SYMBOL = "W3COMMON";
    string internal constant MSIG_SYMBOL = "W3MSIG";
    address internal constant RELAYER = address(0xC701);
    address internal constant COMPOSER = address(0xC702);

    DeployComposerPersistenceHarness internal harness;

    function setUp() public {
        harness = new DeployComposerPersistenceHarness();
    }

    function test_writesStandardOutputConsumedByConfigReaderWithoutMutatingInput() public {
        _cleanup(OUTPUT_CHAIN_ID, OUTPUT_SYMBOL);
        _writeCctpConfig(OUTPUT_CHAIN_ID);
        string memory input = "reviewed-input-sentinel";
        vm.writeFile(_inputPath(OUTPUT_SYMBOL), input);

        harness.seed(_config(OUTPUT_CHAIN_ID, OUTPUT_SYMBOL, RELAYER, COMPOSER), "{}");
        harness.writeOutput();

        assertEq(vm.readFile(_inputPath(OUTPUT_SYMBOL)), input, "reviewed input was rewritten");
        VaultDeployConfig memory output = ConfigReader.readOutputConfig(OUTPUT_CHAIN_ID, OUTPUT_SYMBOL);
        assertEq(output.owner, address(0xA6));
        string memory outputJson = vm.readFile(
            string.concat(_outputDir(OUTPUT_SYMBOL), "/", vm.toString(OUTPUT_CHAIN_ID), "-", OUTPUT_SYMBOL, ".json")
        );
        assertEq(vm.parseJsonAddress(outputJson, ".owner"), address(0xA6));
        assertFalse(vm.keyExistsJson(outputJson, ".roles.owner"));
        assertFalse(vm.keyExistsJson(outputJson, ".predicateParams"));
        assertEq(vm.parseJsonString(outputJson, ".compliance.v1.policyID"), "test-policy");
        assertEq(vm.parseJsonString(outputJson, ".compliance.v2.verificationHash"), "test-v2-policy");
        assertEq(output.compliance.v1.policyID, "test-policy");
        assertEq(output.compliance.v2.verificationHash, "test-v2-policy");
        assertEq(output.common.cctpRelayer, RELAYER, "relayer missing from standard output");
        assertEq(output.vaults.length, 1, "vault output shape changed");
        assertEq(output.vaults[0].composer, COMPOSER, "composer missing from standard output");
        _cleanup(OUTPUT_CHAIN_ID, OUTPUT_SYMBOL);
    }

    function test_outputOverlayFeedsLaterWiringAndHonorsExplicitRelayerOverride() public {
        _cleanup(OVERLAY_CHAIN_ID, OVERLAY_SYMBOL);
        _writeCctpConfig(OVERLAY_CHAIN_ID);
        harness.seed(_config(OVERLAY_CHAIN_ID, OVERLAY_SYMBOL, RELAYER, COMPOSER), "{}");
        harness.writeOutput();

        VaultDeployConfig memory pending = _config(OVERLAY_CHAIN_ID, OVERLAY_SYMBOL, address(0), address(0));
        pending.contracts.share = address(0);
        pending.vaults[0].addr = address(0);
        harness.seed(pending, "{}");
        harness.applyOverridesAndSnapshot();
        assertTrue(harness.overlayOutput(), "standard output was not found");
        assertEq(harness.relayer(), RELAYER, "relayer was not overlaid for authority wiring");
        assertEq(harness.composer(), COMPOSER, "composer was not overlaid for authority wiring");
        assertEq(harness.share(), address(0xA1), "existing share was not retained in output state");
        assertEq(harness.vaultAddress(), address(0xA5), "existing vault was not retained in output state");
        harness.writeCommon();
        assertEq(
            vm.parseJsonAddress(vm.readFile(_commonPath(OVERLAY_CHAIN_ID)), ".cctpRelayer"),
            RELAYER,
            "output relayer was not repaired into canonical common config"
        );

        VaultDeployConfig memory explicitComposer = pending;
        explicitComposer.vaults[0].composer = address(0xC703);
        harness.seed(explicitComposer, "{}");
        harness.overlayOutput();
        assertEq(harness.vaultAddress(), address(0xA5), "missing vault was not overlaid independently");
        assertEq(harness.composer(), address(0xC703), "reviewed composer was overwritten");

        string memory explicitOptOut =
            '{"commonOverrides":{"cctpRelayer":"0x0000000000000000000000000000000000000000"}}';
        VaultDeployConfig memory optOutPending = _config(OVERLAY_CHAIN_ID, OVERLAY_SYMBOL, address(0), address(0));
        optOutPending.contracts.share = address(0);
        optOutPending.vaults[0].addr = address(0);
        harness.seed(optOutPending, explicitOptOut);

        harness.overlayOutput();
        assertEq(harness.relayer(), address(0), "explicit relayer override was bypassed");
        assertEq(harness.composer(), COMPOSER, "composer was not overlaid for authority wiring");
        _cleanup(OVERLAY_CHAIN_ID, OVERLAY_SYMBOL);
    }

    function test_commonPersistenceDoesNotLeakPerVaultOverrides() public {
        _cleanup(COMMON_CHAIN_ID, COMMON_SYMBOL);
        CommonContracts memory canonical = _config(COMMON_CHAIN_ID, COMMON_SYMBOL, address(0), COMPOSER).common;
        canonical.blacklistHook = address(0xB1);
        canonical.seizer = address(0xB2);
        VaultDeployConfig memory config = _config(COMMON_CHAIN_ID, COMMON_SYMBOL, address(0), COMPOSER);
        config.common = canonical;
        string memory overridesJson =
            '{"commonOverrides":{"blacklistHook":"0x00000000000000000000000000000000000000b3","seizer":"0x00000000000000000000000000000000000000b4"}}';
        harness.seed(config, overridesJson);
        harness.applyOverridesAndSnapshot();
        harness.setRelayer(RELAYER);
        harness.writeCommon();

        string memory json = vm.readFile(_commonPath(COMMON_CHAIN_ID));
        assertEq(vm.parseJsonAddress(json, ".cctpRelayer"), RELAYER, "new relayer was not persisted");
        assertEq(vm.parseJsonAddress(json, ".blacklistHook"), canonical.blacklistHook, "override leaked");
        assertEq(vm.parseJsonAddress(json, ".seizer"), canonical.seizer, "override leaked");
        _cleanup(COMMON_CHAIN_ID, COMMON_SYMBOL);
    }

    function test_runMsigFailsBeforeSimulatingRawDeployments() public {
        _cleanup(MSIG_CHAIN_ID, MSIG_SYMBOL);
        _writeCctpConfig(MSIG_CHAIN_ID);
        harness.seed(_config(MSIG_CHAIN_ID, MSIG_SYMBOL, address(0), address(0)), "{}");
        vm.expectRevert("DeployComposer: runMsig cannot deploy CCTP relayer; use runDirect");
        harness.requireExistingDeploymentsForMsig();

        VaultDeployConfig memory composerPending = _config(MSIG_CHAIN_ID, MSIG_SYMBOL, RELAYER, address(0));
        vm.etch(RELAYER, hex"00");
        vm.etch(composerPending.vaults[0].addr, hex"00");
        harness.seed(composerPending, "{}");
        vm.expectRevert("DeployComposer: runMsig cannot deploy composer; use runDirect");
        harness.requireExistingDeploymentsForMsig();
        _cleanup(MSIG_CHAIN_ID, MSIG_SYMBOL);
    }

    function _config(uint256 chainId, string memory symbol, address relayer, address composer_)
        internal
        pure
        returns (VaultDeployConfig memory config)
    {
        config.symbol = symbol;
        config.name = "W3 Test Vault";
        config.deployChainId = chainId;
        config.baseAssetSymbol = "USDC";
        config.vaultType = "NestVaultOFT";
        config.contracts.share = address(0xA1);
        config.contracts.accountant = address(0xA2);
        config.contracts.rolesAuthority = address(0xA3);
        config.common.cctpRelayer = relayer;
        config.common.commonRolesAuthority = address(0xA4);
        config.owner = address(0xA6);
        config.minRate = 1;
        config.compliance.v1.policyID = "test-policy";
        config.compliance.v2.verificationHash = "test-v2-policy";
        config.maxRetryableValue = 1;
        config.vaults = new VaultEntry[](1);
        config.vaults[0].assetSymbol = "USDC";
        config.vaults[0].addr = address(0xA5);
        config.vaults[0].isPegged = true;
        config.vaults[0].composer = composer_;
        config.peers = new uint256[](0);
    }

    function _writeCctpConfig(uint256 chainId) internal {
        vm.writeFile(
            _cctpPath(chainId),
            '{"messageTransmitter":"0x0000000000000000000000000000000000000011","tokenMessenger":"0x0000000000000000000000000000000000000012","tokenMinter":"0x0000000000000000000000000000000000000013","domain":1,"maxFeeBasisPoints":2,"finalityThreshold":2000}'
        );
    }

    function _inputPath(string memory symbol) internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/script/deployment-config/vaults/", symbol, ".json");
    }

    function _outputDir(string memory symbol) internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/script/output/", symbol);
    }

    function _commonPath(uint256 chainId) internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/script/deployment-config/common/", vm.toString(chainId), ".json");
    }

    function _cctpPath(uint256 chainId) internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/config/cctp/", vm.toString(chainId), ".json");
    }

    function _cleanup(uint256 chainId, string memory symbol) internal {
        if (vm.exists(_inputPath(symbol))) vm.removeFile(_inputPath(symbol));
        if (vm.exists(_commonPath(chainId))) vm.removeFile(_commonPath(chainId));
        if (vm.exists(_cctpPath(chainId))) vm.removeFile(_cctpPath(chainId));
        if (vm.exists(_outputDir(symbol))) vm.removeDir(_outputDir(symbol), true);
    }
}
