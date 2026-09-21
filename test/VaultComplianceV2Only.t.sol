// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployAndSetup} from "script/deploy/DeployAndSetup.s.sol";
import {ConfigReader, VaultDeployConfig} from "script/lib/ConfigReader.sol";
import {SerializedTx} from "script/lib/SafeBatchSerialize.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";

contract VaultComplianceV2OnlyHarness is DeployAndSetup {
    function seed(address vault, address proxy, address v1Proxy, bool chainV2Only, bool vaultV2Only) external {
        msigMode = true;
        chainComplianceConfig.v2Only = chainV2Only;
        vaultConfig.compliance.v2Only = vaultV2Only;
        vaultConfig.common.complianceProxy = proxy;
        vaultConfig.common.predicateProxy = v1Proxy;
        vaultConfig.deployChainId = block.chainid;
        vaultConfig.vaults.push();
        vaultConfig.vaults[0].addr = vault;
    }

    function v2Only() external view returns (bool) {
        return isV2Only();
    }

    /// @dev Mirrors the vault-authority part of _setupAuthority.
    function configure(address authority) external {
        string memory json = vm.readFile("config/authority/authority.json");
        _processCapabilities(json, authority);
        _processPublicCapabilities(json, authority);
        _processRoleAssignments(json, authority);
        if (isV2Only()) _configureV2VaultAccess(authority);
    }

    function requireComplianceReady() external view {
        _requireComplianceReady();
    }

    function queued() external view returns (SerializedTx[] memory) {
        return serializedTxs;
    }

    function writeOutput(string memory symbol) external {
        vaultConfig.symbol = symbol;
        vaultConfig.owner = address(0x0C);
        rolesAuthority = address(0x0A);
        commonRolesAuthority = address(0x0B);
        writeDeploymentOutput();
    }
}

