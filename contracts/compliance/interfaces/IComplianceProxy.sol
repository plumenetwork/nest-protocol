// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

// contracts
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {NestVault} from "contracts/NestVault.sol";

// interfaces
import {IComplianceHook} from "contracts/compliance/interfaces/IComplianceHook.sol";
import {ISignatureTransfer} from "@uniswap/permit2/interfaces/ISignatureTransfer.sol";

/// @title  IComplianceProxy
/// @author plumenetwork
/// @notice Compliance-gated deposit/mint entrypoint for NestVault. Provider-agnostic successor to
///         INestVaultPredicateProxy: compliance proofs travel as opaque `bytes` and are validated
///         by a pluggable IComplianceHook.
interface IComplianceProxy {
    /// @notice Allows users to deposit into the NestVault, if the proxy is not paused.
    /// @param  _depositAsset    ERC20     asset to deposit
    /// @param  _depositAmount   uint256   amount of deposit asset to deposit
    /// @param  _receiver        address   address which to forward shares
    /// @param  _vault           NestVault contract to deposit into
    /// @param  _complianceData  bytes     provider-specific compliance proof
    /// @return _shares          uint256   amount of shares minted
    function deposit(
        ERC20 _depositAsset,
        uint256 _depositAmount,
        address _receiver,
        NestVault _vault,
        bytes calldata _complianceData
    ) external returns (uint256 _shares);

    /// @notice Allows users to deposit using a Permit2 signature-based transfer.
    /// @param  _depositAsset    ERC20              asset to deposit
    /// @param  _depositAmount   uint256            amount of deposit asset to deposit
    /// @param  _receiver        address            address which to forward shares
    /// @param  _vault           NestVault          contract to deposit into
    /// @param  _permit2         ISignatureTransfer Permit2 contract address
    /// @param  _nonce           uint256            unique nonce for Permit2 signature
    /// @param  _deadline        uint256            expiration timestamp for the permit
    /// @param  _signature       bytes              Permit2 signature from the token owner
    /// @param  _complianceData  bytes              provider-specific compliance proof
    /// @return _shares          uint256            amount of shares minted
    function depositWithPermit2(
        ERC20 _depositAsset,
        uint256 _depositAmount,
        address _receiver,
        NestVault _vault,
        ISignatureTransfer _permit2,
        uint256 _nonce,
        uint256 _deadline,
        bytes calldata _signature,
        bytes calldata _complianceData
    ) external returns (uint256 _shares);

    /// @notice Deposits assets supplied by msg.sender on behalf of an original depositor.
    /// @dev Publicly callable for dynamic relayers; the compliance hook must authorize the operation
    ///      for msg.sender and `_depositor`.
    /// @param  _vault           NestVault contract to deposit into
    /// @param  _depositAsset    ERC20     asset to deposit
    /// @param  _depositAmount   uint256   amount of deposit asset to deposit
    /// @param  _receiver        address   address which receives shares
    /// @param  _depositor       bytes32   original depositor; supports EVM and 32-byte non-EVM identifiers
    /// @param  _complianceData  bytes     provider-specific compliance data
    /// @return _shares          uint256   amount of shares minted
    function depositOnBehalf(
        NestVault _vault,
        ERC20 _depositAsset,
        uint256 _depositAmount,
        address _receiver,
        bytes32 _depositor,
        bytes calldata _complianceData
    ) external returns (uint256 _shares);

    /// @notice Deposits assets supplied by msg.sender via Permit2 on behalf of an original depositor.
    /// @dev The compliance hook must authorize the operation for msg.sender and `_depositor`.
    ///      The Permit2 signature must be signed by msg.sender.
    /// @param  _vault           NestVault          contract to deposit into
    /// @param  _depositAsset    ERC20              asset to deposit
    /// @param  _depositAmount   uint256            amount of deposit asset to deposit
    /// @param  _receiver        address            address which receives shares
    /// @param  _depositor       bytes32            original depositor; supports EVM and non-EVM identifiers
    /// @param  _permit2         ISignatureTransfer Permit2 contract address
    /// @param  _nonce           uint256            unique nonce for Permit2 signature
    /// @param  _deadline        uint256            expiration timestamp for the permit
    /// @param  _signature       bytes              Permit2 signature from msg.sender
    /// @param  _complianceData  bytes              provider-specific compliance data
    /// @return _shares          uint256            amount of shares minted
    function depositOnBehalfWithPermit2(
        NestVault _vault,
        ERC20 _depositAsset,
        uint256 _depositAmount,
        address _receiver,
        bytes32 _depositor,
        ISignatureTransfer _permit2,
        uint256 _nonce,
        uint256 _deadline,
        bytes calldata _signature,
        bytes calldata _complianceData
    ) external returns (uint256 _shares);

    /// @notice Allows users to mint shares, if the proxy is not paused.
    /// @param  _depositAsset    ERC20     asset to deposit
    /// @param  _shares          uint256   minimum amount of shares to receive
    /// @param  _receiver        address   address which to forward shares
    /// @param  _vault           NestVault contract to deposit into
    /// @param  _complianceData  bytes     provider-specific compliance proof
    /// @return _actualShares    uint256   amount of shares actually minted
    function mint(
        ERC20 _depositAsset,
        uint256 _shares,
        address _receiver,
        NestVault _vault,
        bytes calldata _complianceData
    ) external returns (uint256 _actualShares);

