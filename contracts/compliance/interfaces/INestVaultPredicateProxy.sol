// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

// contracts
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {IPredicateClient, PredicateMessage} from "@predicate/src/interfaces/IPredicateClient.sol";
import {NestVault} from "contracts/NestVault.sol";

interface INestVaultPredicateProxy is IPredicateClient {
    /// @notice Allows users to deposit into the NestVault, if PredicateProxy is not paused
    /// @dev    Publicly callable. Uses the predicate authorization pattern to validate the transaction
    /// @param  _depositAsset     ERC20            asset to deposit
    /// @param  _depositAmount    uint256          amount of deposit asset to deposit
    /// @param  _recipient        address          address which to forward shares
    /// @param  _vault            NestVault        contract to deposit into
    /// @param  _predicateMessage PredicateMessage Predicate message to authorize the transaction
    /// @return _shares           uint256          amount of shares minted
    function deposit(
        ERC20 _depositAsset,
        uint256 _depositAmount,
        address _recipient,
        NestVault _vault,
        PredicateMessage calldata _predicateMessage
    ) external returns (uint256 _shares);

    /// @notice Allows users to mint, if the PredicateProxy contract is not paused
    /// @dev    Publicly callable. Uses the predicate authorization pattern to validate the transaction
    /// @param  _depositAsset     ERC20            asset to deposit
    /// @param  _shares           uint256          amount of shares to mint
    /// @param  _recipient        address          address which to forward shares
    /// @param  _vault            NestVault        contract to deposit into
    /// @param  _predicateMessage PredicateMessage Predicate message to authorize the transaction
    /// @return _depositAmount    uint256          amount of asset deposited
    function mint(
        ERC20 _depositAsset,
        uint256 _shares,
        address _recipient,
        NestVault _vault,
        PredicateMessage calldata _predicateMessage
    ) external returns (uint256 _depositAmount);

    /// @notice Allows whitelisted users to deposit into the NestVault, if PredicateProxy is not paused.
    /// @dev    Restricted to COMPOSER_ROLE. Allows specifying a _depositor (bytes32) different from msg.sender,
    ///         enabling custom predicate verifications for cross-chain deposit integrations.
    /// @dev    Uses the predicate authorization pattern to validate the transaction
    /// @param  _depositAsset     ERC20            asset to deposit
    /// @param  _depositAmount    uint256          amount of deposit asset to deposit
    /// @param  _recipient        address          address which to forward shares
    /// @param  _vault            NestVault        contract to deposit into
    /// @param  _depositor        bytes32          The depositor (bytes32 format to account for non-evm addresses)
    /// @param  _predicateMessage PredicateMessage Predicate message to authorize the transaction
    /// @return _shares           uint256          amount of shares minted
    function deposit(
        ERC20 _depositAsset,
        uint256 _depositAmount,
        address _recipient,
        NestVault _vault,
        bytes32 _depositor, // added to verify the original sender address
        PredicateMessage calldata _predicateMessage
    ) external returns (uint256 _shares);

    /// @notice Allows whitelisted users to mint into the NestVault, if PredicateProxy is not paused.
    /// @dev    Restricted to COMPOSER_ROLE. Allows specifying a _depositor (bytes32) different from msg.sender,
    ///         enabling custom predicate verifications for cross-chain mint integrations.
    /// @dev    Uses the predicate authorization pattern to validate the transaction
    /// @param  _depositAsset     ERC20            asset to deposit
    /// @param  _shares           uint256          amount of shares to mint
    /// @param  _recipient        address          address which to forward shares
    /// @param  _vault            NestVault        contract to deposit into
    /// @param  _depositor        bytes32          The depositor (bytes32 format to account for non-evm addresses)
    /// @param  _predicateMessage PredicateMessage Predicate message to authorize the transaction
    /// @return _depositAmount    uint256          amount of asset deposited
    function mint(
        ERC20 _depositAsset,
        uint256 _shares,
        address _recipient,
        NestVault _vault,
        bytes32 _depositor,
        PredicateMessage calldata _predicateMessage
    ) external returns (uint256 _depositAmount);
}