/// @dev compliance.v2Only opts a single vault into the shared ComplianceProxy on a chain that still runs V1.
contract VaultComplianceV2OnlyTest is Test {
    address constant VAULT = address(0xBEEF);
    address constant PROXY = address(0xCAFE);
    address constant V1_PROXY = address(0xF1F1);
    bytes4 constant DEPOSIT = bytes4(keccak256("deposit(uint256,address)"));
    bytes4 constant MINT = bytes4(keccak256("mint(uint256,address)"));
    RolesAuthority authority;

    function setUp() public {
        authority = new RolesAuthority(address(this), Authority(address(0)));
    }

    function _harness(address v1Proxy, bool chainV2Only, bool vaultV2Only)
        internal
        returns (VaultComplianceV2OnlyHarness h)
    {
        h = new VaultComplianceV2OnlyHarness();
        h.seed(VAULT, PROXY, v1Proxy, chainV2Only, vaultV2Only);
    }

    function _apply(VaultComplianceV2OnlyHarness h) internal {
        h.configure(address(authority));
        SerializedTx[] memory txs = h.queued();
        for (uint256 i; i < txs.length; ++i) {
            (bool ok,) = txs[i].to.call(txs[i].data);
            assertTrue(ok);
        }
    }

    function test_effectiveModeCombinesChainAndVaultFlags() public {
        assertFalse(_harness(V1_PROXY, false, false).v2Only());
        assertTrue(_harness(address(0), true, false).v2Only());
        assertTrue(_harness(V1_PROXY, false, true).v2Only());
        assertTrue(_harness(address(0), true, true).v2Only());
    }

    function test_vaultFlagGatesDepositsToSharedProxyOnV1Chain() public {
        _apply(_harness(V1_PROXY, false, true));
        assertTrue(authority.canCall(PROXY, VAULT, DEPOSIT));
        assertTrue(authority.canCall(PROXY, VAULT, MINT));
        assertFalse(authority.canCall(V1_PROXY, VAULT, DEPOSIT));
        assertFalse(authority.doesUserHaveRole(V1_PROXY, 7));
        assertFalse(authority.isCapabilityPublic(VAULT, DEPOSIT));
        assertFalse(authority.canCall(address(0x123), VAULT, DEPOSIT));
        _assertRedemptionsPublic();
    }

    function test_vaultFlagWithoutV1ProxyKeepsDepositsGated() public {
        // Without the flag an absent V1 proxy would make deposit/mint public (noPredicateProxy).
        _apply(_harness(address(0), false, true));
        assertTrue(authority.canCall(PROXY, VAULT, DEPOSIT));
        assertFalse(authority.isCapabilityPublic(VAULT, DEPOSIT));
        assertFalse(authority.isCapabilityPublic(VAULT, MINT));
        _assertRedemptionsPublic();
    }

    function test_v1ChainWithoutVaultFlagStillGrantsV1Proxy() public {
        _apply(_harness(V1_PROXY, false, false));
        assertTrue(authority.canCall(V1_PROXY, VAULT, DEPOSIT));
        assertTrue(authority.doesUserHaveRole(V1_PROXY, 7));
        assertFalse(authority.canCall(PROXY, VAULT, DEPOSIT));
        assertFalse(authority.isCapabilityPublic(VAULT, DEPOSIT));
        _assertRedemptionsPublic();
    }

    function test_vaultFlagRejectsStalePublicDeposit() public {
        authority.setPublicCapability(VAULT, DEPOSIT, true);
        VaultComplianceV2OnlyHarness h = _harness(V1_PROXY, false, true);
        vm.expectRevert();
        h.configure(address(authority));
    }

    function test_readinessCheckSkipsV1ProxyOnlyForVaultFlag() public {
        // Vault-level: the chain's V1 proxy may stay configured; the shared V2 stack must exist.
        VaultComplianceV2OnlyHarness vaultLevel = _harness(V1_PROXY, false, true);
        vm.expectRevert("DeployAndSetup: activate common V2 compliance first");
        vaultLevel.requireComplianceReady();

        // Chain-level: a configured V1 proxy is a configuration error.
        VaultComplianceV2OnlyHarness chainLevel = _harness(V1_PROXY, true, false);
        vm.expectRevert("DeployAndSetup: V1 proxy configured");
        chainLevel.requireComplianceReady();

        // V1 deployments skip the V2 readiness checks entirely.
        _harness(V1_PROXY, false, false).requireComplianceReady();
    }

    function test_vaultConfigParsesOptionalFlag() public {
        assertFalse(ConfigReader.readVaultConfig("nTEST").compliance.v2Only);
        string memory dir = string.concat(vm.projectRoot(), "/script/deployment-config/vaults/");
        string memory flagged = string.concat(dir, "V2ONLY_PARSE_TEST.json");
        string memory unset = string.concat(dir, "V2ONLY_UNSET_TEST.json");
        vm.writeFile(flagged, _minimalVaultJson("V2ONLY_PARSE_TEST", ',"v2Only":true'));
        vm.writeFile(unset, _minimalVaultJson("V2ONLY_UNSET_TEST", ""));
        VaultDeployConfig memory flaggedConfig = ConfigReader.readVaultConfig("V2ONLY_PARSE_TEST");
        VaultDeployConfig memory unsetConfig = ConfigReader.readVaultConfig("V2ONLY_UNSET_TEST");
        vm.removeFile(flagged);
        vm.removeFile(unset);
        assertTrue(flaggedConfig.compliance.v2Only);
        assertEq(flaggedConfig.compliance.v2.verificationHash, "policy");
        assertFalse(unsetConfig.compliance.v2Only);
    }

    function test_outputRecordsFlagAndReadsBack() public {
        _harness(V1_PROXY, false, true).writeOutput("V2ONLY_OUTPUT_TEST");
        string memory dir = string.concat(vm.projectRoot(), "/script/output/V2ONLY_OUTPUT_TEST");
        string memory json =
            vm.readFile(string.concat(dir, "/", vm.toString(block.chainid), "-V2ONLY_OUTPUT_TEST.json"));
        VaultDeployConfig memory output = ConfigReader.readOutputConfig(block.chainid, "V2ONLY_OUTPUT_TEST");
        vm.removeDir(dir, true);
        assertTrue(vm.keyExistsJson(json, ".compliance.v2Only"));
        assertTrue(output.compliance.v2Only);
    }

    function test_outputOmitsFlagForV1Vaults() public {
        _harness(V1_PROXY, false, false).writeOutput("V1_OUTPUT_TEST");
        string memory dir = string.concat(vm.projectRoot(), "/script/output/V1_OUTPUT_TEST");
        string memory json = vm.readFile(string.concat(dir, "/", vm.toString(block.chainid), "-V1_OUTPUT_TEST.json"));
        VaultDeployConfig memory output = ConfigReader.readOutputConfig(block.chainid, "V1_OUTPUT_TEST");
        vm.removeDir(dir, true);
        assertFalse(vm.keyExistsJson(json, ".compliance.v2Only"));
        assertFalse(output.compliance.v2Only);
    }

    function _assertRedemptionsPublic() internal view {
        string[7] memory signatures = [
            "requestRedeem(uint256,address,address)",
            "instantRedeem(uint256,address,address)",
            "requestRedeemWithPermit2(uint256,address,address,uint256,uint256,bytes)",
            "instantRedeemWithPermit2(uint256,address,address,uint256,uint256,bytes)",
            "redeem(uint256,address,address)",
            "updateRedeem(uint256,address,address)",
            "withdraw(uint256,address,address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes4 selector = bytes4(keccak256(bytes(signatures[i])));
            assertTrue(authority.isCapabilityPublic(VAULT, selector), signatures[i]);
        }
    }

    function _minimalVaultJson(string memory symbol, string memory complianceExtra)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            '{"symbol":"',
            symbol,
            '","name":"Parse test","owner":"0x0000000000000000000000000000000000000001",',
            '"baseAssetSymbol":"USDC","vaultType":"NestVault","contracts":{"vaults":[]},',
            '"accountantParams":{"totalSharesLastUpdate":0,"payoutAddress":"0x0000000000000000000000000000000000000001",',
            '"startingExchangeRate":1000000,"allowedExchangeRateChangeUpper":1000500,"allowedExchangeRateChangeLower":999500,',
            '"minimumUpdateDelayInSeconds":3600,"managementFee":0},"vaultParams":{"minRate":1},',
            '"compliance":{"v1":{"policyID":""},"v2":{"verificationHash":"policy"}',
            complianceExtra,
            '},"composerParams":{"maxRetryableValue":0},',
            '"roles":{"KEEPER_ROLE":[],"UPDATE_EXCHANGE_RATE_ROLE":[],"MANAGER_ROLE":[]},"peers":[]}'
        );
    }
}
