// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

// utils
import {Test} from "forge-std/Test.sol";

// contracts
import {Helper} from "test/Helper.sol";
import {AuthUpgradeable} from "contracts/upgradeable/auth/AuthUpgradeable.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

// libraries
import {Events} from "test/Events.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// types
import {PredicateMessage} from "@predicate/src/interfaces/IPredicateClient.sol";
import {Errors} from "contracts/types/Errors.sol";

contract NestVaultPredicateproxyForkTest is Events, Helper {
    using FixedPointMathLib for uint256;

    /// @dev deposit should work as expected
    function testDeposit() external {
        MOCK_SERVICE_MANAGER.setIsVerified(true);
        uint256 depositAmount = 20_000 * 10 ** ERC20(USDC).decimals();
        uint256 expectedShares = Math.mulDiv(
            depositAmount,
            10 ** ERC20(NALPHA).decimals(),
            NEST_VAULT.accountantWithRateProviders().getRateInQuoteSafe(ERC20(USDC)),
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
        vm.expectRevert(Errors.NestPredicateProxy__PredicateUnauthorizedTransaction.selector);
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
            NEST_VAULT.accountantWithRateProviders().getRateInQuoteSafe(ERC20(USDC)),
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
        vm.expectRevert(Errors.NestPredicateProxy__PredicateUnauthorizedTransaction.selector);
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
}
