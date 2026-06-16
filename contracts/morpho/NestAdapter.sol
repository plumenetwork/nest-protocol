// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {IERC7540Operator} from "contracts/interfaces/IERC7540.sol";
import {ITellerPredicateProxy} from "contracts/interfaces/ITellerPredicateProxy.sol";
import {MarketParams} from "@morpho/interfaces/IMorpho.sol";

import {MorphoAdapter} from "contracts/morpho/MorphoAdapter.sol";
import {AtomicSolverV3} from "contracts/vendor/boring-vault/AtomicSolverV3.sol";
import {NestVaultPredicateProxy, PredicateMessage} from "contracts/NestVaultPredicateProxy.sol";
import {AtomicQueue} from "@boring-vault/src/atomic-queue/AtomicQueue.sol";
import {CrossChainTellerBase} from "@boring-vault/src/base/Roles/CrossChain/CrossChainTellerBase.sol";
import {TellerWithMultiAssetSupport} from "@boring-vault/src/base/Roles/TellerWithMultiAssetSupport.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {ErrorsLib} from "contracts/vendor/bundler3/libraries/ErrorsLib.sol";
import {MathRayLib} from "contracts/vendor/bundler3/libraries/MathRayLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {NestVaultLib} from "contracts/morpho/libraries/NestVaultLib.sol";

