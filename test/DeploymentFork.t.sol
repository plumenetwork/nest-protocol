// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {
    ConfigReader,
    CommonConfig,
    VaultDeployConfig,
    VaultContracts,
    CommonContracts,
    VaultEntry,
    VaultRoles
} from "script/lib/ConfigReader.sol";
import {Constants} from "test/Constants.sol";

// contracts
import {NestVault} from "contracts/NestVault.sol";
import {NestVaultOFT} from "contracts/NestVaultOFT.sol";
import {NestAccountant} from "contracts/accountant/NestAccountant.sol";
import {NestHubAccountant} from "contracts/accountant/NestHubAccountant.sol";
import {NestSpokeAccountant} from "contracts/accountant/NestSpokeAccountant.sol";
import {NestShareOFT} from "contracts/NestShareOFT.sol";
import {NestVaultPredicateProxy} from "contracts/compliance/NestVaultPredicateProxy.sol";
import {NestVaultComposer} from "contracts/integrations/ovault/NestVaultComposer.sol";
import {OperatorRegistry} from "contracts/operators/OperatorRegistry.sol";
import {NestVaultRedeemOperator} from "contracts/operators/NestVaultRedeemOperator.sol";
import {NestShareSeizer} from "contracts/compliance/NestShareSeizer.sol";
import {BlacklistHook} from "contracts/compliance/hooks/BlacklistHook.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {IPredicateManager} from "@predicate/src/interfaces/IPredicateManager.sol";
import {AuthUpgradeable} from "contracts/auth/AuthUpgradeable.sol";

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {IPredicateClient, PredicateMessage} from "@predicate/src/interfaces/IPredicateClient.sol";
import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

// types
import {Errors} from "contracts/types/Errors.sol";
import {NestVaultCoreTypes} from "contracts/types/NestVaultCoreTypes.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

