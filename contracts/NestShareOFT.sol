// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

// contracts
import {OFTUpgradeable} from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {AuthUpgradeable} from "contracts/upgradeable/auth/AuthUpgradeable.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {Errors} from "contracts/types/Errors.sol";

// interfaces
import {IERC7575Share} from "forge-std/interfaces/IERC7575.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IOFT} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITransferHook} from "contracts/interfaces/ITransferHook.sol";

// libraries
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

/// @title  NestShareOFT – Cross-Chain Share Token for NestVault Assets
/// @author plumenetwork
/// @notice ERC-20 share token with LayerZero OFT support enabling cross-chain minting and burning of shares backed by vault assets.
/// @dev    Implements upgradeable OFT, Auth, and IERC7575Share logic. Manages asset-to-share flows via authorized roles and maintains per-asset vault mappings.
contract NestShareOFT is OFTUpgradeable, AuthUpgradeable, IERC7575Share, ERC20PermitUpgradeable {
    using Address for address;
    using SafeTransferLib for ERC20;

    struct NestShareOFTStorage {
        // vault look up that returns the address of the Vault for a specific asset
        mapping(address => address) vault;
        // responsible for implementing `beforeTransfer`.
        ITransferHook hook;
    }

    // keccak256(abi.encode(uint256(keccak256("plumenetwork.storage.nestshare")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant NEST_SHARE_STORAGE_LOCATION =
        0xe362d12f87dacbebef0c9593e58b8b9ba0a58c01c2bee0269d69407ecbfd9e00;

    /// @dev Returns the storage struct for NestShare using a fixed storage slot derived from EIP-7201-style namespacing
    /// @return $ NestShareOFTStorage The NestShareOFTStorage struct reference
    function _getNestShareOFTStorage() internal pure returns (NestShareOFTStorage storage $) {
        assembly {
            $.slot := NEST_SHARE_STORAGE_LOCATION
        }
    }

    /// @notice Emitted when a user deposits an asset and receives shares
    /// @dev    Logs the deposit source, asset, deposited amount, share recipient, and number of shares minted
    /// @param  from   address indexed The address providing the underlying asset
    /// @param  asset  address indexed The ERC20 asset being deposited
    /// @param  amount uint256         The amount of the asset deposited
    /// @param  to     address indexed The address receiving the minted shares
    /// @param  shares uint256         The number of shares minted
    event Enter(address indexed from, address indexed asset, uint256 amount, address indexed to, uint256 shares);

    /// @notice Emitted when a user burns shares and withdraws an asset
    /// @dev    Logs the withdrawal recipient, asset, withdrawal amount, share holder, and number of shares burned
    /// @param  to     address indexed The address receiving the withdrawn asset
    /// @param  asset  address indexed The ERC20 asset being withdrawn
    /// @param  amount uint256         The amount of the asset withdrawn
    /// @param  from   address         The address whose shares are being burned
    /// @param  shares uint256         The number of shares burned
    event Exit(address indexed to, address indexed asset, uint256 amount, address indexed from, uint256 shares);

    /// @notice Emitted when token name and symbol are updated.
    /// @param  newName    string The updated token name.
    /// @param  newSymbol  string The updated token symbol.
    /// @param  version    uint64 The consumed reinitializer version.
    event NameAndSymbolUpdated(string newName, string newSymbol, uint64 version);

    /// @dev Constructor for the NestShare contract.
    /// @param _lzEndpoint address The LayerZero endpoint address.
    constructor(address _lzEndpoint) OFTUpgradeable(_lzEndpoint) {
        _disableInitializers();
    }

    /// @notice Initializes the NestShare token with its metadata and authorization settings
    /// @dev    Initializes OFT and Auth modules using the provided parameters
    /// @param  _name     string The name of the NestShare.
    /// @param  _symbol   string The symbol of the NestShare.
    /// @param  _owner    address The address that will be set as the owner of the contract.
    /// @param  _delegate address The delegate capable of making OApp configurations inside of the endpoint.
    function initialize(string memory _name, string memory _symbol, address _owner, address _delegate)
        public
        initializer
    {
        if (_owner == address(0)) revert Errors.ZeroAddress();
        if (bytes(_name).length == 0 || bytes(_symbol).length == 0) revert Errors.EmptyNameOrSymbol();

        __OFT_init(_name, _symbol, _delegate);
        __Auth_init(_owner, Authority(address(0)));
        __ERC20Permit_init(_name);
    }

    /// @dev    Returns the decimals of the NestShare token
    /// @return uint8 The decimals value (always 6)
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Returns the NestVault address associated with a given asset.
    /// @dev    Returns the address of the NestVault for the given asset
    /// @param  _asset address the ERC-20 token to deposit with into the NestVault
    /// @return        address The address of the NestVault for the given asset
    function vault(address _asset) external view returns (address) {
        return _getNestShareOFTStorage().vault[_asset];
    }

    /// @notice Sets the NestVault address for a specified asset.
    /// @dev    Sets the address of the NestVault for the given asset
    /// @param  _asset address the ERC-20 token to deposit with into the NestVault
    /// @param  _vault address the address of the NestVault
    function setVault(address _asset, address _vault) external requiresAuth {
        _getNestShareOFTStorage().vault[_asset] = _vault;

        emit VaultUpdate(_asset, _vault);
    }

    /// @notice Sets the share token name and symbol.
    /// @dev    Reinitializer step used after upgrades to reset ERC20 metadata.
    /// @dev    This updates the EIP712 domain name, which invalidates all previously signed ERC2612 permit signatures.
    /// @param  _name    string The new token name.
    /// @param  _symbol  string The new token symbol.
    /// @param  _version uint64 The reinitializer version to consume for this metadata update.
    function setNameAndSymbol(string calldata _name, string calldata _symbol, uint64 _version)
        external
        requiresAuth
        reinitializer(_version)
    {
        if (bytes(_name).length == 0 || bytes(_symbol).length == 0) revert Errors.EmptyNameOrSymbol();

        __ERC20_init(_name, _symbol);

        emit NameAndSymbolUpdated(_name, _symbol, _version);
    }

    /// @notice Executes an arbitrary function call from this contract
    /// @dev    Callable by authorized roles (MANAGER_ROLE)
    /// @param  target address The target contract to call
    /// @param  data   bytes   The calldata for the function call
    /// @param  value  uint256 The ETH value to forward with the call
    /// @return result bytes   The raw returned data from the call
    function manage(address target, bytes calldata data, uint256 value)
        external
        requiresAuth
        returns (bytes memory result)
    {
        result = target.functionCallWithValue(data, value);
    }

    /// @notice Executes multiple arbitrary function calls from this contract
    /// @dev    Callable by authorized roles (MANAGER_ROLE)
    /// @param  targets address[] The list of target contracts
    /// @param  data    bytes[]   The list of calldata blobs
    /// @param  values  uint256[] The list of ETH values to forward with each call
    /// @return results bytes[]   The returned data for each call
    function manage(address[] calldata targets, bytes[] calldata data, uint256[] calldata values)
        external
        requiresAuth
        returns (bytes[] memory results)
    {
        uint256 targetsLength = targets.length;
        results = new bytes[](targetsLength);
        for (uint256 i; i < targetsLength; ++i) {
            results[i] = targets[i].functionCallWithValue(data[i], values[i]);
        }
    }

    /// @notice Mints shares in exchange for depositing assets
    /// @dev    Callable by authorized roles (MINTER_ROLE)
    ///         If `assetAmount` is zero, no assets are transferred
    /// @param  from        address The address from which assets are transferred
    /// @param  asset       ERC20   The ERC20 asset deposited
    /// @param  assetAmount uint256 The amount of assets transferred in
    /// @param  to          address The address receiving the minted shares
    /// @param  shareAmount uint256 The number of shares minted
    function enter(address from, ERC20 asset, uint256 assetAmount, address to, uint256 shareAmount)
        external
        requiresAuth
    {
        // Transfer assets in
        if (assetAmount > 0) asset.safeTransferFrom(from, address(this), assetAmount);

        // Mint shares.
        _mint(to, shareAmount);

        emit Enter(from, address(asset), assetAmount, to, shareAmount);
    }

    /// @notice Burns shares and releases assets in return
    /// @dev    Callable by authorized roles (BURNER_ROLE)
    ///         If `assetAmount` is zero, no assets are transferred out
    /// @param  to          address The address receiving the assets
    /// @param  asset       ERC20   The ERC20 asset being withdrawn
    /// @param  assetAmount uint256 The amount of assets transferred out
    /// @param  from        address The address whose shares are burned
    /// @param  shareAmount uint256 The number of shares burned
    function exit(address to, ERC20 asset, uint256 assetAmount, address from, uint256 shareAmount)
        external
        requiresAuth
    {
        // Burn shares.
        _burn(from, shareAmount);

        // Transfer assets out.
        if (assetAmount > 0) asset.safeTransfer(to, assetAmount);

        emit Exit(to, address(asset), assetAmount, from, shareAmount);
    }

    /*//////////////////////////////////////////////////////////////
                    TRANSFER HOOK LOGIC
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Sets the share locker.
     * @notice If set to zero address, the share locker logic is disabled.
     * @dev Callable by OWNER_ROLE.
     * @param _hook address The hook contract implementing `beforeTransfer`.
     */
    function setBeforeTransferHook(address _hook) external requiresAuth {
        _getNestShareOFTStorage().hook = ITransferHook(_hook);
    }

    /// @notice Returns the current before-transfer hook.
    /// @return The hook contract implementing `beforeTransfer` (or zero address if disabled).
    function hook() public view returns (ITransferHook) {
        return _getNestShareOFTStorage().hook;
    }

    /**
     * @notice Check if from addresses shares are locked, reverting if so.
     * @param from address The address sending shares.
     */
    function _callBeforeTransfer(address from) internal view {
        ITransferHook beforeTransferHook = _getNestShareOFTStorage().hook;
        if (address(beforeTransferHook) != address(0)) beforeTransferHook.beforeTransfer(from);
    }

    /// @notice Overrides ERC20 `_update` to enforce the before-transfer hook.
    /// @param from address The address sending shares, or address(0) when minting.
    /// @param to address The address receiving shares, or address(0) when burning.
    /// @param value uint256 The amount of shares being moved.
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0)) {
            _callBeforeTransfer(from);
        }
        super._update(from, to, value);
    }

    /*//////////////////////////////////////////////////////////////
                    INTERFACE SUPPORT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks if the contract supports a given interface
    /// @dev    Supports IERC165, IERC7575Share, IERC20 and IOFT interfaces
    /// @param  _interfaceId bytes4 The interface ID to check for support
    /// @return              bool   true if the contract supports the given interface ID, false otherwise
    function supportsInterface(bytes4 _interfaceId) public pure override returns (bool) {
        return _interfaceId == type(IERC7575Share).interfaceId || _interfaceId == type(IERC165).interfaceId
            || _interfaceId == type(IOFT).interfaceId || _interfaceId == type(IERC20).interfaceId;
    }

    /*//////////////////////////////////////////////////////////////
                        Ownable OVERRIDDEN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc AuthUpgradeable
    function owner() public view override(OwnableUpgradeable, AuthUpgradeable) returns (address) {
        return AuthUpgradeable.owner();
    }

    /// @inheritdoc AuthUpgradeable
    function transferOwnership(address newOwner) public override(OwnableUpgradeable, AuthUpgradeable) requiresAuth {
        AuthUpgradeable.transferOwnership(newOwner);
    }

    /// @inheritdoc AuthUpgradeable
    function acceptOwnership() public override {
        address oldOwner = owner();
        AuthUpgradeable.acceptOwnership();

        emit OwnershipTransferred(oldOwner, owner());
    }

    /// @inheritdoc OwnableUpgradeable
    function renounceOwnership() public view override(OwnableUpgradeable) requiresAuth {
        revert Errors.RenounceOwnershipDisabled();
    }

    /*//////////////////////////////////////////////////////////////
                    ERC20PermitUpgradeable OVERRIDDEN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev Uses the current ERC20 name for EIP712 domain calculations.
    function _EIP712Name() internal view override returns (string memory) {
        return name();
    }

    /// @dev Fallback to version "1" for proxies upgraded before permit initialization existed.
    function _EIP712Version() internal view override returns (string memory) {
        string memory version_ = super._EIP712Version();
        if (bytes(version_).length == 0) return "1";

        return version_;
    }
}
