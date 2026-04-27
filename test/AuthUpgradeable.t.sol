// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

// utils
import {Test} from "forge-std/Test.sol";

// contract
import {AuthUpgradeable} from "contracts/upgradeable/auth/AuthUpgradeable.sol";
import {MockAuthChild} from "test/mock/MockAuthChild.sol";
import {MockAuthority} from "test/mock/MockAuthority.sol";
import {Authority} from "@solmate/auth/Auth.sol";

// libraries
import {Errors} from "contracts/types/Errors.sol";

/// @title OutOfOrderAuthority
/// @notice A mock authority that always reverts with "OUT_OF_ORDER" when any function is called.
/// @dev Used to simulate an authority that is out of order and cannot perform any actions.
contract OutOfOrderAuthority is Authority {
    /// @notice This function always reverts with an error message "OUT_OF_ORDER".
    /// @dev It simulates an authority that is in an unusable state.
    /// @return Always reverts.
    function canCall(address, address, bytes4) public pure override returns (bool) {
        revert("OUT_OF_ORDER");
    }
}

contract AuthUpgradeableTest is Test {
    MockAuthChild mockAuthChild;

    /// @notice Sets up the test environment by initializing `mockAuthChild`.
    /// @dev This function is called before each test to prepare the environment.
    function setUp() public {
        mockAuthChild = new MockAuthChild();
        mockAuthChild.initialize();
    }

    /// @notice Tests transferring ownership as the current owner.
    /// @dev This test ensures that the owner can transfer ownership to a new address.
    function testTransferOwnershipAsOwner() public {
        mockAuthChild.transferOwnership(address(0xBEEF));
        assertEq(mockAuthChild.pendingOwner(), address(0xBEEF));
        vm.prank(address(0xBEEF));
        mockAuthChild.acceptOwnership();
        assertEq(mockAuthChild.owner(), address(0xBEEF));
    }

    /// @notice Tests setting a new authority as the current owner.
    /// @dev This test verifies that the owner can set a new authority.
    function testSetAuthorityAsOwner() public {
        mockAuthChild.setAuthority(Authority(address(0xBEEF)));
        assertEq(address(mockAuthChild.authority()), address(0xBEEF));
    }

    /// @notice Tests calling a function as the current owner.
    /// @dev This test checks that the owner can call functions on the contract.
    function testCallFunctionAsOwner() public {
        mockAuthChild.updateFlag();
    }

    /// @notice Tests transferring ownership with a permissive authority.
    /// @dev This test ensures that ownership transfer works with a permissive authority that allows the action.
    function testTransferOwnershipWithPermissiveAuthority() public {
        address alice = makeAddr("alice");
        mockAuthChild.setAuthority(new MockAuthority(true));
        mockAuthChild.transferOwnership(alice);
        assertEq(mockAuthChild.pendingOwner(), alice);
        vm.startPrank(alice);
        mockAuthChild.acceptOwnership();
        assertEq(mockAuthChild.owner(), alice);
        mockAuthChild.transferOwnership(address(this));
        assertEq(mockAuthChild.pendingOwner(), address(this));
        vm.stopPrank();
    }

    /// @notice Tests setting a new authority with a permissive authority.
    /// @dev This test ensures that ownership transfer works with permissive authority set.
    function testSetAuthorityWithPermissiveAuthority() public {
        address alice = makeAddr("alice");
        mockAuthChild.setAuthority(new MockAuthority(true));
        mockAuthChild.transferOwnership(alice);
        vm.prank(alice);
        mockAuthChild.acceptOwnership();
        mockAuthChild.setAuthority(Authority(address(0xBEEF)));
    }

    /// @notice Tests calling a function with a permissive authority.
    /// @dev This test checks that a function call works with a permissive authority.
    function testCallFunctionWithPermissiveAuthority() public {
        mockAuthChild.setAuthority(new MockAuthority(true));
        mockAuthChild.updateFlag();
    }

    /// @notice Tests setting a new authority as the owner with an out-of-order authority.
    /// @dev This test ensures that setting a new authority fails if the authority is out of order.
    function testSetAuthorityAsOwnerWithOutOfOrderAuthority() public {
        mockAuthChild.setAuthority(new OutOfOrderAuthority());
        mockAuthChild.setAuthority(new MockAuthority(true));
    }

    /// @notice Tests transferring ownership to zero address.
    /// @dev This test ensures that a zero address cannot be owner.
    function testRevertTransferOwnershipZeroAddress() public {
        vm.expectRevert(AuthUpgradeable.AUTH_ZERO_ADDRESS.selector);
        mockAuthChild.transferOwnership(address(0));
    }

    /// @notice Tests transferring ownership as a non-owner.
    /// @dev This test ensures that a non-owner cannot transfer ownership.
    function testRevertTransferOwnershipAsNonOwner() public {
        address alice = makeAddr("alice");
        mockAuthChild.transferOwnership(alice);
        vm.prank(alice);
        mockAuthChild.acceptOwnership();
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        mockAuthChild.transferOwnership(address(0xBEEF));
    }

    /// @notice Tests accepting ownership as a non-new-owner.
    /// @dev This test ensures that a non-new-owner cannot accept ownership.
    function testRevertAcceptOwnershipAsNonNewOwner() public {
        address alice = makeAddr("alice");
        mockAuthChild.transferOwnership(alice);
        vm.startPrank(address(1));
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        mockAuthChild.acceptOwnership();
        vm.stopPrank();
    }

    /// @notice Tests setting a new authority as a non-owner.
    /// @dev This test ensures that a non-owner cannot set the authority.
    function testRevertSetAuthorityAsNonOwner() public {
        address alice = makeAddr("alice");
        mockAuthChild.transferOwnership(alice);
        vm.prank(alice);
        mockAuthChild.acceptOwnership();
        vm.expectRevert();
        mockAuthChild.setAuthority(Authority(address(0xBEEF)));
    }

    /// @notice Tests calling a function as a non-owner.
    /// @dev This test ensures that a non-owner cannot call functions that require ownership.
    function testRevertCallFunctionAsNonOwner() public {
        address alice = makeAddr("alice");
        mockAuthChild.transferOwnership(alice);
        vm.prank(alice);
        mockAuthChild.acceptOwnership();
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        mockAuthChild.updateFlag();
    }

    /// @notice Tests transferring ownership with a restrictive authority.
    /// @dev This test ensures that ownership transfer fails with a restrictive authority.
    function testRevertTransferOwnershipWithRestrictiveAuthority() public {
        address alice = makeAddr("alice");
        mockAuthChild.setAuthority(new MockAuthority(false));
        mockAuthChild.transferOwnership(alice);
        vm.prank(alice);
        mockAuthChild.acceptOwnership();
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        mockAuthChild.transferOwnership(address(this));
    }

    /// @notice Tests setting a new authority with a restrictive authority.
    /// @dev This test ensures that setting a new authority fails with a restrictive authority.
    function testRevertSetAuthorityWithRestrictiveAuthority() public {
        address alice = makeAddr("alice");
        mockAuthChild.setAuthority(new MockAuthority(false));
        mockAuthChild.transferOwnership(alice);
        vm.prank(alice);
        mockAuthChild.acceptOwnership();
        vm.expectRevert();
        mockAuthChild.setAuthority(Authority(address(0xBEEF)));
    }

    /// @notice Tests calling a function with a restrictive authority.
    /// @dev This test ensures that function calls fail with a restrictive authority.
    function testRevertCallFunctionWithRestrictiveAuthority() public {
        address alice = makeAddr("alice");
        mockAuthChild.setAuthority(new MockAuthority(false));
        mockAuthChild.transferOwnership(alice);
        vm.prank(alice);
        mockAuthChild.acceptOwnership();
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        mockAuthChild.updateFlag();
    }

    /// @notice Tests transferring ownership as the owner with an out-of-order authority.
    /// @dev This test ensures that transferring ownership fails when the authority is out of order.
    function testRevertTransferOwnershipAsOwnerWithOutOfOrderAuthority() public {
        mockAuthChild.setAuthority(new OutOfOrderAuthority());
        vm.expectRevert("OUT_OF_ORDER");
        mockAuthChild.transferOwnership(address(0));
    }

    /// @notice Tests calling a function as the owner with an out-of-order authority.
    /// @dev This test ensures that calling functions fails when the authority is out of order.
    function testRevertCallFunctionAsOwnerWithOutOfOrderAuthority() public {
        mockAuthChild.setAuthority(new OutOfOrderAuthority());
        vm.expectRevert("OUT_OF_ORDER");
        mockAuthChild.updateFlag();
    }

    /// @notice Test transferring ownership as the owner to a new owner address.
    /// @dev This is a generic test to transfer ownership, confirming the new owner is set.
    /// @param newOwner The address to which ownership is transferred.
    function testTransferOwnershipAsOwner(address newOwner) public {
        if (newOwner == address(this) || newOwner == address(0)) {
            newOwner = makeAddr("alice");
        }
        mockAuthChild.transferOwnership(newOwner);
        vm.prank(newOwner);
        mockAuthChild.acceptOwnership();
        assertEq(mockAuthChild.owner(), newOwner);
    }

    /// @notice Test setting a new authority as the owner.
    /// @dev This is a generic test to set the authority, confirming the authority address is updated.
    /// @param newAuthority The new authority to set.
    function testSetAuthorityAsOwner(Authority newAuthority) public {
        mockAuthChild.setAuthority(newAuthority);
        assertEq(address(mockAuthChild.authority()), address(newAuthority));
    }

    /// @notice Test transferring ownership with a permissive authority to a new owner.
    /// @dev This test checks ownership transfer with permissive authority.
    /// @param deadOwner The current owner before transfer.
    /// @param newOwner The new address to transfer ownership to.
    function testTransferOwnershipWithPermissiveAuthority(address deadOwner, address newOwner) public {
        if (deadOwner == address(this) || deadOwner == address(0)) {
            deadOwner = makeAddr("alice");
        }
        if (newOwner == address(0)) newOwner = makeAddr("bob");
        mockAuthChild.setAuthority(new MockAuthority(true));
        mockAuthChild.transferOwnership(deadOwner);
        vm.startPrank(deadOwner);
        mockAuthChild.acceptOwnership();
        mockAuthChild.transferOwnership(newOwner);
        vm.stopPrank();
    }

    /// @notice Test setting a new authority with a permissive authority.
    /// @dev This test ensures authority change works with permissive authority.
    /// @param deadOwner The current owner before authority change.
    /// @param newAuthority The new authority to set.
    function testSetAuthorityWithPermissiveAuthority(address deadOwner, Authority newAuthority) public {
        if (deadOwner == address(this) || deadOwner == address(0)) {
            deadOwner = makeAddr("alice");
        }

        mockAuthChild.setAuthority(new MockAuthority(true));
        mockAuthChild.transferOwnership(deadOwner);
        vm.prank(deadOwner);
        mockAuthChild.acceptOwnership();
        mockAuthChild.setAuthority(newAuthority);
    }

    /// @notice Test calling a function with permissive authority.
    /// @dev This test confirms function calls work with permissive authority.
    /// @param deadOwner The current owner before the function call.
    function testCallFunctionWithPermissiveAuthority(address deadOwner) public {
        if (deadOwner == address(this) || deadOwner == address(0)) {
            deadOwner = makeAddr("alice");
        }

        mockAuthChild.setAuthority(new MockAuthority(true));
        mockAuthChild.transferOwnership(deadOwner);
        vm.startPrank(deadOwner);
        mockAuthChild.acceptOwnership();
        mockAuthChild.updateFlag();
        vm.stopPrank();
    }

    /// @notice Test reverting ownership transfer as a non-owner.
    /// @dev This ensures that unauthorized users cannot transfer ownership.
    /// @param deadOwner The current owner before transfer.
    /// @param newOwner The address to transfer ownership to.
    function testRevertTransferOwnershipAsNonOwner(address deadOwner, address newOwner) public {
        if (deadOwner == address(this) || deadOwner == address(0)) {
            deadOwner = makeAddr("alice");
        }

        mockAuthChild.transferOwnership(deadOwner);
        vm.prank(deadOwner);
        mockAuthChild.acceptOwnership();
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        mockAuthChild.transferOwnership(newOwner);
    }

    /// @notice Test reverting authority change as a non-owner.
    /// @dev This test ensures that only the owner can change the authority.
    /// @param deadOwner The current owner before the authority change.
    /// @param newAuthority The new authority to set.
    function testRevertSetAuthorityAsNonOwner(address deadOwner, Authority newAuthority) public {
        if (deadOwner == address(this) || deadOwner == address(0)) {
            deadOwner = makeAddr("alice");
        }

        mockAuthChild.transferOwnership(deadOwner);
        vm.prank(deadOwner);
        mockAuthChild.acceptOwnership();
        vm.expectRevert();
        mockAuthChild.setAuthority(newAuthority);
    }

    /// @notice Test reverting function call as a non-owner.
    /// @dev This ensures that only the owner can call restricted functions.
    /// @param deadOwner The current owner before the function call.
    function testRevertCallFunctionAsNonOwner(address deadOwner) public {
        if (deadOwner == address(this) || deadOwner == address(0)) {
            deadOwner = makeAddr("alice");
        }

        mockAuthChild.transferOwnership(deadOwner);
        vm.prank(deadOwner);
        mockAuthChild.acceptOwnership();
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        mockAuthChild.updateFlag();
    }

    /// @notice Test reverting ownership transfer with restrictive authority.
    /// @dev This ensures that ownership transfer fails with restrictive authority.
    /// @param deadOwner The current owner before transfer.
    /// @param newOwner The new address to transfer ownership to.
    function testRevertTransferOwnershipWithRestrictiveAuthority(address deadOwner, address newOwner) public {
        if (deadOwner == address(this) || deadOwner == address(0)) {
            deadOwner = makeAddr("alice");
        }

        mockAuthChild.setAuthority(new MockAuthority(false));
        mockAuthChild.transferOwnership(deadOwner);
        vm.prank(deadOwner);
        mockAuthChild.acceptOwnership();
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        mockAuthChild.transferOwnership(newOwner);
    }

    /// @notice Test reverting authority change with restrictive authority.
    /// @dev This ensures that changing authority fails with restrictive authority.
    /// @param deadOwner The current owner before authority change.
    /// @param newAuthority The new authority to set.
    function testRevertSetAuthorityWithRestrictiveAuthority(address deadOwner, Authority newAuthority) public {
        if (deadOwner == address(this) || deadOwner == address(0)) {
            deadOwner = makeAddr("alice");
        }

        mockAuthChild.setAuthority(new MockAuthority(false));
        mockAuthChild.transferOwnership(deadOwner);
        vm.prank(deadOwner);
        mockAuthChild.acceptOwnership();
        vm.expectRevert();
        mockAuthChild.setAuthority(newAuthority);
    }

    /// @notice Test reverting function call with restrictive authority.
    /// @dev This ensures that function calls fail with restrictive authority.
    /// @param deadOwner The current owner before the function call.
    function testRevertCallFunctionWithRestrictiveAuthority(address deadOwner) public {
        if (deadOwner == address(this) || deadOwner == address(0)) {
            deadOwner = makeAddr("alice");
        }

        mockAuthChild.setAuthority(new MockAuthority(false));
        mockAuthChild.transferOwnership(deadOwner);
        vm.prank(deadOwner);
        mockAuthChild.acceptOwnership();
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        mockAuthChild.updateFlag();
    }

    /// @notice Test reverting ownership transfer with out-of-order authority.
    /// @dev This ensures that ownership transfer fails with out-of-order authority.
    /// @param deadOwner The current owner before transfer.
    function testRevertTransferOwnershipAsOwnerWithOutOfOrderAuthority(address deadOwner) public {
        if (deadOwner == address(this)) deadOwner = address(0);

        mockAuthChild.setAuthority(new OutOfOrderAuthority());
        vm.expectRevert("OUT_OF_ORDER");
        mockAuthChild.transferOwnership(deadOwner);
    }
}
