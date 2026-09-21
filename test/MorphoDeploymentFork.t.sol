// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {TellerWithMultiAssetSupport} from "@boring-vault/src/base/Roles/TellerWithMultiAssetSupport.sol";
import {AtomicQueue} from "@boring-vault/src/atomic-queue/AtomicQueue.sol";

import {Call, IBundler3} from "contracts/vendor/bundler3/interfaces/IBundler3.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {NestAdapter} from "contracts/integrations/morpho/NestAdapter.sol";
import {NestBundler} from "contracts/integrations/morpho/NestBundler.sol";
import {NestUnlooper} from "contracts/integrations/morpho/NestUnlooper.sol";
import {PredicateMessage} from "@predicate/src/interfaces/IPredicateClient.sol";
import {IComplianceHook} from "contracts/compliance/interfaces/IComplianceHook.sol";
import {BundleCalldataLib} from "contracts/integrations/morpho/libraries/BundleCalldataLib.sol";
import {NestShareMathLib} from "contracts/integrations/morpho/libraries/NestShareMathLib.sol";
import {
    Bundle,
    MarketActions,
    PositionMode,
    Position,
    RouteInput,
    UserIntent
} from "contracts/integrations/morpho/types/BundleTypes.sol";

import {IPredicateManager} from "@predicate/src/interfaces/IPredicateManager.sol";
import {IMorpho, Id, Market, MarketParams, Position as MorphoPosition} from "@morpho/interfaces/IMorpho.sol";
import {MathLib} from "@morpho/libraries/MathLib.sol";
import {MarketParamsLib} from "@morpho/libraries/MarketParamsLib.sol";
import {SharesMathLib} from "@morpho/libraries/SharesMathLib.sol";

import {
    ConfigReader,
    CommonContracts,
    MorphoChainConfig,
    MorphoMarketParams,
    VaultDeployConfig
} from "script/lib/ConfigReader.sol";