/// @title NestAdapter
/// @notice Bundler3 adapter combining `MorphoAdapter` actions with Nest-specific vault actions.
/// @dev Restricts user-owned Nest operations to the current Bundler3 initiator
///      This contract is intended to be used inside Bundler3 multicalls.
/// @custom:security-contact security@morpho.org
contract NestAdapter is MorphoAdapter {
    using MathRayLib for uint256;
    using NestVaultLib for INestVaultCore;
    using SafeERC20 for IERC20;

    /// @notice The atomic queue request for the provided user/market is invalid.
    error InvalidRequest();
    /// @notice The predicate proxy provided for a Nest deposit is not authorized by the vault.
    error UnauthorizedPredicateProxy();

    /// @notice Creates a new Nest adapter bound to a Bundler3 instance.
    /// @param bundler3 Address of the Bundler3 contract.
    /// @param morpho Address of the Morpho contract.
    /// @param wrappedNative Address of canonical wrapped native token used by `MorphoAdapter`.
    constructor(address bundler3, address morpho, address wrappedNative)
        MorphoAdapter(bundler3, morpho, wrappedNative)
    {}

    /* NEST VAULT FUNCTIONS */

    /// @notice Deposits assets into a Nest vault through the predicate proxy.
    /// @dev Assets must have been previously sent to the adapter.
    ///      If `assets` is `type(uint256).max`, the adapter deposits its full asset balance.
    /// @param predicateProxy Predicate proxy that validates and forwards the deposit.
    /// @param vault Address of the Nest vault.
    /// @param assets Amount of assets to deposit.
    /// @param maxSharePriceE27 The maximum share price to accept, scaled by 1e27.
    /// @param receiver Address receiving minted shares.
    /// @param predicateMessage Predicate message to authorize the `initiator` transaction.
    /// @return shares Number of shares minted by the vault.
    function nestPredicateDeposit(
        NestVaultPredicateProxy predicateProxy,
        INestVaultCore vault,
        uint256 assets,
        uint256 maxSharePriceE27,
        address receiver,
        PredicateMessage calldata predicateMessage
    ) external onlyBundler3 returns (uint256 shares) {
        require(receiver != address(0), ErrorsLib.ZeroAddress());
        bytes4 depositSelector =
            bytes4(keccak256("deposit(address,uint256,address,address,(string,uint256,address[],bytes[]))"));
        // The initiator must be authorized to call the deposit, which is the default user-facing entrypoint.
        require(canCall(initiator(), address(predicateProxy), depositSelector), ErrorsLib.UnauthorizedSender());
        // The predicate proxy must validate the initiator's permissions with the provided predicate message.
        require(predicateProxy.genericUserCheckPredicate(initiator(), predicateMessage), ErrorsLib.UnauthorizedSender());
        // The predicate proxy must be authorized by the vault to deposit on behalf of the user/initiator.
        require(canCall(address(predicateProxy), address(vault), vault.deposit.selector), UnauthorizedPredicateProxy());

        IERC20 asset = IERC20(vault.asset());
        if (assets == type(uint256).max) assets = asset.balanceOf(address(this));

        require(assets != 0, ErrorsLib.ZeroAmount());

        asset.forceApprove(address(vault), type(uint256).max);
        shares = vault.deposit(assets, receiver);
        asset.forceApprove(address(vault), 0);

        require(assets.rDivUp(shares) <= maxSharePriceE27, ErrorsLib.SlippageExceeded());
    }

    /// @notice Mints shares in a Nest vault through the predicate proxy.
    /// @dev Assets must have been previously sent to the adapter.
    ///      If `shares` is `type(uint256).max`, the adapter mints from its full asset balance.
    /// @param predicateProxy Predicate proxy that validates and forwards the deposit.
    /// @param vault Address of the Nest vault.
    /// @param shares Amount of shares to mint.
    /// @param maxSharePriceE27 The maximum share price to accept, scaled by 1e27.
    /// @param receiver Address receiving minted shares.
    /// @param predicateMessage Predicate message to authorize the `initiator` transaction.
    /// @return assets Amount of assets consumed to mint `shares`.
    function nestPredicateMint(
        NestVaultPredicateProxy predicateProxy,
        INestVaultCore vault,
        uint256 shares,
        uint256 maxSharePriceE27,
        address receiver,
        PredicateMessage calldata predicateMessage
    ) external onlyBundler3 returns (uint256 assets) {
        require(receiver != address(0), ErrorsLib.ZeroAddress());
        bytes4 mintSelector =
            bytes4(keccak256("mint(address,uint256,address,address,(string,uint256,address[],bytes[]))"));
        // The initiator must be authorized to call the mint, which is the default user-facing entrypoint.
        require(canCall(initiator(), address(predicateProxy), mintSelector), ErrorsLib.UnauthorizedSender());
        // The predicate proxy must validate the initiator's permissions with the provided predicate message.
        require(predicateProxy.genericUserCheckPredicate(initiator(), predicateMessage), ErrorsLib.UnauthorizedSender());
        // The predicate proxy must be authorized by the vault to mint on behalf of the user/initiator.
        require(canCall(address(predicateProxy), address(vault), vault.mint.selector), UnauthorizedPredicateProxy());

        IERC20 asset = IERC20(vault.asset());
        if (shares == type(uint256).max) shares = vault.previewDeposit(asset.balanceOf(address(this)));

        require(shares != 0, ErrorsLib.ZeroAmount());

        asset.forceApprove(address(vault), type(uint256).max);
        assets = vault.mint(shares, receiver);
        asset.forceApprove(address(vault), 0);

        require(assets.rDivUp(shares) <= maxSharePriceE27, ErrorsLib.SlippageExceeded());
    }

    /// @notice Deposits assets into a Nest vault.
    /// @dev Assets must have been previously sent to the adapter.
    /// @param vault Address of the Nest vault.
    /// @param assets Amount of assets to deposit.
    /// @param maxSharePriceE27 The maximum share price to accept, scaled by 1e27.
    /// @param receiver Address receiving minted shares.
    /// @return shares Number of shares minted by the vault.
    function nestDeposit(INestVaultCore vault, uint256 assets, uint256 maxSharePriceE27, address receiver)
        external
        onlyBundler3
        returns (uint256 shares)
    {
        require(receiver != address(0), ErrorsLib.ZeroAddress());
        require(canCall(initiator(), address(vault), vault.deposit.selector), ErrorsLib.UnauthorizedSender());

        IERC20 asset = IERC20(vault.asset());
        if (assets == type(uint256).max) assets = asset.balanceOf(address(this));

        require(assets != 0, ErrorsLib.ZeroAmount());

        asset.forceApprove(address(vault), type(uint256).max);
        shares = vault.deposit(assets, receiver);
        asset.forceApprove(address(vault), 0);

        require(assets.rDivUp(shares) <= maxSharePriceE27, ErrorsLib.SlippageExceeded());
    }

    /// @notice Mints shares from a Nest vault.
    /// @dev Assets must already be held by the adapter.
    /// @param vault Address of the Nest vault.
    /// @param shares Amount of shares to mint.
    /// @param maxSharePriceE27 The maximum share price to accept, scaled by 1e27.
    /// @param receiver Address receiving minted shares.
    /// @return assets Amount of assets consumed to mint `shares`.
    function nestMint(INestVaultCore vault, uint256 shares, uint256 maxSharePriceE27, address receiver)
        external
        onlyBundler3
        returns (uint256 assets)
    {
        require(receiver != address(0), ErrorsLib.ZeroAddress());
        require(shares != 0, ErrorsLib.ZeroShares());
        require(canCall(initiator(), address(vault), vault.mint.selector), ErrorsLib.UnauthorizedSender());

        IERC20 asset = IERC20(vault.asset());
        if (shares == type(uint256).max) shares = vault.previewDeposit(asset.balanceOf(address(this)));
        require(shares != 0, ErrorsLib.ZeroShares());

        asset.forceApprove(address(vault), type(uint256).max);
        assets = vault.mint(shares, receiver);
        asset.forceApprove(address(vault), 0);

        require(assets.rDivUp(shares) <= maxSharePriceE27, ErrorsLib.SlippageExceeded());
    }

    /// @notice Executes `instantRedeem` on a Nest vault.
    /// @dev If `owner` is external, they must have previously approved the vault to transfer their shares.
    /// Otherwise, vault shares must have been previously sent to the adapter.
    /// @param vault Address of the Nest vault.
    /// @param shares Amount of shares to redeem instantly. Pass `type(uint256).max` to redeem the maximum allowed by the vault and the owner's balance.
    /// @param receiver Address receiving redeemed assets.
    /// @param minSharePriceE27 The minimum number of assets to receive per share, scaled by 1e27.
    /// @param owner Address whose shares are redeemed.
    /// @return assets Post-fee assets received from redemption.
    /// @return fee Fee retained by the vault.
    function nestInstantRedeem(
        INestVaultCore vault,
        uint256 shares,
        uint256 minSharePriceE27,
        address receiver,
        address owner
    ) external onlyBundler3 returns (uint256 assets, uint256 fee) {
        require(shares != 0, ErrorsLib.ZeroShares());
        require(receiver != address(0), ErrorsLib.ZeroAddress());
        require(isOwnerOrOperator(address(vault), owner), ErrorsLib.UnexpectedOwner());
        require(canCall(initiator(), address(vault), vault.instantRedeem.selector), ErrorsLib.UnauthorizedSender());

        if (shares == type(uint256).max) {
            uint256 ownerBalance = vault.balanceOf(owner);
            uint256 maxInstantRedeemShares = vault.getInstantRedeemLiquidity();
            shares = ownerBalance < maxInstantRedeemShares ? ownerBalance : maxInstantRedeemShares;
        }

        require(shares != 0, ErrorsLib.ZeroShares());

        if (owner == address(this)) IERC20(vault.share()).forceApprove(address(vault), shares);
        (assets, fee) = vault.instantRedeem(shares, receiver, owner);
        if (owner == address(this)) IERC20(vault.share()).forceApprove(address(vault), 0);

        require(assets.rDivDown(shares) >= minSharePriceE27, ErrorsLib.SlippageExceeded());
    }

    /// @notice Executes the full async redeem cycle of a Nest vault in one call.
    /// @dev Callable only from Bundler3.
    ///      The redeem flow consists of: `requestRedeem`, `fulfillRedeem`, and `withdraw`.
    ///      If `owner` is external, they must have previously approved the vault to transfer their shares.
    ///      Otherwise, vault shares must have been previously sent to the adapter.
    ///      The `controller` address is used to track the redeem request and must be unique per concurrent request. A common pattern is to use the initiator address as the controller.
    /// @param vault Address of the Nest vault.
    /// @param shares Amount of shares to redeem.
    /// @param minSharePriceE27 The minimum number of assets to receive per share, scaled by 1e27.
    /// @param receiver Address receiving redeemed assets.
    /// @param controller Controller used for request/fulfill/redeem.
    /// @param owner Address whose shares are redeemed.
    /// @return assets Assets received from final redeem.
    function nestRequestAndRedeem(
        INestVaultCore vault,
        uint256 shares,
        uint256 minSharePriceE27,
        address receiver,
        address controller,
        address owner
    ) external onlyBundler3 returns (uint256 assets) {
        require(receiver != address(0), ErrorsLib.ZeroAddress());
        require(isOwnerOrOperator(address(vault), owner), ErrorsLib.UnexpectedOwner());
        require(canCall(initiator(), address(vault), vault.fulfillRedeem.selector), ErrorsLib.UnauthorizedSender());

        if (shares == type(uint256).max) shares = vault.balanceOf(owner);
        require(shares != 0, ErrorsLib.ZeroShares());

        IERC20 share = IERC20(vault.share());

        share.forceApprove(address(vault), shares);
        vault.requestRedeem(shares, controller, owner);
        share.forceApprove(address(vault), 0);
        assets = vault.fulfillRedeem(controller, shares);
        vault.withdraw(assets, receiver, controller);

        require(assets.rDivDown(shares) >= minSharePriceE27, ErrorsLib.SlippageExceeded());
    }

    /// @notice Requests an async redeem on a Nest vault.
    /// @dev If `shares` is `type(uint256).max`, all shares owned by `owner` are requested.
    ///      If `owner` is external, they must have previously approved the vault to transfer their shares.
    ///      Callable only from Bundler3.
    /// @param vault Address of the Nest vault.
    /// @param shares Amount of shares to request for redeem.
    /// @param controller Controller that owns and tracks the async redeem request.
    /// @param owner Address whose shares are being redeemed.
    /// @return requestId Identifier of the created redeem request.
    function nestRequestRedeem(INestVaultCore vault, uint256 shares, address controller, address owner)
        external
        onlyBundler3
        returns (uint256 requestId)
    {
        require(shares != 0, ErrorsLib.ZeroShares());
        require(isOwnerOrOperator(address(vault), owner), ErrorsLib.UnexpectedOwner());
        require(canCall(initiator(), address(vault), vault.requestRedeem.selector), ErrorsLib.UnauthorizedSender());

        if (shares == type(uint256).max) shares = vault.balanceOf(owner);
        require(shares != 0, ErrorsLib.ZeroShares());

        IERC20 share = IERC20(vault.share());

        share.forceApprove(address(vault), shares);
        requestId = vault.requestRedeem(shares, controller, owner);
        share.forceApprove(address(vault), 0);
    }

    /// @notice Fulfills a pending async redeem request on a Nest vault.
    /// @dev If `shares` is `type(uint256).max`, the function fulfills the full claimable amount for
    ///      (`requestId`, `controller`).
    /// @param vault Address of the Nest vault.
    /// @param requestId Identifier of the redeem request to fulfill.
    /// @param controller Controller that owns the async redeem request.
    /// @param shares Amount of shares to fulfill.
    /// @param minSharePriceE27 The minimum number of assets to receive per share, scaled by 1e27.
    /// @return assets Assets made claimable by fulfilling the request.
    function nestFulfillRedeem(
        INestVaultCore vault,
        uint256 requestId,
        address controller,
        uint256 shares,
        uint256 minSharePriceE27
    ) external onlyBundler3 returns (uint256 assets) {
        require(shares != 0, ErrorsLib.ZeroShares());
        require(canCall(initiator(), address(vault), vault.fulfillRedeem.selector), ErrorsLib.UnauthorizedSender());

        if (shares == type(uint256).max) {
            uint256 claimableShares = vault.pendingRedeemRequest(requestId, controller);
            require(claimableShares != 0, ErrorsLib.ZeroShares());
            shares = claimableShares;
        }

        assets = vault.fulfillRedeem(controller, shares);
        require(assets.rDivDown(shares) >= minSharePriceE27, ErrorsLib.SlippageExceeded());
    }

    /// @notice Withdraws fulfilled async assets from a Nest vault.
    /// @dev If `assets` is `type(uint256).max`, the maximum withdrawable amount for `owner` is used.
    /// @param vault Address of the Nest vault.
    /// @param assets Amount of assets to withdraw.
    /// @param minSharePriceE27 The minimum number of assets to receive per share, scaled by 1e27.
    /// @param receiver Address receiving withdrawn assets.
    /// @param owner Address used as the owner/controller in the vault withdraw call.
    function nestWithdraw(
        INestVaultCore vault,
        uint256 assets,
        uint256 minSharePriceE27,
        address receiver,
        address owner
    ) external onlyBundler3 {
        require(receiver != address(0), ErrorsLib.ZeroAddress());
        require(isOwnerOrOperator(address(vault), owner), ErrorsLib.UnexpectedOwner());
        require(canCall(initiator(), address(vault), vault.withdraw.selector), ErrorsLib.UnauthorizedSender());

        if (assets == type(uint256).max) assets = vault.maxWithdraw(owner);
        require(assets != 0, ErrorsLib.ZeroAmount());

        uint256 shares = vault.withdraw(assets, receiver, owner);
        require(assets.rDivDown(shares) >= minSharePriceE27, ErrorsLib.SlippageExceeded());
    }

    /// @notice Redeems fulfilled async shares from a Nest vault.
    /// @dev If `shares` is `type(uint256).max`, the maximum redeemable amount for `owner` is used.
    /// @param vault Address of the Nest vault.
    /// @param shares Amount of shares to redeem.
    /// @param minSharePriceE27 The minimum number of assets to receive per share, scaled by 1e27.
    /// @param receiver Address receiving redeemed assets.
    /// @param owner Address used as the owner/controller in the vault redeem call.
    function nestRedeem(INestVaultCore vault, uint256 shares, uint256 minSharePriceE27, address receiver, address owner)
        external
        onlyBundler3
    {
        require(receiver != address(0), ErrorsLib.ZeroAddress());
        require(isOwnerOrOperator(address(vault), owner), ErrorsLib.UnexpectedOwner());
        require(canCall(initiator(), address(vault), vault.redeem.selector), ErrorsLib.UnauthorizedSender());

        if (shares == type(uint256).max) shares = vault.maxRedeem(owner);

        require(shares != 0, ErrorsLib.ZeroShares());

        uint256 assets = vault.redeem(shares, receiver, owner);
        require(assets.rDivDown(shares) >= minSharePriceE27, ErrorsLib.SlippageExceeded());
    }

    /* LEGACY VAULT FUNCTIONS */

    /// @notice Deposits assets through the legacy predicate proxy + teller path.
    /// @dev Assets must have been previously sent to the adapter.
    ///      If `assets` is `type(uint256).max`, the adapter deposits its full `depositAsset` balance.
    /// @param predicateProxy Legacy predicate proxy that validates and forwards the teller deposit.
    /// @param depositAsset Asset to deposit.
    /// @param assets Asset amount to deposit.
    /// @param minimumMint Minimum acceptable shares minted by the teller flow.
    /// @param receiver Address receiving minted shares.
    /// @param teller Cross-chain teller used by the legacy proxy deposit path.
    /// @param predicateMessage Predicate message to authorize the `initiator` transaction.
    /// @return shares Number of shares minted by the teller flow.
    function tellerPredicateDeposit(
        ITellerPredicateProxy predicateProxy,
        ERC20 depositAsset,
        uint256 assets,
        uint256 minimumMint,
        address receiver,
        CrossChainTellerBase teller,
        PredicateMessage calldata predicateMessage
    ) external onlyBundler3 returns (uint256 shares) {
        require(receiver != address(0), ErrorsLib.ZeroAddress());
        require(address(teller) != address(0), ErrorsLib.ZeroAddress());
        require(predicateProxy.genericUserCheckPredicate(initiator(), predicateMessage), ErrorsLib.UnauthorizedSender());
        require(
            canCall(address(predicateProxy), address(teller), teller.deposit.selector), UnauthorizedPredicateProxy()
        );

        if (assets == type(uint256).max) assets = depositAsset.balanceOf(address(this));
        require(assets != 0, ErrorsLib.ZeroAmount());

        IERC20 asset = IERC20(address(depositAsset));
        address vault = address(teller.vault());
        asset.forceApprove(vault, type(uint256).max);
        shares = teller.deposit(depositAsset, assets, minimumMint);
        asset.forceApprove(vault, 0);
    }

    /// @notice Executes an AtomicQueue redemption solve for one user and forwards redeemed loan assets.
    /// @dev Callable only from Bundler3.
    ///      The `onBehalf` account must authorize the Bundler initiator on Morpho and approve this adapter
    ///      to transfer the redeemed loan token amount to `receiver`.
    /// @param solver Atomic solver used to execute `redeemSolve`.
    /// @param queue Atomic queue instance passed into the solver call.
    /// @param teller Teller contract used by the atomic solver to settle vault assets.
    /// @param marketParams Morpho market params used to derive offer (collateral) and want (loan) tokens.
    /// @param onBehalf Position owner and atomic-queue user being solved for.
    /// @param receiver Recipient of redeemed loan-token proceeds.
    /// @param maxAssets Max loan-token amount the solver is allowed to spend into queue settlement.
    /// @param minimumAssetsOut Minimum loan-token amount expected from redeeming the received shares.
    function atomicSolverRedeemSolve(
        AtomicSolverV3 solver,
        AtomicQueue queue,
        TellerWithMultiAssetSupport teller,
        MarketParams calldata marketParams,
        address onBehalf,
        address receiver,
        uint256 maxAssets,
        uint256 minimumAssetsOut
    ) external onlyBundler3 {
        require(receiver != address(0), ErrorsLib.ZeroAddress());
        require(MORPHO.isAuthorized(onBehalf, initiator()), ErrorsLib.UnauthorizedSender());
        require(canCall(initiator(), address(solver), solver.redeemSolve.selector), ErrorsLib.UnauthorizedSender());

        address[] memory users = new address[](1);
        users[0] = onBehalf;

        ERC20 offer = ERC20(marketParams.collateralToken);
        ERC20 want = ERC20(marketParams.loanToken);
        (AtomicQueue.SolveMetaData[] memory solveMetaData,,) = queue.viewSolveMetaData(offer, want, users);
        require(
            solveMetaData.length == 1 && solveMetaData[0].user == onBehalf && solveMetaData[0].flags == 0
                && solveMetaData[0].assetsToOffer != 0 && solveMetaData[0].assetsForWant != 0,
            InvalidRequest()
        );

        uint256 balanceBefore = want.balanceOf(onBehalf);
        IERC20(address(want)).forceApprove(address(solver), type(uint256).max);
        solver.redeemSolve(queue, offer, want, users, minimumAssetsOut, maxAssets, teller);
        IERC20(address(want)).forceApprove(address(solver), 0);
        uint256 receivedAssets = want.balanceOf(onBehalf) - balanceBefore;

        require(receivedAssets > 0, ErrorsLib.ZeroAmount());

        // Transfer the redeemed `want` from the user to the `receiver`. The user must have approved the adapter beforehand.
        IERC20(address(want)).safeTransferFrom(onBehalf, receiver, receivedAssets);
    }

    /* ERC20 HELPERS */

    /// @notice Transfers the adapter's non-zero balance of the Market tokens to the receiver.
    /// @param marketParams The Morpho market params used to determine the tokens to transfer.
    /// @param receiver The address that will receive the tokens.
    function adapterSweep(MarketParams calldata marketParams, address receiver) external onlyBundler3 {
        require(receiver != address(0), ErrorsLib.ZeroAddress());

        IERC20 loanToken = IERC20(marketParams.loanToken);
        uint256 balance = loanToken.balanceOf(address(this));
        if (balance != 0) SafeERC20.safeTransfer(loanToken, receiver, balance);

        IERC20 collateralToken = IERC20(marketParams.collateralToken);
        balance = collateralToken.balanceOf(address(this));
        if (balance != 0) SafeERC20.safeTransfer(collateralToken, receiver, balance);
    }

    /* AUTHORIZATION HELPERS */

    /// @notice Checks if the initiator is authorized to call a specific function in the target contract.
    /// @dev This is implemented to maintain strict access control for Nest vault interactions, ensuring that both the adapter and initiator have the necessary permissions to perform actions on the vault.
    /// @param caller The address of the caller attempting to execute the function.
    /// @param target The address of the target contract (e.g., the Nest vault).
    /// @param functionSig The function selector of the action being performed (e.g., `instantRedeem.selector`).
    /// @return True if initiator can call `functionSig` on `target`.
    function canCall(address caller, address target, bytes4 functionSig) internal view returns (bool) {
        return Authority(Auth(target).authority()).canCall(caller, target, functionSig);
    }

    /// @notice Checks if the initiator is either the vault itself, the owner, or an operator authorized by owner.
    /// @dev This function is used to determine if the initiator has permission to perform actions on behalf of the owner in the vault.
    /// @param vault The address of the Nest vault.
    /// @param owner The address of the owner whose permissions are being checked.
    /// @return True if initiator is allowed to act for `owner` in `vault`.
    function isOwnerOrOperator(address vault, address owner) internal view returns (bool) {
        address _initiator = initiator();
        return owner == address(this) || owner == _initiator || IERC7540Operator(vault).isOperator(owner, _initiator);
    }
}
