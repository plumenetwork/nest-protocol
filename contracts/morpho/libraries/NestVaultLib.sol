// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {NestHubAccountant} from "contracts/accountant/NestHubAccountant.sol";
import {AccountantWithRateProviders} from "@boring-vault/src/base/Roles/AccountantWithRateProviders.sol";
import {NestVaultCoreTypes} from "contracts/libraries/nest-vault/NestVaultCoreTypes.sol";
import {NestVaultAccountingLogic} from "contracts/libraries/nest-vault/NestVaultAccountingLogic.sol";

/// @notice Backward-compatible legacy Nest vault extension exposing the accountant getter.
interface ILegacyNestVaultCore is INestVaultCore {
    /// @notice Returns the legacy accountant contract used by the vault.
    function accountantWithRateProviders() external view returns (AccountantWithRateProviders);
}

/// @title NestVaultLib
/// @notice Minimal share/asset conversion helpers using a vault accountant rate.
library NestVaultLib {
    /// @notice Reads the current accountant rate and one-share scalar for a vault.
    /// @param vault Vault contract to query.
    /// @return rate Accountant quote per share.
    /// @return oneShare Base units representing one full share (`10 ** vault.decimals()`).
    function getRate(INestVaultCore vault) internal view returns (uint256 rate, uint256 oneShare) {
        address asset = vault.asset();
        address accountant;
        try vault.accountant() returns (NestHubAccountant acct) {
            accountant = address(acct);
        } catch {
            accountant = address(ILegacyNestVaultCore(address(vault)).accountantWithRateProviders());
        }
        rate = NestHubAccountant(accountant).getRateInQuoteSafe(ERC20(asset));
        oneShare = 10 ** vault.decimals();
    }

    /// @notice Returns current instant redeem liquidity expressed in shares.
    /// @param vault Vault contract to query.
    /// @return instantRedeemLiquidity Share amount redeemable from the share contract's current asset buffer.
    function getInstantRedeemLiquidity(INestVaultCore vault) internal view returns (uint256 instantRedeemLiquidity) {
        uint256 assetBuffer = ERC20(vault.asset()).balanceOf(vault.share());
        (uint256 rate, uint256 oneShare) = getRate(vault);
        instantRedeemLiquidity = Math.mulDiv(assetBuffer, oneShare, rate, Math.Rounding.Floor);
    }

    /// @notice Returns owner's loan-asset token balance for the vault asset.
    /// @param vault Vault that defines the asset token.
    /// @param owner Account whose balance is queried.
    /// @return Asset token balance of `owner`.
    function getAssetBalance(INestVaultCore vault, address owner) internal view returns (uint256) {
        return ERC20(vault.asset()).balanceOf(owner);
    }

    /// @notice Returns owner's share token balance for the vault share.
    /// @param vault Vault that defines the share token.
    /// @param owner Account whose balance is queried.
    /// @return Share token balance of `owner`.
    function getShareBalance(INestVaultCore vault, address owner) internal view returns (uint256) {
        return ERC20(vault.share()).balanceOf(owner);
    }

    /// @notice Computes the minimum shares to redeem so that post-fee assets >= targetPostFeeAssets.
    /// @dev Uses the exact fee-inversion formula (`calculatePreFeeAmount`) to avoid rounding shortfall.
    ///      Returns 0 when `targetPostFeeAssets` is 0.
    /// @param vault Vault to read rate and fee config from.
    /// @param targetPostFeeAssets Minimum post-fee assets the redeem must produce.
    /// @param feeType Fee type to apply (Redemption or InstantRedemption).
    /// @return shares Minimum shares required.
    function getMinRedeemShares(INestVaultCore vault, uint256 targetPostFeeAssets, NestVaultCoreTypes.Fees feeType)
        internal
        view
        returns (uint256 shares)
    {
        if (targetPostFeeAssets == 0) return 0;

        (uint32 feeRate, uint256 flatFee) = vault.fees(feeType);
        uint256 requiredGross = NestVaultAccountingLogic.calculatePreFeeAmount(targetPostFeeAssets, feeRate, flatFee);

        (uint256 rate, uint256 oneShare) = getRate(vault);
        shares = Math.mulDiv(requiredGross, oneShare, rate, Math.Rounding.Ceil);
    }
}