/// @title  MorphoDeploymentForkTest
/// @notice Fork-based integration test that loads deployed addresses from `common/<chainId>.json` and
///         the deployed pUSD nALPHA NestVault from `output/nALPHA/<chainId>-nALPHA.json`, replays the
///         queued multisig batch from `output/msig/<chainId>-nALPHA-SetupAuthority.json`, and exercises
///         loop & unloop dataflow on Plume (chain 98866) for the nALPHA / pUSD Morpho market.
/// @dev    The msig replay impersonates each target's owner per Solmate Auth semantics (owner always
///         passes `requiresAuth`). After replay the chain state matches the post-Safe-execution state
///         that the `SetupAuthority` script produced.
contract MorphoDeploymentForkTest is Test {
    using stdJson for string;
    using MathLib for uint256;
    using MarketParamsLib for MarketParams;
    using NestShareMathLib for uint256;
    using SharesMathLib for uint256;

    /// @dev Field order is alphabetical to match `vm.parseJson` decoding rules. `operation` and `value`
    ///      are stored as strings because the Safe export emits them as quoted strings.
    struct SafeTx {
        bytes data;
        string operation;
        address to;
        string value;
    }

    string internal constant PLUME_RPC_ENV = "PLUME_RPC_URL";
    string internal constant REPLAY_MSIG_ENV = "REPLAY_MSIG";
    uint256 internal constant CHAIN_ID_PLUME = 98866;
    // Vault under test; override with VAULT_SYMBOL. Market params come from config/morpho/<chainId>.json.
    string internal constant DEFAULT_SYMBOL = "nALPHA";

    bytes4 internal constant PREDICATE_VALIDATE_SIGNATURES_SELECTOR = IPredicateManager.validateSignatures.selector;

    uint256 internal constant UNIT = 1e6;
    uint256 internal constant USER_INITIAL_PUSD = 500 * UNIT;

    address internal user = makeAddr("user");
    address internal solver = makeAddr("solver");

    // Deployed contracts loaded from common/<chainId>.json.
    NestAdapter internal adapter;
    NestBundler internal bundler;
    NestUnlooper internal unlooper;
    address internal complianceProxyAddr;

    // External Plume infrastructure.
    IMorpho internal morpho;
    IBundler3 internal bundler3;
    address internal atomicSolver;
    address internal atomicQueue;
    TellerWithMultiAssetSupport internal teller;

    // Per-vault market, resolved from config/morpho/<chainId>.json for the selected VAULT_SYMBOL.
    string internal vaultSymbol;
    address internal collateralToken; // vault SHARE token (Morpho collateral)
    address internal loanToken; // borrowed asset (pUSD)

    // Deployed loan-asset NestVault for the selected vault (from output config).
    INestVaultCore internal pusdVault;
    MarketParams internal marketParams;

    function setUp() public {
        string memory rpcUrl = vm.envOr(PLUME_RPC_ENV, string("https://rpc.plume.org"));
        vm.createSelectFork(rpcUrl);

        CommonContracts memory cc = ConfigReader.readCommonProxyConfig(CHAIN_ID_PLUME);
        MorphoChainConfig memory mc = ConfigReader.readMorphoConfig(CHAIN_ID_PLUME);

        // Vault under test (default = Morpho-enabled nALPHA). Every vault-specific address and
        // market param below is resolved from config for this symbol.
        vaultSymbol = vm.envOr("VAULT_SYMBOL", DEFAULT_SYMBOL);

        // Resolve the Morpho contracts the way deploy/setup does: overlay the selected vault's
        // `commonOverrides` on top of the chain common config. A vault that opts out of Morpho
        // (e.g. nCREDIT zeroes nestAdapter/nestUnlooper) must make this suite fail loudly rather
        // than silently exercising the chain-wide adapter.
        string memory rawVaultJson =
            vm.readFile(string.concat("script/deployment-config/vaults/", vaultSymbol, ".json"));
        address nestAdapter =
            ConfigReader.effectiveCommonAddress(rawVaultJson, "nestAdapter", CHAIN_ID_PLUME, cc.nestAdapter);
        address nestBundler =
            ConfigReader.effectiveCommonAddress(rawVaultJson, "nestBundler", CHAIN_ID_PLUME, cc.nestBundler);
        address nestUnlooper =
            ConfigReader.effectiveCommonAddress(rawVaultJson, "nestUnlooper", CHAIN_ID_PLUME, cc.nestUnlooper);

        require(nestAdapter != address(0), string.concat("nestAdapter disabled by commonOverrides for ", vaultSymbol));
        require(nestBundler != address(0), string.concat("nestBundler disabled by commonOverrides for ", vaultSymbol));
        require(nestUnlooper != address(0), string.concat("nestUnlooper disabled by commonOverrides for ", vaultSymbol));

        adapter = NestAdapter(payable(nestAdapter));
        bundler = NestBundler(nestBundler);
        unlooper = NestUnlooper(nestUnlooper);
        // Prefer the V2 compliance proxy; fall back to the V1 predicate proxy for chains
        // whose common config has not been migrated yet.
        complianceProxyAddr = cc.complianceProxy != address(0) ? cc.complianceProxy : cc.predicateProxy;

        morpho = IMorpho(mc.morpho);
        bundler3 = IBundler3(mc.bundler3);
        atomicSolver = mc.atomicSolver;
        atomicQueue = mc.atomicQueue;

        // Per-vault Morpho market params (collateral = vault SHARE token, loan = pUSD).
        MorphoMarketParams memory m = ConfigReader.readMorphoMarket(CHAIN_ID_PLUME, vaultSymbol);
        collateralToken = m.collateralToken;
        loanToken = m.loanToken;
        teller = TellerWithMultiAssetSupport(m.legacyTeller);

        VaultDeployConfig memory vc = ConfigReader.readOutputConfig(CHAIN_ID_PLUME, vaultSymbol);
        pusdVault = INestVaultCore(_findVaultByAsset(vc, "pUSD"));
        require(
            address(pusdVault) != address(0),
            string.concat("pUSD vault not deployed in output config for ", vaultSymbol)
        );
        assertEq(pusdVault.asset(), loanToken, "loan vault asset mismatch");
        assertEq(pusdVault.share(), collateralToken, "vault share mismatch");

        marketParams = MarketParams({
            loanToken: loanToken, collateralToken: collateralToken, oracle: m.oracle, irm: m.irm, lltv: m.lltv
        });
        Market memory mkt = morpho.market(marketParams.id());
        assertGt(mkt.totalSupplyAssets, 0, string.concat("Morpho market not found on fork for ", vaultSymbol));

        _bypassComplianceValidation();
        _bypassAtomicSolverAuth();
        if (vm.envOr(REPLAY_MSIG_ENV, true)) _replaySetupAuthorityMsig();
        _seedUserAndApprove();

        // Seed collateral reserve on the loan asset so the instant-redeem path has liquidity.
        deal(collateralToken, loanToken, 1_000 * UNIT, true);
    }

    /*//////////////////////////////////////////////////////////////
                              LOOP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_loop_modernRoute_opensTargetPosition() public {
        _executeLoop(50 * UNIT, 100 * UNIT, _route(false, false, false));

        (uint256 borrow, uint256 collateral) = _getPosition(user);
        assertEq(collateral, 100 * UNIT, "collateral target");
        assertApproxEqAbs(borrow, 50 * UNIT, 1, "borrow target");
    }

    // function test_loop_legacyDepositRoute_opensTargetPosition() public {
    //     _executeLoop(50 * UNIT, 100 * UNIT, _route(false, true, false));

    //     (uint256 borrow, uint256 collateral) = _getPosition(user);
    //     assertEq(collateral, 100 * UNIT, "collateral target");
    //     assertApproxEqAbs(borrow, 50 * UNIT, 1, "borrow target");
    // }

    /*//////////////////////////////////////////////////////////////
                             UNLOOP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_unloop_legacyRoute_via_atomicQueue() public {
        _executeLoop(50 * UNIT, 100 * UNIT, _route(false, false, false));

        uint96 offerAmount = uint96(40 * UNIT);
        _seedAtomicRedeemRequest(offerAmount);

        address unlooperOwner = Auth(address(unlooper)).owner();
        vm.prank(unlooperOwner);
        unlooper.execute(marketParams, pusdVault, teller, user, true);

        (, uint256 collateral) = _getPosition(user);
        assertEq(collateral, 100 * UNIT - offerAmount, "collateral reduced by offerAmount");
    }

    /// @dev The modern unloop path reads the vault's per-type `fees(Fees)` getter, introduced by the
    ///      vault fee upgrade. It is expected to revert for any VAULT_SYMBOL whose pUSD vault has not
    ///      yet had its Upgrade-vault batch executed on the forked chain (nALPHA is upgraded; nOPAL /
    ///      nTBILL are not). Replay 98866-<sym>-Upgrade-vault.json on-chain to make this pass.
    function test_unloop_modernRoute_via_unloopRequest() public {
        _executeLoop(50 * UNIT, 100 * UNIT, _route(false, false, false));

        (uint256 borrowBefore, uint256 collateralBefore) = _getPosition(user);

        uint64 deadline = uint64(block.timestamp + 1 days);
        vm.prank(user);
        unlooper.updateUnloopRequest(marketParams, 10_000, 0, deadline);

        address unlooperOwner = Auth(address(unlooper)).owner();
        vm.prank(unlooperOwner);
        unlooper.execute(marketParams, pusdVault, teller, user, false);

        (uint256 borrowAfter, uint256 collateralAfter) = _getPosition(user);
        assertLt(borrowAfter, borrowBefore, "borrow reduced");
        assertLt(collateralAfter, collateralBefore, "collateral reduced");
        // Modern path clears the stored request after execution.
        assertEq(unlooper.getUnloopRequest(user, marketParams).deadline, 0, "request cleared");
    }

    /*//////////////////////////////////////////////////////////////
                              HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Short-circuits compliance/predicate validation only. Authority/role wiring is expected
    ///      to be configured on chain via SetupAuthority. Handles both proxy generations: the V1
    ///      predicate proxy (mock its service manager) and the V2 compliance proxy (mock its hook).
    function _bypassComplianceValidation() internal {
        (bool ok, bytes memory ret) = complianceProxyAddr.staticcall(abi.encodeWithSignature("getPredicateManager()"));
        if (ok && ret.length == 32) {
            vm.mockCall(
                abi.decode(ret, (address)),
                abi.encodeWithSelector(PREDICATE_VALIDATE_SIGNATURES_SELECTOR),
                abi.encode(true)
            );
        }
        (ok, ret) = complianceProxyAddr.staticcall(abi.encodeWithSignature("complianceHook()"));
        if (ok && ret.length == 32) {
            vm.mockCall(
                abi.decode(ret, (address)),
                abi.encodeWithSelector(IComplianceHook.checkCompliance.selector),
                abi.encode(true)
            );
        }
    }

    function _bypassAtomicSolverAuth() internal {
        address solverAuthority = address(Auth(atomicSolver).authority());
        vm.mockCall(solverAuthority, abi.encodeWithSelector(Authority.canCall.selector), abi.encode(true));
    }

    /// @dev Replays the `SetupAuthority` Safe batch by impersonating the owner of each target. Owner
    ///      always passes `requiresAuth` per Solmate Auth, so this matches what the multisig will
    ///      produce once it executes the queued payloads on chain.
    function _replaySetupAuthorityMsig() internal {
        string memory path = string.concat("script/output/msig/98866-", vaultSymbol, "-SetupAuthority.json");
        // Only some vaults ship a pending SetupAuthority batch; when absent the on-chain authority
        // is assumed already configured, so the replay is skipped.
        try vm.readFile(path) returns (string memory json) {
            SafeTx[] memory txs = abi.decode(json.parseRaw(".transactions"), (SafeTx[]));
            for (uint256 i; i < txs.length; ++i) {
                address target = txs[i].to;
                vm.prank(Auth(target).owner());
                (bool ok, bytes memory ret) = target.call(txs[i].data);
                require(ok, string.concat("msig tx[", vm.toString(i), "] reverted"));
                ret;
            }
        } catch {}
    }

    function _seedUserAndApprove() internal {
        deal(loanToken, user, USER_INITIAL_PUSD, true);

        vm.startPrank(user);
        ERC20(loanToken).approve(address(pusdVault), type(uint256).max);
        ERC20(loanToken).approve(address(adapter), type(uint256).max);
        ERC20(collateralToken).approve(address(pusdVault), type(uint256).max);
        ERC20(collateralToken).approve(address(adapter), type(uint256).max);

        pusdVault.setOperator(address(adapter), true);

        morpho.setAuthorization(address(adapter), true);
        morpho.setAuthorization(address(unlooper), true);

        vm.stopPrank();
    }

    function _executeLoop(uint256 targetBorrow, uint256 targetCollateral, RouteInput memory route) internal {
        UserIntent memory intent = _targetIntent(targetBorrow, targetCollateral);
        Bundle memory bundle =
            bundler.getBundle(intent, route, _emptyComplianceData(), pusdVault, address(teller), user, user);
        Call[] memory calls = BundleCalldataLib.getBundleCalls(bundle);

        vm.prank(user);
        bundler3.multicall(calls);
    }

    function _seedAtomicRedeemRequest(uint96 offerAmount) internal {
        uint256 assetsForWant = uint256(offerAmount).convertToAssets(pusdVault, Math.Rounding.Floor);
        uint256 atomicPrice = assetsForWant * UNIT / offerAmount;
        require(atomicPrice <= type(uint88).max, "atomic price overflow");

        vm.startPrank(user);
        ERC20(collateralToken).approve(atomicQueue, offerAmount);
        ERC20(loanToken).approve(address(adapter), assetsForWant);
        AtomicQueue(atomicQueue)
            .updateAtomicRequest(
                ERC20(collateralToken),
                ERC20(loanToken),
                AtomicQueue.AtomicRequest({
                deadline: uint64(block.timestamp + 1 days),
                atomicPrice: uint88(atomicPrice),
                offerAmount: offerAmount,
                inSolve: false
            })
            );
        vm.stopPrank();
    }

    function _findVaultByAsset(VaultDeployConfig memory vc, string memory symbol) internal pure returns (address) {
        bytes32 needle = keccak256(bytes(symbol));
        for (uint256 i; i < vc.vaults.length; ++i) {
            if (keccak256(bytes(vc.vaults[i].assetSymbol)) == needle) return vc.vaults[i].addr;
        }
        return address(0);
    }

    function _targetIntent(uint256 borrow, uint256 collateral) internal view returns (UserIntent memory intent) {
        intent = UserIntent({
            market: marketParams,
            assetAllowance: type(uint256).max,
            shareAllowance: type(uint256).max,
            maxSharePriceE27: type(uint256).max,
            minSharePriceE27: 0,
            maxRepaySharePriceE27: type(uint256).max,
            mode: PositionMode.Target,
            target: Position({loan: borrow, collateral: collateral}),
            delta: MarketActions({borrow: 0, flashRepay: 0, repay: 0, supplyCollateral: 0, withdrawCollateral: 0})
        });
    }

    function _route(bool legacyRedemption, bool legacyDeposit, bool instantRedeem)
        internal
        pure
        returns (RouteInput memory route)
    {
        route = RouteInput({
            legacyRedemption: legacyRedemption,
            legacyDeposit: legacyDeposit,
            instantRedeem: instantRedeem,
            compliantRedemption: false
        });
    }

    /// @dev Legacy routes decode this as a `PredicateMessage`; modern routes treat it as opaque bytes.
    function _emptyComplianceData() internal pure returns (bytes memory) {
        return abi.encode(
            PredicateMessage({
                taskId: "",
                expireByTime: type(uint256).max,
                signerAddresses: new address[](0),
                signatures: new bytes[](0)
            })
        );
    }

    function _getPosition(address owner) internal view returns (uint256 borrowAssets, uint256 collateral) {
        Id id = marketParams.id();
        MorphoPosition memory pos = morpho.position(id, owner);
        Market memory mkt = morpho.market(id);
        borrowAssets = uint256(pos.borrowShares).toAssetsUp(mkt.totalBorrowAssets, mkt.totalBorrowShares);
        collateral = uint256(pos.collateral);
    }
}
