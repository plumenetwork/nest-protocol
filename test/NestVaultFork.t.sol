// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

// utils
import {Test} from "forge-std/Test.sol";

// interfaces
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC7540Redeem, IERC7540Operator} from "forge-std/interfaces/IERC7540.sol";

// contracts
import {NestVault} from "contracts/NestVault.sol";
import {AuthUpgradeable} from "contracts/upgradeable/auth/AuthUpgradeable.sol";
import {BoringVault} from "@boring-vault/src/base/BoringVault.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Helper} from "test/Helper.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MockRateProvider} from "test/mock/MockRateProvider.sol";

// libraries
import {Events} from "test/Events.sol";
import {Errors} from "contracts/types/Errors.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {DataTypes} from "contracts/types/DataTypes.sol";

/// @title NestVaultForkTest
/// @dev This contract contains various test functions to validate the functionality of the NestVault contract.
///      It uses Forge for testing and simulates multiple scenarios for deposit, mint, withdraw, and redeem functions.
contract NestVaultForkTest is Events, Helper {
    using FixedPointMathLib for uint256;

    // Test user private key and address for signing (for Permit2 tests)
    uint256 internal permit2UserPrivateKey;
    address internal permit2User;

    function setUp() public override {
        super.setUp();
        // Use a random private key that results in an address without code
        permit2UserPrivateKey = uint256(keccak256("test user permit2 vault"));
        permit2User = vm.addr(permit2UserPrivateKey);
        // Ensure user is an EOA (no code)
        vm.etch(permit2User, "");
    }

    /// @dev Reverts when trying to deploy with zero boring vault address
    function testRevertDeployBoringVaultZeroAddress() public {
        address payable _bVault;
        vm.expectRevert(Errors.ZERO_ADDRESS.selector);
        new NestVault(_bVault);
    }

    /// @dev Reverts when accountantWithRateProviders is passed as zero address
    function testRevertInitializeAccountantWithRateProvidersZeroAddress() public {
        address _accountantWithRateProviders = address(0);
        address _asset = USDC;
        address _owner = address(this);
        uint256 _minRate = 1e3;
        vm.expectRevert(Errors.ZERO_ADDRESS.selector);
        new TransparentUpgradeableProxy(
            address(_logic),
            address(this),
            abi.encodeCall(NEST_VAULT.initialize, (_accountantWithRateProviders, _asset, _owner, _minRate))
        );
    }

    /// @dev Reverts when asset is passed as zero address
    function testRevertInitializeAssetZeroAddress() public {
        address _accountantWithRateProviders = NALPHA_ACCOUNTANT;
        address _asset = address(0);
        address _owner = address(this);
        uint256 _minRate = 1e3;
        vm.expectRevert(Errors.ZERO_ADDRESS.selector);
        new TransparentUpgradeableProxy(
            address(_logic),
            address(this),
            abi.encodeCall(NEST_VAULT.initialize, (_accountantWithRateProviders, _asset, _owner, _minRate))
        );
    }

    /// @dev Reverts when owner is passed as zero address
    function testRevertInitializeOwnerZeroAddress() public {
        address _accountantWithRateProviders = NALPHA_ACCOUNTANT;
        address _asset = USDC;
        address _owner = address(0);
        uint256 _minRate = 1e3;
        vm.expectRevert(Errors.ZERO_ADDRESS.selector);
        new TransparentUpgradeableProxy(
            address(_logic),
            address(this),
            abi.encodeCall(NEST_VAULT.initialize, (_accountantWithRateProviders, _asset, _owner, _minRate))
        );
    }

    /// @dev Reverts when. min rate is equal to 10 ** asset decimals
    function testRevertInitializeMinRateEqualtoInvalid() public {
        address _accountantWithRateProviders = NALPHA_ACCOUNTANT;
        address _asset = USDC;
        address _owner = address(1);
        uint256 _minRate = 1e6;
        vm.expectRevert(Errors.INVALID_RATE.selector);
        new TransparentUpgradeableProxy(
            address(_logic),
            address(this),
            abi.encodeCall(NEST_VAULT.initialize, (_accountantWithRateProviders, _asset, _owner, _minRate))
        );
    }

    /// @dev Reverts when. min rate is greater than 10 ** asset decimals
    function testRevertInitializeMinRateGreaterInvalid() public {
        address _accountantWithRateProviders = NALPHA_ACCOUNTANT;
        address _asset = USDC;
        address _owner = address(1);
        uint256 _minRate = 1e7;
        vm.expectRevert(Errors.INVALID_RATE.selector);
        new TransparentUpgradeableProxy(
            address(_logic),
            address(this),
            abi.encodeCall(NEST_VAULT.initialize, (_accountantWithRateProviders, _asset, _owner, _minRate))
        );
    }

    /// @dev Test for verifying that the correct authority is set for the NestVault contract.
    function testSetAuthorityAsOwner() public view {
        assertEq(address(NEST_VAULT.authority()), address(boringAuthority));
    }

    /// @dev Test for checking the version of the NestVault contract.
    function testVersion() public view {
        assertEq(NEST_VAULT.version(), "0.0.1");
    }

    /// @dev Test for checking the interfaces supported by the NestVault contract.
    ///      Verifies if the contract supports IERC7540Operator, IERC165, and IERC7540Redeem interfaces.
    function testSupportsInterface() public view {
        // Check if the contract supports the IERC7540Operator interface
        bytes4 operatorInterfaceId = 0xe3bc4e65;
        assertTrue(NEST_VAULT.supportsInterface(operatorInterfaceId), "Should support IERC7540Operator");

        // Check if the contract supports the IERC165 interface
        bytes4 ierc165InterfaceId = 0x01ffc9a7;
        assertTrue(NEST_VAULT.supportsInterface(ierc165InterfaceId), "Should support IERC165");

        // Check if the contract supports the IERC7540Redeem interface
        bytes4 redeemInterfaceId = 0x620ee8e4;
        assertTrue(NEST_VAULT.supportsInterface(redeemInterfaceId), "Should support IERC7540Redeem");

        // Check if the contract supports the IERC7575 interface
        bytes4 ierc7575InterfaceId = 0x2f0a18c5;
        assertTrue(NEST_VAULT.supportsInterface(ierc7575InterfaceId), "Should support IERC7575");

        // Check for an unsupported interface (e.g., a random interface ID)
        bytes4 unsupportedInterfaceId = bytes4(keccak256("randomInterface()"));
        assertFalse(NEST_VAULT.supportsInterface(unsupportedInterfaceId), "Should not support unsupported interface");
    }

    /// @dev Test for verifying the total assets in the NestVault contract.
    ///      Compares the total assets in the vault with the expected value.
    function testTotalAssets() public view {
        uint256 expectedTotalAssets = BoringVault(NALPHA).totalSupply()
            .mulDivDown(
                NEST_VAULT.accountantWithRateProviders().getRateInQuoteSafe(ERC20(USDC)), 10 ** ERC20(NALPHA).decimals()
            );
        assertEq(NEST_VAULT.totalAssets(), expectedTotalAssets);
    }

    /// @dev Test for setting accountant with rate provider should succeed
    function testSetAccountantWithRateProviders() public {
        MockRateProvider _rateProviderMock = new MockRateProvider();
        NEST_VAULT.setAccountantWithRateProviders(address(_rateProviderMock));
        assertEq(address(_rateProviderMock), address(NEST_VAULT.accountantWithRateProviders()));
    }

    /// @dev Test for setting accountant with rate provider called with unauthorized
    ///      caller should revert
    function testRevertSetAccountantWithRateProvidersUnauthorized() public {
        MockRateProvider _rateProviderMock = new MockRateProvider();
        vm.startPrank(makeAddr("alice"));
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        NEST_VAULT.setAccountantWithRateProviders(address(_rateProviderMock));
        vm.stopPrank();
    }

    /// @dev Test for setting accountant with rate provider called with zero address
    ///      should revert
    function testRevertSetAccountantWithRateProvidersZeroAddress() public {
        vm.expectRevert(Errors.ZERO_ADDRESS.selector);
        NEST_VAULT.setAccountantWithRateProviders(address(0));
    }

    /// @dev Test for verifying the deposit functionality of the NestVault contract.
    ///      Deposits a certain amount of USDC and checks if the shares are correctly issued.
    function testDeposit() public {
        uint256 depositAmount = 20_000 * 10 ** ERC20(USDC).decimals();
        uint256 expectedShares = Math.mulDiv(
            depositAmount,
            10 ** ERC20(NALPHA).decimals(),
            NEST_VAULT.accountantWithRateProviders().getRateInQuoteSafe(ERC20(USDC)),
            Math.Rounding.Floor
        );
        uint256 userUSDCBalanceBefore = ERC20(USDC).balanceOf(ETHEREUM_USDC_WHALE);
        uint256 usernALPHABalanceBefore = ERC20(address(NEST_VAULT)).balanceOf(ETHEREUM_USDC_WHALE);
        uint256 vaultUSDCBalanceBefore = ERC20(USDC).balanceOf(NALPHA);
        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);
        vm.stopPrank();
        assertEq(expectedShares, shares);
        assertEq(depositAmount + vaultUSDCBalanceBefore, ERC20(USDC).balanceOf(NALPHA));
        assertEq(ERC20(ERC20(address(NEST_VAULT))).balanceOf(ETHEREUM_USDC_WHALE), usernALPHABalanceBefore + shares);
        assertEq(ERC20(USDC).balanceOf(ETHEREUM_USDC_WHALE), userUSDCBalanceBefore - depositAmount);
    }

    /// @dev Test for verifying the deposit functionality when an unauthorized call is made.
    //       Ensures that the deposit fails if the public capability is turned off.
    function testRevertDepositUnauthorized() public {
        vm.prank(boringAuthority.owner());
        boringAuthority.setPublicCapability(address(NEST_VAULT), NEST_VAULT.deposit.selector, false);
        uint256 depositAmount = 20_000 * 10 ** ERC20(USDC).decimals();
        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        vm.expectRevert(Errors.UNAUTHORIZED.selector);
        NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);
        vm.stopPrank();
    }

    /// @dev Test for verifying the mint functionality of the NestVault contract.
    ///     Mints a specified amount of shares and checks the amount of USDC deposited.
    function testMint() public {
        uint256 mintAmount = 10_000 * 10 ** ERC20(NALPHA).decimals();

        // Get the expected amount of USDC that should be deposited to mint `mintAmount` shares
        uint256 expectedUSDCDeposit = Math.mulDiv(
            mintAmount,
            NEST_VAULT.accountantWithRateProviders().getRateInQuoteSafe(ERC20(USDC)),
            10 ** ERC20(NALPHA).decimals(),
            Math.Rounding.Ceil
        );

        uint256 userUSDCBalanceBefore = ERC20(USDC).balanceOf(ETHEREUM_USDC_WHALE);
        uint256 usernALPHABalanceBefore = ERC20(NALPHA).balanceOf(ETHEREUM_USDC_WHALE);
        uint256 vaultUSDCBalanceBefore = ERC20(USDC).balanceOf(NALPHA);

        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);

        // Call the mint function, requesting to mint `mintAmount` of NALPHA shares
        uint256 usdcDeposited = NEST_VAULT.mint(mintAmount, ETHEREUM_USDC_WHALE);

        vm.stopPrank();

        // Assert that the returned amount of USDC corresponds to the expected deposit
        assertEq(usdcDeposited, expectedUSDCDeposit);

        // Assert that the vault's USDC balance has increased by the expected deposit
        assertEq(vaultUSDCBalanceBefore + expectedUSDCDeposit, ERC20(USDC).balanceOf(NALPHA));

        // Assert that the user's NALPHA balance has increased by the minted shares
        assertEq(ERC20(NALPHA).balanceOf(ETHEREUM_USDC_WHALE), usernALPHABalanceBefore + mintAmount);

        // Assert that the user's USDC balance has decreased by the deposited amount
        assertEq(ERC20(USDC).balanceOf(ETHEREUM_USDC_WHALE), userUSDCBalanceBefore - expectedUSDCDeposit);
    }

    /// @dev should redeem instantly
    function testInstantRedeem() public {
        // User deposits USDC to receive shares (setup phase)
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();

        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 mintedShares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);
        vm.stopPrank();

        // Approve SHARE to vault for redemption
        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(address(NALPHA)).approve(address(NEST_VAULT), type(uint256).max);
        vm.stopPrank();

        uint32 _instantRedemptionFee = 1e4; // 1%
        NEST_VAULT.setFee(DataTypes.Fees.InstantRedemption, _instantRedemptionFee);
        assertEq(_instantRedemptionFee, 1e4);

        // Expected pre-fee asset value of the shares
        uint256 expectedAssets = NEST_VAULT.convertToAssets(mintedShares);

        // Expected fee = assets * fee / 1e6
        uint256 expectedFee = (expectedAssets * _instantRedemptionFee) / 1_000_000;
        uint256 expectedPostFee = expectedAssets - expectedFee;

        // Capture balances before redeem
        uint256 receiverUSDCbefore = ERC20(USDC).balanceOf(ETHEREUM_USDC_WHALE);
        uint256 vaultUSDCbefore = ERC20(USDC).balanceOf(NALPHA);
        uint256 userSharesBefore = ERC20(address(NALPHA)).balanceOf(ETHEREUM_USDC_WHALE);

        // Expect InstantRedeem event
        vm.expectEmit(true, true, true, true);
        emit InstantRedeem(mintedShares, expectedAssets, expectedPostFee, ETHEREUM_USDC_WHALE);

        // Do instantRedeem
        vm.startPrank(ETHEREUM_USDC_WHALE);
        (uint256 postFee, uint256 feeAmount) =
            NEST_VAULT.instantRedeem(mintedShares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);
        vm.stopPrank();

        // Assertions on return values
        assertEq(postFee, expectedPostFee);
        assertEq(feeAmount, expectedFee);

        // Assertions on balances
        assertEq(ERC20(USDC).balanceOf(ETHEREUM_USDC_WHALE), receiverUSDCbefore + expectedPostFee);

        assertEq(ERC20(USDC).balanceOf(NALPHA), vaultUSDCbefore - expectedPostFee);

        assertEq(ERC20(address(NALPHA)).balanceOf(ETHEREUM_USDC_WHALE), userSharesBefore - mintedShares);
    }

    /// @dev should redeem instantly with authorized operator
    function testInstantRedeem_OperatorAuthorized() public {
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();

        // Deposit to get shares
        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);

        // Approve SHARE to vault
        ERC20(address(NALPHA)).approve(address(NEST_VAULT), type(uint256).max);
        vm.stopPrank();

        // Set operator
        address operator = address(0xA11CE);
        vm.prank(ETHEREUM_USDC_WHALE);
        NEST_VAULT.setOperator(operator, true);

        uint256 receiverUSDCbefore = ERC20(USDC).balanceOf(ETHEREUM_USDC_WHALE);

        // Operator performs instant redeem on behalf of owner
        vm.prank(operator);
        NEST_VAULT.instantRedeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        assertGt(ERC20(USDC).balanceOf(ETHEREUM_USDC_WHALE), receiverUSDCbefore);
    }

    /// @dev revert when instant redeem, is called by unauthorized caller
    function testRevertInstantRedeemUnauthorizedCaller() public {
        vm.prank(boringAuthority.owner());
        boringAuthority.setPublicCapability(address(NEST_VAULT), NEST_VAULT.instantRedeem.selector, false);

        vm.startPrank(address(1));
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);

        // Attempt to call withdraw with unauthorized caller
        NEST_VAULT.instantRedeem(0, address(0), address(0));
        vm.stopPrank();
    }

    /// @dev revert if caller is nor owner neither operator
    function testInstantRedeem_UnauthorizedCallerNotOperator() public {
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();

        // Owner deposits enough to get shares (required setup)
        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 mintedShares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);
        vm.stopPrank();

        // Owner approves SHARE to vault (required for redeem)
        vm.prank(ETHEREUM_USDC_WHALE);
        ERC20(address(NALPHA)).approve(address(NEST_VAULT), mintedShares);

        // attacker (not owner, not operator)
        address attacker = address(0xBEEF);

        // attacker attempts to redeem owner’s shares → should revert
        vm.prank(attacker);
        vm.expectRevert(Errors.UNAUTHORIZED.selector);
        NEST_VAULT.instantRedeem(
            mintedShares,
            attacker, // receiver
            ETHEREUM_USDC_WHALE // owner
        );
    }

    /// @dev should revert when trying to redeem with more shares
    function testInstantRedeem_InsufficientShareBalance() public {
        // Owner deposits to receive some shares
        uint256 depositAmount = 1_000 * 10 ** ERC20(USDC).decimals();

        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 mintedShares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);
        vm.stopPrank();

        // Owner approves SHARE to vault
        vm.prank(ETHEREUM_USDC_WHALE);
        ERC20(address(NALPHA)).approve(address(NEST_VAULT), type(uint256).max);

        // Try redeeming MORE shares than owned → should revert
        uint256 tooManyShares = mintedShares + 1;

        vm.prank(ETHEREUM_USDC_WHALE);
        vm.expectRevert(Errors.INSUFFICIENT_BALANCE.selector);
        NEST_VAULT.instantRedeem(
            tooManyShares,
            ETHEREUM_USDC_WHALE, // receiver
            ETHEREUM_USDC_WHALE // owner
        );
    }

    /// @dev reverts when trying to redeem zero shares
    function testInstantRedeem_ZeroShares() public {
        vm.prank(ETHEREUM_USDC_WHALE);
        vm.expectRevert(Errors.ZERO_SHARES.selector);
        NEST_VAULT.instantRedeem(0, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);
    }

    /// @dev reverts if receiver did not received expected underlying assets
    function testInstantRedeem_TransferInsufficient() public {
        uint256 depositAmount = 1_000 * 10 ** ERC20(USDC).decimals();

        // Deposit to get shares
        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 mintedShares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);

        // Approve SHARE
        ERC20(address(NALPHA)).approve(address(NEST_VAULT), type(uint256).max);
        vm.stopPrank();

        bytes4 balanceOfSelector = bytes4(keccak256("balanceOf(address)"));
        vm.mockCall(
            USDC,
            abi.encodeWithSelector(balanceOfSelector, address(ETHEREUM_USDC_WHALE)),
            abi.encode(uint256(0)) // force balance to return 0
        );

        vm.prank(ETHEREUM_USDC_WHALE);
        vm.expectRevert(Errors.TRANSFER_INSUFFICIENT.selector);
        NEST_VAULT.instantRedeem(mintedShares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);
    }

    /// @dev should be able to update redeem request
    function testUpdateRedeem() public {
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();

        // --- Setup ---
        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);

        uint256 shares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);

        // Approve shares for redemption
        ERC20(NALPHA).approve(address(NEST_VAULT), shares);

        // Create initial redeem request
        NEST_VAULT.requestRedeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        // Before update
        assertEq(NEST_VAULT.pendingRedeemRequest(shares, ETHEREUM_USDC_WHALE), shares);

        uint256 newShares = shares / 2;
        uint256 returnAmount = shares - newShares;

        uint256 beforeOwner = ERC20(address(NEST_VAULT)).balanceOf(ETHEREUM_USDC_WHALE);

        // --- Act ---
        vm.expectEmit(true, true, true, true);
        emit RedeemUpdated(ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE, shares, newShares);

        NEST_VAULT.updateRedeem(newShares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        // --- Assert ---

        // New pending shares
        uint256 pendingAfter = NEST_VAULT.pendingRedeemRequest(newShares, ETHEREUM_USDC_WHALE);
        assertEq(pendingAfter, newShares, "pending updated");

        // Return amount (old - new) was transferred out
        uint256 afterOwner = ERC20(address(NEST_VAULT)).balanceOf(ETHEREUM_USDC_WHALE);
        assertEq(afterOwner - beforeOwner, returnAmount);

        vm.stopPrank();
    }

    /// @dev revert when update redeem, is called by unauthorized caller
    function testRevertUpdateRedeemUnauthorizedCaller() public {
        vm.prank(boringAuthority.owner());
        boringAuthority.setPublicCapability(address(NEST_VAULT), NEST_VAULT.updateRedeem.selector, false);

        vm.startPrank(address(1));
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);

        // Attempt to call withdraw with unauthorized caller
        NEST_VAULT.updateRedeem(0, address(0), address(0));
        vm.stopPrank();
    }

    /// @dev reverts when called by nor an owner neither an operator
    function testUpdateRedeem_Unauthorized() public {
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();

        // Setup by whale
        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);
        ERC20(NALPHA).approve(address(NEST_VAULT), shares);
        NEST_VAULT.requestRedeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);
        vm.stopPrank();

        // Unauthorized caller tries update
        address attacker = address(0xBEEF);
        vm.startPrank(attacker);
        vm.expectRevert(Errors.UNAUTHORIZED.selector);
        NEST_VAULT.updateRedeem(shares / 2, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);
        vm.stopPrank();
    }

    /// @dev reverts when owner updates redeem without controller authorization
    function testUpdateRedeem_ControllerNotAuthorized() public {
        address controller = makeAddr("controller");
        address operator = makeAddr("operator");
        address owner = ETHEREUM_USDC_WHALE;
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();

        vm.startPrank(owner);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, owner);
        ERC20(NALPHA).approve(address(NEST_VAULT), shares);
        NEST_VAULT.setOperator(operator, true);
        vm.stopPrank();

        vm.prank(controller);
        NEST_VAULT.setOperator(operator, true);

        vm.prank(operator);
        NEST_VAULT.requestRedeem(shares, controller, owner);

        vm.prank(owner);
        vm.expectRevert(Errors.UNAUTHORIZED.selector);
        NEST_VAULT.updateRedeem(shares / 2, controller, owner);
    }

    /// @dev attacker cannot zero pending after a valid controller request
    function testUpdateRedeem_AttackerCannotZeroPendingAfterControllerRequest() public {
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();

        // Controller creates pending redeem for own shares
        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);
        ERC20(NALPHA).approve(address(NEST_VAULT), shares);
        NEST_VAULT.requestRedeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);
        vm.stopPrank();

        assertEq(NEST_VAULT.pendingRedeemRequest(shares, ETHEREUM_USDC_WHALE), shares, "pending set");

        // Unauthorized attacker cannot zero out pending
        address attacker = address(0xBADBEEF);
        vm.startPrank(attacker);
        vm.expectRevert(Errors.UNAUTHORIZED.selector);
        NEST_VAULT.updateRedeem(0, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);
        vm.stopPrank();

        assertEq(NEST_VAULT.pendingRedeemRequest(shares, ETHEREUM_USDC_WHALE), shares, "pending intact");
        assertEq(ERC20(address(NALPHA)).balanceOf(attacker), 0, "attacker received nothing");
    }

    /// @dev revert when trying to update with no share holdings
    function testUpdateRedeem_NoPendingRedeem() public {
        vm.startPrank(ETHEREUM_USDC_WHALE);

        vm.expectRevert(Errors.NO_PENDING_REDEEM.selector);
        NEST_VAULT.updateRedeem(10, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        vm.stopPrank();
    }

    /// @dev revert when trying to increase pending redeem amount
    function testUpdateRedeem_InsufficientBalance() public {
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();

        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);
        ERC20(NALPHA).approve(address(NEST_VAULT), shares);
        NEST_VAULT.requestRedeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        uint256 newShares = shares + 1; // deliberately larger

        vm.expectRevert(Errors.INSUFFICIENT_BALANCE.selector);
        NEST_VAULT.updateRedeem(newShares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        vm.stopPrank();
    }

    /// @dev no operation when trying to update redeem with same amount as old shares
    function testUpdateRedeem_NoOp() public {
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();

        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);
        ERC20(NALPHA).approve(address(NEST_VAULT), shares);
        NEST_VAULT.requestRedeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        uint256 before = NEST_VAULT.pendingRedeemRequest(shares, ETHEREUM_USDC_WHALE);

        // Should NOT revert, NOT emit, NOT modify state
        NEST_VAULT.updateRedeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        uint256 _after = NEST_VAULT.pendingRedeemRequest(shares, ETHEREUM_USDC_WHALE);

        assertEq(_after, before, "no-op must not change shares");

        vm.stopPrank();
    }

    /// @dev revert when withdraw is called by unauthorized caller
    function testRevertWithdrawUnauthorizedCaller() public {
        vm.prank(boringAuthority.owner());
        boringAuthority.setPublicCapability(address(NEST_VAULT), NEST_VAULT.withdraw.selector, false);

        vm.startPrank(address(1));
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);

        // Attempt to call withdraw with unauthorized caller
        NEST_VAULT.withdraw(0, address(0), address(0));
        vm.stopPrank();
    }

    /// @dev revert when receiver address passed is address(0)
    function testRevertWithdrawReceiverZeroAddress() public {
        vm.expectRevert(Errors.ZERO_ADDRESS.selector);
        NEST_VAULT.withdraw(0, address(0), address(this));
    }

    /// @dev Test for the withdrawal process in the Nest Vault.
    ///      This test simulates the entire deposit, redeem request, and withdraw cycle.
    ///      Ensures that after a withdrawal, pending redeem requests are properly cleared.
    function testWithdraw() public {
        uint256 depositAmount = 20_000 * 10 ** ERC20(USDC).decimals();

        vm.startPrank(ETHEREUM_USDC_WHALE);

        // Approve and deposit
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);

        // Approve redeem
        ERC20(NALPHA).approve(address(NEST_VAULT), shares);

        // Request redeem
        NEST_VAULT.requestRedeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        // Check the pending redeem request
        uint256 pendingShares = NEST_VAULT.pendingRedeemRequest(shares, ETHEREUM_USDC_WHALE);
        assertEq(pendingShares, shares, "Pending redeem request should match requested shares");

        // Fulfill redeem
        uint256 assets = NEST_VAULT.fulfillRedeem(ETHEREUM_USDC_WHALE, shares);

        // Check the claimable redeem request
        uint256 claimableShares = NEST_VAULT.claimableRedeemRequest(shares, ETHEREUM_USDC_WHALE);
        assertEq(claimableShares, shares, "Claimable redeem request should match fulfilled shares");

        // Check max withdraw for the controller
        uint256 maxWithdrawAmount = NEST_VAULT.maxWithdraw(ETHEREUM_USDC_WHALE);
        assertEq(maxWithdrawAmount, assets, "Max withdraw should match the claimable assets");

        // Withdraw the assets
        NEST_VAULT.withdraw(assets, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        // Ensure pending redeem is now 0 after withdrawal
        pendingShares = NEST_VAULT.pendingRedeemRequest(shares, ETHEREUM_USDC_WHALE);
        assertEq(pendingShares, 0, "Pending redeem request should be 0 after withdrawal");

        vm.stopPrank();
    }

    /// @dev Test should revert when unauthorized caller calls redeem
    function testRevertRedeemUnauthorizedCaller() public {
        vm.prank(boringAuthority.owner());
        boringAuthority.setPublicCapability(address(NEST_VAULT), NEST_VAULT.redeem.selector, false);

        vm.startPrank(address(1));
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);

        // Attempt to call redeem with unauthorized caller
        NEST_VAULT.redeem(0, address(0), address(0));
        vm.stopPrank();
    }

    /// @dev revert when receiver address passed is address(0)
    function testRevertRedeemReceiverZeroAddress() public {
        vm.expectRevert(Errors.ZERO_ADDRESS.selector);
        NEST_VAULT.redeem(0, address(0), address(this));
    }

    /// @dev Test for redeeming shares in the Nest Vault.
    ///      Simulates the deposit, redeem request, and redemption process for vault shares.
    function testRedeem() public {
        uint256 depositAmount = 20_000 * 10 ** ERC20(USDC).decimals();

        vm.startPrank(ETHEREUM_USDC_WHALE);

        // Approve and deposit
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);

        // Approve redeem
        ERC20(NALPHA).approve(address(NEST_VAULT), shares);

        // Request redeem
        NEST_VAULT.requestRedeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        // Check the pending redeem request
        uint256 pendingShares = NEST_VAULT.pendingRedeemRequest(shares, ETHEREUM_USDC_WHALE);
        assertEq(pendingShares, shares, "Pending redeem request should match requested shares");

        // Fulfill redeem
        NEST_VAULT.fulfillRedeem(ETHEREUM_USDC_WHALE, shares);

        // Check the claimable redeem request
        uint256 claimableShares = NEST_VAULT.claimableRedeemRequest(shares, ETHEREUM_USDC_WHALE);
        assertEq(claimableShares, shares, "Claimable redeem request should match fulfilled shares");

        // Check max redeem for the controller
        uint256 maxRedeemAmount = NEST_VAULT.maxRedeem(ETHEREUM_USDC_WHALE);
        assertEq(maxRedeemAmount, shares, "Max redeem should match the claimable shares");

        // Redeem the shares
        NEST_VAULT.redeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        // Ensure pending redeem is now 0 after redeem
        pendingShares = NEST_VAULT.pendingRedeemRequest(shares, ETHEREUM_USDC_WHALE);
        assertEq(pendingShares, 0, "Pending redeem request should be 0 after redeem");

        vm.stopPrank();
    }

    /// @dev Test for reverting when trying to fulfill a redeem request with invalid shares.
    ///     This ensures that the function reverts when the shares do not match the requested redeem shares.
    function testRevertFulfillRedeemInvalidShares() public {
        uint256 depositAmount = 20_000 * 10 ** ERC20(USDC).decimals();
        vm.startPrank(ETHEREUM_USDC_WHALE);

        // Approve and deposit
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);

        // Approve redeem
        ERC20(NALPHA).approve(address(NEST_VAULT), shares);

        // Request redeem
        NEST_VAULT.requestRedeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        // Get the current pending shares (after requestRedeem)
        uint256 pendingShares = NEST_VAULT.pendingRedeemRequest(shares, ETHEREUM_USDC_WHALE);
        assertEq(pendingShares, shares, "Pending redeem request should match requested shares");

        // Try to fulfill redeem with more shares than requested
        uint256 invalidShares = shares + 1; // Invalid because the requested redeem shares is exactly `shares`
        vm.expectRevert(Errors.ZERO_SHARES.selector);
        NEST_VAULT.fulfillRedeem(ETHEREUM_USDC_WHALE, invalidShares);

        // Now, simulate zero shares in the pending redeem (by fulfilling the redeem)
        NEST_VAULT.fulfillRedeem(ETHEREUM_USDC_WHALE, shares);

        // Check that no shares are pending anymore (should be zero)
        pendingShares = NEST_VAULT.pendingRedeemRequest(shares, ETHEREUM_USDC_WHALE);
        assertEq(pendingShares, 0, "Pending redeem request should be 0 after fulfilling redeem");

        // Try to fulfill redeem again with zero shares pending
        vm.expectRevert(Errors.ZERO_SHARES.selector);
        NEST_VAULT.fulfillRedeem(ETHEREUM_USDC_WHALE, shares);

        vm.stopPrank();
    }

    /// @dev Fulfill is auth-gated; rate source change should not block an authorized caller
    function testFulfillRedeem_HaircutViaRateSwitch_allowsAuthorizedCaller() public {
        uint256 depositAmount = 20_000 * 10 ** ERC20(USDC).decimals();

        // User deposits and queues async redeem (controller = user)
        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);
        ERC20(NALPHA).approve(address(NEST_VAULT), shares);
        NEST_VAULT.requestRedeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);
        vm.stopPrank();

        // Admin changes rate source, but is not controller/operator
        MockRateProvider lowRateProvider = new MockRateProvider();
        uint256 lowRate = NEST_VAULT.minRate();
        lowRateProvider.setRate(lowRate);

        vm.startPrank(boringAuthority.owner());
        boringAuthority.setPublicCapability(
            address(NEST_VAULT), NEST_VAULT.setAccountantWithRateProviders.selector, true
        );
        NEST_VAULT.setAccountantWithRateProviders(address(lowRateProvider));

        // Fulfill from an authorized caller should succeed
        uint256 assets = NEST_VAULT.fulfillRedeem(ETHEREUM_USDC_WHALE, shares);
        vm.stopPrank();

        // Pending moved to claimable
        uint256 pendingShares = NEST_VAULT.pendingRedeemRequest(0, ETHEREUM_USDC_WHALE);
        assertEq(pendingShares, 0, "pending should be cleared");
        uint256 claimable = NEST_VAULT.claimableRedeemRequest(0, ETHEREUM_USDC_WHALE);
        assertEq(claimable, shares, "claimable should equal fulfilled shares");
        assertGt(assets, 0, "assets should be non-zero");
    }

    /// @dev owner can set a different controller without controller authorization
    function testRequestRedeem_ControllerMismatchCreatesPending() public {
        uint256 depositAmount = 20_000 * 10 ** ERC20(USDC).decimals();
        address controller = makeAddr("controller");

        // Owner deposits and requests redeem with a different controller
        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);
        ERC20(NALPHA).approve(address(NEST_VAULT), shares);
        uint256 ownerSharesBefore = ERC20(address(NALPHA)).balanceOf(ETHEREUM_USDC_WHALE);
        uint256 vaultSharesBefore = ERC20(address(NALPHA)).balanceOf(address(NEST_VAULT));

        NEST_VAULT.requestRedeem(shares, controller, ETHEREUM_USDC_WHALE);
        vm.stopPrank();

        // Pending shares are tracked under the controller (not the owner)
        assertEq(NEST_VAULT.pendingRedeemRequest(0, controller), shares, "pending created for controller");
        assertEq(NEST_VAULT.pendingRedeemRequest(0, ETHEREUM_USDC_WHALE), 0, "owner has no pending");
        assertEq(
            ERC20(address(NALPHA)).balanceOf(ETHEREUM_USDC_WHALE),
            ownerSharesBefore - shares,
            "owner shares transferred"
        );
        assertEq(
            ERC20(address(NALPHA)).balanceOf(address(NEST_VAULT)),
            vaultSharesBefore + shares,
            "vault holds pending shares"
        );
    }

    /// @dev Test should revert when unauthorized caller calls requestRedeem
    function testRevertRequestRedeemUnauthorizedCaller() public {
        vm.prank(boringAuthority.owner());
        boringAuthority.setPublicCapability(address(NEST_VAULT), NEST_VAULT.requestRedeem.selector, false);

        vm.startPrank(address(1));
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);

        // Attempt to call requestRedeem with unauthorized caller
        NEST_VAULT.requestRedeem(0, address(0), address(0));
        vm.stopPrank();
    }

    /// @dev Test for unauthorized redeem requests, ensuring that only authorized controllers can request redeem.
    function testRevertRequestRedeemUnauthorized() public {
        address controller = makeAddr("controller");
        address operator = makeAddr("operator");
        address owner = controller; // owner is the controller
        uint256 shares = 100; // Arbitrary share amount

        // Make sure the operator is not authorized
        vm.startPrank(operator);
        vm.expectRevert(Errors.UNAUTHORIZED.selector);

        // Attempt to call requestRedeem with unauthorized operator
        NEST_VAULT.requestRedeem(shares, controller, owner);

        vm.stopPrank();
    }

    /// @dev Reverts when controller is the zero address
    function testRevertRequestRedeemControllerZeroAddress() public {
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();

        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);
        ERC20(NALPHA).approve(address(NEST_VAULT), shares);

        vm.expectRevert(Errors.ZERO_ADDRESS.selector);
        NEST_VAULT.requestRedeem(shares, address(0), ETHEREUM_USDC_WHALE);
        vm.stopPrank();
    }

    /// @dev operator can request redeem for owner with a different controller when authorized by owner
    function testRequestRedeem_OperatorCanSetDifferentController() public {
        address controller = makeAddr("controller");
        address operator = makeAddr("operator");

        uint256 depositAmount = 1_000 * 10 ** ERC20(USDC).decimals();
        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);
        ERC20(NALPHA).approve(address(NEST_VAULT), shares);
        NEST_VAULT.setOperator(operator, true);
        vm.stopPrank();

        uint256 ownerSharesBefore = ERC20(address(NALPHA)).balanceOf(ETHEREUM_USDC_WHALE);
        uint256 vaultSharesBefore = ERC20(address(NALPHA)).balanceOf(address(NEST_VAULT));

        vm.prank(operator);
        NEST_VAULT.requestRedeem(shares, controller, ETHEREUM_USDC_WHALE);

        assertEq(NEST_VAULT.pendingRedeemRequest(0, controller), shares, "pending created for controller");
        assertEq(NEST_VAULT.pendingRedeemRequest(0, ETHEREUM_USDC_WHALE), 0, "owner has no pending");
        assertEq(
            ERC20(address(NALPHA)).balanceOf(ETHEREUM_USDC_WHALE),
            ownerSharesBefore - shares,
            "owner shares transferred"
        );
        assertEq(
            ERC20(address(NALPHA)).balanceOf(address(NEST_VAULT)),
            vaultSharesBefore + shares,
            "vault holds pending shares"
        );
    }

    /// @dev Test for requesting a redeem with insufficient balance.
    ///      This ensures that a redeem cannot be requested when the caller does not have enough shares.
    function testRevertRequestRedeemInsufficientBalance() public {
        address controller = makeAddr("controller");
        address owner = controller;
        uint256 shares = 100; // Arbitrary share amount

        // Ensure the owner has no balance
        vm.startPrank(owner);
        vm.expectRevert(Errors.INSUFFICIENT_BALANCE.selector);

        // Attempt to call requestRedeem when the owner has insufficient balance
        NEST_VAULT.requestRedeem(shares, controller, owner);

        vm.stopPrank();
    }

    /// @dev Test for requesting a redeem with zero shares.
    ///      This ensures that requesting redeem with zero shares reverts as expected.
    function testRevertRequestRedeemZeroShares() public {
        address controller = makeAddr("controller");
        address owner = controller;
        uint256 shares = 0; // Zero shares

        vm.startPrank(owner);
        vm.expectRevert(Errors.ZERO_SHARES.selector);

        // Attempt to call requestRedeem with zero shares
        NEST_VAULT.requestRedeem(shares, controller, owner);

        vm.stopPrank();
    }

    /// @dev Test for unauthorized withdrawal requests, ensuring that only authorized users can withdraw.
    function testRevertWithdrawUnauthorized() public {
        uint256 depositAmount = 20_000 * 10 ** ERC20(USDC).decimals();
        vm.startPrank(ETHEREUM_USDC_WHALE);

        // Deposit some funds
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);

        // Approve redeem
        ERC20(NALPHA).approve(address(NEST_VAULT), shares);

        // Request redeem for these shares
        NEST_VAULT.requestRedeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        // Set up a different address that is neither the controller nor an operator
        address unauthorizedUser = address(0x123);
        vm.startPrank(unauthorizedUser);

        // Expect revert with "Errors.UNAUTHORIZED()" because the unauthorizedUser is neither the controller nor an operator
        vm.expectRevert(Errors.UNAUTHORIZED.selector);
        NEST_VAULT.withdraw(depositAmount, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        vm.stopPrank();
    }

    /// @notice Tests that the vault reverts when attempting to withdraw with zero assets.
    /// @dev This function ensures that the `withdraw` function in the vault reverts with the `Errors.ZERO_ASSETS` error if assets = 0.
    function testRevertWithdrawZeroAssets() public {
        uint256 depositAmount = 20_000 * 10 ** ERC20(USDC).decimals();
        vm.startPrank(ETHEREUM_USDC_WHALE);

        // Deposit some funds
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);

        // Approve redeem
        ERC20(NALPHA).approve(address(NEST_VAULT), shares);

        // Request redeem for these shares
        NEST_VAULT.requestRedeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        // Expect revert with "Errors.ZERO_ASSETS()" because assets = 0
        vm.expectRevert(Errors.ZERO_ASSETS.selector);
        NEST_VAULT.withdraw(0, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        vm.stopPrank();
    }

    /// @notice Tests that the vault reverts when a user tries to redeem without proper authorization.
    /// @dev This test ensures that only authorized users (e.g., the controller or an operator) can call `redeem`.
    function testRevertRedeemUnauthorized() public {
        uint256 depositAmount = 20_000 * 10 ** ERC20(USDC).decimals();
        vm.startPrank(ETHEREUM_USDC_WHALE);

        // Deposit some funds
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);

        // Approve redeem
        ERC20(NALPHA).approve(address(NEST_VAULT), shares);

        // Request redeem for these shares
        NEST_VAULT.requestRedeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        // Set up a different address that is neither the controller nor an operator
        address unauthorizedUser = address(0x123);
        vm.startPrank(unauthorizedUser);

        // Expect revert with "Errors.UNAUTHORIZED()" because the unauthorizedUser is neither the controller nor an operator
        vm.expectRevert(Errors.UNAUTHORIZED.selector);
        NEST_VAULT.redeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        vm.stopPrank();
    }

    /// @notice Tests that the vault reverts when attempting to redeem zero shares.
    /// @dev This function checks that redeeming zero shares results in a revert with the `Errors.ZERO_SHARES` error.
    function testRevertRedeemZeroShares() public {
        uint256 depositAmount = 20_000 * 10 ** ERC20(USDC).decimals();
        vm.startPrank(ETHEREUM_USDC_WHALE);

        // Deposit some funds
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);

        // Approve redeem
        ERC20(NALPHA).approve(address(NEST_VAULT), shares);

        // Request redeem for these shares
        NEST_VAULT.requestRedeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        // Expect revert with "Errors.ZERO_SHARES()" because shares = 0
        vm.expectRevert(Errors.ZERO_SHARES.selector);
        NEST_VAULT.redeem(0, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        vm.stopPrank();
    }

    /// @dev Test should revert when unauthorized caller calls fulfillRedeem
    function testRevertFulfillRedeemUnauthorizedCaller() public {
        vm.prank(boringAuthority.owner());
        boringAuthority.setPublicCapability(address(NEST_VAULT), NEST_VAULT.fulfillRedeem.selector, false);

        vm.startPrank(address(1));
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);

        // Attempt to call fulfillRedeem with unauthorized caller
        NEST_VAULT.fulfillRedeem(address(0), 0);
        vm.stopPrank();
    }

    // /// @notice Tests that the vault reverts when attempting to redeem with zero payout.
    // /// @dev This test simulates a scenario where there are no assets available for redemption and expects the `ERC7540Vault/zero-payout` error.
    // function testRevertRedeemZeroPayoutCondition() public {
    //     uint256 depositAmount = 20_000 * 10 ** ERC20(USDC).decimals();
    //     vm.startPrank(ETHEREUM_USDC_WHALE);

    //     // Deposit some funds
    //     ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
    //     uint256 shares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);

    //     // Approve redeem
    //     ERC20(NALPHA).approve(address(NEST_VAULT), shares);

    //     // Request redeem for these shares
    //     NEST_VAULT.requestRedeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

    //     // Fulfill the redeem request (this should update the claimable redeems with assets and shares)
    //     NEST_VAULT.fulfillRedeem(ETHEREUM_USDC_WHALE, shares);

    //     // Now, simulate the state where there are no assets available for this controller by performing a withdrawal
    //     uint256 initialClaimableShares = NEST_VAULT.claimableRedeemRequest(0, ETHEREUM_USDC_WHALE);
    //     uint256 assetsBeforeWithdraw = NEST_VAULT.maxWithdraw(ETHEREUM_USDC_WHALE);

    //     // To simulate the "no assets" scenario, we manually perform a withdraw so that it empties the claimable assets.
    //     NEST_VAULT.withdraw(assetsBeforeWithdraw, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

    //     // After the withdrawal, claimable assets should be zero, but claimable shares still exist.
    //     uint256 claimableSharesAfterWithdraw = NEST_VAULT.claimableRedeemRequest(0, ETHEREUM_USDC_WHALE);
    //     assertEq(
    //         claimableSharesAfterWithdraw,
    //         initialClaimableShares,
    //         "Claimable shares should remain the same after withdrawal"
    //     );

    //     // Try to redeem and expect it to revert with ERC7540_ZERO_PAYOUT because assets are now zero but shares exist
    //     vm.expectRevert(Errors.ERC7540_ZERO_PAYOUT.selector);
    //     NEST_VAULT.redeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

    //     vm.stopPrank();
    // }

    /// @notice Tests that the vault allows the owner to set an operator successfully.
    /// @dev This test ensures that the `setOperator` function correctly updates the operator mapping and emits the `OperatorSet` event.
    function testSetOperatorSuccess() public {
        address owner = makeAddr("owner");
        address operator = makeAddr("operator");
        vm.startPrank(owner); // simulate actions as owner
        // Expect the OperatorSet event
        vm.expectEmit(true, true, true, true);
        emit OperatorSet(owner, operator, true);

        // Call the setOperator function
        bool success = NEST_VAULT.setOperator(operator, true);

        // Check that the function executed successfully
        assertEq(success, true);

        // Verify the operator mapping is correctly set
        bool isOperatorSet = NEST_VAULT.isOperator(owner, operator);
        assertEq(isOperatorSet, true);
    }

    /// @dev reverts when tries to set zero as operator address
    function testRevertSetOperatorZeroAddress() public {
        address operator = address(0);
        // Expect the revert error message
        vm.expectRevert(Errors.ZERO_ADDRESS.selector);
        NEST_VAULT.setOperator(operator, true); // Owner cannot set themselves as operator
    }

    /// @dev reverts when tries to set self as operator
    function testRevertSetSelfAsOperator() public {
        address owner = makeAddr("owner");
        vm.startPrank(owner);
        // Expect the revert error message
        vm.expectRevert(Errors.ERC7540_SELF_OPERATOR_NOT_ALLOWED.selector);
        NEST_VAULT.setOperator(owner, true); // Owner cannot set themselves as operator
    }

    /// @notice Tests that the vault reverts when an owner attempts to set themselves as an operator.
    /// @dev This function ensures that the `setOperator` function throws the `Errors.ERC7540_SELF_OPERATOR_NOT_ALLOWED` error if the owner tries to set themselves as an operator.
    function testAuthorizeOperatorSuccess() public {
        // Declare local variables inside the test function
        (address controller, uint256 controllerKey) = makeAddrAndKey("controller");
        address operator = makeAddr("operator");
        bytes32 nonce = keccak256(abi.encodePacked("0x01"));
        uint256 validDeadline = block.timestamp + 1 days;

        bytes memory signature =
            createValidSignature(NEST_VAULT, nonce, validDeadline, operator, controller, controllerKey, true);

        vm.startPrank(controller);

        // Expect the event to be emitted
        vm.expectEmit(true, true, true, true);
        emit OperatorSet(controller, operator, true);

        // Call the authorizeOperator function
        bool success = NEST_VAULT.authorizeOperator(
            controller,
            operator,
            true,
            nonce, // Pass the nonce as bytes32
            validDeadline,
            signature
        );

        // Assertions
        assertEq(success, true);
        assertEq(NEST_VAULT.isOperator(controller, operator), true);
    }

    /// @dev reverts when trying to set controller as zero address
    function testRevertAuthorizeOperatorControllerZeroAddress() public {
        bytes32 nonce = keccak256(abi.encodePacked("0x01"));
        vm.expectRevert(Errors.ZERO_ADDRESS.selector);
        NEST_VAULT.authorizeOperator(address(0), address(0), false, nonce, 0, "0x");
    }

    /// @dev reverts when trying to set operator as zero address
    function testRevertAuthorizeOperatorOperatorZeroAddress() public {
        bytes32 nonce = keccak256(abi.encodePacked("0x01"));
        vm.expectRevert(Errors.ZERO_ADDRESS.selector);
        NEST_VAULT.authorizeOperator(address(1), address(0), false, nonce, 0, "0x");
    }

    /// @notice Tests that the vault reverts when attempting to authorize an operator as the controller itself.
    /// @dev This function ensures that the controller cannot authorize themselves as an operator. The test expects the `Errors.ERC7540_SELF_OPERATOR_NOT_ALLOWED` revert error.
    function testRevertCannotAuthorizeSelfAsOperator() public {
        (address controller, uint256 controllerKey) = makeAddrAndKey("controller");
        address operator = controller; // Set operator to be the same as the controller
        bytes32 nonce = keccak256(abi.encodePacked("0x01"));
        uint256 validDeadline = block.timestamp + 1 days;

        // Create the signature for the valid controller address
        bytes memory signature =
            createValidSignature(NEST_VAULT, nonce, validDeadline, operator, controller, controllerKey, true);

        vm.startPrank(controller);

        // Expect the revert with the correct error message
        vm.expectRevert(Errors.ERC7540_SELF_OPERATOR_NOT_ALLOWED.selector);

        // Call the authorizeOperator function with controller as operator
        NEST_VAULT.authorizeOperator(controller, operator, true, nonce, validDeadline, signature);
    }

    /// @notice Tests that the vault reverts when an invalid signer is used for authorizing an operator.
    /// @dev This function checks that the `authorizeOperator` function fails when the signer address is not the controller's address. The test expects the `Errors.INVALID_SIGNER` revert error.
    function testRevertInvalidSigner() public {
        address controller = makeAddr("controller");
        address operator = makeAddr("operator"); // Use a valid operator address
        bytes32 nonce = keccak256(abi.encodePacked("0x01"));
        uint256 validDeadline = block.timestamp + 1 days;
        (address invalidSigner, uint256 invalidSignerKey) = makeAddrAndKey("invalidSigner");

        // Create a valid signature for the controller address
        bytes memory signature =
            createValidSignature(NEST_VAULT, nonce, validDeadline, operator, controller, invalidSignerKey, true);

        // Use a different address (not the controller) to sign the message, which should result in an invalid signer

        vm.startPrank(invalidSigner);

        // Expect revert with the "INVALID_SIGNER" message
        vm.expectRevert(Errors.INVALID_SIGNER.selector);

        // Call the authorizeOperator function with the invalid signer
        NEST_VAULT.authorizeOperator(controller, operator, true, nonce, validDeadline, signature);
    }

    /// @notice Tests that the vault reverts when the same authorization is used twice.
    /// @dev This function ensures that the authorization nonce cannot be reused. The test expects the `Errors.ERC7540_USED_AUTHORIZATION` revert error on a second authorization with the same nonce.
    function testRevertAuthorizationUsed() public {
        (address controller, uint256 controllerKey) = makeAddrAndKey("controller");
        address operator = makeAddr("operator");
        bytes32 nonce = keccak256(abi.encodePacked("0x01"));
        uint256 validDeadline = block.timestamp + 1 days;

        // Create a valid signature for the controller
        bytes memory signature =
            createValidSignature(NEST_VAULT, nonce, validDeadline, operator, controller, controllerKey, true);

        vm.startPrank(controller);

        // First call: authorization should be successful
        bool success = NEST_VAULT.authorizeOperator(controller, operator, true, nonce, validDeadline, signature);

        // Assertions for the first call
        assertEq(success, true);
        assertEq(NEST_VAULT.isOperator(controller, operator), true);

        // Second call with the same nonce should revert
        vm.expectRevert(Errors.ERC7540_USED_AUTHORIZATION.selector);

        NEST_VAULT.authorizeOperator(controller, operator, true, nonce, validDeadline, signature);
    }

    /// @notice Tests that the vault reverts when the authorization has expired.
    /// @dev This function ensures that any authorization with an expired deadline will fail. The test expects the `Errors.ERC7540_EXPIRED` revert error.
    function testRevertExpiredDeadline() public {
        (address controller, uint256 controllerKey) = makeAddrAndKey("controller");
        address operator = makeAddr("operator");
        bytes32 nonce = keccak256(abi.encodePacked("0x01"));

        // Set an expired deadline
        uint256 expiredDeadline = block.timestamp - 1 hours;

        // Create the signature for the expired deadline
        bytes memory signature =
            createValidSignature(NEST_VAULT, nonce, expiredDeadline, operator, controller, controllerKey, true);

        vm.startPrank(controller);

        // Expect the revert with the correct error message
        vm.expectRevert(Errors.ERC7540_EXPIRED.selector);

        // Call the authorizeOperator function with the expired deadline
        NEST_VAULT.authorizeOperator(controller, operator, true, nonce, expiredDeadline, signature);
    }

    /// @notice Tests that the controller can authorize an operator with a false approval.
    /// @dev This function ensures that the `authorizeOperator` function works with a false approval and updates the operator status accordingly. The test expects the `OperatorSet` event to be emitted with false approval.
    function testAuthorizeOperatorFalseApproval() public {
        // Declare local variables inside the test function
        (address controller, uint256 controllerKey) = makeAddrAndKey("controller");
        address operator = makeAddr("operator");
        bytes32 nonce = keccak256(abi.encodePacked("0x01"));
        uint256 validDeadline = block.timestamp + 1 days;

        bytes memory signature =
            createValidSignature(NEST_VAULT, nonce, validDeadline, operator, controller, controllerKey, false);

        vm.startPrank(controller);

        // Expect the event to be emitted
        vm.expectEmit(true, true, true, true);
        emit OperatorSet(controller, operator, false);

        // Call the authorizeOperator function
        bool success = NEST_VAULT.authorizeOperator(
            controller,
            operator,
            false,
            nonce, // Pass the nonce as bytes32
            validDeadline,
            signature
        );

        // Assertions
        assertEq(success, true);
        assertEq(NEST_VAULT.isOperator(controller, operator), false);
    }

    /// @notice Tests that the vault reverts when calling previewWithdraw during an asynchronous flow.
    /// @dev This function ensures that the `previewWithdraw` function reverts with the `Errors.ERC7540_ASYNC_FLOW` error when called in an asynchronous state.
    function testRevertPreviewWithdraw() public {
        vm.expectRevert(Errors.ERC7540_ASYNC_FLOW.selector);
        NEST_VAULT.previewWithdraw(0);
    }

    /// @notice Tests that the vault reverts when calling previewRedeem during an asynchronous flow.
    /// @dev This function ensures that the `previewRedeem` function reverts with the `Errors.ERC7540_ASYNC_FLOW` error when called in an asynchronous state.
    function testRevertPreviewRedeem() public {
        vm.expectRevert(Errors.ERC7540_ASYNC_FLOW.selector);
        NEST_VAULT.previewRedeem(0);
    }
}
