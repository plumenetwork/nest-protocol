// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {BaseConfigScript} from "script/lib/BaseConfigScript.sol";

import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";

import {console} from "forge-std/console.sol";

/// @title  RunIndexingTestTxs
/// @notice Walks every active vault for a given symbol through the full lifecycle
///         (deposit → requestRedeem → fulfillRedeem → redeem → instantRedeem) so backend
///         indexers can observe each event variant. Direct EOA broadcast only.
/// @dev    Assumes `deposit(uint256,address)` is already a public capability on every
///         active vault (true for nTEST). Redeem-side selectors are public per the
///         standard authority.json config; `fulfillRedeem` requires CAN_SOLVE_ROLE which
///         the deployer holds per the vault's `roles` config.
///
///         Inputs (env):
///           VAULT_SYMBOL   — vault config to drive (required)
///           CHAIN_ID       — target chain (required)
///           PRIVATE_KEY    — deployer key (required)
///           NUM_ITERATIONS — uint, default 1. Lifecycle iterations per vault.
///           DEPOSIT_AMOUNT — uint, default 10_000_000 ($10 in 6-decimal USDC). Asset units.
///
///         Usage:
///           VAULT_SYMBOL=nTEST CHAIN_ID=98866 NUM_ITERATIONS=2 DEPOSIT_AMOUNT=10000000 \
///             forge script script/dev/RunIndexingTestTxs.s.sol --sig "runDirect()" \
///             --rpc-url $PLUME_RPC --broadcast
contract RunIndexingTestTxs is BaseConfigScript {
    uint256 private numIterations;
    uint256 private depositAmount;

    function setUp() public {
        loadConfigs(vm.envString("VAULT_SYMBOL"));
        numIterations = vm.envOr("NUM_ITERATIONS", uint256(1));
        depositAmount = vm.envOr("DEPOSIT_AMOUNT", uint256(10_000_000));
        require(numIterations > 0, "RunIndexingTestTxs: NUM_ITERATIONS must be > 0");
        require(depositAmount > 0, "RunIndexingTestTxs: DEPOSIT_AMOUNT must be > 0");
    }

    function runDirect() external {
        address eoa = deployer();
        vm.startBroadcast(deployerPrivateKey);
        _runFlows(eoa);
        vm.stopBroadcast();
    }

    function _runFlows(address actor) internal {
        IShareToken share = IShareToken(vaultConfig.contracts.share);

        for (uint256 iter = 0; iter < numIterations; iter++) {
            console.log("=== iteration", iter + 1, "of", numIterations);
            for (uint256 v = 0; v < vaultConfig.vaults.length; v++) {
                address vault = vaultConfig.vaults[v].addr;
                if (!isActive(vault)) continue;
                _runVaultLifecycle(actor, share, INestVaultCore(vault));
            }
        }
    }

    function _runVaultLifecycle(address actor, IShareToken share, INestVaultCore vault) internal {
        address assetAddr = vault.asset();
        IERC20Like asset = IERC20Like(assetAddr);

        console.log("--- vault", address(vault), "asset", assetAddr);

        // 1) deposit → mint shares
        asset.approve(address(vault), depositAmount);
        uint256 sharesMinted = vault.deposit(depositAmount, actor);
        console.log("    deposit", depositAmount, "-> shares", sharesMinted);
        require(sharesMinted > 1, "RunIndexingTestTxs: deposit yielded too few shares to split");

        // 2) split: half through async path, half through instant path
        uint256 asyncShares = sharesMinted / 2;
        uint256 instantShares = sharesMinted - asyncShares;

        // Single allowance covers both safeTransferFrom calls (requestRedeem + instantRedeem).
        share.approve(address(vault), sharesMinted);

        // 3) async path: requestRedeem → fulfillRedeem → redeem
        vault.requestRedeem(asyncShares, actor, actor);
        console.log("    requestRedeem", asyncShares);

        vault.fulfillRedeem(actor, asyncShares);
        console.log("    fulfillRedeem", asyncShares);

        uint256 redeemAssets = vault.redeem(asyncShares, actor, actor);
        console.log("    redeem -> assets", redeemAssets);

        // 4) instant path
        (uint256 postFee, uint256 feeAmount) = vault.instantRedeem(instantShares, actor, actor);
        console.log("    instantRedeem postFee", postFee, "fee", feeAmount);
    }
}

interface IERC20Like {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IShareToken {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}