/// @title  DeploymentForkTest
/// @notice Fork test that validates a deployment configuration end-to-end.
///         Reads the vault JSON config, forks the deployment chain, and exercises
///         every contract flow (user + keeper) to assert authorities and permissions.
/// @dev    Usage:
///           VAULT_SYMBOL=nTEST forge test --match-contract DeploymentForkTest -vvv
///         To read from deployment output (written by DeployAndSetup):
///           VAULT_SYMBOL=nTEST USE_OUTPUT=true forge test --match-contract DeploymentForkTest -vvv
contract DeploymentForkTest is Test, Constants {
    using stdJson for string;
    // forceApprove tolerates non-standard ERC20s whose approve() returns no bool
    // (e.g. USDT/TetherToken) and resets a stale non-zero allowance to 0 first.
    using SafeERC20 for IERC20;

    // ─── Config ──────────────────────────────────────────────────────
    VaultDeployConfig internal vaultConfig;
    CommonConfig internal commonConfig;

    // ─── Contracts ───────────────────────────────────────────────────
    NestShareOFT internal share;
    NestAccountant internal accountant;
    RolesAuthority internal rolesAuthority;
    RolesAuthority internal commonRolesAuthority;
    NestVaultPredicateProxy internal predicateProxy;
    OperatorRegistry internal operatorRegistry;
    NestVaultRedeemOperator internal redeemOperator;

    // Per-asset arrays (parallel indexed)
    address[] internal vaults;
    address[] internal composers;
    address[] internal assets;

    // ─── Actors ──────────────────────────────────────────────────────
    address internal owner;
    address[] internal accountantKeepers;
    address[] internal crosschainKeepers;
    address[] internal managers;

    address internal user = makeAddr("user");
    address internal randomUser = makeAddr("randomUser");

    // Per-config arrays
    address[] internal redeemKeepers;

    // ─── Test Amounts ────────────────────────────────────────────────
    uint256 internal constant DEPOSIT_AMOUNT = 100e6; // 100 USDC (6 decimals)
    uint256 internal constant MINT_SHARES = 100e6; // 100 shares (6 decimals)

    // ─── Setup ───────────────────────────────────────────────────────

    function setUp() public {
        string memory vaultSymbol = vm.envString("VAULT_SYMBOL");

        // Load config — use output file if USE_OUTPUT=true, otherwise input config
        uint256 chainId = vm.envUint("CHAIN_ID");
        bool useOutput = _envBoolOr("USE_OUTPUT", true);
        if (useOutput) {
            vaultConfig = ConfigReader.readOutputConfig(chainId, vaultSymbol);
            vaultConfig.deployChainId = chainId;
        } else {
            vaultConfig = ConfigReader.readVaultConfig(vaultSymbol);
            vaultConfig = ConfigReader.resolveConfigForChain(vaultConfig, chainId);
        }
        commonConfig = ConfigReader.readCommonConfig(chainId);

        // Fork — skip if already running on a fork (e.g. --fork-url was passed)
        try vm.activeFork() {
        // already forked, nothing to do
        }
        catch {
            string memory rpcUrl = vm.envString(commonConfig.rpcEnvVar);
            vm.createSelectFork(rpcUrl);
        }

        // Bind contracts
        share = NestShareOFT(payable(vaultConfig.contracts.share));
        accountant = NestAccountant(vaultConfig.contracts.accountant);
        rolesAuthority = RolesAuthority(address(Auth(vaultConfig.contracts.share).authority()));
        predicateProxy = NestVaultPredicateProxy(vaultConfig.common.predicateProxy);
        if (ConfigReader.isActive(address(predicateProxy))) {
            commonRolesAuthority = RolesAuthority(address(Auth(address(predicateProxy)).authority()));
        }

        if (ConfigReader.isActive(vaultConfig.common.operatorRegistry)) {
            operatorRegistry = OperatorRegistry(vaultConfig.common.operatorRegistry);
        }
        if (ConfigReader.isActive(vaultConfig.common.redeemOperator)) {
            redeemOperator = NestVaultRedeemOperator(vaultConfig.common.redeemOperator);
        }

        // Roles
        owner = ConfigReader.resolvedOwner(vaultConfig);
        accountantKeepers = vaultConfig.roles.UPDATE_EXCHANGE_RATE_ROLE;
        crosschainKeepers = vaultConfig.roles.KEEPER_ROLE;
        managers = vaultConfig.roles.MANAGER_ROLE;
        redeemKeepers = vaultConfig.roles.CAN_SOLVE_ROLE;

        // Per-asset addresses
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            VaultEntry memory ve = vaultConfig.vaults[i];
            address assetAddr = ConfigReader.readAssetAddress(chainId, ve.assetSymbol);
            assets.push(assetAddr);
            vaults.push(ve.addr);
            composers.push(ve.composer);
        }

        // Execute Safe owner batch (role/permission setup) if EXECUTE_BATCH=true
        if (_envBoolOr("EXECUTE_BATCH", false)) {
            _executeSafeBatch();
            // Apply authority configuration from JSON configs onto the fork
            _setupAuthority();
        }

        // Mock predicate service manager so deposits pass authorization
        _setupMockPredicate();

        // Fund user with deposit assets
        _fundUser(user, DEPOSIT_AMOUNT * 10);
    }

    // ═══════════════════════════════════════════════════════════════════
    //                    PREDICATE PROXY TESTS
    // ═══════════════════════════════════════════════════════════════════

    function test_predicateProxy_deposit() public {
        if (!_isActive(address(predicateProxy))) return;

        uint256 exercised;
        for (uint256 i = 0; i < vaults.length; i++) {
            if (vaults[i] == address(0)) continue;
            exercised++;
            address asset = assets[i];
            uint256 amount = _normalizeAmount(DEPOSIT_AMOUNT, asset);

            uint256 sharesBefore = share.balanceOf(user);

            vm.startPrank(user);
            IERC20(asset).forceApprove(address(predicateProxy), amount);
            uint256 shares = predicateProxy.deposit(
                ERC20(asset), amount, user, NestVault(payable(vaults[i])), _emptyPredicateMessage()
            );
            vm.stopPrank();

            assertGt(shares, 0, "predicateProxy.deposit: should mint shares");
            assertEq(share.balanceOf(user), sharesBefore + shares, "predicateProxy.deposit: balance mismatch");
        }
        assertGt(exercised, 0, "predicateProxy.deposit: no vaults exercised");
    }

    function test_predicateProxy_mint() public {
        if (!_isActive(address(predicateProxy))) return;

        uint256 exercised;
        for (uint256 i = 0; i < vaults.length; i++) {
            if (vaults[i] == address(0)) continue;
            exercised++;
            address asset = assets[i];
            uint256 sharesToMint = _normalizeAmount(MINT_SHARES, address(share));

            // Approve enough for the mint
            uint256 requiredAssets = NestVault(payable(vaults[i])).previewMint(sharesToMint);

            uint256 sharesBefore = share.balanceOf(user);

            vm.startPrank(user);
            IERC20(asset).forceApprove(address(predicateProxy), requiredAssets);
            uint256 deposited = predicateProxy.mint(
                ERC20(asset), sharesToMint, user, NestVault(payable(vaults[i])), _emptyPredicateMessage()
            );
            vm.stopPrank();

            assertGt(deposited, 0, "predicateProxy.mint: should deposit assets");
            assertEq(share.balanceOf(user), sharesBefore + sharesToMint, "predicateProxy.mint: balance mismatch");
        }
        assertGt(exercised, 0, "predicateProxy.mint: no vaults exercised");
    }

    // ═══════════════════════════════════════════════════════════════════
    //                        NEST VAULT TESTS
    // ═══════════════════════════════════════════════════════════════════

    function test_vault_instantRedeem() public {
        uint256 exercised;
        for (uint256 i = 0; i < vaults.length; i++) {
            if (vaults[i] == address(0)) continue;
            exercised++;
            NestVault vault = NestVault(payable(vaults[i]));
            address asset = assets[i];

            // First deposit to get shares
            uint256 shares = _depositViaProxy(i, user, _normalizeAmount(DEPOSIT_AMOUNT, asset));

            uint256 assetBefore = IERC20(asset).balanceOf(user);

            vm.startPrank(user);
            share.approve(address(vault), shares);
            (uint256 postFee, uint256 fee) = vault.instantRedeem(shares, user, user);
            vm.stopPrank();

            assertGt(postFee, 0, "vault.instantRedeem: should return assets");
            // Fee + postFee should equal the total redemption value
            assertEq(
                IERC20(asset).balanceOf(user), assetBefore + postFee, "vault.instantRedeem: asset balance mismatch"
            );
            // Verify fee is accounted for via previewInstantRedeem
            (uint256 expectedPostFee, uint256 expectedFee) = vault.previewInstantRedeem(shares);
            assertEq(postFee, expectedPostFee, "vault.instantRedeem: postFee mismatch with preview");
            assertEq(fee, expectedFee, "vault.instantRedeem: fee mismatch with preview");
        }
        assertGt(exercised, 0, "vault.instantRedeem: no vaults exercised");
    }

    function test_vault_requestRedeem_fulfillRedeem_redeem() public {
        uint256 exercised;
        for (uint256 i = 0; i < vaults.length; i++) {
            if (vaults[i] == address(0)) continue;
            exercised++;
            NestVault vault = NestVault(payable(vaults[i]));
            address asset = assets[i];

            // Deposit to get shares
            uint256 shares = _depositViaProxy(i, user, _normalizeAmount(DEPOSIT_AMOUNT, asset));

            // requestRedeem
            vm.startPrank(user);
            share.approve(address(vault), shares);
            vault.requestRedeem(shares, user, user);
            vm.stopPrank();

            uint256 pending = vault.pendingRedeemRequest(0, user);
            assertEq(pending, shares, "vault.requestRedeem: pending mismatch");

            // fulfillRedeem (keeper: CAN_SOLVE_ROLE = 11)
            address keeper = _getKeeperWithRole(CAN_SOLVE_ROLE);
            if (keeper == address(0)) {
                // Use owner as fallback — they should be authorized
                keeper = owner;
            }
            vm.prank(keeper);
            vault.fulfillRedeem(user, shares);

            uint256 claimable = vault.claimableRedeemRequest(0, user);
            assertGt(claimable, 0, "vault.fulfillRedeem: should have claimable shares");

            // redeem
            uint256 assetBefore = IERC20(asset).balanceOf(user);
            vm.prank(user);
            uint256 redeemedAssets = vault.redeem(claimable, user, user);

            assertGt(redeemedAssets, 0, "vault.redeem: should return assets");
            assertEq(
                IERC20(asset).balanceOf(user), assetBefore + redeemedAssets, "vault.redeem: asset balance mismatch"
            );
        }
        assertGt(exercised, 0, "vault.requestRedeem_fulfillRedeem_redeem: no vaults exercised");
    }

    function test_vault_updateRedeem() public {
        uint256 exercised;
        for (uint256 i = 0; i < vaults.length; i++) {
            if (vaults[i] == address(0)) continue;
            exercised++;
            NestVault vault = NestVault(payable(vaults[i]));
            address asset = assets[i];

            uint256 shares = _depositViaProxy(i, user, _normalizeAmount(DEPOSIT_AMOUNT, asset));

            // requestRedeem full
            vm.startPrank(user);
            share.approve(address(vault), shares);
            vault.requestRedeem(shares, user, user);
            vm.stopPrank();

            // updateRedeem to reduce by half — user gets shares back
            uint256 halfShares = shares / 2;
            uint256 sharesBefore = share.balanceOf(user);

            vm.prank(user);
            vault.updateRedeem(halfShares, user, user);

            uint256 pendingAfter = vault.pendingRedeemRequest(0, user);
            assertEq(pendingAfter, halfShares, "vault.updateRedeem: pending mismatch");
            assertGt(share.balanceOf(user), sharesBefore, "vault.updateRedeem: shares should be returned");
        }
        assertGt(exercised, 0, "vault.updateRedeem: no vaults exercised");
    }

    function test_vault_deposit_directlyReverts() public {
        // When predicateProxy is set, direct vault deposit should revert for random users
        if (!_isActive(address(predicateProxy))) return;

        uint256 exercised;
        for (uint256 i = 0; i < vaults.length; i++) {
            if (vaults[i] == address(0)) continue;
            exercised++;
            NestVault vault = NestVault(payable(vaults[i]));
            address asset = assets[i];
            uint256 amount = _normalizeAmount(DEPOSIT_AMOUNT, asset);

            deal(asset, randomUser, amount);

            vm.startPrank(randomUser);
            IERC20(asset).forceApprove(address(vault), amount);
            vm.expectRevert();
            vault.deposit(amount, randomUser);
            vm.stopPrank();
        }
        assertGt(exercised, 0, "vault.deposit_directlyReverts: no vaults exercised");
    }

    function test_vault_mint_directlyReverts() public {
        if (!_isActive(address(predicateProxy))) return;

        uint256 exercised;
        for (uint256 i = 0; i < vaults.length; i++) {
            if (vaults[i] == address(0)) continue;
            exercised++;
            NestVault vault = NestVault(payable(vaults[i]));
            address asset = assets[i];
            uint256 amount = _normalizeAmount(DEPOSIT_AMOUNT, asset);

            deal(asset, randomUser, amount);

            vm.startPrank(randomUser);
            IERC20(asset).forceApprove(address(vault), amount);
            vm.expectRevert();
            vault.mint(1e6, randomUser);
            vm.stopPrank();
        }
        assertGt(exercised, 0, "vault.mint_directlyReverts: no vaults exercised");
    }

    // ═══════════════════════════════════════════════════════════════════
    //                      NEST ACCOUNTANT TESTS
    // ═══════════════════════════════════════════════════════════════════

    function test_accountant_updateExchangeRate_keeperOnly() public {
        if (accountantKeepers.length == 0) return;

        address keeper = accountantKeepers[0];

        (uint96 exchangeRate, uint32 minimumUpdateDelayInSeconds,) = _accountantCommon();

        // Resolve chain type and share supply before pranking (Hub requires the supplied
        // totalShareSupply to be >= the live SHARE.totalSupply(); Spoke ignores the arg).
        bool isHub = _expectsHubAccountant();
        uint128 totalShareSupply = uint128(IERC20(address(share)).totalSupply());

        // Warp past minimum update delay
        vm.warp(block.timestamp + minimumUpdateDelayInSeconds + 1);

        // Keeper should succeed
        vm.prank(keeper);
        _callUpdateExchangeRate(isHub, exchangeRate, totalShareSupply); // same rate, within bounds

        // Random user should revert
        vm.warp(block.timestamp + minimumUpdateDelayInSeconds + 1);
        vm.prank(randomUser);
        vm.expectRevert();
        _callUpdateExchangeRate(isHub, exchangeRate, totalShareSupply);
    }

    function test_accountant_claimFees_viaManage() public {
        if (managers.length == 0) return;
        // claimFees lives only on the Hub accountant; Spokes neither accrue nor claim fees,
        // so their implementation has no claimFees selector. manage()-auth itself is covered
        // by test_share_manage_managerOnly.
        if (!_expectsHubAccountant()) return;

        address manager = managers[0];

        // claimFees must be called via manager → share.manage() → accountant.claimFees()
        // This validates MANAGER_ROLE auth and manage() wiring end-to-end
        (,, uint128 feesOwedInBase) = _accountantCommon();

        bytes memory claimFeesCall = abi.encodeWithSelector(NestAccountant.claimFees.selector, ERC20(assets[0]));

        if (feesOwedInBase == 0) {
            // Should revert with ZeroFeesOwed when routed through manage()
            vm.prank(manager);
            vm.expectRevert(Errors.ZeroFeesOwed.selector);
            share.manage(address(accountant), claimFeesCall, 0);
        } else {
            // Fees owed — claim them via manage
            vm.prank(manager);
            share.manage(address(accountant), claimFeesCall, 0);
        }

        // Random user should not be able to call manage
        vm.prank(randomUser);
        vm.expectRevert();
        share.manage(address(accountant), claimFeesCall, 0);
    }

    // ═══════════════════════════════════════════════════════════════════
    //                  FEE FEATURE TESTS (this upgrade)
    // ═══════════════════════════════════════════════════════════════════
    // These exercise the fee machinery introduced by the upgrade. Production
    // configs (e.g. nCREDIT) ship with all fees set to 0, so these tests
    // actively configure non-zero fees on the fork to prove the engine works.
    // Accountant-side tests are gated on the config resolving to a NestHubAccountant
    // on the forked chain (Hub lives only on hubChainId — default 98866; spokes skip).
    // EXECUTE_BATCH=true also replays the pending Upgrade-vault msig batch, so the Hub
    // accountant is live; without it (or off the hub chain) these are expected to fail/skip.

    // ─── NestVault per-type fees ──────────────────────────────────────

    function test_vault_depositFee_accruesAndClaims() public {
        if (managers.length == 0) return;

        uint256 exercised;
        for (uint256 i = 0; i < vaults.length; i++) {
            if (vaults[i] == address(0)) continue;
            exercised++;
            NestVault vault = NestVault(payable(vaults[i]));
            address asset = assets[i];

            // 0.5% deposit fee. maxFees may be 0 on the fork (per-type fee struct is new
            // this upgrade), so raise the cap to FEE_CAP first. flat stays 0.
            address vaultOwner = _authOwner(address(vault));
            vm.startPrank(vaultOwner);
            vault.setMaxFee(
                NestVaultCoreTypes.Fees.Deposit, NestVaultCoreTypes.Fee({rate: NestVaultCoreTypes.FEE_CAP, flat: 0})
            );
            vault.setFee(NestVaultCoreTypes.Fees.Deposit, NestVaultCoreTypes.Fee({rate: 5000, flat: 0}));
            vm.stopPrank();

            uint256 claimableBefore = vault.claimableFees(NestVaultCoreTypes.Fees.Deposit);
            _depositViaProxy(i, user, _normalizeAmount(DEPOSIT_AMOUNT, asset));
            uint256 owed = vault.claimableFees(NestVaultCoreTypes.Fees.Deposit);
            assertGt(owed, claimableBefore, "depositFee: claimable did not grow");

            // Claim is SHARE-only, routed via manager → share.manage() → vault.claimFee().
            address receiver = makeAddr("depositFeeReceiver");
            uint256 recvBefore = IERC20(asset).balanceOf(receiver);
            vm.prank(managers[0]);
            share.manage(
                address(vault),
                abi.encodeWithSignature("claimFee(uint8,address)", uint8(NestVaultCoreTypes.Fees.Deposit), receiver),
                0
            );
            assertEq(IERC20(asset).balanceOf(receiver), recvBefore + owed, "depositFee: receiver payout mismatch");
            assertEq(vault.claimableFees(NestVaultCoreTypes.Fees.Deposit), 0, "depositFee: claimable not cleared");
        }
        assertGt(exercised, 0, "depositFee: no vaults exercised");
    }

    function test_vault_redemptionFee_accrues() public {
        uint256 exercised;
        for (uint256 i = 0; i < vaults.length; i++) {
            if (vaults[i] == address(0)) continue;
            exercised++;
            NestVault vault = NestVault(payable(vaults[i]));
            address asset = assets[i];

            // 0.5% redemption fee on async fulfillment. Raise the cap first (see above).
            address vaultOwner = _authOwner(address(vault));
            vm.startPrank(vaultOwner);
            vault.setMaxFee(
                NestVaultCoreTypes.Fees.Redemption, NestVaultCoreTypes.Fee({rate: NestVaultCoreTypes.FEE_CAP, flat: 0})
            );
            vault.setFee(NestVaultCoreTypes.Fees.Redemption, NestVaultCoreTypes.Fee({rate: 5000, flat: 0}));
            vm.stopPrank();

            uint256 shares = _depositViaProxy(i, user, _normalizeAmount(DEPOSIT_AMOUNT, asset));
            vm.startPrank(user);
            share.approve(address(vault), shares);
            vault.requestRedeem(shares, user, user);
            vm.stopPrank();

            (, uint256 expectedFee) = vault.previewFulfillRedeem(shares);
            assertGt(expectedFee, 0, "redemptionFee: preview fee is zero");

            uint256 claimableBefore = vault.claimableFees(NestVaultCoreTypes.Fees.Redemption);
            address keeper = _getKeeperWithRole(CAN_SOLVE_ROLE);
            if (keeper == address(0)) keeper = owner;
            vm.prank(keeper);
            vault.fulfillRedeem(user, shares);

            assertGt(
                vault.claimableFees(NestVaultCoreTypes.Fees.Redemption),
                claimableBefore,
                "redemptionFee: claimable did not grow"
            );
        }
        assertGt(exercised, 0, "redemptionFee: no vaults exercised");
    }

    function test_vault_setFee_requiresAuth() public {
        uint256 idx = _firstActiveVault();
        if (idx == type(uint256).max) return;

        vm.prank(randomUser);
        vm.expectRevert();
        NestVault(payable(vaults[idx]))
            .setFee(NestVaultCoreTypes.Fees.Deposit, NestVaultCoreTypes.Fee({rate: 5000, flat: 0}));
    }

    // ─── NestHubAccountant management & performance fees ──────────────

    function test_accountant_managementFee_accrues() public {
        if (!_expectsHubAccountant()) return;
        uint256 idx = _firstActiveVault();
        if (idx == type(uint256).max) return;

        // Need live share supply for management-fee accrual.
        _depositViaProxy(idx, user, _normalizeAmount(DEPOSIT_AMOUNT, assets[idx]));
        _widenAccountantBounds();
        NestHubAccountant hub = _hub();

        // Seed lastGrossRate so the management-fee basis (min(lastGross, new)) is non-zero.
        uint96 gross = uint96(hub.getRate());
        _keeperUpdateRate(gross);

        // Enable a 2% annual management fee (checkpoints time).
        vm.prank(_authOwner(address(accountant)));
        hub.updateManagementFee(0.02e6);

        uint128 feesBefore = hub.getAccountantState().feesOwedInBase;

        // Accrue ~30 days under the fee, then re-submit the same gross rate.
        vm.warp(block.timestamp + 30 days);
        address keeper = accountantKeepers.length > 0 ? accountantKeepers[0] : owner;
        uint128 supplyNow = uint128(share.totalSupply());
        vm.prank(keeper);
        hub.updateExchangeRate(gross, supplyNow);

        NestHubAccountant.AccountantState memory s = hub.getAccountantState();
        assertGt(s.feesOwedInBase, feesBefore, "managementFee: feesOwedInBase did not grow");
        assertLt(s.exchangeRate, gross, "managementFee: net rate should fall below gross");
    }

    function test_accountant_performanceFee_accrues() public {
        if (!_expectsHubAccountant()) return;
        uint256 idx = _firstActiveVault();
        if (idx == type(uint256).max) return;

        _depositViaProxy(idx, user, _normalizeAmount(DEPOSIT_AMOUNT, assets[idx]));
        _widenAccountantBounds();
        NestHubAccountant hub = _hub();

        // Seed a known gross-rate checkpoint as keeper.
        uint96 gross = uint96(hub.getRate());
        _keeperUpdateRate(gross);

        // Enable a 10% performance fee with no hurdle / no holdback (all immediate),
        // anchoring the HWM at the current gross rate.
        vm.startPrank(_authOwner(address(accountant)));
        hub.updatePerformanceFee(0.1e6);
        hub.resetHighWaterMark(gross);
        vm.stopPrank();

        uint128 feesBefore = hub.getAccountantState().feesOwedInBase;

        // Submit a +1% gross rate → gain above HWM → performance fee charged.
        uint96 higher = uint96((uint256(gross) * 101) / 100);
        _keeperUpdateRate(higher);

        assertGt(hub.getAccountantState().feesOwedInBase, feesBefore, "performanceFee: feesOwedInBase did not grow");
        assertEq(
            hub.getPerformanceFeeCheckpoint().highWaterMark, higher, "performanceFee: HWM should move to new gross"
        );
    }

    function test_accountant_feeSetters_requireAuth() public {
        if (!_expectsHubAccountant()) return;
        NestHubAccountant hub = _hub();
        vm.startPrank(randomUser);
        vm.expectRevert();
        hub.updateManagementFee(0.01e6);
        vm.expectRevert();
        hub.updatePerformanceFee(0.01e6);
        vm.expectRevert();
        hub.updateHurdleRate(0.01e6);
        vm.expectRevert();
        hub.updateHoldbackRate(0.01e6);
        vm.expectRevert();
        hub.resetHighWaterMark(1e6);
        vm.stopPrank();
    }

    function test_accountant_claimFees_paysPayoutAddress() public {
        if (!_expectsHubAccountant()) return;
        if (managers.length == 0) return;
        uint256 idx = _firstActiveVault();
        if (idx == type(uint256).max) return;

        // Accrue management fees so feesOwedInBase > 0.
        _depositViaProxy(idx, user, _normalizeAmount(DEPOSIT_AMOUNT, assets[idx]));
        _widenAccountantBounds();
        NestHubAccountant hub = _hub();
        // Seed lastGrossRate, then enable a 5% management fee and accrue ~30 days.
        uint96 gross = uint96(hub.getRate());
        _keeperUpdateRate(gross);
        vm.prank(_authOwner(address(accountant)));
        hub.updateManagementFee(0.05e6);
        vm.warp(block.timestamp + 30 days);
        address keeper = accountantKeepers.length > 0 ? accountantKeepers[0] : owner;
        uint128 supplyNow = uint128(share.totalSupply());
        vm.prank(keeper);
        hub.updateExchangeRate(gross, supplyNow);

        NestHubAccountant.AccountantState memory s = hub.getAccountantState();
        if (s.feesOwedInBase == 0) return; // nothing accrued, skip payout assertion
        uint256 owed = s.feesOwedInBase;
        address payout = s.payoutAddress;

        // claimFees pulls the fee asset from SHARE → payoutAddress. Claim in base so
        // the payout equals feesOwedInBase 1:1. Fund + approve from SHARE for the pull.
        ERC20 base = accountant.base();
        deal(address(base), address(share), owed);
        vm.prank(address(share));
        IERC20(address(base)).forceApprove(address(accountant), owed);

        uint256 payoutBefore = IERC20(address(base)).balanceOf(payout);

        vm.prank(managers[0]);
        share.manage(address(accountant), abi.encodeWithSelector(NestHubAccountant.claimFees.selector, base), 0);

        assertEq(IERC20(address(base)).balanceOf(payout), payoutBefore + owed, "claimFees: payout mismatch");
        assertEq(hub.getAccountantState().feesOwedInBase, 0, "claimFees: feesOwed not cleared");
    }

    // ═══════════════════════════════════════════════════════════════════
    //                      NEST SHARE OFT TESTS
    // ═══════════════════════════════════════════════════════════════════

    function test_share_transfer() public {
        // Deposit to get shares, then transfer
        uint256 exercised;
        for (uint256 i = 0; i < vaults.length; i++) {
            if (vaults[i] == address(0)) continue;
            exercised++;

            uint256 shares = _depositViaProxy(i, user, _normalizeAmount(DEPOSIT_AMOUNT, assets[i]));

            address recipient = makeAddr("recipient");
            uint256 recipientBefore = share.balanceOf(recipient);

            vm.prank(user);
            share.transfer(recipient, shares);

            assertEq(share.balanceOf(recipient), recipientBefore + shares, "share.transfer: balance mismatch");
        }
        assertGt(exercised, 0, "share.transfer: no vaults exercised");
    }

    function test_share_manage_managerOnly() public {
        if (managers.length == 0) return;

        address manager = managers[0];

        // Manager should be able to call manage — test with a harmless view call
        bytes memory callData = abi.encodeWithSignature("name()");

        vm.prank(manager);
        share.manage(address(share), callData, 0);

        // Random user should revert
        vm.prank(randomUser);
        vm.expectRevert();
        share.manage(address(share), callData, 0);
    }

    // ═══════════════════════════════════════════════════════════════════
    //                     OPERATOR REGISTRY TESTS
    // ═══════════════════════════════════════════════════════════════════

    function test_operatorRegistry_setOperator() public {
        if (!_isActive(address(operatorRegistry))) return;

        address operator = makeAddr("operator");

        // Test the OperatorRegistry contract directly
        vm.prank(user);
        operatorRegistry.setOperator(operator, true);
        assertTrue(operatorRegistry.isOperator(user, operator), "operatorRegistry: should be approved");

        vm.prank(user);
        operatorRegistry.setOperator(operator, false);
        assertFalse(operatorRegistry.isOperator(user, operator), "operatorRegistry: should be revoked");

        // Also test vault.setOperator to ensure it writes the vault-local mapping
        uint256 exercised;
        for (uint256 i = 0; i < vaults.length; i++) {
            if (vaults[i] == address(0)) continue;
            exercised++;
            NestVault vault = NestVault(payable(vaults[i]));

            vm.prank(user);
            vault.setOperator(operator, true);
            assertTrue(vault.isOperator(user, operator), "vault.setOperator: should be approved");

            vm.prank(user);
            vault.setOperator(operator, false);
            assertFalse(vault.isOperator(user, operator), "vault.setOperator: should be revoked");
        }
        assertGt(exercised, 0, "operatorRegistry: no vaults exercised");
    }

    function test_redeemOperator_redeem() public {
        if (!_isActive(address(redeemOperator))) return;
        if (vaults.length == 0 || vaults[0] == address(0)) return;

        NestVault vault = NestVault(payable(vaults[0]));
        address asset = assets[0];

        // Deposit and request redeem
        uint256 shares = _depositViaProxy(0, user, _normalizeAmount(DEPOSIT_AMOUNT, asset));

        vm.startPrank(user);
        share.approve(address(vault), shares);
        vault.requestRedeem(shares, user, user);
        // Authorize redeemOperator via vault.setOperator
        vault.setOperator(address(redeemOperator), true);
        vm.stopPrank();

        // fulfillAndRedeem by keeper (KEEPER_ROLE = 14 or CAN_SOLVE_ROLE = 11)
        address keeper = _getKeeperWithRole(CAN_SOLVE_ROLE);
        if (keeper == address(0)) keeper = owner;

        // Fulfill first
        vm.prank(keeper);
        vault.fulfillRedeem(user, shares);

        // Now keeper calls redeemOperator.redeem
        address redeemKeeper = _getRedeemOperatorKeeper();
        if (redeemKeeper == address(0)) return; // skip if no keeper configured

        uint256 assetBefore = IERC20(asset).balanceOf(user);

        vm.prank(redeemKeeper);
        uint256 redeemedAssets = redeemOperator.redeem(
            NestVaultRedeemOperator.RedeemRequest({vault: INestVaultCore(vaults[0]), controller: user, shares: shares})
        );

        assertGt(redeemedAssets, 0, "redeemOperator.redeem: should return assets");
        assertEq(IERC20(asset).balanceOf(user), assetBefore + redeemedAssets, "redeemOperator.redeem: balance mismatch");
    }

    function test_redeemOperator_fulfillAndRedeem() public {
        if (!_isActive(address(redeemOperator))) return;
        if (vaults.length == 0 || vaults[0] == address(0)) return;

        NestVault vault = NestVault(payable(vaults[0]));
        address asset = assets[0];

        uint256 shares = _depositViaProxy(0, user, _normalizeAmount(DEPOSIT_AMOUNT, asset));

        vm.startPrank(user);
        share.approve(address(vault), shares);
        vault.requestRedeem(shares, user, user);
        vault.setOperator(address(redeemOperator), true);
        vm.stopPrank();

        address redeemKeeper = _getRedeemOperatorKeeper();
        if (redeemKeeper == address(0)) return;

        uint256 assetBefore = IERC20(asset).balanceOf(user);

        vm.prank(redeemKeeper);
        uint256 redeemedAssets = redeemOperator.fulfillAndRedeem(
            NestVaultRedeemOperator.RedeemRequest({vault: INestVaultCore(vaults[0]), controller: user, shares: shares})
        );

        assertGt(redeemedAssets, 0, "redeemOperator.fulfillAndRedeem: should return assets");
        assertEq(
            IERC20(asset).balanceOf(user),
            assetBefore + redeemedAssets,
            "redeemOperator.fulfillAndRedeem: balance mismatch"
        );
    }

    function test_redeemOperator_redeemAll() public {
        if (!_isActive(address(redeemOperator))) return;
        if (vaults.length == 0 || vaults[0] == address(0)) return;

        NestVault vault = NestVault(payable(vaults[0]));
        address asset = assets[0];

        uint256 shares = _depositViaProxy(0, user, _normalizeAmount(DEPOSIT_AMOUNT, asset));

        vm.startPrank(user);
        share.approve(address(vault), shares);
        vault.requestRedeem(shares, user, user);
        vault.setOperator(address(redeemOperator), true);
        vm.stopPrank();

        // Fulfill first
        address keeper = _getKeeperWithRole(CAN_SOLVE_ROLE);
        if (keeper == address(0)) keeper = owner;
        vm.prank(keeper);
        vault.fulfillRedeem(user, shares);

        address redeemKeeper = _getRedeemOperatorKeeper();
        if (redeemKeeper == address(0)) return;

        uint256 assetBefore = IERC20(asset).balanceOf(user);

        vm.prank(redeemKeeper);
        uint256 redeemedAssets = redeemOperator.redeemAll(INestVaultCore(vaults[0]), user);

        assertGt(redeemedAssets, 0, "redeemOperator.redeemAll: should return assets");
        assertEq(
            IERC20(asset).balanceOf(user), assetBefore + redeemedAssets, "redeemOperator.redeemAll: balance mismatch"
        );
    }

    function test_redeemOperator_fulfillAndRedeemAll() public {
        if (!_isActive(address(redeemOperator))) return;
        if (vaults.length == 0 || vaults[0] == address(0)) return;

        NestVault vault = NestVault(payable(vaults[0]));
        address asset = assets[0];

        uint256 shares = _depositViaProxy(0, user, _normalizeAmount(DEPOSIT_AMOUNT, asset));

        vm.startPrank(user);
        share.approve(address(vault), shares);
        vault.requestRedeem(shares, user, user);
        vault.setOperator(address(redeemOperator), true);
        vm.stopPrank();

        address redeemKeeper = _getRedeemOperatorKeeper();
        if (redeemKeeper == address(0)) return;

        uint256 assetBefore = IERC20(asset).balanceOf(user);

        vm.prank(redeemKeeper);
        uint256 redeemedAssets = redeemOperator.fulfillAndRedeemAll(INestVaultCore(vaults[0]), user);

        assertGt(redeemedAssets, 0, "redeemOperator.fulfillAndRedeemAll: should return assets");
        assertEq(
            IERC20(asset).balanceOf(user),
            assetBefore + redeemedAssets,
            "redeemOperator.fulfillAndRedeemAll: balance mismatch"
        );
    }

    function test_redeemOperator_batchRedeem() public {
        if (!_isActive(address(redeemOperator))) return;
        if (vaults.length == 0 || vaults[0] == address(0)) return;

        NestVault vault = NestVault(payable(vaults[0]));
        address asset = assets[0];

        uint256 shares = _depositViaProxy(0, user, _normalizeAmount(DEPOSIT_AMOUNT, asset));

        vm.startPrank(user);
        share.approve(address(vault), shares);
        vault.requestRedeem(shares, user, user);
        vault.setOperator(address(redeemOperator), true);
        vm.stopPrank();

        // Fulfill
        address keeper = _getKeeperWithRole(CAN_SOLVE_ROLE);
        if (keeper == address(0)) keeper = owner;
        vm.prank(keeper);
        vault.fulfillRedeem(user, shares);

        address redeemKeeper = _getRedeemOperatorKeeper();
        if (redeemKeeper == address(0)) return;

        NestVaultRedeemOperator.RedeemRequest[] memory requests = new NestVaultRedeemOperator.RedeemRequest[](1);
        requests[0] =
            NestVaultRedeemOperator.RedeemRequest({vault: INestVaultCore(vaults[0]), controller: user, shares: shares});

        vm.prank(redeemKeeper);
        uint256[] memory assetsOut = redeemOperator.batchRedeem(requests);

        assertGt(assetsOut[0], 0, "redeemOperator.batchRedeem: should return assets");
    }

    function test_redeemOperator_batchFulfillAndRedeem() public {
        if (!_isActive(address(redeemOperator))) return;
        if (vaults.length == 0 || vaults[0] == address(0)) return;

        NestVault vault = NestVault(payable(vaults[0]));
        address asset = assets[0];

        uint256 shares = _depositViaProxy(0, user, _normalizeAmount(DEPOSIT_AMOUNT, asset));

        vm.startPrank(user);
        share.approve(address(vault), shares);
        vault.requestRedeem(shares, user, user);
        vault.setOperator(address(redeemOperator), true);
        vm.stopPrank();

        address redeemKeeper = _getRedeemOperatorKeeper();
        if (redeemKeeper == address(0)) return;

        NestVaultRedeemOperator.RedeemRequest[] memory requests = new NestVaultRedeemOperator.RedeemRequest[](1);
        requests[0] =
            NestVaultRedeemOperator.RedeemRequest({vault: INestVaultCore(vaults[0]), controller: user, shares: shares});

        vm.prank(redeemKeeper);
        uint256[] memory assetsOut = redeemOperator.batchFulfillAndRedeem(requests);

        assertGt(assetsOut[0], 0, "redeemOperator.batchFulfillAndRedeem: should return assets");
    }

    // ═══════════════════════════════════════════════════════════════════
    //                     NEST SHARE SEIZER TESTS
    // ═══════════════════════════════════════════════════════════════════

    function test_seizer_seize() public {
        // NestShareSeizer is deployed separately — check if it exists via the authority
        address seizer = _findSeizer();
        if (!_isActive(seizer)) return;
        if (vaults.length == 0 || vaults[0] == address(0)) return;

        NestShareSeizer nestSeizer = NestShareSeizer(seizer);

        // Deposit shares to user
        uint256 shares = _depositViaProxy(0, user, _normalizeAmount(DEPOSIT_AMOUNT, assets[0]));

        // Blacklist user first
        BlacklistHook blHook = BlacklistHook(address(share.hook()));
        if (address(blHook) == address(0)) return;

        address blHookOwner = Auth(address(blHook)).owner();
        vm.prank(blHookOwner);
        blHook.blacklist(user);

        address recipient = makeAddr("seizureRecipient");
        uint256 recipientBefore = share.balanceOf(recipient);

        // Seize (owner/authorized caller)
        address seizerOwner = Auth(seizer).owner();
        vm.prank(seizerOwner);
        nestSeizer.seize(share, user, recipient, shares);

        assertEq(share.balanceOf(recipient), recipientBefore + shares, "seizer.seize: recipient balance mismatch");
        assertEq(share.balanceOf(user), 0, "seizer.seize: user should have 0 shares");
        // User should be re-blacklisted
        assertTrue(blHook.isBlacklisted(user), "seizer.seize: user should remain blacklisted");
    }

    function test_seizer_seizeAndRedeem() public {
        address seizer = _findSeizer();
        if (!_isActive(seizer)) return;
        if (vaults.length == 0 || vaults[0] == address(0)) return;

        NestShareSeizer nestSeizer = NestShareSeizer(seizer);
        address asset = assets[0];

        uint256 shares = _depositViaProxy(0, user, _normalizeAmount(DEPOSIT_AMOUNT, asset));

        BlacklistHook blHook = BlacklistHook(address(share.hook()));
        if (address(blHook) == address(0)) return;

        address blHookOwner = Auth(address(blHook)).owner();
        vm.prank(blHookOwner);
        blHook.blacklist(user);

        address recipient = makeAddr("seizureRecipient");
        uint256 recipientAssetBefore = IERC20(asset).balanceOf(recipient);

        address seizerOwner = Auth(seizer).owner();
        vm.prank(seizerOwner);
        nestSeizer.seizeAndRedeem(INestVaultCore(vaults[0]), user, recipient, shares);

        assertGt(
            IERC20(asset).balanceOf(recipient),
            recipientAssetBefore,
            "seizer.seizeAndRedeem: recipient should receive assets"
        );
        assertEq(share.balanceOf(user), 0, "seizer.seizeAndRedeem: user should have 0 shares");
        assertTrue(blHook.isBlacklisted(user), "seizer.seizeAndRedeem: user should remain blacklisted");
    }

    // ═══════════════════════════════════════════════════════════════════
    //                      BLACKLIST HOOK TESTS
    // ═══════════════════════════════════════════════════════════════════

    function test_blacklistHook_pause() public {
        BlacklistHook blHook = BlacklistHook(address(share.hook()));
        if (address(blHook) == address(0)) return;

        // Deposit shares so the paused-transfer test is exercised
        if (vaults.length > 0 && vaults[0] != address(0)) {
            _depositViaProxy(0, user, _normalizeAmount(DEPOSIT_AMOUNT, assets[0]));
        }
        require(share.balanceOf(user) > 0, "blacklistHook.pause: user must have shares to test transfer block");

        // Owner can pause
        vm.prank(owner);
        blHook.pause();
        assertTrue(blHook.isPaused(), "blacklistHook.pause: should be paused");

        // Transfers should fail while paused
        vm.prank(user);
        vm.expectRevert(BlacklistHook.BlacklistHook__Paused.selector);
        share.transfer(randomUser, 1);

        // Owner can unpause
        vm.prank(owner);
        blHook.unpause();
        assertFalse(blHook.isPaused(), "blacklistHook.unpause: should be unpaused");

        // Random user cannot pause
        vm.prank(randomUser);
        vm.expectRevert();
        blHook.pause();
    }

    function test_blacklistHook_setBlacklist() public {
        BlacklistHook blHook = BlacklistHook(address(share.hook()));
        if (address(blHook) == address(0)) return;

        // Deposit to user first so they have shares
        if (vaults.length > 0 && vaults[0] != address(0)) {
            _depositViaProxy(0, user, _normalizeAmount(DEPOSIT_AMOUNT, assets[0]));
        }

        // Owner can blacklist
        address blHookOwner = Auth(address(blHook)).owner();
        vm.prank(blHookOwner);
        blHook.blacklist(user);
        assertTrue(blHook.isBlacklisted(user), "blacklistHook.setBlacklist: should be blacklisted");

        // Blacklisted user cannot transfer
        if (share.balanceOf(user) > 0) {
            vm.prank(user);
            vm.expectRevert(abi.encodeWithSelector(BlacklistHook.BlacklistHook__Blacklisted.selector, user));
            share.transfer(randomUser, 1);
        }

        // Owner can remove from blacklist
        vm.prank(blHookOwner);
        blHook.unblacklist(user);
        assertFalse(blHook.isBlacklisted(user), "blacklistHook.setBlacklist: should be unblacklisted");

        // Random user cannot set blacklist
        vm.prank(randomUser);
        vm.expectRevert();
        blHook.blacklist(user);
    }

    // ═══════════════════════════════════════════════════════════════════
    //                     NEST COMPOSER TESTS
    // ═══════════════════════════════════════════════════════════════════

    // Note: Cross-chain composer tests require LayerZero endpoint mocking.
    // Auth/capability tests use unauthorized callers; flow tests use local sends (dstEid = VAULT_EID).

    function test_composer_exists_and_authorized() public view {
        uint256 exercised;
        for (uint256 i = 0; i < composers.length; i++) {
            if (!_isActive(composers[i])) continue;
            exercised++;

            // Verify composer has COMPOSER_ROLE assigned
            assertTrue(
                rolesAuthority.doesUserHaveRole(composers[i], COMPOSER_ROLE), "composer: should have COMPOSER_ROLE"
            );
        }
        // Only assert if any composers are configured
        if (exercised == 0) return;
    }

    function test_composer_capabilities() public {
        uint256 exercised;
        for (uint256 i = 0; i < composers.length; i++) {
            if (!_isActive(composers[i])) continue;
            exercised++;

            NestVaultComposer composer = NestVaultComposer(payable(composers[i]));

            // Verify COMPOSER_ROLE has the required capabilities on vault for all composer routes
            if (vaults[i] != address(0)) {
                bytes4 instantRedeemSel = bytes4(keccak256("instantRedeem(uint256,address,address)"));
                bytes4 requestRedeemSel = bytes4(keccak256("requestRedeem(uint256,address,address)"));
                bytes4 redeemSel = bytes4(keccak256("redeem(uint256,address,address)"));

                assertTrue(
                    rolesAuthority.doesRoleHaveCapability(COMPOSER_ROLE, vaults[i], instantRedeemSel),
                    "composer: COMPOSER_ROLE should have instantRedeem capability on vault"
                );
                assertTrue(
                    rolesAuthority.doesRoleHaveCapability(COMPOSER_ROLE, vaults[i], requestRedeemSel),
                    "composer: COMPOSER_ROLE should have requestRedeem capability on vault"
                );
                assertTrue(
                    rolesAuthority.doesRoleHaveCapability(COMPOSER_ROLE, vaults[i], redeemSel),
                    "composer: COMPOSER_ROLE should have redeem capability on vault"
                );
            }

            // Verify COMPOSER_ROLE has updateRedeem capability on vault
            if (vaults[i] != address(0)) {
                bytes4 updateRedeemSel = bytes4(keccak256("updateRedeem(uint256,address,address)"));
                assertTrue(
                    rolesAuthority.doesRoleHaveCapability(COMPOSER_ROLE, vaults[i], updateRedeemSel),
                    "composer: COMPOSER_ROLE should have updateRedeem capability on vault"
                );
            }

            // Verify unauthorized caller cannot call composer entrypoints
            vm.prank(randomUser);
            vm.expectRevert();
            composer.depositAndSend(bytes32(uint256(uint160(randomUser))), 1e6, _emptySendParam(), randomUser);

            vm.prank(randomUser);
            vm.expectRevert();
            composer.redeemAndSend(bytes32(uint256(uint160(randomUser))), 1e6, _emptySendParam(), randomUser);

            vm.prank(randomUser);
            vm.expectRevert();
            composer.finishRedeemAndSend(1, bytes32(uint256(uint160(randomUser))), _emptySendParam(), randomUser);

            vm.prank(randomUser);
            vm.expectRevert();
            composer.updateRequestRedeemAndSend(1, bytes32(uint256(uint160(randomUser))), _emptySendParam(), randomUser);
        }
        if (exercised == 0) return;
    }

    function test_composer_depositAndSend_local() public {
        uint256 exercised;
        for (uint256 i = 0; i < composers.length; i++) {
            if (!_isActive(composers[i])) continue;
            if (vaults[i] == address(0)) continue;
            exercised++;

            NestVaultComposer composer = NestVaultComposer(payable(composers[i]));
            uint32 vaultEid = composer.VAULT_EID();
            address recipient = makeAddr("composerDepositRecipient");

            uint256 depositAmount = _normalizeAmount(DEPOSIT_AMOUNT, assets[i]);

            // Fund owner with assets and approve composer
            deal(assets[i], owner, depositAmount);
            vm.prank(owner);
            IERC20(assets[i]).forceApprove(address(composer), depositAmount);

            // Build local SendParam (dstEid = VAULT_EID routes to _sendLocal, no LZ)
            bytes memory predicateMsg = abi.encode(_emptyPredicateMessage());
            SendParam memory sendParam = SendParam({
                dstEid: vaultEid,
                to: bytes32(uint256(uint160(recipient))),
                amountLD: 0,
                minAmountLD: 0,
                extraOptions: "",
                composeMsg: "",
                oftCmd: predicateMsg
            });

            uint256 recipientSharesBefore = IERC20(address(share)).balanceOf(recipient);

            vm.prank(owner);
            composer.depositAndSend(depositAmount, sendParam, owner);

            uint256 recipientSharesAfter = IERC20(address(share)).balanceOf(recipient);
            assertGt(
                recipientSharesAfter, recipientSharesBefore, "composer.depositAndSend: recipient should receive shares"
            );
        }
        if (exercised == 0) return;
    }

    function test_composer_redeemAndSend_local() public {
        uint256 exercised;
        for (uint256 i = 0; i < composers.length; i++) {
            if (!_isActive(composers[i])) continue;
            if (vaults[i] == address(0)) continue;
            exercised++;

            NestVaultComposer composer = NestVaultComposer(payable(composers[i]));
            uint32 vaultEid = composer.VAULT_EID();
            address recipient = makeAddr("composerRedeemRecipient");

            // Deposit first to get shares (as owner)
            uint256 depositAmount = _normalizeAmount(DEPOSIT_AMOUNT, assets[i]);
            deal(assets[i], owner, depositAmount);
            vm.startPrank(owner);
            IERC20(assets[i]).forceApprove(address(predicateProxy), depositAmount);
            uint256 shares = predicateProxy.deposit(
                ERC20(assets[i]), depositAmount, owner, NestVault(payable(vaults[i])), _emptyPredicateMessage()
            );
            vm.stopPrank();
            assertGt(shares, 0, "composer.redeemAndSend: should have shares to redeem");

            // Approve composer for shares
            vm.prank(owner);
            IERC20(address(share)).approve(address(composer), shares);

            // Build local SendParam
            SendParam memory sendParam = SendParam({
                dstEid: vaultEid,
                to: bytes32(uint256(uint160(recipient))),
                amountLD: 0,
                minAmountLD: 0,
                extraOptions: "",
                composeMsg: "",
                oftCmd: ""
            });

            uint256 recipientAssetsBefore = IERC20(assets[i]).balanceOf(recipient);

            vm.prank(owner);
            composer.redeemAndSend(shares, sendParam, owner);

            uint256 recipientAssetsAfter = IERC20(assets[i]).balanceOf(recipient);
            assertGt(
                recipientAssetsAfter, recipientAssetsBefore, "composer.redeemAndSend: recipient should receive assets"
            );
        }
        if (exercised == 0) return;
    }

    // ═══════════════════════════════════════════════════════════════════
    //                    AUTHORITY VERIFICATION TESTS
    // ═══════════════════════════════════════════════════════════════════

    function test_authority_vaultHasTellerRole() public view {
        for (uint256 i = 0; i < vaults.length; i++) {
            if (vaults[i] == address(0)) continue;
            assertTrue(
                rolesAuthority.doesUserHaveRole(vaults[i], TELLER_ROLE), "authority: vault should have TELLER_ROLE"
            );
        }
    }

    function test_authority_predicateProxyHasPredicateRole() public view {
        if (!_isActive(address(predicateProxy))) return;
        assertTrue(
            rolesAuthority.doesUserHaveRole(address(predicateProxy), PREDICATE_PROXY_ROLE),
            "authority: predicateProxy should have PREDICATE_PROXY_ROLE"
        );
    }

    function test_authority_accountantKeepersHaveUpdateRole() public view {
        for (uint256 i = 0; i < accountantKeepers.length; i++) {
            assertTrue(
                rolesAuthority.doesUserHaveRole(accountantKeepers[i], UPDATE_EXCHANGE_RATE_ROLE),
                "authority: accountant keeper should have UPDATE_EXCHANGE_RATE_ROLE"
            );
        }
    }

    function test_authority_managersHaveManagerRole() public view {
        for (uint256 i = 0; i < managers.length; i++) {
            assertTrue(
                rolesAuthority.doesUserHaveRole(managers[i], MANAGER_ROLE),
                "authority: manager should have MANAGER_ROLE"
            );
        }
    }

    function test_authority_shareEnterExitRequiresTellerRole() public view {
        // enter and exit on share should require TELLER_ROLE
        assertTrue(
            rolesAuthority.doesRoleHaveCapability(TELLER_ROLE, address(share), NestShareOFT.enter.selector),
            "authority: TELLER_ROLE should have enter capability on share"
        );
        assertTrue(
            rolesAuthority.doesRoleHaveCapability(TELLER_ROLE, address(share), NestShareOFT.exit.selector),
            "authority: TELLER_ROLE should have exit capability on share"
        );
    }

    function test_authority_managerCanManageShare() public view {
        assertTrue(
            rolesAuthority.doesRoleHaveCapability(
                MANAGER_ROLE, address(share), bytes4(keccak256("manage(address,bytes,uint256)"))
            ),
            "authority: MANAGER_ROLE should have manage capability on share"
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //                          HELPERS
    // ═══════════════════════════════════════════════════════════════════

    function _setupMockPredicate() internal {
        if (!_isActive(address(predicateProxy))) return;

        // Mock validateSignatures on the deployed service manager to always return true
        address serviceManager = predicateProxy.getPredicateManager();
        vm.mockCall(
            serviceManager, abi.encodeWithSelector(IPredicateManager.validateSignatures.selector), abi.encode(true)
        );
    }

    function _fundUser(address _user, uint256 _baseAmount) internal {
        for (uint256 i = 0; i < assets.length; i++) {
            uint256 amount = _normalizeAmount(_baseAmount, assets[i]);
            deal(assets[i], _user, amount);
        }
    }

    function _depositViaProxy(uint256 _assetIndex, address _depositor, uint256 _amount)
        internal
        returns (uint256 _shares)
    {
        address vault = vaults[_assetIndex];
        address asset = assets[_assetIndex];
        require(vault != address(0), "vault not set for asset index");

        if (_isActive(address(predicateProxy))) {
            vm.startPrank(_depositor);
            IERC20(asset).forceApprove(address(predicateProxy), _amount);
            _shares = predicateProxy.deposit(
                ERC20(asset), _amount, _depositor, NestVault(payable(vault)), _emptyPredicateMessage()
            );
            vm.stopPrank();
        } else {
            vm.startPrank(_depositor);
            IERC20(asset).forceApprove(vault, _amount);
            _shares = NestVault(payable(vault)).deposit(_amount, _depositor);
            vm.stopPrank();
        }
    }

    function _emptyPredicateMessage() internal pure returns (PredicateMessage memory) {
        return PredicateMessage({
            taskId: "", expireByTime: type(uint256).max, signerAddresses: new address[](0), signatures: new bytes[](0)
        });
    }

    function _normalizeAmount(uint256 _amount, address _token) internal view returns (uint256) {
        uint8 tokenDecimals = IERC20Metadata(_token).decimals();
        if (tokenDecimals == 6) return _amount;
        if (tokenDecimals > 6) return _amount * 10 ** (tokenDecimals - 6);
        return _amount / 10 ** (6 - tokenDecimals);
    }

    function _getKeeperWithRole(uint8 _role) internal view returns (address) {
        // Check accountant keepers first
        for (uint256 i = 0; i < accountantKeepers.length; i++) {
            if (rolesAuthority.doesUserHaveRole(accountantKeepers[i], _role)) {
                return accountantKeepers[i];
            }
        }
        // Check crosschain keepers
        for (uint256 i = 0; i < crosschainKeepers.length; i++) {
            if (rolesAuthority.doesUserHaveRole(crosschainKeepers[i], _role)) {
                return crosschainKeepers[i];
            }
        }
        // Check owner
        if (rolesAuthority.doesUserHaveRole(owner, _role)) {
            return owner;
        }
        return address(0);
    }

    function _getRedeemOperatorKeeper() internal view returns (address) {
        // Redeem operator is governed by commonRolesAuthority, not rolesAuthority.
        // Keepers need KEEPER_ROLE (14) on the common authority.
        if (address(commonRolesAuthority) == address(0)) return address(0);

        // Check the dedicated redeemKeepers config array first.
        for (uint256 i = 0; i < redeemKeepers.length; i++) {
            if (commonRolesAuthority.doesUserHaveRole(redeemKeepers[i], KEEPER_ROLE)) {
                return redeemKeepers[i];
            }
        }
        // Fallback: check other keeper arrays
        for (uint256 i = 0; i < crosschainKeepers.length; i++) {
            if (commonRolesAuthority.doesUserHaveRole(crosschainKeepers[i], KEEPER_ROLE)) {
                return crosschainKeepers[i];
            }
        }
        for (uint256 i = 0; i < accountantKeepers.length; i++) {
            if (commonRolesAuthority.doesUserHaveRole(accountantKeepers[i], KEEPER_ROLE)) {
                return accountantKeepers[i];
            }
        }
        return address(0);
    }

    function _findSeizer() internal view returns (address) {
        return vaultConfig.common.seizer;
    }

    function _emptySendParam() internal pure returns (SendParam memory) {
        return SendParam({
            dstEid: 0, to: bytes32(0), amountLD: 0, minAmountLD: 0, extraOptions: "", composeMsg: "", oftCmd: ""
        });
    }

    /// @dev Replays a Safe transaction-builder JSON batch as `owner`.
    function _executeSafeBatch() internal {
        // Replay the role/permission setup batch (required).
        _replayMsigBatch("DeployAndSetup", true, false);
        // Then apply the pending fee upgrade (NestHubAccountant + new vault/composer
        // impls) so the Hub fee tests exercise upgraded code. Optional + tolerant: an
        // absent file, or impls not yet deployed on the fork, are skipped rather than
        // failing setUp — so non-Hub tests keep running.
        _replayMsigBatch("Upgrade-vault", false, true);
    }

    /// @dev Replays a Safe batch from script/output/msig/<chain>-<symbol>-<kind>.json,
    ///      pranking the correct caller per tx.
    /// @param required             revert if the batch file is absent
    /// @param tolerateMissingImpl  for upgradeAndCall txs, skip the batch (instead of
    ///                             reverting) when the target impl has no code on the fork
    function _replayMsigBatch(string memory batchKind, bool required, bool tolerateMissingImpl) internal {
        string memory batchPath = string.concat(
            "script/output/msig/",
            vm.toString(vaultConfig.deployChainId),
            "-",
            vaultConfig.symbol,
            "-",
            batchKind,
            ".json"
        );

        string memory json;
        try vm.readFile(batchPath) returns (string memory j) {
            json = j;
        } catch {
            require(!required, string.concat("DeploymentForkTest: missing required batch ", batchPath));
            return;
        }

        for (uint256 i = 0; i < 50; i++) {
            string memory key = string.concat(".transactions[", vm.toString(i), "]");
            if (!vm.keyExistsJson(json, key)) break;

            address to = vm.parseJsonAddress(json, string.concat(key, ".to"));
            bytes memory data = vm.parseJsonBytes(json, string.concat(key, ".data"));

            // upgradeAndCall(proxy, impl, data): if the new impl isn't deployed on this
            // fork, OZ's _setImplementation would revert. Skip the rest of the batch so
            // setUp survives and config-gated Hub tests fail explicitly instead.
            if (tolerateMissingImpl && data.length >= 68 && bytes4(data) == 0x9623609d) {
                address impl;
                assembly {
                    impl := mload(add(data, 68))
                }
                if (impl.code.length == 0) {
                    emit log_named_address("DeploymentForkTest: skipping upgrade batch, impl not on fork", impl);
                    return;
                }
            }

            // Determine the right caller: contract owner for Auth contracts,
            // or the OApp's LZ endpoint delegate for endpoint calls
            address caller = _batchTxCaller(to, data);
            vm.prank(caller, caller);
            (bool success,) = to.call(data);
            require(success, string.concat("SafeBatch tx[", vm.toString(i), "] failed"));
        }
    }

    /// @dev Determines the right msg.sender for a batch transaction.
    ///      For Auth-based contracts, returns the on-chain owner.
    ///      For LZ endpoint calls, queries the OApp's delegate.
    function _batchTxCaller(address to, bytes memory data) internal view returns (address) {
        // acceptOwnership() — caller must be pendingOwner (AuthUpgradeable / Ownable2Step)
        if (data.length == 4 && bytes4(data) == 0x79ba5097) {
            (bool ok, bytes memory ret) = to.staticcall(abi.encodeWithSignature("pendingOwner()"));
            if (ok && ret.length == 32) {
                address p = abi.decode(ret, (address));
                if (p != address(0)) return p;
            }
        }

        // upgradeAndCall(proxy, impl, data) — caller must be the ProxyAdmin (Ownable) owner
        if (data.length >= 4 && bytes4(data) == 0x9623609d) {
            (bool ok, bytes memory ret) = to.staticcall(abi.encodeWithSignature("owner()"));
            if (ok && ret.length == 32) {
                address o = abi.decode(ret, (address));
                if (o != address(0)) return o;
            }
        }

        // Try solmate Auth contracts (have both owner() and authority())
        try Auth(to).authority() {
            try Auth(to).owner() returns (address o) {
                if (o != address(0)) return o;
            } catch {}
        } catch {}

        // For LZ endpoint calls (e.g. setConfig), the first calldata param is the OApp.
        // Query the endpoint's delegates mapping for that OApp.
        if (data.length >= 36) {
            address oapp;
            assembly {
                oapp := mload(add(data, 36))
            }
            (bool ok, bytes memory ret) = to.staticcall(abi.encodeWithSignature("delegates(address)", oapp));
            if (ok && ret.length == 32) {
                address delegate = abi.decode(ret, (address));
                if (delegate != address(0)) return delegate;
            }
        }

        return owner;
    }

    function _envBoolOr(string memory key, bool defaultValue) internal view returns (bool) {
        try vm.envBool(key) returns (bool val) {
            return val;
        } catch {
            return defaultValue;
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //                    AUTHORITY SETUP FROM CONFIG
    // ═══════════════════════════════════════════════════════════════════

    /// @dev Reads authority JSON configs and applies capabilities + role assignments on the fork.
    function _setupAuthority() internal {
        _ensureAuthoritySet();

        string memory root = vm.projectRoot();

        // Vault authority (governs share, accountant, vaults, composers)
        {
            string memory json = vm.readFile(string.concat(root, "/config/authority/authority.json"));
            address authOwner = Auth(address(rolesAuthority)).owner();
            _applyCapabilities(json, address(rolesAuthority), authOwner);
            _applyPublicCapabilities(json, address(rolesAuthority), authOwner);
            _applyRoleAssignments(json, address(rolesAuthority), authOwner);
        }

        // Common authority (governs predicateProxy, redeemOperator, cctpRelayer, operatorRegistry)
        if (address(commonRolesAuthority) != address(0)) {
            string memory json = vm.readFile(string.concat(root, "/config/authority/common-authority.json"));
            address authOwner = Auth(address(commonRolesAuthority)).owner();
            _applyCapabilities(json, address(commonRolesAuthority), authOwner);
            _applyPublicCapabilities(json, address(commonRolesAuthority), authOwner);
            _applyRoleAssignments(json, address(commonRolesAuthority), authOwner);
        }
    }

    function _ensureAuthoritySet() internal {
        for (uint256 i = 0; i < vaults.length; i++) {
            if (vaults[i] != address(0)) _setAuthorityOn(vaults[i], address(rolesAuthority));
            if (i < composers.length && _isActive(composers[i])) {
                _setAuthorityOn(composers[i], address(rolesAuthority));
            }
        }
        _setAuthorityOn(address(share), address(rolesAuthority));
        _setAuthorityOn(address(accountant), address(rolesAuthority));

        if (address(commonRolesAuthority) != address(0)) {
            if (_isActive(address(predicateProxy))) {
                _setAuthorityOn(address(predicateProxy), address(commonRolesAuthority));
            }
            if (_isActive(vaultConfig.common.cctpRelayer)) {
                _setAuthorityOn(vaultConfig.common.cctpRelayer, address(commonRolesAuthority));
            }
            if (_isActive(vaultConfig.common.redeemOperator)) {
                _setAuthorityOn(vaultConfig.common.redeemOperator, address(commonRolesAuthority));
            }
            if (_isActive(vaultConfig.common.blacklistHook)) {
                _setAuthorityOn(vaultConfig.common.blacklistHook, address(commonRolesAuthority));
            }
        }
    }

    function _setAuthorityOn(address target, address auth) internal {
        if (address(Auth(target).authority()) == auth) return;
        vm.prank(Auth(target).owner());
        Auth(target).setAuthority(Authority(auth));
    }

    function _applyCapabilities(string memory json, address auth, address authOwner) internal {
        bytes memory raw = json.parseRaw(".capabilities");
        bytes[] memory arr = abi.decode(raw, (bytes[]));

        for (uint256 i = 0; i < arr.length; i++) {
            string memory p = string.concat(".capabilities[", vm.toString(i), "]");

            string memory conditionalOn = _tryReadJsonString(json, string.concat(p, ".conditionalOn"));
            if (bytes(conditionalOn).length > 0 && !_checkAuthorityCondition(conditionalOn)) continue;

            uint8 role = uint8(json.readUint(string.concat(p, ".role")));
            address[] memory targets = _resolveTargets(json.readString(string.concat(p, ".target")));
            string[] memory fns = json.readStringArray(string.concat(p, ".functions"));

            for (uint256 t = 0; t < targets.length; t++) {
                if (!_isActive(targets[t])) continue;
                for (uint256 f = 0; f < fns.length; f++) {
                    vm.prank(authOwner);
                    RolesAuthority(auth).setRoleCapability(role, targets[t], bytes4(keccak256(bytes(fns[f]))), true);
                }
            }
        }
    }

    function _applyPublicCapabilities(string memory json, address auth, address authOwner) internal {
        bytes memory raw = json.parseRaw(".publicCapabilities");
        bytes[] memory arr = abi.decode(raw, (bytes[]));

        for (uint256 i = 0; i < arr.length; i++) {
            string memory p = string.concat(".publicCapabilities[", vm.toString(i), "]");

            string memory conditionalOn = _tryReadJsonString(json, string.concat(p, ".conditionalOn"));
            if (bytes(conditionalOn).length > 0 && !_checkAuthorityCondition(conditionalOn)) continue;

            address[] memory targets = _resolveTargets(json.readString(string.concat(p, ".target")));
            string[] memory fns = json.readStringArray(string.concat(p, ".functions"));

            for (uint256 t = 0; t < targets.length; t++) {
                if (!_isActive(targets[t])) continue;
                for (uint256 f = 0; f < fns.length; f++) {
                    vm.prank(authOwner);
                    RolesAuthority(auth).setPublicCapability(targets[t], bytes4(keccak256(bytes(fns[f]))), true);
                }
            }
        }
    }

    function _applyRoleAssignments(string memory json, address auth, address authOwner) internal {
        bytes memory raw = json.parseRaw(".roleAssignments");
        bytes[] memory arr = abi.decode(raw, (bytes[]));

        for (uint256 i = 0; i < arr.length; i++) {
            string memory p = string.concat(".roleAssignments[", vm.toString(i), "]");

            string memory conditionalOn = _tryReadJsonString(json, string.concat(p, ".conditionalOn"));
            if (bytes(conditionalOn).length > 0 && !_checkAuthorityCondition(conditionalOn)) continue;

            uint8 role = uint8(json.readUint(string.concat(p, ".role")));
            address[] memory users = _resolveUsers(json.readString(string.concat(p, ".user")));

            for (uint256 u = 0; u < users.length; u++) {
                if (!_isActive(users[u])) continue;
                vm.prank(authOwner);
                RolesAuthority(auth).setUserRole(users[u], role, true);
            }
        }
    }

    function _resolveTargets(string memory name) internal view returns (address[] memory) {
        bytes32 h = keccak256(bytes(name));
        if (h == keccak256("vault")) return vaults;
        if (h == keccak256("composer")) return composers;
        if (h == keccak256("share")) return _singletonArray(address(share));
        if (h == keccak256("accountant")) return _singletonArray(address(accountant));
        if (h == keccak256("cctpRelayer")) return _singletonArray(vaultConfig.common.cctpRelayer);
        if (h == keccak256("redeemOperator")) return _singletonArray(vaultConfig.common.redeemOperator);
        if (h == keccak256("operatorRegistry")) return _singletonArray(vaultConfig.common.operatorRegistry);
        if (h == keccak256("predicateProxy")) return _singletonArray(address(predicateProxy));
        if (h == keccak256("complianceProxy")) return _singletonArray(vaultConfig.common.complianceProxy);
        if (h == keccak256("shareSeizer")) return _singletonArray(vaultConfig.common.seizer);
        if (h == keccak256("blacklistHook")) return _singletonArray(vaultConfig.common.blacklistHook);
        if (h == keccak256("nestAdapter")) return _singletonArray(vaultConfig.common.nestAdapter);
        if (h == keccak256("nestBundler")) return _singletonArray(vaultConfig.common.nestBundler);
        if (h == keccak256("nestUnlooper")) return _singletonArray(vaultConfig.common.nestUnlooper);
        revert(string.concat("_resolveTargets: unknown '", name, "'"));
    }

    function _resolveUsers(string memory name) internal view returns (address[] memory) {
        bytes32 h = keccak256(bytes(name));
        if (h == keccak256("vault")) return vaults;
        if (h == keccak256("composer")) return composers;
        if (h == keccak256("share")) return _singletonArray(address(share));
        if (h == keccak256("blacklistHook")) return _singletonArray(vaultConfig.common.blacklistHook);
        if (h == keccak256("predicateProxy")) return _singletonArray(address(predicateProxy));
        if (h == keccak256("cctpRelayer")) return _singletonArray(vaultConfig.common.cctpRelayer);
        if (h == keccak256("redeemOperator")) return _singletonArray(vaultConfig.common.redeemOperator);
        if (h == keccak256("owner")) return _singletonArray(owner);
        if (h == keccak256("shareSeizer")) return _singletonArray(vaultConfig.common.seizer);
        if (h == keccak256("nestAdapter")) return _singletonArray(vaultConfig.common.nestAdapter);
        if (h == keccak256("nestBundler")) return _singletonArray(vaultConfig.common.nestBundler);
        if (h == keccak256("nestUnlooper")) return _singletonArray(vaultConfig.common.nestUnlooper);
        if (h == keccak256("MANAGER_ROLE")) return managers;
        if (h == keccak256("UPDATE_EXCHANGE_RATE_ROLE")) return accountantKeepers;
        if (h == keccak256("KEEPER_ROLE")) return crosschainKeepers;
        if (h == keccak256("CAN_SOLVE_ROLE")) return redeemKeepers;
        if (h == keccak256("OWNER_ROLE")) return vaultConfig.roles.OWNER_ROLE;
        if (h == keccak256("PAUSER_ROLE")) return vaultConfig.roles.PAUSER_ROLE;
        if (h == keccak256("DEPOSITOR_ROLE")) return vaultConfig.roles.DEPOSITOR_ROLE;
        revert(string.concat("_resolveUsers: unknown '", name, "'"));
    }

    function _checkAuthorityCondition(string memory condition) internal view returns (bool) {
        bytes32 h = keccak256(bytes(condition));
        if (h == keccak256("predicateProxy")) return _isActive(address(predicateProxy));
        if (h == keccak256("noPredicateProxy")) return !_isActive(address(predicateProxy));
        if (h == keccak256("composer")) {
            for (uint256 i = 0; i < composers.length; i++) {
                if (_isActive(composers[i])) return true;
            }
            return false;
        }
        if (h == keccak256("cctpRelayer")) return _isActive(vaultConfig.common.cctpRelayer);
        if (h == keccak256("redeemOperator")) return _isActive(vaultConfig.common.redeemOperator);
        if (h == keccak256("operatorRegistry")) return _isActive(vaultConfig.common.operatorRegistry);
        if (h == keccak256("shareSeizer")) return _isActive(vaultConfig.common.seizer);
        if (h == keccak256("blacklistHook")) return _isActive(vaultConfig.common.blacklistHook);
        if (h == keccak256("nestAdapter")) return _isActive(vaultConfig.common.nestAdapter);
        if (h == keccak256("nestBundler")) return _isActive(vaultConfig.common.nestBundler);
        if (h == keccak256("nestUnlooper")) return _isActive(vaultConfig.common.nestUnlooper);
        if (h == keccak256("complianceProxy")) return _isActive(vaultConfig.common.complianceProxy);
        if (h == keccak256("vaultTypeOFT")) {
            return keccak256(bytes(vaultConfig.vaultType)) == keccak256("NestVaultOFT");
        }
        if (h == keccak256("vaultTypeNotOFT")) {
            return keccak256(bytes(vaultConfig.vaultType)) != keccak256("NestVaultOFT");
        }
        return true;
    }

    function _isActive(address addr) internal pure returns (bool) {
        return ConfigReader.isActive(addr);
    }

    // ─── Fee-test helpers ─────────────────────────────────────────────

    /// @dev Index of the first configured vault, or type(uint256).max if none.
    function _firstActiveVault() internal view returns (uint256) {
        for (uint256 i = 0; i < vaults.length; i++) {
            if (vaults[i] != address(0)) return i;
        }
        return type(uint256).max;
    }

    /// @dev True when this vault's config resolves to a NestHubAccountant on the forked
    ///      chain (Hub lives only on `hubChainId`; spokes use NestSpokeAccountant). Gating
    ///      on config — not runtime — means a Hub-chain run whose upgrade was not applied
    ///      (EXECUTE_BATCH unset / impls absent) fails loudly instead of silently skipping.
    function _expectsHubAccountant() internal view returns (bool) {
        string memory raw = vm.readFile(string.concat("script/deployment-config/vaults/", vaultConfig.symbol, ".json"));
        return keccak256(bytes(ConfigReader.effectiveAccountantType(raw, vaultConfig.deployChainId)))
            == keccak256(bytes("NestHubAccountant"));
    }

    function _hub() internal view returns (NestHubAccountant) {
        return NestHubAccountant(address(accountant));
    }

    /// @dev Reads the AccountantState fields common to every accountant variant, decoding
    ///      against the correct concrete struct per chain. Hub returns 11 fields, base 10,
    ///      spoke 9; decoding against the wrong type reverts on short returndata. The first
    ///      9 fields are identical across all three, so this returns the shared subset.
    function _accountantCommon()
        internal
        view
        returns (uint96 exchangeRate, uint32 minimumUpdateDelayInSeconds, uint128 feesOwedInBase)
    {
        if (_expectsHubAccountant()) {
            NestHubAccountant.AccountantState memory hs = _hub().getAccountantState();
            return (hs.exchangeRate, hs.minimumUpdateDelayInSeconds, hs.feesOwedInBase);
        }
        NestSpokeAccountant.AccountantState memory ss = NestSpokeAccountant(address(accountant)).getAccountantState();
        return (ss.exchangeRate, ss.minimumUpdateDelayInSeconds, ss.feesOwedInBase);
    }

    /// @dev Calls updateExchangeRate against the correct concrete type per chain. Both Hub and
    ///      Spoke use the 2-arg `updateExchangeRate(uint96,uint128)` signature; only the abstract
    ///      base NestAccountant exposes the 1-arg form, which is not deployed. The Hub enforces
    ///      `totalShareSupply >= SHARE.totalSupply()`; the Spoke ignores the second arg. Resolve
    ///      `isHub`/`totalShareSupply` before pranking so the prank lands on this call.
    function _callUpdateExchangeRate(bool isHub, uint96 rate, uint128 totalShareSupply) internal {
        if (isHub) {
            _hub().updateExchangeRate(rate, totalShareSupply);
        } else {
            NestSpokeAccountant(address(accountant)).updateExchangeRate(rate, totalShareSupply);
        }
    }

    /// @dev The actual on-chain Auth owner of a contract (config `owner` may differ on
    ///      the fork; admin calls are `requiresAuth` and the owner is always authorized).
    function _authOwner(address target) internal view returns (address) {
        return Auth(target).owner();
    }

    /// @dev Relax the accountant rate-change bounds so fee-driven net-rate moves
    ///      don't trip RateOutOfBounds during these behavioural tests.
    function _widenAccountantBounds() internal {
        vm.startPrank(_authOwner(address(accountant)));
        accountant.updateUpper(2e6); // +100%
        accountant.updateLower(1); // ~-100%
        vm.stopPrank();
    }

    /// @dev Push a fresh gross rate as keeper, respecting the minimum update delay.
    function _keeperUpdateRate(uint96 grossRate) internal {
        address keeper = accountantKeepers.length > 0 ? accountantKeepers[0] : owner;
        NestHubAccountant hub = _hub();
        NestHubAccountant.AccountantState memory s = hub.getAccountantState();
        vm.warp(block.timestamp + s.minimumUpdateDelayInSeconds + 1);
        // Read supply BEFORE pranking: an external call in the arg list (share.totalSupply())
        // would otherwise consume the vm.prank, leaving updateExchangeRate called by the test
        // contract → AUTH_UNAUTHORIZED.
        uint128 supply = uint128(share.totalSupply());
        vm.prank(keeper);
        hub.updateExchangeRate(grossRate, supply);
    }

    function _tryReadJsonString(string memory json, string memory key) internal pure returns (string memory) {
        try vm.parseJsonString(json, key) returns (string memory val) {
            return val;
        } catch {
            return "";
        }
    }

    function _singletonArray(address addr) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = addr;
    }
}
