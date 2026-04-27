// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {NestVault} from "contracts/NestVault.sol";
import {OperatorRegistry} from "contracts/operators/OperatorRegistry.sol";
import {MockNestVault} from "test/mock/MockNestVault.sol";
import {MockRateProvider} from "test/mock/MockRateProvider.sol";
import {MockAuthority} from "test/mock/MockAuthority.sol";
import {Errors} from "contracts/types/Errors.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {ERC20Mock} from "@layerzerolabs/oft-evm-upgradeable/test/mocks/ERC20Mock.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract NestVaultOperatorRegistryTest is Test {
    bytes32 private constant AUTHORIZE_TYPEHASH = keccak256(
        "AuthorizeOperator(address controller,address operator,bool approved,bytes32 nonce,uint256 deadline)"
    );

    uint256 private constant SHARES = 1_000_000;

    address private constant PROXY_ADMIN = address(0xBEEF);

    MockNestVault private vault;
    OperatorRegistry private registry;
    ERC20Mock private share;
    ERC20Mock private asset;
    MockRateProvider private accountant;

    address private controller;
    uint256 private controllerKey;
    address private operator;

    function setUp() public {
        controllerKey = 0xA11CE;
        controller = vm.addr(controllerKey);
        operator = address(0xB0B);

        share = new ERC20Mock("Share", "SHARE");
        asset = new ERC20Mock("Asset", "AST");
        accountant = new MockRateProvider();
        accountant.setRate(1e6);

        vault = MockNestVault(
            _deployContractAndProxy(
                type(MockNestVault).creationCode,
                abi.encode(payable(address(share))),
                abi.encodeCall(
                    NestVault.initialize, (address(accountant), address(asset), address(this), 1, address(0))
                )
            )
        );

        MockAuthority mockAuthority = new MockAuthority(true);
        vault.setAuthority(Authority(address(mockAuthority)));

        registry = new OperatorRegistry(address(this), Authority(address(0)));
        vault.setOperatorRegistry(address(registry));
    }

    function test_isOperator_usesRegistry() public {
        _authorizeInRegistry(true);
        assertTrue(vault.isOperator(controller, operator));
    }

    function test_requestRedeem_revertsForUnapprovedOperator() public {
        _mintSharesToController(SHARES);

        vm.prank(operator);
        vm.expectRevert(Errors.Unauthorized.selector);
        vault.requestRedeem(SHARES, controller, controller);
    }

    function test_requestRedeem_succeedsForRegistryOperator() public {
        _mintSharesToController(SHARES);
        _authorizeInRegistry(true);

        vm.prank(operator);
        vault.requestRedeem(SHARES, controller, controller);

        assertEq(vault.pendingRedeemRequest(0, controller), SHARES);
    }

    function _authorizeInRegistry(bool approved) internal {
        bytes32 nonce = bytes32("nonce");
        uint256 deadline = block.timestamp + 1 days;
        bytes memory signature = _signAuthorize(controller, controllerKey, operator, approved, nonce, deadline);
        registry.authorizeOperator(controller, operator, approved, nonce, deadline, signature);
    }

    function _mintSharesToController(uint256 amount) internal {
        share.mint(controller, amount);
        vm.prank(controller);
        share.approve(address(vault), amount);
    }

    function _signAuthorize(
        address controllerAddress,
        uint256 controllerPrivateKey,
        address operatorAddress,
        bool approved,
        bytes32 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(AUTHORIZE_TYPEHASH, controllerAddress, operatorAddress, approved, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerPrivateKey, digest);
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

    function _deployContractAndProxy(
        bytes memory _bytecode,
        bytes memory _constructorArgs,
        bytes memory _initializeArgs
    ) internal returns (address addr) {
        bytes memory bytecode = bytes.concat(_bytecode, _constructorArgs);
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(addr)) { revert(0, 0) }
        }

        return address(new TransparentUpgradeableProxy(addr, PROXY_ADMIN, _initializeArgs));
    }
}