    /// @notice Restricted on-behalf mint specifying a `_depositor` distinct from msg.sender, for
    ///         cross-chain integrations (bytes32 to account for non-EVM addresses).
    /// @param  _depositAsset    ERC20     asset to deposit
    /// @param  _shares          uint256   minimum amount of shares to receive
    /// @param  _receiver        address   address which to forward shares
    /// @param  _vault           NestVault contract to deposit into
    /// @param  _depositor       bytes32   the original depositor being attested
    /// @param  _complianceData  bytes     provider-specific compliance data
    /// @return _actualShares    uint256   amount of shares actually minted
    function mintOnBehalf(
        ERC20 _depositAsset,
        uint256 _shares,
        address _receiver,
        NestVault _vault,
        bytes32 _depositor,
        bytes calldata _complianceData
    ) external returns (uint256 _actualShares);

    /// @notice Pulls `_shares` from msg.sender and requests an async redemption through the proxy.
    /// @dev The proxy is the owner reported by the vault; the proxy event preserves msg.sender as
    ///      the original owner. The user approves the proxy, not the vault or an ERC-7540 operator.
    /// @param  _shares          uint256   amount of shares to request redemption for
    /// @param  _controller      address   controller credited with the pending redemption
    /// @param  _vault           NestVault contract to request the redemption from
    /// @param  _complianceData  bytes     provider-specific compliance proof
    /// @return _requestId       uint256   the ERC-7540 request id
    function requestRedeem(uint256 _shares, address _controller, NestVault _vault, bytes calldata _complianceData)
        external
        returns (uint256 _requestId);

    /// @notice Pulls shares into the proxy with Permit2 and requests an async redemption.
    /// @dev Uses the vault's canonical Permit2 contract with a signature authorizing this proxy as
    ///      spender, then calls the standard vault redeem path with the proxy as owner.
    /// @param  _shares          uint256   amount of shares to request redemption for
    /// @param  _controller      address   controller credited with the pending redemption
    /// @param  _vault           NestVault contract to request the redemption from
    /// @param  _nonce           uint256   unique nonce for Permit2 signature
    /// @param  _deadline        uint256   expiration timestamp for the permit
    /// @param  _signature       bytes     Permit2 signature from msg.sender
    /// @param  _complianceData  bytes     provider-specific compliance proof
    /// @return _requestId       uint256   the ERC-7540 request id
    function requestRedeemWithPermit2(
        uint256 _shares,
        address _controller,
        NestVault _vault,
        uint256 _nonce,
        uint256 _deadline,
        bytes calldata _signature,
        bytes calldata _complianceData
    ) external returns (uint256 _requestId);

    /// @notice Pulls `_shares` from msg.sender and instantly redeems them; assets go to `_receiver`.
    /// @dev The proxy is the owner reported by the vault; the proxy event preserves msg.sender as
    ///      the original owner. The user approves the proxy, not the vault or an ERC-7540 operator.
    /// @param  _shares          uint256   amount of shares to redeem instantly
    /// @param  _receiver        address   address receiving the redeemed assets
    /// @param  _vault           NestVault contract to redeem from
    /// @param  _complianceData  bytes     provider-specific compliance proof
    /// @return _postFeeAmount   uint256   assets received by `_receiver` after fees
    /// @return _feeAmount       uint256   fee deducted from the gross redemption amount
    function instantRedeem(uint256 _shares, address _receiver, NestVault _vault, bytes calldata _complianceData)
        external
        returns (uint256 _postFeeAmount, uint256 _feeAmount);

    /// @notice Pulls shares into the proxy with Permit2 and instantly redeems them.
    /// @dev Uses the vault's canonical Permit2 contract with a signature authorizing this proxy as
    ///      spender, then calls the standard vault redeem path with the proxy as owner.
    /// @param  _shares          uint256   amount of shares to redeem instantly
    /// @param  _receiver        address   address receiving the redeemed assets
    /// @param  _vault           NestVault contract to redeem from
    /// @param  _nonce           uint256   unique nonce for Permit2 signature
    /// @param  _deadline        uint256   expiration timestamp for the permit
    /// @param  _signature       bytes     Permit2 signature from msg.sender
    /// @param  _complianceData  bytes     provider-specific compliance proof
    /// @return _postFeeAmount   uint256   assets received by `_receiver` after fees
    /// @return _feeAmount       uint256   fee deducted from the gross redemption amount
    function instantRedeemWithPermit2(
        uint256 _shares,
        address _receiver,
        NestVault _vault,
        uint256 _nonce,
        uint256 _deadline,
        bytes calldata _signature,
        bytes calldata _complianceData
    ) external returns (uint256 _postFeeAmount, uint256 _feeAmount);

    /// @notice Checks a user against the compliance hook without executing any transfer.
    /// @param  _user            address the user to check
    /// @param  _complianceData  bytes   provider-specific compliance proof
    /// @return bool `true` if the user is authorized
    function genericUserCheck(address _user, bytes calldata _complianceData) external returns (bool);

    /// @notice Checks an explicit caller and user pair against the compliance hook.
    /// @param  _caller          address the caller the compliance proof must attest for
    /// @param  _user            bytes32 the user to check
    /// @param  _complianceData  bytes   provider-specific compliance proof
    /// @return bool `true` if the caller/user pair is authorized
    function genericUserCheck(address _caller, bytes32 _user, bytes calldata _complianceData) external returns (bool);

    /// @notice The compliance hook consulted before every deposit/mint.
    function complianceHook() external view returns (IComplianceHook);

    /// @notice Updates the compliance hook. Access-controlled.
    /// @param  _complianceHook IComplianceHook the new hook
    function setComplianceHook(IComplianceHook _complianceHook) external;
}
