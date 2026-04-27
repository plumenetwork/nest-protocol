// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

// utils
import {Test} from "forge-std/Test.sol";

// interfaces
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC7540Redeem, IERC7540Operator} from "forge-std/interfaces/IERC7540.sol";
import {ISignatureTransfer} from "@uniswap/permit2/interfaces/ISignatureTransfer.sol";

// contracts
import {NestVault} from "contracts/NestVault.sol";
import {AuthUpgradeable} from "contracts/upgradeable/auth/AuthUpgradeable.sol";
import {BoringVault} from "@boring-vault/src/base/BoringVault.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Helper} from "test/Helper.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MockRateProvider} from "test/mock/MockRateProvider.sol";
import {MockLegacyAccountant} from "test/mock/MockLegacyAccountant.sol";
import {MockEmptyFallback, MockShortReturnData} from "test/mock/MockEmptyFallback.sol";

// libraries
import {Events} from "test/Events.sol";
import {Errors} from "contracts/types/Errors.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {NestVaultCoreTypes} from "contracts/libraries/nest-vault/NestVaultCoreTypes.sol";

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
        vm.expectRevert(Errors.ZeroAddress.selector);
        new NestVault(_bVault, PERMIT2);
    }

    /// @dev Reverts when accountant is passed as zero address
    function testRevertInitializeAccountantWithRateProvidersZeroAddress() public {
        address _accountant = address(0);
        address _asset = USDC;
        address _owner = address(this);
        uint256 _minRate = 1e3;
        vm.expectRevert(Errors.ZeroAddress.selector);
        new TransparentUpgradeableProxy(
            address(_logic),
            address(this),
            abi.encodeCall(NEST_VAULT.initialize, (_accountant, _asset, _owner, _minRate, address(0)))
        );
    }

    /// @dev Reverts when asset is passed as zero address
    function testRevertInitializeAssetZeroAddress() public {
        address _accountant = NALPHA_ACCOUNTANT;
        address _asset = address(0);
        address _owner = address(this);
        uint256 _minRate = 1e3;
        vm.expectRevert(Errors.ZeroAddress.selector);
        new TransparentUpgradeableProxy(
            address(_logic),
            address(this),
            abi.encodeCall(NEST_VAULT.initialize, (_accountant, _asset, _owner, _minRate, address(0)))
        );
    }

    /// @dev Reverts when owner is passed as zero address
    function testRevertInitializeOwnerZeroAddress() public {
        address _accountant = NALPHA_ACCOUNTANT;
        address _asset = USDC;
        address _owner = address(0);
        uint256 _minRate = 1e3;
        vm.expectRevert(Errors.ZeroAddress.selector);
        new TransparentUpgradeableProxy(
            address(_logic),
            address(this),
            abi.encodeCall(NEST_VAULT.initialize, (_accountant, _asset, _owner, _minRate, address(0)))
        );
    }

    /// @dev Reverts when. min rate is equal to 10 ** asset decimals
    function testRevertInitializeMinRateEqualtoInvalid() public {
        address _accountant = NALPHA_ACCOUNTANT;
        address _asset = USDC;
        address _owner = address(1);
        uint256 _minRate = 1e6;
        vm.expectRevert(Errors.InvalidRate.selector);
        new TransparentUpgradeableProxy(
            address(_logic),
            address(this),
            abi.encodeCall(NEST_VAULT.initialize, (_accountant, _asset, _owner, _minRate, address(0)))
        );
    }

    /// @dev Reverts when. min rate is greater than 10 ** asset decimals
    function testRevertInitializeMinRateGreaterInvalid() public {
        address _accountant = NALPHA_ACCOUNTANT;
        address _asset = USDC;
        address _owner = address(1);
        uint256 _minRate = 1e7;
        vm.expectRevert(Errors.InvalidRate.selector);
        new TransparentUpgradeableProxy(
            address(_logic),
            address(this),
            abi.encodeCall(NEST_VAULT.initialize, (_accountant, _asset, _owner, _minRate, address(0)))
        );
    }

    /// @dev Test for verifying that the correct authority is set for the NestVault contract.
    function testSetAuthorityAsOwner() public view {
        assertEq(address(NEST_VAULT.authority()), address(boringAuthority));
    }

    /// @dev Test for checking the version of the NestVault contract.
    function testVersion() public view {
        assertEq(NEST_VAULT.version(), "0.0.2");
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
    ///      totalAssets = (totalSupply - accountant.totalPendingShares) * rate / ONE_SHARE
    function testTotalAssets() public view {
        uint256 totalPendingShares = NEST_ACCOUNTANT.totalPendingShares();
        uint256 expectedTotalAssets = (BoringVault(NALPHA).totalSupply() - totalPendingShares)
        .mulDivDown(NEST_VAULT.accountant().getRateInQuoteSafe(ERC20(USDC)), 10 ** ERC20(NALPHA).decimals());
        assertEq(NEST_VAULT.totalAssets(), expectedTotalAssets);
    }

    /// @dev Test for setting accountant with rate provider should succeed
    function testsetAccountant() public {
        MockRateProvider _rateProviderMock = new MockRateProvider();
        address oldAccountant = address(NEST_VAULT.accountant());
        vm.expectEmit(true, true, false, true);
        emit SetAccountant(oldAccountant, address(_rateProviderMock));
        NEST_VAULT.setAccountant(address(_rateProviderMock));
        assertEq(address(_rateProviderMock), address(NEST_VAULT.accountant()));
    }

    /// @dev Test for setting accountant with rate provider called with unauthorized
    ///      caller should revert
    function testRevertsetAccountantUnauthorized() public {
        MockRateProvider _rateProviderMock = new MockRateProvider();
        vm.startPrank(makeAddr("alice"));
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        NEST_VAULT.setAccountant(address(_rateProviderMock));
        vm.stopPrank();
    }

    /// @dev Test for setting a legacy AccountantWithRateProviders-style accountant should succeed
    function testsetAccountantLegacy() public {
        MockLegacyAccountant legacyAccountant = new MockLegacyAccountant();
        legacyAccountant.setRate(1e6); // Set a valid rate
        NEST_VAULT.setAccountant(address(legacyAccountant));
        assertEq(address(legacyAccountant), address(NEST_VAULT.accountant()));
    }

    /// @dev Test for setting a paused accountant should succeed if it's otherwise compatible
    function testsetAccountantPaused() public {
        NEST_ACCOUNTANT.pause();
        NEST_VAULT.setAccountant(address(NEST_ACCOUNTANT));
        assertEq(address(NEST_ACCOUNTANT), address(NEST_VAULT.accountant()));
    }

    /// @dev Test for setting an EOA (externally owned account) as accountant should revert
    ///      EOAs have no code, so staticcall succeeds with empty data - we must reject this
    function testRevertsetAccountantEOA() public {
        address eoa = makeAddr("eoa_accountant");
        vm.expectRevert(Errors.IncompatibleAccountant.selector);
        NEST_VAULT.setAccountant(eoa);
    }

    /// @dev Test for setting a contract with fallback that returns empty data should revert
    ///      Such contracts would pass a basic staticcall success check but return no meaningful data
    function testRevertsetAccountantEmptyFallback() public {
        MockEmptyFallback emptyFallback = new MockEmptyFallback();
        vm.expectRevert(Errors.IncompatibleAccountant.selector);
        NEST_VAULT.setAccountant(address(emptyFallback));
    }

    /// @dev Test for setting a contract that returns less than 32 bytes should revert
    ///      A valid uint256 return requires at least 32 bytes
    function testRevertsetAccountantShortReturnData() public {
        MockShortReturnData shortReturn = new MockShortReturnData();
        vm.expectRevert(Errors.IncompatibleAccountant.selector);
        NEST_VAULT.setAccountant(address(shortReturn));
    }

    /// @dev Test for verifying the deposit functionality of the NestVault contract.
    ///      Deposits a certain amount of USDC and checks if the shares are correctly issued.
    function testDeposit() public {
        uint256 depositAmount = 20_000 * 10 ** ERC20(USDC).decimals();
        uint256 expectedShares = Math.mulDiv(
            depositAmount,
            10 ** ERC20(NALPHA).decimals(),
            NEST_VAULT.accountant().getRateInQuoteSafe(ERC20(USDC)),
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

    /// @dev Reverts when deposit assets would mint zero shares (high rate edge case)
    function testDepositRevertZeroShares() public {
        // Configure rate provider to an extreme (but capped) rate so previewDeposit returns zero shares
        MockRateProvider highRateProvider = new MockRateProvider();
        highRateProvider.setRate(1e30);
        NEST_VAULT.setAccountant(address(highRateProvider));

        uint256 depositAmount = 1; // smallest non-zero USDC unit

        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        vm.expectRevert(Errors.ZeroShares.selector);
        NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);
        vm.stopPrank();
    }

    /// @dev Test for verifying the deposit functionality when an unauthorized call is made.
    //       Ensures that the deposit fails if the public capability is turned off.
    function testRevertDepositUnauthorized() public {
        vm.prank(boringAuthority.owner());
        boringAuthority.setPublicCapability(address(NEST_VAULT), NEST_VAULT.deposit.selector, false);
        uint256 depositAmount = 20_000 * 10 ** ERC20(USDC).decimals();
        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        vm.expectRevert(Errors.Unauthorized.selector);
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
            NEST_VAULT.accountant().getRateInQuoteSafe(ERC20(USDC)),
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
        NEST_VAULT.setFee(NestVaultCoreTypes.Fees.InstantRedemption, _instantRedemptionFee);
        assertEq(_instantRedemptionFee, 1e4);

        // Expected pre-fee asset value of the shares
        uint256 expectedAssets = NEST_VAULT.convertToAssets(mintedShares);

        // Expected fee = assets * fee / 1e6
        uint256 expectedFee = (expectedAssets * _instantRedemptionFee) / 1_000_000;
        uint256 expectedPostFee = expectedAssets - expectedFee;

        // Capture balances before redeem
        uint256 receiverUSDCbefore = ERC20(USDC).balanceOf(ETHEREUM_USDC_WHALE);
        uint256 vaultUSDCbefore = ERC20(USDC).balanceOf(NALPHA);
        uint256 feeVaultUSDCbefore = ERC20(USDC).balanceOf(address(NEST_VAULT));
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
        assertEq(ERC20(USDC).balanceOf(NALPHA), vaultUSDCbefore - expectedAssets);
        assertEq(ERC20(USDC).balanceOf(address(NEST_VAULT)), feeVaultUSDCbefore + expectedFee);
        assertEq(ERC20(address(NALPHA)).balanceOf(ETHEREUM_USDC_WHALE), userSharesBefore - mintedShares);
        assertEq(NEST_VAULT.claimableFees(NestVaultCoreTypes.Fees.InstantRedemption), expectedFee);
    }

    /// @dev should claim accrued instant redemption fees
    function testClaimFee() public {
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();

        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 mintedShares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);
        ERC20(address(NALPHA)).approve(address(NEST_VAULT), type(uint256).max);
        vm.stopPrank();

        uint32 instantRedemptionFee = 1e4; // 1%
        NEST_VAULT.setFee(NestVaultCoreTypes.Fees.InstantRedemption, instantRedemptionFee);

        uint256 expectedAssets = NEST_VAULT.convertToAssets(mintedShares);
        uint256 expectedFee = (expectedAssets * instantRedemptionFee) / 1_000_000;

        vm.prank(ETHEREUM_USDC_WHALE);
        NEST_VAULT.instantRedeem(mintedShares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        address receiver = address(0xFEE);
        uint256 receiverUSDCbefore = ERC20(USDC).balanceOf(receiver);
        uint256 feeVaultUSDCbefore = ERC20(USDC).balanceOf(address(NEST_VAULT));
        assertEq(NEST_VAULT.claimableFees(NestVaultCoreTypes.Fees.InstantRedemption), expectedFee);

        vm.expectEmit(true, true, false, true);
        emit FeeClaimed(NestVaultCoreTypes.Fees.InstantRedemption, receiver, expectedFee);
        uint256 claimedFeeAmount = NEST_VAULT.claimFee(NestVaultCoreTypes.Fees.InstantRedemption, receiver);

        assertEq(claimedFeeAmount, expectedFee);
        assertEq(NEST_VAULT.claimableFees(NestVaultCoreTypes.Fees.InstantRedemption), 0);
        assertEq(ERC20(USDC).balanceOf(receiver), receiverUSDCbefore + expectedFee);
        assertEq(ERC20(USDC).balanceOf(address(NEST_VAULT)), feeVaultUSDCbefore - expectedFee);
    }

    /// @dev revert claimFee when called by unauthorized caller
    function testRevertClaimFeeUnauthorizedCaller() public {
        vm.prank(address(1));
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        NEST_VAULT.claimFee(NestVaultCoreTypes.Fees.InstantRedemption, address(1));
    }

    /// @dev revert claimFee when no fees are owed
    function testRevertClaimFeeZeroFeesOwed() public {
        vm.expectRevert(Errors.ZeroFeesOwed.selector);
        NEST_VAULT.claimFee(NestVaultCoreTypes.Fees.InstantRedemption, address(this));
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
        vm.expectRevert(Errors.Unauthorized.selector);
        NEST_VAULT.instantRedeem(
            mintedShares,
            attacker, // receiver
            ETHEREUM_USDC_WHALE // owner
        );
    }

    /// @dev reverts when trying to redeem zero shares
    function testInstantRedeem_ZeroShares() public {
        vm.prank(ETHEREUM_USDC_WHALE);
        vm.expectRevert(Errors.ZeroShares.selector);
        NEST_VAULT.instantRedeem(0, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);
    }

    /// @dev reverts when instant redeem receiver is zero address
    function testInstantRedeem_ZeroReceiver() public {
        uint256 depositAmount = 1_000 * 10 ** ERC20(USDC).decimals();

        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 mintedShares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);
        ERC20(address(NALPHA)).approve(address(NEST_VAULT), mintedShares);

        vm.expectRevert(Errors.ZeroAddress.selector);
        NEST_VAULT.instantRedeem(mintedShares, address(0), ETHEREUM_USDC_WHALE);
        vm.stopPrank();
    }

    /// @dev reverts with transfer fail when owner share balance is insufficient
    function testInstantRedeem_InsufficientShareBalance() public {
        uint256 depositAmount = 1_000 * 10 ** ERC20(USDC).decimals();

        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 mintedShares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);
        ERC20(address(NALPHA)).approve(address(NEST_VAULT), type(uint256).max);

        vm.expectRevert("TRANSFER_FROM_FAILED");
        NEST_VAULT.instantRedeem(mintedShares + 1, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);
        vm.stopPrank();
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
        vm.expectRevert(Errors.TransferInsufficient.selector);
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

    /// @dev returned shares from updateRedeem must go to receiver, not controller
    function testUpdateRedeem_ReturnsSharesToReceiver() public {
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();
        address receiver = makeAddr("receiver");

        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);

        uint256 shares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);
        ERC20(NALPHA).approve(address(NEST_VAULT), shares);
        NEST_VAULT.requestRedeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        uint256 newShares = shares / 2;
        uint256 returnAmount = shares - newShares;

        uint256 receiverBefore = ERC20(address(NEST_VAULT)).balanceOf(receiver);
        uint256 controllerBefore = ERC20(address(NEST_VAULT)).balanceOf(ETHEREUM_USDC_WHALE);

        vm.expectEmit(true, true, true, true);
        emit RedeemUpdated(ETHEREUM_USDC_WHALE, receiver, ETHEREUM_USDC_WHALE, shares, newShares);
        NEST_VAULT.updateRedeem(newShares, ETHEREUM_USDC_WHALE, receiver);

        uint256 receiverAfter = ERC20(address(NEST_VAULT)).balanceOf(receiver);
        uint256 controllerAfter = ERC20(address(NEST_VAULT)).balanceOf(ETHEREUM_USDC_WHALE);

        assertEq(receiverAfter - receiverBefore, returnAmount, "receiver must receive returned shares");
        assertEq(controllerAfter, controllerBefore, "controller must not receive returned shares");
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
        vm.expectRevert(Errors.Unauthorized.selector);
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
        vm.expectRevert(Errors.Unauthorized.selector);
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
        vm.expectRevert(Errors.Unauthorized.selector);
        NEST_VAULT.updateRedeem(0, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);
        vm.stopPrank();

        assertEq(NEST_VAULT.pendingRedeemRequest(shares, ETHEREUM_USDC_WHALE), shares, "pending intact");
        assertEq(ERC20(address(NALPHA)).balanceOf(attacker), 0, "attacker received nothing");
    }

    /// @dev revert when trying to update with no share holdings
    function testUpdateRedeem_NoPendingRedeem() public {
        vm.startPrank(ETHEREUM_USDC_WHALE);

        vm.expectRevert(Errors.NoPendingRedeem.selector);
        NEST_VAULT.updateRedeem(10, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        vm.stopPrank();
    }

    /// @dev revert when updateRedeem receiver is the zero address
    function testRevertUpdateRedeemReceiverZeroAddress() public {
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();

        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);
        ERC20(NALPHA).approve(address(NEST_VAULT), shares);
        NEST_VAULT.requestRedeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        vm.expectRevert(Errors.ZeroAddress.selector);
        NEST_VAULT.updateRedeem(shares / 2, ETHEREUM_USDC_WHALE, address(0));

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

        vm.expectRevert(Errors.InsufficientBalance.selector);
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

    /// @dev Test that requestRedeem updates both vault and accountant totalPendingShares
    function testRequestRedeem_UpdatesGlobalPendingShares() public {
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();

        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);
        ERC20(NALPHA).approve(address(NEST_VAULT), shares);

        uint256 vaultPendingBefore = NEST_VAULT.totalPendingShares();
        uint256 accountantPendingBefore = NEST_ACCOUNTANT.totalPendingShares();

        NEST_VAULT.requestRedeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        uint256 vaultPendingAfter = NEST_VAULT.totalPendingShares();
        uint256 accountantPendingAfter = NEST_ACCOUNTANT.totalPendingShares();

        assertEq(vaultPendingAfter, vaultPendingBefore + shares, "vault pending should increase");
        assertEq(accountantPendingAfter, accountantPendingBefore + shares, "accountant pending should increase");

        vm.stopPrank();
    }

    /// @dev Test that fulfillRedeem updates both vault and accountant totalPendingShares
    function testFulfillRedeem_UpdatesGlobalPendingShares() public {
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();

        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);
        ERC20(NALPHA).approve(address(NEST_VAULT), shares);
        NEST_VAULT.requestRedeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        uint256 vaultPendingBefore = NEST_VAULT.totalPendingShares();
        uint256 accountantPendingBefore = NEST_ACCOUNTANT.totalPendingShares();

        // Fulfill redeem
        NEST_VAULT.fulfillRedeem(ETHEREUM_USDC_WHALE, shares);

        uint256 vaultPendingAfter = NEST_VAULT.totalPendingShares();
        uint256 accountantPendingAfter = NEST_ACCOUNTANT.totalPendingShares();

        assertEq(vaultPendingAfter, vaultPendingBefore - shares, "vault pending should decrease");
        assertEq(accountantPendingAfter, accountantPendingBefore - shares, "accountant pending should decrease");

        vm.stopPrank();
    }

    /// @dev Test that updateRedeem updates both vault and accountant totalPendingShares
    function testUpdateRedeem_UpdatesGlobalPendingShares() public {
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();

        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);
        ERC20(NALPHA).approve(address(NEST_VAULT), shares);
        NEST_VAULT.requestRedeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        uint256 vaultPendingBefore = NEST_VAULT.totalPendingShares();
        uint256 accountantPendingBefore = NEST_ACCOUNTANT.totalPendingShares();

        uint256 newShares = shares / 2;
        uint256 returnAmount = shares - newShares;

        NEST_VAULT.updateRedeem(newShares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        uint256 vaultPendingAfter = NEST_VAULT.totalPendingShares();
        uint256 accountantPendingAfter = NEST_ACCOUNTANT.totalPendingShares();

        assertEq(
            vaultPendingAfter, vaultPendingBefore - returnAmount, "vault pending should decrease by returned amount"
        );
        assertEq(
            accountantPendingAfter,
            accountantPendingBefore - returnAmount,
            "accountant pending should decrease by returned amount"
        );

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
        vm.expectRevert(Errors.ZeroAddress.selector);
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
        vm.expectRevert(Errors.ZeroAddress.selector);
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
        vm.expectRevert(Errors.InsufficientBalance.selector);
        NEST_VAULT.fulfillRedeem(ETHEREUM_USDC_WHALE, invalidShares);

        // Now, simulate zero shares in the pending redeem (by fulfilling the redeem)
        NEST_VAULT.fulfillRedeem(ETHEREUM_USDC_WHALE, shares);

        // Check that no shares are pending anymore (should be zero)
        pendingShares = NEST_VAULT.pendingRedeemRequest(shares, ETHEREUM_USDC_WHALE);
        assertEq(pendingShares, 0, "Pending redeem request should be 0 after fulfilling redeem");

        // Try to fulfill redeem again with zero shares pending
        vm.expectRevert(Errors.NoPendingRedeem.selector);
        NEST_VAULT.fulfillRedeem(ETHEREUM_USDC_WHALE, shares);

        vm.stopPrank();
    }

    /// @dev Fulfill is auth-gated; rate source change should not block the controller from fulfilling their own redeem
    function testFulfillRedeem_HaircutViaRateSwitch_allowsAuthorizedCaller() public {
        uint256 depositAmount = 20_000 * 10 ** ERC20(USDC).decimals();

        // User deposits and queues async redeem (controller = user)
        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, ETHEREUM_USDC_WHALE);
        ERC20(NALPHA).approve(address(NEST_VAULT), shares);
        NEST_VAULT.requestRedeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);
        vm.stopPrank();

        // Admin changes rate source
        MockRateProvider lowRateProvider = new MockRateProvider();
        uint256 lowRate = NEST_VAULT.minRate();
        lowRateProvider.setRate(lowRate);
        // Initialize pending shares to match what was recorded in NEST_ACCOUNTANT
        lowRateProvider.increaseTotalPendingShares(NEST_ACCOUNTANT.totalPendingShares());

        vm.startPrank(boringAuthority.owner());
        boringAuthority.setPublicCapability(address(NEST_VAULT), NEST_VAULT.setAccountant.selector, true);
        NEST_VAULT.setAccountant(address(lowRateProvider));
        vm.stopPrank();

        // Controller fulfills their own redeem - should succeed even after rate change
        vm.prank(ETHEREUM_USDC_WHALE);
        uint256 assets = NEST_VAULT.fulfillRedeem(ETHEREUM_USDC_WHALE, shares);

        // Pending moved to claimable
        uint256 pendingShares = NEST_VAULT.pendingRedeemRequest(0, ETHEREUM_USDC_WHALE);
        assertEq(pendingShares, 0, "pending should be cleared");
        uint256 claimable = NEST_VAULT.claimableRedeemRequest(0, ETHEREUM_USDC_WHALE);
        assertEq(claimable, shares, "claimable should equal fulfilled shares");
        assertGt(assets, 0, "assets should be non-zero");
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
        uint256 depositAmount = 1_000 * 10 ** ERC20(USDC).decimals();

        // Setup owner with shares and approval so transfer succeeds first.
        deal(USDC, owner, depositAmount);
        vm.startPrank(owner);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, owner);
        ERC20(NALPHA).approve(address(NEST_VAULT), shares);
        vm.stopPrank();

        // Make sure the operator is not authorized
        vm.startPrank(operator);
        vm.expectRevert(Errors.Unauthorized.selector);

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

        vm.expectRevert(Errors.ZeroAddress.selector);
        NEST_VAULT.requestRedeem(shares, address(0), ETHEREUM_USDC_WHALE);
        vm.stopPrank();
    }

    /// @dev operator can request redeem for owner with a different controller when authorized by both owner and controller
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

        // Controller must also authorize the operator
        vm.prank(controller);
        NEST_VAULT.setOperator(operator, true);

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

    /// @dev Test for requesting a redeem with zero shares.
    ///      This ensures that requesting redeem with zero shares reverts as expected.
    function testRevertRequestRedeemZeroShares() public {
        address controller = makeAddr("controller");
        address owner = controller;
        uint256 shares = 0; // Zero shares

        vm.startPrank(owner);
        vm.expectRevert(Errors.ZeroShares.selector);

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

        // Expect revert with "Errors.Unauthorized()" because the unauthorizedUser is neither the controller nor an operator
        vm.expectRevert(Errors.Unauthorized.selector);
        NEST_VAULT.withdraw(depositAmount, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        vm.stopPrank();
    }

    /// @notice Tests that the vault reverts when attempting to withdraw with zero assets.
    /// @dev This function ensures that the `withdraw` function in the vault reverts with the `Errors.ZeroAssets` error if assets = 0.
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

        // Expect revert with "Errors.ZeroAssets()" because assets = 0
        vm.expectRevert(Errors.ZeroAssets.selector);
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

        // Expect revert with "Errors.Unauthorized()" because the unauthorizedUser is neither the controller nor an operator
        vm.expectRevert(Errors.Unauthorized.selector);
        NEST_VAULT.redeem(shares, ETHEREUM_USDC_WHALE, ETHEREUM_USDC_WHALE);

        vm.stopPrank();
    }

    /// @notice Tests that the vault reverts when attempting to redeem zero shares.
    /// @dev This function checks that redeeming zero shares results in a revert with the `Errors.ZeroShares` error.
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

        // Expect revert with "Errors.ZeroShares()" because shares = 0
        vm.expectRevert(Errors.ZeroShares.selector);
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
    //     vm.expectRevert(Errors.ERC7540ZeroPayout.selector);
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
        vm.expectRevert(Errors.ZeroAddress.selector);
        NEST_VAULT.setOperator(operator, true); // Owner cannot set themselves as operator
    }

    /// @dev reverts when tries to set self as operator
    function testRevertSetSelfAsOperator() public {
        address owner = makeAddr("owner");
        vm.startPrank(owner);
        // Expect the revert error message
        vm.expectRevert(Errors.ERC7540SelfOperatorNotAllowed.selector);
        NEST_VAULT.setOperator(owner, true); // Owner cannot set themselves as operator
    }

    /// @notice Tests that the vault reverts when an owner attempts to set themselves as an operator.
    /// @dev This function ensures that the `setOperator` function throws the `Errors.ERC7540SelfOperatorNotAllowed` error if the owner tries to set themselves as an operator.
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
        vm.expectRevert(Errors.ZeroAddress.selector);
        NEST_VAULT.authorizeOperator(address(0), address(0), false, nonce, 0, "0x");
    }

    /// @dev reverts when trying to set operator as zero address
    function testRevertAuthorizeOperatorOperatorZeroAddress() public {
        bytes32 nonce = keccak256(abi.encodePacked("0x01"));
        vm.expectRevert(Errors.ZeroAddress.selector);
        NEST_VAULT.authorizeOperator(address(1), address(0), false, nonce, 0, "0x");
    }

    /// @notice Tests that the vault reverts when attempting to authorize an operator as the controller itself.
    /// @dev This function ensures that the controller cannot authorize themselves as an operator. The test expects the `Errors.ERC7540SelfOperatorNotAllowed` revert error.
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
        vm.expectRevert(Errors.ERC7540SelfOperatorNotAllowed.selector);

        // Call the authorizeOperator function with controller as operator
        NEST_VAULT.authorizeOperator(controller, operator, true, nonce, validDeadline, signature);
    }

    /// @notice Tests that the vault reverts when an invalid signer is used for authorizing an operator.
    /// @dev This function checks that the `authorizeOperator` function fails when the signer address is not the controller's address. The test expects the `Errors.ERC7540InvalidSigner` revert error.
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
        vm.expectRevert(Errors.ERC7540InvalidSigner.selector);

        // Call the authorizeOperator function with the invalid signer
        NEST_VAULT.authorizeOperator(controller, operator, true, nonce, validDeadline, signature);
    }

    /// @notice Tests that the vault reverts when the same authorization is used twice.
    /// @dev This function ensures that the authorization nonce cannot be reused. The test expects the `Errors.ERC7540UsedAuthorization` revert error on a second authorization with the same nonce.
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
        vm.expectRevert(Errors.ERC7540UsedAuthorization.selector);

        NEST_VAULT.authorizeOperator(controller, operator, true, nonce, validDeadline, signature);
    }

    /// @notice Tests that the vault reverts when the authorization has expired.
    /// @dev This function ensures that any authorization with an expired deadline will fail. The test expects the `Errors.ERC7540Expired` revert error.
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
        vm.expectRevert(Errors.ERC7540Expired.selector);

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
    /// @dev This function ensures that the `previewWithdraw` function reverts with the `Errors.ERC7540AsyncFlow` error when called in an asynchronous state.
    function testRevertPreviewWithdraw() public {
        vm.expectRevert(Errors.ERC7540AsyncFlow.selector);
        NEST_VAULT.previewWithdraw(0);
    }

    /// @notice Tests that the vault reverts when calling previewRedeem during an asynchronous flow.
    /// @dev This function ensures that the `previewRedeem` function reverts with the `Errors.ERC7540AsyncFlow` error when called in an asynchronous state.
    function testRevertPreviewRedeem() public {
        vm.expectRevert(Errors.ERC7540AsyncFlow.selector);
        NEST_VAULT.previewRedeem(0);
    }

    // ========================================= PERMIT2 TESTS =========================================

    /// @dev instantRedeemWithPermit2 should work as expected
    function testInstantRedeemWithPermit2() external {
        // User deposits USDC to receive shares (setup phase)
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();

        // Deal USDC to permit2User and deposit to get shares
        deal(USDC, permit2User, depositAmount);
        vm.startPrank(permit2User);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 mintedShares = NEST_VAULT.deposit(depositAmount, permit2User);
        vm.stopPrank();

        // Approve SHARE to Permit2 for signature-based transfer
        vm.prank(permit2User);
        ERC20(address(NALPHA)).approve(PERMIT2, type(uint256).max);

        uint32 _instantRedemptionFee = 1e4; // 1%
        NEST_VAULT.setFee(NestVaultCoreTypes.Fees.InstantRedemption, _instantRedemptionFee);

        // Expected pre-fee asset value of the shares
        uint256 expectedAssets = NEST_VAULT.convertToAssets(mintedShares);
        uint256 expectedFee = (expectedAssets * _instantRedemptionFee) / 1_000_000;
        uint256 expectedPostFee = expectedAssets - expectedFee;

        // Capture balances before redeem
        uint256 receiverUSDCbefore = ERC20(USDC).balanceOf(permit2User);
        uint256 feeVaultUSDCbefore = ERC20(USDC).balanceOf(address(NEST_VAULT));
        uint256 userSharesBefore = ERC20(address(NALPHA)).balanceOf(permit2User);

        // Create permit for shares
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature =
            _signPermit(address(NALPHA), mintedShares, address(NEST_VAULT), nonce, deadline, permit2UserPrivateKey);

        // Expect InstantRedeem event
        vm.expectEmit(true, true, true, true);
        emit InstantRedeem(mintedShares, expectedAssets, expectedPostFee, permit2User);

        // Do instantRedeemWithPermit2
        vm.prank(permit2User);
        (uint256 postFee, uint256 feeAmount) =
            NEST_VAULT.instantRedeemWithPermit2(mintedShares, permit2User, permit2User, nonce, deadline, signature);

        // Assertions on return values
        assertEq(postFee, expectedPostFee);
        assertEq(feeAmount, expectedFee);

        // Assertions on balances
        assertEq(ERC20(USDC).balanceOf(permit2User), receiverUSDCbefore + expectedPostFee);
        assertEq(ERC20(USDC).balanceOf(address(NEST_VAULT)), feeVaultUSDCbefore + expectedFee);
        assertEq(ERC20(address(NALPHA)).balanceOf(permit2User), userSharesBefore - mintedShares);
        assertEq(NEST_VAULT.claimableFees(NestVaultCoreTypes.Fees.InstantRedemption), expectedFee);
    }

    /// @dev instantRedeemWithPermit2 should work with authorized operator
    function testInstantRedeemWithPermit2_OperatorAuthorized() external {
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();

        // Deal USDC to permit2User and deposit to get shares
        deal(USDC, permit2User, depositAmount);
        vm.startPrank(permit2User);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, permit2User);
        vm.stopPrank();

        // Approve SHARE to Permit2
        vm.prank(permit2User);
        ERC20(address(NALPHA)).approve(PERMIT2, type(uint256).max);

        // Set operator
        address operator = address(0xA11CE);
        vm.prank(permit2User);
        NEST_VAULT.setOperator(operator, true);

        uint256 receiverUSDCbefore = ERC20(USDC).balanceOf(permit2User);

        // Create permit (signed by owner)
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature =
            _signPermit(address(NALPHA), shares, address(NEST_VAULT), nonce, deadline, permit2UserPrivateKey);

        // Operator performs instant redeem with permit2 on behalf of owner
        vm.prank(operator);
        NEST_VAULT.instantRedeemWithPermit2(shares, permit2User, permit2User, nonce, deadline, signature);

        assertGt(ERC20(USDC).balanceOf(permit2User), receiverUSDCbefore);
    }

    /// @dev revert instantRedeemWithPermit2 when caller is not owner nor operator
    function testInstantRedeemWithPermit2_UnauthorizedCallerNotOperator() external {
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();

        // Owner deposits
        deal(USDC, permit2User, depositAmount);
        vm.startPrank(permit2User);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 mintedShares = NEST_VAULT.deposit(depositAmount, permit2User);
        ERC20(address(NALPHA)).approve(PERMIT2, type(uint256).max);
        vm.stopPrank();

        // Attacker (not owner, not operator)
        address attacker = address(0xBEEF);

        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature =
            _signPermit(address(NALPHA), mintedShares, address(NEST_VAULT), nonce, deadline, permit2UserPrivateKey);

        // Attacker attempts to redeem → should revert
        vm.prank(attacker);
        vm.expectRevert(Errors.Unauthorized.selector);
        NEST_VAULT.instantRedeemWithPermit2(mintedShares, attacker, permit2User, nonce, deadline, signature);
    }

    /// @dev revert instantRedeemWithPermit2 with zero shares
    function testInstantRedeemWithPermit2_ZeroShares() external {
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature =
            _signPermit(address(NALPHA), 0, address(NEST_VAULT), nonce, deadline, permit2UserPrivateKey);

        vm.prank(permit2User);
        vm.expectRevert(Errors.ZeroShares.selector);
        NEST_VAULT.instantRedeemWithPermit2(0, permit2User, permit2User, nonce, deadline, signature);
    }

    /// @dev revert instantRedeemWithPermit2 with invalid signature (wrong signer)
    function testInstantRedeemWithPermit2_InvalidSigner() external {
        uint256 depositAmount = 1_000 * 10 ** ERC20(USDC).decimals();

        deal(USDC, permit2User, depositAmount);
        vm.startPrank(permit2User);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 mintedShares = NEST_VAULT.deposit(depositAmount, permit2User);
        ERC20(address(NALPHA)).approve(PERMIT2, type(uint256).max);
        vm.stopPrank();

        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;
        // Sign with wrong private key
        uint256 wrongPrivateKey = 0x87654321;
        bytes memory signature =
            _signPermit(address(NALPHA), mintedShares, address(NEST_VAULT), nonce, deadline, wrongPrivateKey);

        vm.expectRevert(); // InvalidSigner
        vm.prank(permit2User);
        NEST_VAULT.instantRedeemWithPermit2(mintedShares, permit2User, permit2User, nonce, deadline, signature);
    }

    /// @dev requestRedeemWithPermit2 should work as expected
    function testRequestRedeemWithPermit2() external {
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();

        // Deal USDC to permit2User and deposit to get shares
        deal(USDC, permit2User, depositAmount);
        vm.startPrank(permit2User);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 mintedShares = NEST_VAULT.deposit(depositAmount, permit2User);
        vm.stopPrank();

        // Approve SHARE to Permit2
        vm.prank(permit2User);
        ERC20(address(NALPHA)).approve(PERMIT2, type(uint256).max);

        // Create permit for shares
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature =
            _signPermit(address(NALPHA), mintedShares, address(NEST_VAULT), nonce, deadline, permit2UserPrivateKey);

        // Expect RedeemRequest event
        vm.expectEmit(true, true, true, true);
        emit RedeemRequest(permit2User, permit2User, 0, permit2User, mintedShares);

        // Do requestRedeemWithPermit2
        vm.prank(permit2User);
        uint256 requestId =
            NEST_VAULT.requestRedeemWithPermit2(mintedShares, permit2User, permit2User, nonce, deadline, signature);

        // Assertions
        assertEq(requestId, 0);
        assertEq(NEST_VAULT.pendingRedeemRequest(0, permit2User), mintedShares);
    }

    /// @dev requestRedeemWithPermit2 should work with authorized operator
    function testRequestRedeemWithPermit2_OperatorAuthorized() external {
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();

        // Deal USDC to permit2User and deposit to get shares
        deal(USDC, permit2User, depositAmount);
        vm.startPrank(permit2User);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 shares = NEST_VAULT.deposit(depositAmount, permit2User);
        ERC20(address(NALPHA)).approve(PERMIT2, type(uint256).max);
        vm.stopPrank();

        // Set operator
        address operator = address(0xA11CE);
        vm.prank(permit2User);
        NEST_VAULT.setOperator(operator, true);

        // Create permit (signed by owner)
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature =
            _signPermit(address(NALPHA), shares, address(NEST_VAULT), nonce, deadline, permit2UserPrivateKey);

        // Operator performs request redeem with permit2 on behalf of owner
        vm.prank(operator);
        NEST_VAULT.requestRedeemWithPermit2(shares, permit2User, permit2User, nonce, deadline, signature);

        assertEq(NEST_VAULT.pendingRedeemRequest(0, permit2User), shares);
    }

    /// @dev requestRedeemWithPermit2 reverts if caller is neither owner nor operator
    function testRequestRedeemWithPermit2_UnauthorizedCallerNotOperator() external {
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();

        // Owner deposits
        deal(USDC, permit2User, depositAmount);
        vm.startPrank(permit2User);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 mintedShares = NEST_VAULT.deposit(depositAmount, permit2User);
        ERC20(address(NALPHA)).approve(PERMIT2, type(uint256).max);
        vm.stopPrank();

        // Attacker (not owner, not operator)
        address attacker = address(0xBEEF);

        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature =
            _signPermit(address(NALPHA), mintedShares, address(NEST_VAULT), nonce, deadline, permit2UserPrivateKey);

        // Attacker cannot request redeem without being owner or operator, even with a valid Permit2 signature
        vm.prank(attacker);
        vm.expectRevert(Errors.Unauthorized.selector);
        NEST_VAULT.requestRedeemWithPermit2(mintedShares, attacker, permit2User, nonce, deadline, signature);

        assertEq(NEST_VAULT.pendingRedeemRequest(0, attacker), 0);
    }

    /// @dev revert requestRedeemWithPermit2 with zero controller address
    function testRequestRedeemWithPermit2_ZeroController() external {
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();

        // Owner deposits
        deal(USDC, permit2User, depositAmount);
        vm.startPrank(permit2User);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 mintedShares = NEST_VAULT.deposit(depositAmount, permit2User);
        ERC20(address(NALPHA)).approve(PERMIT2, type(uint256).max);
        vm.stopPrank();

        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature =
            _signPermit(address(NALPHA), mintedShares, address(NEST_VAULT), nonce, deadline, permit2UserPrivateKey);

        // Owner attempts to request redeem with zero controller → should revert
        vm.prank(permit2User);
        vm.expectRevert(Errors.ZeroAddress.selector);
        NEST_VAULT.requestRedeemWithPermit2(mintedShares, address(0), permit2User, nonce, deadline, signature);
    }

    /// @dev revert requestRedeemWithPermit2 with zero shares
    function testRequestRedeemWithPermit2_ZeroShares() external {
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature =
            _signPermit(address(NALPHA), 0, address(NEST_VAULT), nonce, deadline, permit2UserPrivateKey);

        vm.prank(permit2User);
        vm.expectRevert(Errors.ZeroShares.selector);
        NEST_VAULT.requestRedeemWithPermit2(0, permit2User, permit2User, nonce, deadline, signature);
    }

    /// @dev revert requestRedeemWithPermit2 with nonce reuse
    function testRequestRedeemWithPermit2_NonceReused() external {
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();

        // Owner deposits
        deal(USDC, permit2User, depositAmount);
        vm.startPrank(permit2User);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 mintedShares = NEST_VAULT.deposit(depositAmount, permit2User);
        ERC20(address(NALPHA)).approve(PERMIT2, type(uint256).max);
        vm.stopPrank();

        uint256 nonce = 12345;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 halfShares = mintedShares / 2;
        bytes memory signature =
            _signPermit(address(NALPHA), halfShares, address(NEST_VAULT), nonce, deadline, permit2UserPrivateKey);

        // First request should succeed
        vm.prank(permit2User);
        NEST_VAULT.requestRedeemWithPermit2(halfShares, permit2User, permit2User, nonce, deadline, signature);

        // Second request with same nonce should fail
        vm.expectRevert(); // InvalidNonce
        vm.prank(permit2User);
        NEST_VAULT.requestRedeemWithPermit2(halfShares, permit2User, permit2User, nonce, deadline, signature);
    }

    /// @dev revert instantRedeemWithPermit2 when deadline has passed
    function testInstantRedeemWithPermit2_ExpiredDeadline() external {
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();

        // Owner deposits
        deal(USDC, permit2User, depositAmount);
        vm.startPrank(permit2User);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 mintedShares = NEST_VAULT.deposit(depositAmount, permit2User);
        ERC20(address(NALPHA)).approve(PERMIT2, type(uint256).max);
        vm.stopPrank();

        uint256 nonce = 0;
        uint256 expiredDeadline = block.timestamp - 1 hours;
        bytes memory signature = _signPermit(
            address(NALPHA), mintedShares, address(NEST_VAULT), nonce, expiredDeadline, permit2UserPrivateKey
        );

        vm.expectRevert(); // SignatureExpired
        vm.prank(permit2User);
        NEST_VAULT.instantRedeemWithPermit2(mintedShares, permit2User, permit2User, nonce, expiredDeadline, signature);
    }

    /// @dev revert requestRedeemWithPermit2 when deadline has passed
    function testRequestRedeemWithPermit2_ExpiredDeadline() external {
        uint256 depositAmount = 10_000 * 10 ** ERC20(USDC).decimals();

        // Owner deposits
        deal(USDC, permit2User, depositAmount);
        vm.startPrank(permit2User);
        ERC20(USDC).approve(address(NEST_VAULT), type(uint256).max);
        uint256 mintedShares = NEST_VAULT.deposit(depositAmount, permit2User);
        ERC20(address(NALPHA)).approve(PERMIT2, type(uint256).max);
        vm.stopPrank();

        uint256 nonce = 0;
        uint256 expiredDeadline = block.timestamp - 1 hours;
        bytes memory signature = _signPermit(
            address(NALPHA), mintedShares, address(NEST_VAULT), nonce, expiredDeadline, permit2UserPrivateKey
        );

        vm.expectRevert(); // SignatureExpired
        vm.prank(permit2User);
        NEST_VAULT.requestRedeemWithPermit2(mintedShares, permit2User, permit2User, nonce, expiredDeadline, signature);
    }
}
