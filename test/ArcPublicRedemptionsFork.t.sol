// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {NestVault} from "contracts/NestVault.sol";
import {ConfigReader, VaultDeployConfig} from "script/lib/ConfigReader.sol";

/// @dev Runs only on a local Arc fork; applies the prepared batch as the existing Safe owner.
contract ArcPublicRedemptionsForkTest is Test {
    address constant SAFE = 0xa08A0Dc480BD60d1d56C8Eec6c722125eAfEa982;
    string constant BATCH = "generated/arc-public-redemptions/5042-EnablePublicRedemptions.json";

    function test_arcPublicRedemptionBatch() public {
        if (!vm.envOr("RUN_ARC_REDEMPTION_FORK", false)) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(vm.envString("ARC_RPC_URL"), 21_002_366);
        assertEq(block.chainid, 5042);
        string memory batch = vm.readFile(BATCH);
        assertEq(vm.parseJsonString(batch, ".chainId"), "5042");
        assertEq(vm.parseJsonAddress(batch, ".meta.createdFromSafeAddress"), SAFE);
        assertFalse(vm.keyExistsJson(batch, ".transactions[12]"));
        string[3] memory symbols = ["nOPAL", "nFALCON", "FACTOR"];
        string[4] memory signatures = [
            "requestRedeem(uint256,address,address)",
            "instantRedeem(uint256,address,address)",
            "requestRedeemWithPermit2(uint256,address,address,uint256,uint256,bytes)",
            "instantRedeemWithPermit2(uint256,address,address,uint256,uint256,bytes)"
        ];
        for (uint256 i; i < symbols.length; ++i) {
            VaultDeployConfig memory config = ConfigReader.readOutputConfig(5042, symbols[i]);
            RolesAuthority authority = RolesAuthority(config.contracts.rolesAuthority);
            NestVault vault = NestVault(config.vaults[0].addr);
            assertEq(authority.owner(), SAFE);
            for (uint256 j; j < signatures.length; ++j) {
                bytes4 selector = bytes4(keccak256(bytes(signatures[j])));
                assertFalse(authority.isCapabilityPublic(address(vault), selector));
                string memory path = string.concat(".transactions[", vm.toString(i * 4 + j), "]");
                assertEq(vm.parseJsonAddress(batch, string.concat(path, ".to")), address(authority));
                assertEq(vm.parseJsonString(batch, string.concat(path, ".value")), "0");
                assertEq(vm.parseJsonString(batch, string.concat(path, ".operation")), "0");
                bytes memory data = vm.parseJsonBytes(batch, string.concat(path, ".data"));
                assertEq(data, abi.encodeCall(RolesAuthority.setPublicCapability, (address(vault), selector, true)));
                vm.prank(SAFE);
                (bool ok,) = address(authority).call(data);
                assertTrue(ok);
                assertTrue(authority.isCapabilityPublic(address(vault), selector));
            }
            assertFalse(authority.isCapabilityPublic(address(vault), bytes4(keccak256("deposit(uint256,address)"))));
            assertFalse(authority.isCapabilityPublic(address(vault), bytes4(keccak256("mint(uint256,address)"))));

            // Seed test shares; exercise the real request/cancel flow with no compliance proof.
            // Instant USDC payouts are outside this permission/request regression test.
            address user = makeAddr(symbols[i]);
            uint256 shares = 1_000;
            ERC20 share = ERC20(config.contracts.share);
            deal(address(share), user, shares * 2, true);
            vm.startPrank(user);
            share.approve(address(vault), shares * 2);
            vault.requestRedeem(shares, user, user);
            assertEq(vault.pendingRedeemRequest(0, user), shares);
            vault.updateRedeem(0, user, user);
            assertEq(vault.pendingRedeemRequest(0, user), 0);
            assertEq(share.balanceOf(user), shares * 2);
            vm.stopPrank();
        }
    }
}
