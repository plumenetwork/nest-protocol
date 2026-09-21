// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {SetupAuthority} from "script/setup/SetupAuthority.s.sol";
import {ConfigReader, VaultDeployConfig} from "script/lib/ConfigReader.sol";

/// @dev Exposes the real config loader and symbolic name resolvers for testing.
contract SetupAuthorityHarness is SetupAuthority {
    function load(string memory symbol) external {
        loadConfigs(symbol);
    }

    function loadBaseAssetOverrides(string memory symbol, uint256 chainId) external {
        rawVaultConfigJson =
            vm.readFile(string.concat(vm.projectRoot(), "/script/deployment-config/vaults/", symbol, ".json"));
        vaultConfig = ConfigReader.readVaultConfig(symbol);
        _applyBaseAssetOverrides(chainId);
    }

    function users(string memory name) external view returns (address[] memory) {
        return _resolveUsers(name);
    }

    function targets(string memory name) external view returns (address[] memory) {
        return _resolveTargets(name);
    }

    function parseOwner(string memory json) external view returns (address) {
        return ConfigReader.readOwner(json);
    }

    function resolveOwner(address explicitOwner, address protocolTimelock) external pure returns (address) {
        VaultDeployConfig memory config;
        config.owner = explicitOwner;
        config.common.protocolTimelock = protocolTimelock;
        return ConfigReader.resolvedOwner(config);
    }

    function startingExchangeRate() external view returns (uint96) {
        return vaultConfig.accountantParams.startingExchangeRate;
    }

    function baseAssetSymbol() external view returns (string memory) {
        return vaultConfig.baseAssetSymbol;
    }

    function _readAssetDecimals(uint256 chainId, string memory symbol) internal pure override returns (uint8) {
        if (chainId == 56 && keccak256(bytes(symbol)) == keccak256("USDT")) return 18;
        return 6;
    }
}

