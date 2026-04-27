// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

// utils
import {Test} from "forge-std/Test.sol";

// contracts
import {Helper} from "test/Helper.sol";
import {AuthUpgradeable} from "contracts/upgradeable/auth/AuthUpgradeable.sol";
import {NestVaultPredicateProxy} from "contracts/NestVaultPredicateProxy.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// libraries
import {Events} from "test/Events.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// types
import {PredicateMessage} from "@predicate/src/interfaces/IPredicateClient.sol";
import {Errors} from "contracts/types/Errors.sol";

// interfaces
import {ISignatureTransfer} from "@uniswap/permit2/interfaces/ISignatureTransfer.sol";

contract NestVaultPredicateProxyForkTest is Events, Helper {
    using FixedPointMathLib for uint256;

    // Test user private key and address for signing (for Permit2 tests)
    uint256 internal userPrivateKey;
    address internal user;

    function setUp() public override {
        super.setUp();
        // Use a random private key that results in an address without code
        userPrivateKey = uint256(keccak256("test user permit2"));
        user = vm.addr(userPrivateKey);
        // Ensure user is an EOA (no code)
        vm.etch(user, "");
    }

    /// @dev deposit should work as expected
    function testDeposit() external {
        MOCK_SERVICE_MANAGER.setIsVerified(true);
        uint256 depositAmount = 20_000 * 10 ** ERC20(USDC).decimals();
        uint256 expectedShares = Math.mulDiv(
            depositAmount,
            10 ** ERC20(NALPHA).decimals(),
            NEST_VAULT.accountant().getRateInQuoteSafe(ERC20(USDC)),
            Math.Rounding.Floor
        );
        uint256 userUSDCBalanceBefore = ERC20(USDC).balanceOf(ETHEREUM_USDC_WHALE);
        uint256 usernALPHABalanceBefore = ERC20(NALPHA).balanceOf(ETHEREUM_USDC_WHALE);
        uint256 vaultUSDCBalanceBefore = ERC20(USDC).balanceOf(NALPHA);
        vm.startPrank(ETHEREUM_USDC_WHALE);
        ERC20(USDC).approve(address(NEST_VAULT_PREDICATE_PROXY), type(uint256).max);
        uint256 shares = NEST_VAULT_PREDICATE_PROXY.deposit(
            ERC20(USDC),
            depositAmount,
            ETHEREUM_USDC_WHALE,
            NEST_VAULT,
            PredicateMessage({
                taskId: "", expireByTime: 0, signerAddresses: new address[](0), signatures: new bytes[](0)
            })
        );
        vm.stopPrank();
        assertEq(expectedShares, shares);
        assertEq(depositAmount + vaultUSDCBalanceBefore, ERC20(USDC).balanceOf(NALPHA));
        assertEq(ERC20(NALPHA).balanceOf(ETHEREUM_USDC_WHALE), usernALPHABalanceBefore + shares);
        assertEq(ERC20(USDC).balanceOf(ETHEREUM_USDC_WHALE), userUSDCBalanceBefore - depositAmount);
    }

    /// @dev should revert when pause while depositing
    function testRevertDepositUnauthorized() external {
        MOCK_SERVICE_MANAGER.setIsVerified(false);
        vm.expectRevert(Errors.NestPredicateProxyPredicateUnauthorizedTransaction.selector);
        NEST_VAULT_PREDICATE_PROXY.deposit(
            ERC20(USDC),
            0,
            ETHEREUM_USDC_WHALE,
            NEST_VAULT,
            PredicateMessage({
                taskId: "", expireByTime: 0, signerAddresses: new address[](0), signatures: new bytes[](0)
            })
        );
    }

    /// @dev should revert when unauthorized user deposits
    function testRevertDepositPaused() external {
        NEST_VAULT_PREDICATE_PROXY.pause();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        NEST_VAULT_PREDICATE_PROXY.deposit(
            ERC20(USDC),
            0,
            ETHEREUM_USDC_WHALE,
            NEST_VAULT,
            PredicateMessage({
                taskId: "", expireByTime: 0, signerAddresses: new address[](0), signatures: new bytes[](0)
            })
        );
    }

    /// @dev mint should work as expected
    function testMint() public {
        MOCK_SERVICE_MANAGER.setIsVerified(true);
        uint256 mintAmount = 10_000 * 10 ** ERC20(NALPHA).decimals();
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
        ERC20(USDC).approve(address(NEST_VAULT_PREDICATE_PROXY), type(uint256).max);

        // Call the mint function, requesting to mint `mintAmount` of NALPHA shares
        uint256 usdcDeposited = NEST_VAULT_PREDICATE_PROXY.mint(
            ERC20(USDC),
            mintAmount,
            ETHEREUM_USDC_WHALE,
            NEST_VAULT,
            PredicateMessage({
                taskId: "", expireByTime: 0, signerAddresses: new address[](0), signatures: new bytes[](0)
            })
        );

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

    /// @dev should revert when an unauthorized user deposits
    function testRevertMintUnauthorized() public {
        MOCK_SERVICE_MANAGER.setIsVerified(false);
        vm.expectRevert(Errors.NestPredicateProxyPredicateUnauthorizedTransaction.selector);
        NEST_VAULT_PREDICATE_PROXY.mint(
            ERC20(USDC),
            0,
            ETHEREUM_USDC_WHALE,
            NEST_VAULT,
            PredicateMessage({
                taskId: "", expireByTime: 0, signerAddresses: new address[](0), signatures: new bytes[](0)
            })
        );
    }

    /// @dev should revert when pause while depositing
    function testRevertMintPaused() public {
        NEST_VAULT_PREDICATE_PROXY.pause();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        NEST_VAULT_PREDICATE_PROXY.mint(
            ERC20(USDC),
            0,
            ETHEREUM_USDC_WHALE,
            NEST_VAULT,
            PredicateMessage({
                taskId: "", expireByTime: 0, signerAddresses: new address[](0), signatures: new bytes[](0)
            })
        );
    }

    /// @dev Ensure only the owner can set the policy
    function testSetPolicyAsOwner() public {
        NEST_VAULT_PREDICATE_PROXY.setPolicy("abc");

        assertEq(NEST_VAULT_PREDICATE_PROXY.getPolicy(), "abc", "Policy ID should match the updated value");
    }

    /// @dev should revert when trying to set policy using non owner
    function testRevertSetPolicyAsNonOwner() public {
        address nonOwner = makeAddr("alice");
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(AuthUpgradeable.AUTH_UNAUTHORIZED.selector, nonOwner));
        NEST_VAULT_PREDICATE_PROXY.setPolicy("abc");
    }

    /// @dev initialize reverts when owner is zero
    function testInitializeRevertZeroOwner() public {
        address impl = address(new NestVaultPredicateProxy());

        vm.expectRevert(Errors.ZeroAddress.selector);
        new TransparentUpgradeableProxy(
            impl,
            address(this),
            abi.encodeWithSelector(
                NestVaultPredicateProxy.initialize.selector, address(0), address(MOCK_SERVICE_MANAGER), POLICY_ID
            )
        );
    }

    /// @dev initialize reverts when service manager is zero
    function testInitializeRevertZeroServiceManager() public {
        address impl = address(new NestVaultPredicateProxy());

        vm.expectRevert(Errors.ZeroAddress.selector);
        new TransparentUpgradeableProxy(
            impl,
            address(this),
            abi.encodeWithSelector(NestVaultPredicateProxy.initialize.selector, address(this), address(0), POLICY_ID)
        );
    }

    ///@dev Ensure only the owner can set the predicate manager
    function testSetPredicateManagerAsOwner() public {
        NEST_VAULT_PREDICATE_PROXY.setPredicateManager(address(1));

        assertEq(
            NEST_VAULT_PREDICATE_PROXY.getPredicateManager(),
            address(1),
            "Predicate manager should match the updated address"
        );
    }

    ///@dev should revert when non owner sets predicate manager
    function testRevertSetPredicateManagerAsNonOwner() public {
        address nonOwner = makeAddr("alice");
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(AuthUpgradeable.AUTH_UNAUTHORIZED.selector, nonOwner));
        NEST_VAULT_PREDICATE_PROXY.setPredicateManager(address(1));
    }

    ///@dev Ensure ownership transfer works as expected
    function testOwnershipTransfer() public {
        address newOwner = makeAddr("alice");
        NEST_VAULT_PREDICATE_PROXY.transferOwnership(newOwner);
        vm.prank(newOwner);
        NEST_VAULT_PREDICATE_PROXY.acceptOwnership();
        assertEq(NEST_VAULT_PREDICATE_PROXY.owner(), newOwner, "Ownership should be transferred to newOwner");
    }

    /// @dev only owner can pause
    function testPause() public {
        NEST_VAULT_PREDICATE_PROXY.pause();
        assertEq(NEST_VAULT_PREDICATE_PROXY.paused(), true);
    }

    /// @dev only owner can pause
    function testRevertPauseUnauthorized() public {
        address nonOwner = makeAddr("alice");
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(AuthUpgradeable.AUTH_UNAUTHORIZED.selector, nonOwner));
        NEST_VAULT_PREDICATE_PROXY.pause();
    }

    /// @dev only owner can unpause
    function testUnpause() public {
        NEST_VAULT_PREDICATE_PROXY.pause();
        NEST_VAULT_PREDICATE_PROXY.unpause();
        assertEq(NEST_VAULT_PREDICATE_PROXY.paused(), false);
    }

    /// @dev revert when unauthorized user unpauses
    function testRevertUnpauseUnauthorized() public {
        NEST_VAULT_PREDICATE_PROXY.pause();
        address nonOwner = makeAddr("alice");
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(AuthUpgradeable.AUTH_UNAUTHORIZED.selector, nonOwner));
        NEST_VAULT_PREDICATE_PROXY.unpause();
    }

    /// @dev should return true for valid user
    function testGenericUserCheckPredicateAuthorized() public {
        MOCK_SERVICE_MANAGER.setIsVerified(true);
        assertEq(
            NEST_VAULT_PREDICATE_PROXY.genericUserCheckPredicate(
                address(1),
                PredicateMessage({
                    taskId: "", expireByTime: 0, signerAddresses: new address[](0), signatures: new bytes[](0)
                })
            ),
            true
        );
    }

    /// @dev should return false for invalid user
    function testGenericUserCheckPredicateUnauthorized() public {
        MOCK_SERVICE_MANAGER.setIsVerified(false);
        assertEq(
            NEST_VAULT_PREDICATE_PROXY.genericUserCheckPredicate(
                address(1),
                PredicateMessage({
                    taskId: "", expireByTime: 0, signerAddresses: new address[](0), signatures: new bytes[](0)
                })
            ),
            false
        );
    }

    // ========================================= PERMIT2 TESTS =========================================

    /// @dev depositWithPermit2 should work as expected
    function testDepositWithPermit2() external {
        MOCK_SERVICE_MANAGER.setIsVerified(true);
        uint256 depositAmount = 20_000 * 10 ** ERC20(USDC).decimals();
        uint256 expectedShares = Math.mulDiv(
            depositAmount,
            10 ** ERC20(NALPHA).decimals(),
            NEST_VAULT.accountant().getRateInQuoteSafe(ERC20(USDC)),
            Math.Rounding.Floor
        );

        // Deal USDC to user and set up Permit2 approval
        deal(USDC, user, depositAmount);
        vm.prank(user);
        ERC20(USDC).approve(PERMIT2, type(uint256).max);

        uint256 userUSDCBalanceBefore = ERC20(USDC).balanceOf(user);
        uint256 usernALPHABalanceBefore = ERC20(NALPHA).balanceOf(user);
        uint256 vaultUSDCBalanceBefore = ERC20(USDC).balanceOf(NALPHA);

        // Create permit
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature =
            _signPermit(USDC, depositAmount, address(NEST_VAULT_PREDICATE_PROXY), nonce, deadline, userPrivateKey);

        vm.prank(user);
        uint256 shares = NEST_VAULT_PREDICATE_PROXY.depositWithPermit2(
            ERC20(USDC),
            depositAmount,
            user,
            NEST_VAULT,
            ISignatureTransfer(PERMIT2),
            nonce,
            deadline,
            signature,
            PredicateMessage({
                taskId: "", expireByTime: 0, signerAddresses: new address[](0), signatures: new bytes[](0)
            })
        );

        assertEq(expectedShares, shares);
        assertEq(depositAmount + vaultUSDCBalanceBefore, ERC20(USDC).balanceOf(NALPHA));
        assertEq(ERC20(NALPHA).balanceOf(user), usernALPHABalanceBefore + shares);
        assertEq(ERC20(USDC).balanceOf(user), userUSDCBalanceBefore - depositAmount);
    }

    /// @dev should revert depositWithPermit2 when predicate unauthorized
    function testRevertDepositWithPermit2Unauthorized() external {
        MOCK_SERVICE_MANAGER.setIsVerified(false);
        uint256 depositAmount = 1000 * 10 ** ERC20(USDC).decimals();

        deal(USDC, user, depositAmount);
        vm.prank(user);
        ERC20(USDC).approve(PERMIT2, type(uint256).max);

        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature =
            _signPermit(USDC, depositAmount, address(NEST_VAULT_PREDICATE_PROXY), nonce, deadline, userPrivateKey);

        vm.expectRevert(Errors.NestPredicateProxyPredicateUnauthorizedTransaction.selector);
        vm.prank(user);
        NEST_VAULT_PREDICATE_PROXY.depositWithPermit2(
            ERC20(USDC),
            depositAmount,
            user,
            NEST_VAULT,
            ISignatureTransfer(PERMIT2),
            nonce,
            deadline,
            signature,
            PredicateMessage({
                taskId: "", expireByTime: 0, signerAddresses: new address[](0), signatures: new bytes[](0)
            })
        );
    }

    /// @dev should revert depositWithPermit2 when paused
    function testRevertDepositWithPermit2Paused() external {
        NEST_VAULT_PREDICATE_PROXY.pause();
        uint256 depositAmount = 1000 * 10 ** ERC20(USDC).decimals();

        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature =
            _signPermit(USDC, depositAmount, address(NEST_VAULT_PREDICATE_PROXY), nonce, deadline, userPrivateKey);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(user);
        NEST_VAULT_PREDICATE_PROXY.depositWithPermit2(
            ERC20(USDC),
            depositAmount,
            user,
            NEST_VAULT,
            ISignatureTransfer(PERMIT2),
            nonce,
            deadline,
            signature,
            PredicateMessage({
                taskId: "", expireByTime: 0, signerAddresses: new address[](0), signatures: new bytes[](0)
            })
        );
    }

    /// @dev should revert depositWithPermit2 when signature is invalid (wrong signer)
    function testRevertDepositWithPermit2InvalidSigner() external {
        MOCK_SERVICE_MANAGER.setIsVerified(true);
        uint256 depositAmount = 1000 * 10 ** ERC20(USDC).decimals();

        deal(USDC, user, depositAmount);
        vm.prank(user);
        ERC20(USDC).approve(PERMIT2, type(uint256).max);

        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;
        // Sign with wrong private key
        uint256 wrongPrivateKey = 0x87654321;
        bytes memory signature =
            _signPermit(USDC, depositAmount, address(NEST_VAULT_PREDICATE_PROXY), nonce, deadline, wrongPrivateKey);

        vm.expectRevert(); // InvalidSigner
        vm.prank(user);
        NEST_VAULT_PREDICATE_PROXY.depositWithPermit2(
            ERC20(USDC),
            depositAmount,
            user,
            NEST_VAULT,
            ISignatureTransfer(PERMIT2),
            nonce,
            deadline,
            signature,
            PredicateMessage({
                taskId: "", expireByTime: 0, signerAddresses: new address[](0), signatures: new bytes[](0)
            })
        );
    }

    /// @dev should revert depositWithPermit2 when nonce is reused
    function testRevertDepositWithPermit2NonceReused() external {
        MOCK_SERVICE_MANAGER.setIsVerified(true);
        uint256 depositAmount = 1000 * 10 ** ERC20(USDC).decimals();

        deal(USDC, user, depositAmount * 2);
        vm.prank(user);
        ERC20(USDC).approve(PERMIT2, type(uint256).max);

        uint256 nonce = 12345;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature =
            _signPermit(USDC, depositAmount, address(NEST_VAULT_PREDICATE_PROXY), nonce, deadline, userPrivateKey);

        // First deposit should succeed
        vm.prank(user);
        NEST_VAULT_PREDICATE_PROXY.depositWithPermit2(
            ERC20(USDC),
            depositAmount,
            user,
            NEST_VAULT,
            ISignatureTransfer(PERMIT2),
            nonce,
            deadline,
            signature,
            PredicateMessage({
                taskId: "", expireByTime: 0, signerAddresses: new address[](0), signatures: new bytes[](0)
            })
        );

        // Second deposit with same nonce should fail
        vm.expectRevert(); // InvalidNonce
        vm.prank(user);
        NEST_VAULT_PREDICATE_PROXY.depositWithPermit2(
            ERC20(USDC),
            depositAmount,
            user,
            NEST_VAULT,
            ISignatureTransfer(PERMIT2),
            nonce,
            deadline,
            signature,
            PredicateMessage({
                taskId: "", expireByTime: 0, signerAddresses: new address[](0), signatures: new bytes[](0)
            })
        );
    }

    /// @dev should revert depositWithPermit2 when deadline has passed
    function testRevertDepositWithPermit2ExpiredDeadline() external {
        MOCK_SERVICE_MANAGER.setIsVerified(true);
        uint256 depositAmount = 1000 * 10 ** ERC20(USDC).decimals();

        deal(USDC, user, depositAmount);
        vm.prank(user);
        ERC20(USDC).approve(PERMIT2, type(uint256).max);

        uint256 nonce = 0;
        uint256 expiredDeadline = block.timestamp - 1 hours;
        bytes memory signature = _signPermit(
            USDC, depositAmount, address(NEST_VAULT_PREDICATE_PROXY), nonce, expiredDeadline, userPrivateKey
        );

        vm.expectRevert(); // SignatureExpired
        vm.prank(user);
        NEST_VAULT_PREDICATE_PROXY.depositWithPermit2(
            ERC20(USDC),
            depositAmount,
            user,
            NEST_VAULT,
            ISignatureTransfer(PERMIT2),
            nonce,
            expiredDeadline,
            signature,
            PredicateMessage({
                taskId: "", expireByTime: 0, signerAddresses: new address[](0), signatures: new bytes[](0)
            })
        );
    }
}
