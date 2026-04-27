// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {OperatorRegistry} from "contracts/operators/OperatorRegistry.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {Errors} from "contracts/types/Errors.sol";

contract OperatorRegistryTest is Test {
    event OperatorSet(address indexed controller, address indexed operator, bool approved);

    bytes32 private constant AUTHORIZE_TYPEHASH = keccak256(
        "AuthorizeOperator(address controller,address operator,bool approved,bytes32 nonce,uint256 deadline)"
    );

    OperatorRegistry private registry;

    function setUp() public {
        registry = new OperatorRegistry(address(this), Authority(address(0)));
    }

    function test_constructor_zeroOwner_reverts() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new OperatorRegistry(address(0), Authority(address(0)));
    }

    function test_setOperator_requiresAuth() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert("UNAUTHORIZED");
        registry.setOperator(address(0xCAFE), true);
    }

    function test_setOperator_zeroAddress_reverts() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        registry.setOperator(address(0), true);
    }

    function test_setOperator_setsAndEmits() public {
        address operator = address(0xB0B);

        vm.expectEmit(true, true, true, true);
        emit OperatorSet(address(this), operator, true);

        bool success = registry.setOperator(operator, true);
        assertTrue(success);
        assertTrue(registry.isOperator(address(this), operator));
    }

    function test_authorizeOperator_requiresAuth() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert("UNAUTHORIZED");
        registry.authorizeOperator(address(0xA11CE), address(0xB0B), true, bytes32("n"), block.timestamp + 1 days, "");
    }

    function test_authorizeOperator_zeroController_reverts() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        registry.authorizeOperator(address(0), address(0xB0B), true, bytes32("n"), block.timestamp + 1 days, "");
    }

    function test_authorizeOperator_zeroOperator_reverts() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        registry.authorizeOperator(address(0xA11CE), address(0), true, bytes32("n"), block.timestamp + 1 days, "");
    }

    function test_authorizeOperator_selfOperator_reverts() public {
        address controller = address(0xA11CE);
        vm.expectRevert(Errors.ERC7540SelfOperatorNotAllowed.selector);
        registry.authorizeOperator(controller, controller, true, bytes32("n"), block.timestamp + 1 days, "");
    }

    function test_authorizeOperator_expired_reverts() public {
        address controller = address(0xA11CE);
        address operator = address(0xB0B);
        vm.expectRevert(Errors.ERC7540Expired.selector);
        registry.authorizeOperator(controller, operator, true, bytes32("n"), block.timestamp - 1, "");
    }

    function test_authorizeOperator_invalidSigner_reverts() public {
        uint256 controllerKey = 0xA11CE;
        address controller = vm.addr(controllerKey);
        address operator = address(0xB0B);
        bytes32 nonce = bytes32("nonce");
        uint256 deadline = block.timestamp + 1 days;

        bytes memory signature = _signAuthorize(controller, 0xB0B0, operator, true, nonce, deadline);

        vm.expectRevert(Errors.ERC7540InvalidSigner.selector);
        registry.authorizeOperator(controller, operator, true, nonce, deadline, signature);
    }

    function test_authorizeOperator_reusedNonce_reverts() public {
        uint256 controllerKey = 0xA11CE;
        address controller = vm.addr(controllerKey);
        address operator = address(0xB0B);
        bytes32 nonce = bytes32("nonce");
        uint256 deadline = block.timestamp + 1 days;

        bytes memory signature = _signAuthorize(controller, controllerKey, operator, true, nonce, deadline);

        registry.authorizeOperator(controller, operator, true, nonce, deadline, signature);

        vm.expectRevert(Errors.ERC7540UsedAuthorization.selector);
        registry.authorizeOperator(controller, operator, true, nonce, deadline, signature);
    }

    function test_authorizeOperator_success_setsOperator() public {
        uint256 controllerKey = 0xA11CE;
        address controller = vm.addr(controllerKey);
        address operator = address(0xB0B);
        bytes32 nonce = bytes32("nonce");
        uint256 deadline = block.timestamp + 1 days;

        bytes memory signature = _signAuthorize(controller, controllerKey, operator, true, nonce, deadline);

        vm.expectEmit(true, true, true, true);
        emit OperatorSet(controller, operator, true);

        bool success = registry.authorizeOperator(controller, operator, true, nonce, deadline, signature);
        assertTrue(success);
        assertTrue(registry.isOperator(controller, operator));
    }

    function _signAuthorize(
        address controller,
        uint256 controllerKey,
        address operator,
        bool approved,
        bytes32 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(AUTHORIZE_TYPEHASH, controller, operator, approved, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("OperatorRegistry")),
                keccak256(bytes("1")),
                block.chainid,
                address(registry)
            )
        );
    }
}
