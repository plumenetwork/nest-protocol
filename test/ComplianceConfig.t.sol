// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployComplianceProxy} from "script/deploy/DeployComplianceProxy.s.sol";
import {ConfigReader, ChainComplianceConfig, VaultDeployConfig} from "script/lib/ConfigReader.sol";

contract ComplianceConfigHarness is DeployComplianceProxy {
    function load(string memory symbol, uint256 chainId)
        external
        returns (string memory, address, string memory, address, bool)
    {
        vaultConfig = ConfigReader.resolveConfigForChain(ConfigReader.readVaultConfig(symbol), chainId);
        chainComplianceConfig = ConfigReader.readComplianceConfig(chainId);
        _loadComplianceConfig(symbol);
        return (apiChain, predicateRegistry, verificationHash, complianceProxy, activateHook);
    }

    function readChain(uint256 chainId) external view returns (ChainComplianceConfig memory) {
        return ConfigReader.readComplianceConfig(chainId);
    }
}

contract ComplianceConfigTest is Test {
    function test_allCommonConfigsLoadWithoutPredicate() public view {
        uint256[9] memory chainIds = [uint256(1), 56, 480, 5042, 8453, 9745, 42161, 43114, 98866];
        for (uint256 i; i < chainIds.length; ++i) {
            uint256 chainId = chainIds[i];
            string memory json =
                vm.readFile(string.concat(vm.projectRoot(), "/config/common/", vm.toString(chainId), ".json"));
            assertFalse(vm.keyExistsJson(json, ".predicate"));
            assertEq(ConfigReader.readCommonConfig(chainId).chainId, chainId);
            ChainComplianceConfig memory config = ConfigReader.readComplianceConfig(chainId);
            assertEq(config.chainId, chainId);
            assertEq(config.v2Only, chainId == 5042);
            if (chainId == 43114) {
                assertEq(config.v2.apiChain, "");
                assertEq(config.v2.predicateRegistry, address(0));
            } else {
                assertGt(bytes(config.v2.apiChain).length, 0);
                assertEq(config.v2.predicateRegistry, 0xe15a8Ca5BD8464283818088c1760d8f23B6a216E);
            }
        }
    }

    function test_ntestDeploymentCombinesChainSettingsVaultPolicyAndDeploymentAddresses() public {
        address registry = 0xe15a8Ca5BD8464283818088c1760d8f23B6a216E;
        vm.etch(registry, hex"00");
        ComplianceConfigHarness harness = new ComplianceConfigHarness();
        (string memory apiChain, address loadedRegistry, string memory policy, address proxy, bool activate) =
            harness.load("nTEST", 98866);
        assertEq(apiChain, "plume");
        assertEq(loadedRegistry, registry);
        assertEq(policy, "x-managed-policy-8a45c2ae80a41dac8475d7b73a432c95");
        assertEq(proxy, 0xF325E0f939963b42A22538B98b30E1CAeB2C37bA);
        assertFalse(activate);
        assertEq(harness.readChain(98866).v1.serviceManager, 0xdeaf0225C4D31E8a2C99893aB95bAB1790B8A687);
        assertEq(ConfigReader.readVaultConfig("nTEST").compliance.v1.policyID, "x-nest-prod-006");
    }

    function test_commonComplianceRejectsWrongChain() public {
        uint256 chainId = 999_999_978;
        string memory path = string.concat(vm.projectRoot(), "/config/compliance/", vm.toString(chainId), ".json");
        vm.writeFile(path, '{"chainId":98866}');
        ComplianceConfigHarness harness = new ComplianceConfigHarness();
        vm.expectRevert("ConfigReader: compliance chain mismatch");
        harness.readChain(chainId);
        vm.removeFile(path);
    }

    function test_legacyDeploymentOutputStillLoads() public {
        string memory dir = string.concat(vm.projectRoot(), "/script/output/COMPLIANCE_LEGACY");
        string memory path = string.concat(dir, "/999999978-COMPLIANCE_LEGACY.json");
        vm.createDir(dir, true);
        vm.writeFile(
            path,
            string.concat(
                '{"symbol":"COMPLIANCE_LEGACY","name":"Legacy output","owner":"0x0000000000000000000000000000000000000001",',
                '"baseAssetSymbol":"USDC","vaultType":"NestVault","contracts":{"vaults":[]},',
                '"accountantParams":{"totalSharesLastUpdate":0,"payoutAddress":"0x0000000000000000000000000000000000000001",',
                '"startingExchangeRate":1000000,"allowedExchangeRateChangeUpper":1000500,"allowedExchangeRateChangeLower":999500,',
                '"minimumUpdateDelayInSeconds":3600,"managementFee":0},"vaultParams":{"minRate":1},',
                '"predicateParams":{"policyID":"legacy-policy"},"composerParams":{"maxRetryableValue":0},',
                '"roles":{"KEEPER_ROLE":[],"UPDATE_EXCHANGE_RATE_ROLE":[],"MANAGER_ROLE":[]},"peers":[]}'
            )
        );
        VaultDeployConfig memory config = ConfigReader.readOutputConfig(999_999_978, "COMPLIANCE_LEGACY");
        assertEq(config.compliance.v1.policyID, "legacy-policy");
        assertEq(config.compliance.v2.verificationHash, "");
        vm.removeDir(dir, true);
    }
}