/// @title  DeployConfigParseTest
/// @notice Guards the config schema contract (Octane V1): every checked-in vault config must load
///         on every chain it is declared on, and every symbolic target/user name in the authority
///         JSONs must resolve. Pure JSON parsing + storage reads — no RPC calls, deterministic.
contract DeployConfigParseTest is Test {
    uint256 internal constant SOLANA_CHAIN_ID = 101;

    SetupAuthorityHarness internal harness;
    string internal vaultChainsJson;

    function setUp() public {
        vm.setEnv("PRIVATE_KEY", "1");
        harness = new SetupAuthorityHarness();
        vaultChainsJson =
            vm.readFile(string.concat(vm.projectRoot(), "/script/deployment-config/vaults/vault-chains.json"));
    }

    /// @dev Every vault config in vault-chains.json must parse on each of its EVM deploy chains.
    function test_allVaultConfigsLoadOnAllChains() public {
        string[] memory symbols = vm.parseJsonKeys(vaultChainsJson, ".");
        for (uint256 i = 0; i < symbols.length; i++) {
            if (keccak256(bytes(symbols[i])) == keccak256("_note")) continue;
            string memory vaultJson =
                vm.readFile(string.concat(vm.projectRoot(), "/script/deployment-config/vaults/", symbols[i], ".json"));
            assertFalse(vm.keyExistsJson(vaultJson, ".predicateParams"), "legacy compliance key in vault input");
            VaultDeployConfig memory config = ConfigReader.readVaultConfig(symbols[i]);
            assertEq(config.compliance.v1.policyID, vm.parseJsonString(vaultJson, ".compliance.v1.policyID"));
            assertEq(
                config.compliance.v2.verificationHash, vm.parseJsonString(vaultJson, ".compliance.v2.verificationHash")
            );
            uint256[] memory chains = vm.parseJsonUintArray(vaultChainsJson, string.concat(".", symbols[i]));
            for (uint256 j = 0; j < chains.length; j++) {
                if (chains[j] == SOLANA_CHAIN_ID) continue;
                vm.setEnv("CHAIN_ID", vm.toString(chains[j]));
                harness.load(symbols[i]);
            }
        }
    }

    /// @dev A base-asset override rescales the hub-denominated starting rate to the selected
    ///      chain asset's decimals without requiring duplicated per-chain rate configuration.
    function test_baseAssetOverridesScaleStartingExchangeRate() public {
        string[] memory symbols = vm.parseJsonKeys(vaultChainsJson, ".");
        uint256 checked;
        for (uint256 i = 0; i < symbols.length; i++) {
            if (keccak256(bytes(symbols[i])) == keccak256("_note")) continue;

            string memory vaultJson =
                vm.readFile(string.concat(vm.projectRoot(), "/script/deployment-config/vaults/", symbols[i], ".json"));
            assertFalse(
                vm.keyExistsJson(vaultJson, ".startingExchangeRateOverrides"),
                string.concat(symbols[i], ": startingExchangeRateOverrides is obsolete")
            );
            uint256[] memory chains = vm.parseJsonUintArray(vaultChainsJson, string.concat(".", symbols[i]));
            for (uint256 j = 0; j < chains.length; j++) {
                string memory chainId = vm.toString(chains[j]);
                string memory overrideKey = string.concat(".baseAssetOverrides.", chainId);
                if (!vm.keyExistsJson(vaultJson, overrideKey)) continue;

                harness.loadBaseAssetOverrides(symbols[i], chains[j]);
                uint256 expectedRate = vm.parseJsonUint(vaultJson, ".accountantParams.startingExchangeRate");
                if (chains[j] == 56) expectedRate *= 1e12;
                assertEq(
                    harness.startingExchangeRate(),
                    expectedRate,
                    string.concat(symbols[i], ": incorrectly scaled starting exchange rate")
                );
                assertEq(harness.baseAssetSymbol(), vm.parseJsonString(vaultJson, overrideKey));
                checked++;
            }
        }
        assertEq(checked, 18, "unexpected number of base asset overrides checked");
    }

    function test_topLevelOwner_isRequiredAndNonZero() public {
        assertEq(
            harness.parseOwner('{"owner":"0x0000000000000000000000000000000000000123","roles":{}}'), address(0x123)
        );
        vm.expectRevert("ConfigReader: owner required");
        harness.parseOwner('{"roles":{}}');
        vm.expectRevert("ConfigReader: owner required");
        harness.parseOwner('{"roles":{"owner":"0x0000000000000000000000000000000000000456"}}');
        vm.expectRevert("ConfigReader: owner required");
        harness.parseOwner('{"owner":"0x0000000000000000000000000000000000000000"}');
        assertEq(ConfigReader.readVaultConfig("nBASIS").owner, 0x34e8BB9E0fa50d63BfCa1D8E83ddba0D9fD5C062);
        assertEq(ConfigReader.readVaultConfig("nFALCON").owner, 0x8fAACdC65de5D78975dF4f9DC4B6548979cEb23A);
    }

    function test_resolvedOwner_usesExplicitOwner() public view {
        assertEq(harness.resolveOwner(address(0xA11CE), address(0xBEEF)), address(0xA11CE));
    }

    function test_resolvedOwner_rejectsMissingOwnerEvenWithCommonTimelock() public {
        vm.expectRevert("ConfigReader: owner required");
        harness.resolveOwner(address(0), address(0xBEEF));
        vm.expectRevert("ConfigReader: owner required");
        harness.resolveOwner(address(0), address(0));
    }

    /// @dev Every target/user name in both authority JSONs must resolve on every deploy chain.
    function test_authorityNamesResolveOnAllChains() public {
        (uint256[] memory chains, string[] memory chainSymbols, uint256 n) = _collectChains();
        string memory authority = vm.readFile(string.concat(vm.projectRoot(), "/config/authority/authority.json"));
        string memory commonAuthority =
            vm.readFile(string.concat(vm.projectRoot(), "/config/authority/common-authority.json"));

        for (uint256 i = 0; i < n; i++) {
            vm.setEnv("CHAIN_ID", vm.toString(chains[i]));
            harness.load(chainSymbols[i]);
            _walkAuthority(authority);
            _walkAuthority(commonAuthority);
        }
    }

    /// @dev Distinct EVM chain ids in vault-chains.json, each with one vault symbol deployed there.
    function _collectChains() internal view returns (uint256[] memory chains, string[] memory chainSymbols, uint256 n) {
        string[] memory symbols = vm.parseJsonKeys(vaultChainsJson, ".");
        chains = new uint256[](64);
        chainSymbols = new string[](64);
        for (uint256 i = 0; i < symbols.length; i++) {
            if (keccak256(bytes(symbols[i])) == keccak256("_note")) continue;
            uint256[] memory vaultChains = vm.parseJsonUintArray(vaultChainsJson, string.concat(".", symbols[i]));
            for (uint256 j = 0; j < vaultChains.length; j++) {
                if (vaultChains[j] == SOLANA_CHAIN_ID) continue;
                bool seen = false;
                for (uint256 k = 0; k < n; k++) {
                    if (chains[k] == vaultChains[j]) seen = true;
                }
                if (!seen) {
                    chains[n] = vaultChains[j];
                    chainSymbols[n] = symbols[i];
                    n++;
                }
            }
        }
    }

    function _walkAuthority(string memory json) internal view {
        _walkTargets(json, ".capabilities");
        _walkTargets(json, ".publicCapabilities");
        _walkTargets(json, ".revokeCapabilities");
        _walkUsers(json, ".roleAssignments");
        _walkUsers(json, ".revokeRoleAssignments");
    }

    function _walkTargets(string memory json, string memory key) internal view {
        if (!vm.keyExistsJson(json, key)) return;
        for (uint256 i = 0; vm.keyExistsJson(json, string.concat(key, "[", vm.toString(i), "].target")); i++) {
            harness.targets(vm.parseJsonString(json, string.concat(key, "[", vm.toString(i), "].target")));
        }
    }

    function _walkUsers(string memory json, string memory key) internal view {
        if (!vm.keyExistsJson(json, key)) return;
        for (uint256 i = 0; vm.keyExistsJson(json, string.concat(key, "[", vm.toString(i), "].user")); i++) {
            harness.users(vm.parseJsonString(json, string.concat(key, "[", vm.toString(i), "].user")));
        }
    }
}
