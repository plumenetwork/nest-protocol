// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployAndSetup} from "script/deploy/DeployAndSetup.s.sol";
import {ConfigReader, VaultDeployConfig} from "script/lib/ConfigReader.sol";
import {SerializedTx} from "script/lib/SafeBatchSerialize.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";

contract ArcDeploymentHarness is DeployAndSetup {
    function seed(address vault, address proxy) external {
        msigMode = true;
        chainComplianceConfig.v2Only = true;
        vaultConfig.common.complianceProxy = proxy;
        vaultConfig.vaults.push();
        vaultConfig.vaults[0].addr = vault;
    }

    function configure(address authority) external {
        _processPublicCapabilities(vm.readFile("config/authority/authority.json"), authority);
        _configureV2VaultAccess(authority);
    }

    function queued() external view returns (SerializedTx[] memory) {
        return serializedTxs;
    }

    function loadedOwner(string memory symbol) external returns (address) {
        loadConfigs(symbol);
        return ConfigReader.resolvedOwner(vaultConfig);
    }

    function loadedPeers(string memory symbol) external returns (uint256[] memory) {
        loadConfigs(symbol);
        return vaultConfig.peers;
    }

    function _readAssetDecimals(uint256 chainId, string memory symbol) internal pure override returns (uint8) {
        if (chainId == 56 && keccak256(bytes(symbol)) == keccak256("USDT")) return 18;
        return 6;
    }
}

contract ArcDeploymentTest is Test {
    address constant VAULT = address(0xBEEF);
    address constant PROXY = address(0xCAFE);
    ArcDeploymentHarness harness;
    RolesAuthority authority;

    function setUp() public {
        harness = new ArcDeploymentHarness();
        harness.seed(VAULT, PROXY);
        authority = new RolesAuthority(address(this), Authority(address(0)));
    }

    function test_v2OnlyGatesDepositsAndKeepsRedemptionsPublic() public {
        harness.configure(address(authority));
        SerializedTx[] memory txs = harness.queued();
        for (uint256 i; i < txs.length; ++i) {
            (bool ok,) = txs[i].to.call(txs[i].data);
            assertTrue(ok);
        }
        string[2] memory gated = ["deposit(uint256,address)", "mint(uint256,address)"];
        for (uint256 i; i < gated.length; ++i) {
            bytes4 selector = bytes4(keccak256(bytes(gated[i])));
            assertTrue(authority.canCall(PROXY, VAULT, selector));
            assertFalse(authority.canCall(address(0x123), VAULT, selector));
        }
        _assertRedemptionsPublic();
    }

    function test_v2OnlyRejectsStalePublicDeposit() public {
        authority.setPublicCapability(VAULT, bytes4(keccak256("deposit(uint256,address)")), true);
        vm.expectRevert();
        harness.configure(address(authority));
    }

    function test_v2OnlyAcceptsExistingPublicRedeemRequest() public {
        authority.setPublicCapability(VAULT, bytes4(keccak256("requestRedeem(uint256,address,address)")), true);
        harness.configure(address(authority));
        SerializedTx[] memory txs = harness.queued();
        for (uint256 i; i < txs.length; ++i) {
            (bool ok,) = txs[i].to.call(txs[i].data);
            assertTrue(ok);
        }
        _assertRedemptionsPublic();
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
            assertTrue(authority.canCall(address(0x123), VAULT, selector), signatures[i]);
        }
    }

    function test_arcOwnerOverridesUseMultisigWithoutChangingPlumeOwner() public {
        string memory originalKey = vm.envOr("PRIVATE_KEY", string(""));
        string memory originalChain = vm.envOr("CHAIN_ID", string(""));
        vm.setEnv("PRIVATE_KEY", "1");
        string[4] memory symbols = ["nCOMMON", "nOPAL", "nFALCON", "FACTOR"];
        for (uint256 i; i < symbols.length; ++i) {
            vm.setEnv("CHAIN_ID", "5042");
            assertEq(harness.loadedOwner(symbols[i]), ConfigReader.readCommonConfig(5042).multisig);
            vm.setEnv("CHAIN_ID", "98866");
            assertEq(harness.loadedOwner(symbols[i]), ConfigReader.readVaultConfig(symbols[i]).owner);
        }
        vm.setEnv("PRIVATE_KEY", originalKey);
        vm.setEnv("CHAIN_ID", originalChain);
    }

    function test_arcPeersAreReciprocalOnEveryExistingEvmChainAndExcludeSolana() public {
        string memory originalKey = vm.envOr("PRIVATE_KEY", string(""));
        string memory originalChain = vm.envOr("CHAIN_ID", string(""));
        vm.setEnv("PRIVATE_KEY", "1");
        string[3] memory symbols = ["nOPAL", "nFALCON", "FACTOR"];
        for (uint256 i; i < symbols.length; ++i) {
            vm.setEnv("CHAIN_ID", "5042");
            uint256[] memory arcPeers = harness.loadedPeers(symbols[i]);
            uint256[] memory basePeers = ConfigReader.readVaultConfig(symbols[i]).peers;
            assertEq(arcPeers.length + 2, basePeers.length); // Arc itself and Solana are excluded.
            for (uint256 j; j < basePeers.length; ++j) {
                uint256 chain = basePeers[j];
                if (chain == 101 || chain == 5042) {
                    assertFalse(_contains(arcPeers, chain));
                    continue;
                }
                assertTrue(_contains(arcPeers, chain), "Arc outbound peer missing");
                vm.setEnv("CHAIN_ID", vm.toString(chain));
                uint256[] memory reversePeers = harness.loadedPeers(symbols[i]);
                assertTrue(_contains(reversePeers, 5042), "Arc reverse peer missing");
                assertTrue(_contains(reversePeers, 101), "existing Solana route changed");
            }
        }
        vm.setEnv("PRIVATE_KEY", originalKey);
        vm.setEnv("CHAIN_ID", originalChain);
    }

    function _contains(uint256[] memory peers, uint256 chain) internal pure returns (bool) {
        for (uint256 i; i < peers.length; ++i) {
            if (peers[i] == chain) return true;
        }
        return false;
    }

    function test_arcConfigsResolveExactlyOneUSDCVaultAndSpokeAccountants() public view {
        assertTrue(ConfigReader.readComplianceConfig(5042).v2Only);
        assertFalse(ConfigReader.readComplianceConfig(98866).v2Only);
        assertEq(ConfigReader.readLZConfig(5042).eid, 30417);
        assertEq(ConfigReader.readCCTPConfig(5042).domain, 26);
        assertEq(ConfigReader.readCCTPConfig(5042).finalityThreshold, 2000);
        string[3] memory symbols = ["nOPAL", "nFALCON", "FACTOR"];
        for (uint256 i; i < symbols.length; ++i) {
            VaultDeployConfig memory config =
                ConfigReader.resolveConfigForChain(ConfigReader.readVaultConfig(symbols[i]), 5042);
            assertEq(config.vaults.length, 1);
            assertEq(config.vaults[0].assetSymbol, "USDC");
            string memory raw = vm.readFile(string.concat("script/deployment-config/vaults/", symbols[i], ".json"));
            assertEq(ConfigReader.effectiveAccountantType(raw, 5042), "NestSpokeAccountant");
        }
    }
}
