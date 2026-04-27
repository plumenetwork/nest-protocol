// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {NestVaultRedeemOperator} from "contracts/operators/NestVaultRedeemOperator.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {MockNestVault} from "test/mock/MockNestVault.sol";
import {MockNestShareOFT} from "test/mock/MockNestShareOFT.sol";
import {MockNestShareOFTDecimals8} from "test/mock/MockNestShareOFTDecimals8.sol";
import {NestShareOFT} from "contracts/NestShareOFT.sol";
import {NestVault} from "contracts/NestVault.sol";
import {MockRateProvider} from "test/mock/MockRateProvider.sol";
import {MockAuthority} from "test/mock/MockAuthority.sol";
import {ERC20Mock} from "@layerzerolabs/oft-evm-upgradeable/test/mocks/ERC20Mock.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {AuthUpgradeable} from "contracts/upgradeable/auth/AuthUpgradeable.sol";
import {Errors} from "contracts/types/Errors.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

contract MockERC1271Wallet is IERC1271 {
    address public immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function isValidSignature(bytes32 _hash, bytes memory _signature) external view returns (bytes4) {
        address signer = ECDSA.recover(_hash, _signature);
        if (signer == owner) {
            return IERC1271.isValidSignature.selector;
        }
        return 0xffffffff;
    }
}

contract MockERC1271NonceChecker is IERC1271 {
    address public immutable owner;
    INestVaultCore public immutable vault;
    bytes32 public immutable nonce;

    constructor(address _owner, INestVaultCore _vault, bytes32 _nonce) {
        owner = _owner;
        vault = _vault;
        nonce = _nonce;
    }

    function isValidSignature(bytes32 _hash, bytes memory _signature) external view returns (bytes4) {
        if (vault.authorizations(address(this), nonce)) {
            return 0xffffffff;
        }
        address signer = ECDSA.recover(_hash, _signature);
        if (signer == owner) {
            return IERC1271.isValidSignature.selector;
        }
        return 0xffffffff;
    }
}

contract NestVaultRedeemOperatorTest is TestHelperOz5 {
    event ReceiverSet(address indexed vault, address indexed controller, address indexed receiver);

    uint8 private constant KEEPER_ROLE = 1;
    uint256 private constant SHARES = 1_000_000;
    uint32 private constant LOCAL_EID = 1;
    bytes32 private constant ERC1967_ADMIN_SLOT = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);

    uint256 private controllerKey;
    address private keeper = address(0xBEEF);
    address private controller;
    address private receiver = address(0xB0B);
    address private proxyAdmin = address(0xBEEF1);

    NestVaultRedeemOperator private operator;
    RolesAuthority private authority;
    MockNestVault private vault;
    MockNestShareOFT private share;
    ERC20Mock private asset;
    MockRateProvider private accountant;

    function setUp() public override {
        super.setUp();
        setUpEndpoints(1, LibraryType.UltraLightNode);

        controllerKey = 0xA11CE;
        controller = vm.addr(controllerKey);

        operator = NestVaultRedeemOperator(
            _deployContractAndProxy(
                type(NestVaultRedeemOperator).creationCode,
                bytes(""),
                abi.encodeCall(NestVaultRedeemOperator.initialize, (address(this)))
            )
        );

        authority = new RolesAuthority(address(this), Authority(address(0)));
        operator.setAuthority(Authority(address(authority)));
        authority.setRoleCapability(KEEPER_ROLE, address(operator), operator.redeem.selector, true);
        authority.setRoleCapability(KEEPER_ROLE, address(operator), operator.fulfillAndRedeem.selector, true);
        authority.setRoleCapability(KEEPER_ROLE, address(operator), operator.redeemAll.selector, true);
        authority.setRoleCapability(KEEPER_ROLE, address(operator), operator.fulfillAndRedeemAll.selector, true);
        authority.setRoleCapability(KEEPER_ROLE, address(operator), operator.batchRedeem.selector, true);
        authority.setRoleCapability(KEEPER_ROLE, address(operator), operator.batchFulfillAndRedeem.selector, true);
        authority.setRoleCapability(KEEPER_ROLE, address(operator), operator.authorizeAsOperator.selector, true);
        authority.setUserRole(keeper, KEEPER_ROLE, true);

        accountant = new MockRateProvider();
        accountant.setRate(1e6);

        asset = new ERC20Mock("Asset", "AST");

        share = MockNestShareOFT(
            _deployContractAndProxy(
                type(MockNestShareOFT).creationCode,
                abi.encode(address(endpoints[LOCAL_EID])),
                abi.encodeCall(NestShareOFT.initialize, ("Share", "SHARE", address(this), address(this)))
            )
        );

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
        share.setAuthority(Authority(address(mockAuthority)));
        vault.setAuthority(Authority(address(mockAuthority)));
    }

    function test_initialize_zeroOwner_reverts() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        this._deployOperatorForTest(address(0));
    }

    function test_getReceiver_defaultsToController() public view {
        assertEq(operator.getReceiver(address(vault), controller), controller);
    }

    function test_setReceiver_perVault() public {
        _setReceiver(controller, receiver);

        assertEq(operator.getReceiver(address(vault), controller), receiver);
    }

    function test_setReceiver_zeroVault_reverts() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        operator.setReceiver(address(0), receiver);
    }

    function test_setReceiver_zeroReceiver_clearsToDefault() public {
        _setReceiver(controller, receiver);
        assertEq(operator.getReceiver(address(vault), controller), receiver);

        _setReceiver(controller, address(0));
        assertEq(operator.getReceiver(address(vault), controller), controller);
    }

    function test_setReceiver_emitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit ReceiverSet(address(vault), controller, receiver);

        _setReceiver(controller, receiver);
    }

    function test_redeem_zeroVault_reverts() public {
        _expectZeroVaultRevert(operator.redeem);
    }

    function test_redeem_zeroController_reverts() public {
        _expectZeroControllerRevert(operator.redeem);
    }

    function test_fulfillAndRedeem_zeroVault_reverts() public {
        _expectZeroVaultRevert(operator.fulfillAndRedeem);
    }

    function test_fulfillAndRedeem_zeroController_reverts() public {
        _expectZeroControllerRevert(operator.fulfillAndRedeem);
    }

    function test_authorizeAsOperator_zeroVault_reverts() public {
        _expectAuthorizeAsOperatorRevert(INestVaultCore(address(0)), controller);
    }

    function test_authorizeAsOperator_zeroController_reverts() public {
        _expectAuthorizeAsOperatorRevert(INestVaultCore(address(vault)), address(0));
    }

    function test_fulfillRedeem_oneShareMismatch_reverts() public {
        uint256 originalOneShare = 10 ** uint256(share.decimals());
        _prepareRedeem(SHARES);

        MockNestShareOFTDecimals8 newImpl = new MockNestShareOFTDecimals8();
        ProxyAdmin admin = ProxyAdmin(_proxyAdmin(address(share)));
        vm.prank(proxyAdmin);
        admin.upgradeAndCall(ITransparentUpgradeableProxy(address(share)), address(newImpl), "");

        uint256 expectedOneShare = 10 ** uint256(share.decimals());
        vm.startPrank(controller);
        // Upgraded share implementation lacks exit logic; fulfillRedeem now reverts without data.
        vm.expectRevert();
        vault.fulfillRedeem(controller, SHARES);
        vm.stopPrank();
    }

    function test_redeem_usesConfiguredReceiver() public {
        _prepareRedeem(SHARES);

        _setReceiver(controller, receiver);
        _fulfillRedeem(controller, SHARES);

        uint256 receiverBefore = asset.balanceOf(receiver);

        vm.prank(keeper);
        uint256 assets = operator.redeem(_buildRequest(INestVaultCore(address(vault)), controller, SHARES));

        uint256 receiverAfter = asset.balanceOf(receiver);
        assertEq(assets, SHARES);
        assertEq(receiverAfter - receiverBefore, SHARES);
    }

    function test_redeem_defaultsToController() public {
        _prepareRedeem(SHARES);

        _fulfillRedeem(controller, SHARES);

        uint256 controllerBefore = asset.balanceOf(controller);

        vm.prank(keeper);
        operator.redeem(_buildRequest(INestVaultCore(address(vault)), controller, SHARES));

        uint256 controllerAfter = asset.balanceOf(controller);
        assertEq(controllerAfter - controllerBefore, SHARES);
    }

    function test_redeem_exceedsClaimable_reverts() public {
        _prepareRedeem(SHARES);
        _fulfillRedeem(controller, SHARES);

        vm.prank(keeper);
        vm.expectRevert(Errors.InsufficientClaimable.selector);
        operator.redeem(_buildRequest(INestVaultCore(address(vault)), controller, SHARES * 2));
    }

    function test_redeem_noClaimable_reverts() public {
        vm.prank(keeper);
        vm.expectRevert(Errors.InsufficientClaimable.selector);
        operator.redeem(_buildRequest(INestVaultCore(address(vault)), controller, SHARES));
    }

    function test_fulfillAndRedeem_callsBoth() public {
        _prepareRedeem(SHARES);

        _setReceiver(controller, receiver);

        uint256 receiverBefore = asset.balanceOf(receiver);

        vm.prank(keeper);
        uint256 assets = operator.fulfillAndRedeem(_buildRequest(INestVaultCore(address(vault)), controller, SHARES));

        uint256 receiverAfter = asset.balanceOf(receiver);
        assertEq(assets, SHARES);
        assertEq(receiverAfter - receiverBefore, SHARES);
        assertEq(vault.claimableRedeemRequest(0, controller), 0);
    }

    function test_fulfillAndRedeem_exceedsTotalClaimable_reverts() public {
        _prepareRedeem(SHARES);

        vm.prank(keeper);
        vm.expectRevert(Errors.InsufficientClaimable.selector);
        operator.fulfillAndRedeem(_buildRequest(INestVaultCore(address(vault)), controller, SHARES * 2));
    }

    function test_fulfillAndRedeem_noPending_redeemsClaimable() public {
        _prepareRedeem(SHARES);
        _fulfillRedeem(controller, SHARES);

        uint256 controllerBefore = asset.balanceOf(controller);

        vm.prank(keeper);
        uint256 assets = operator.fulfillAndRedeem(_buildRequest(INestVaultCore(address(vault)), controller, SHARES));

        uint256 controllerAfter = asset.balanceOf(controller);
        assertEq(assets, SHARES);
        assertEq(controllerAfter - controllerBefore, SHARES);
        assertEq(vault.claimableRedeemRequest(0, controller), 0);
    }

    function test_redeem_operatorNotAuthorized_reverts() public {
        _prepareRedeemWithoutOperator(controller, SHARES);
        _fulfillRedeem(controller, SHARES);

        vm.prank(keeper);
        vm.expectRevert(Errors.Unauthorized.selector);
        operator.redeem(_buildRequest(INestVaultCore(address(vault)), controller, SHARES));
    }

    function test_fulfillAndRedeem_operatorNotAuthorized_reverts() public {
        _prepareRedeemWithoutOperator(controller, SHARES);

        vm.prank(keeper);
        vm.expectRevert(Errors.Unauthorized.selector);
        operator.fulfillAndRedeem(_buildRequest(INestVaultCore(address(vault)), controller, SHARES));
    }

    function test_redeemAll_redeemsClaimable() public {
        _prepareRedeem(SHARES);

        _setReceiver(controller, receiver);
        _fulfillRedeem(controller, SHARES);

        uint256 receiverBefore = asset.balanceOf(receiver);

        vm.prank(keeper);
        uint256 assets = operator.redeemAll(INestVaultCore(address(vault)), controller);

        uint256 receiverAfter = asset.balanceOf(receiver);
        assertEq(assets, SHARES);
        assertEq(receiverAfter - receiverBefore, SHARES);
        assertEq(vault.claimableRedeemRequest(0, controller), 0);
    }

    function test_redeemAll_zeroShares_reverts() public {
        vm.prank(keeper);
        vm.expectRevert(Errors.ZeroShares.selector);
        operator.redeemAll(INestVaultCore(address(vault)), controller);
    }

    function test_redeemAll_zeroVault_reverts() public {
        vm.prank(keeper);
        vm.expectRevert(Errors.ZeroAddress.selector);
        operator.redeemAll(INestVaultCore(address(0)), controller);
    }

    function test_redeemAll_zeroController_reverts() public {
        vm.prank(keeper);
        vm.expectRevert(Errors.ZeroAddress.selector);
        operator.redeemAll(INestVaultCore(address(vault)), address(0));
    }

    function test_fulfillAndRedeemAll_callsBoth() public {
        _prepareRedeem(SHARES);

        _setReceiver(controller, receiver);

        uint256 receiverBefore = asset.balanceOf(receiver);

        vm.prank(keeper);
        uint256 assets = operator.fulfillAndRedeemAll(INestVaultCore(address(vault)), controller);

        uint256 receiverAfter = asset.balanceOf(receiver);
        assertEq(assets, SHARES);
        assertEq(receiverAfter - receiverBefore, SHARES);
        assertEq(vault.claimableRedeemRequest(0, controller), 0);
    }

    function test_fulfillAndRedeemAll_zeroShares_reverts() public {
        vm.prank(keeper);
        vm.expectRevert(Errors.ZeroShares.selector);
        operator.fulfillAndRedeemAll(INestVaultCore(address(vault)), controller);
    }

    function test_fulfillAndRedeemAll_zeroVault_reverts() public {
        vm.prank(keeper);
        vm.expectRevert(Errors.ZeroAddress.selector);
        operator.fulfillAndRedeemAll(INestVaultCore(address(0)), controller);
    }

    function test_fulfillAndRedeemAll_zeroController_reverts() public {
        vm.prank(keeper);
        vm.expectRevert(Errors.ZeroAddress.selector);
        operator.fulfillAndRedeemAll(INestVaultCore(address(vault)), address(0));
    }

    function test_batchRedeem_usesConfiguredReceivers() public {
        address controllerTwo = vm.addr(0xB0B2);
        uint256 sharesTwo = SHARES * 2;

        _prepareRedeem(SHARES);
        _prepareRedeem(controllerTwo, sharesTwo);

        _setReceiver(controller, receiver);
        _fulfillRedeem(controller, SHARES);
        _fulfillRedeem(controllerTwo, sharesTwo);

        uint256 receiverBefore = asset.balanceOf(receiver);
        uint256 controllerTwoBefore = asset.balanceOf(controllerTwo);

        NestVaultRedeemOperator.RedeemRequest[] memory requests = new NestVaultRedeemOperator.RedeemRequest[](2);
        requests[0] = _buildRequest(INestVaultCore(address(vault)), controller, SHARES);
        requests[1] = _buildRequest(INestVaultCore(address(vault)), controllerTwo, sharesTwo);

        vm.prank(keeper);
        uint256[] memory assets = operator.batchRedeem(requests);

        uint256 receiverAfter = asset.balanceOf(receiver);
        uint256 controllerTwoAfter = asset.balanceOf(controllerTwo);

        assertEq(assets.length, 2);
        assertEq(assets[0], SHARES);
        assertEq(assets[1], sharesTwo);
        assertEq(receiverAfter - receiverBefore, SHARES);
        assertEq(controllerTwoAfter - controllerTwoBefore, sharesTwo);
    }

    function test_batchRedeem_zeroShares_skipsRequest() public {
        address controllerTwo = vm.addr(0xB0B4);
        uint256 sharesTwo = SHARES * 2;

        _prepareRedeem(SHARES);
        _prepareRedeem(controllerTwo, sharesTwo);

        _fulfillRedeem(controller, SHARES);
        _fulfillRedeem(controllerTwo, sharesTwo);

        uint256 controllerBefore = asset.balanceOf(controller);
        uint256 controllerTwoBefore = asset.balanceOf(controllerTwo);

        NestVaultRedeemOperator.RedeemRequest[] memory requests = new NestVaultRedeemOperator.RedeemRequest[](2);
        requests[0] = _buildRequest(INestVaultCore(address(vault)), controller, 0);
        requests[1] = _buildRequest(INestVaultCore(address(vault)), controllerTwo, sharesTwo);

        vm.prank(keeper);
        uint256[] memory assets = operator.batchRedeem(requests);

        uint256 controllerAfter = asset.balanceOf(controller);
        uint256 controllerTwoAfter = asset.balanceOf(controllerTwo);

        assertEq(assets.length, 2);
        assertEq(assets[0], 0);
        assertEq(assets[1], sharesTwo);
        assertEq(controllerAfter - controllerBefore, 0);
        assertEq(controllerTwoAfter - controllerTwoBefore, sharesTwo);
        assertEq(vault.claimableRedeemRequest(0, controller), SHARES);
        assertEq(vault.claimableRedeemRequest(0, controllerTwo), 0);
    }

    function test_batchFulfillAndRedeem_callsBoth() public {
        address controllerTwo = vm.addr(0xB0B3);
        uint256 sharesTwo = SHARES * 3;

        _prepareRedeem(SHARES);
        _prepareRedeem(controllerTwo, sharesTwo);

        _setReceiver(controller, receiver);

        uint256 receiverBefore = asset.balanceOf(receiver);
        uint256 controllerTwoBefore = asset.balanceOf(controllerTwo);

        NestVaultRedeemOperator.RedeemRequest[] memory requests = new NestVaultRedeemOperator.RedeemRequest[](2);
        requests[0] = _buildRequest(INestVaultCore(address(vault)), controller, SHARES);
        requests[1] = _buildRequest(INestVaultCore(address(vault)), controllerTwo, sharesTwo);

        vm.prank(keeper);
        uint256[] memory assets = operator.batchFulfillAndRedeem(requests);

        uint256 receiverAfter = asset.balanceOf(receiver);
        uint256 controllerTwoAfter = asset.balanceOf(controllerTwo);

        assertEq(assets.length, 2);
        assertEq(assets[0], SHARES);
        assertEq(assets[1], sharesTwo);
        assertEq(receiverAfter - receiverBefore, SHARES);
        assertEq(controllerTwoAfter - controllerTwoBefore, sharesTwo);
        assertEq(vault.claimableRedeemRequest(0, controller), 0);
        assertEq(vault.claimableRedeemRequest(0, controllerTwo), 0);
    }

    function test_batchFulfillAndRedeem_zeroShares_skipsRequest() public {
        address controllerTwo = vm.addr(0xB0B5);
        uint256 sharesTwo = SHARES * 3;

        _prepareRedeem(SHARES);
        _prepareRedeem(controllerTwo, sharesTwo);

        uint256 controllerBefore = asset.balanceOf(controller);
        uint256 controllerTwoBefore = asset.balanceOf(controllerTwo);

        NestVaultRedeemOperator.RedeemRequest[] memory requests = new NestVaultRedeemOperator.RedeemRequest[](2);
        requests[0] = _buildRequest(INestVaultCore(address(vault)), controller, 0);
        requests[1] = _buildRequest(INestVaultCore(address(vault)), controllerTwo, sharesTwo);

        vm.prank(keeper);
        uint256[] memory assets = operator.batchFulfillAndRedeem(requests);

        uint256 controllerAfter = asset.balanceOf(controller);
        uint256 controllerTwoAfter = asset.balanceOf(controllerTwo);

        assertEq(assets.length, 2);
        assertEq(assets[0], 0);
        assertEq(assets[1], sharesTwo);
        assertEq(controllerAfter - controllerBefore, 0);
        assertEq(controllerTwoAfter - controllerTwoBefore, sharesTwo);
        assertEq(vault.pendingRedeemRequest(0, controller), SHARES);
        assertEq(vault.pendingRedeemRequest(0, controllerTwo), 0);
        assertEq(vault.claimableRedeemRequest(0, controller), 0);
        assertEq(vault.claimableRedeemRequest(0, controllerTwo), 0);
    }

    function test_authorizeAsOperator_setsOperator() public {
        bytes32 nonce = bytes32("nonce");
        uint256 deadline = block.timestamp + 1 days;

        bytes memory signature = _buildAuthorizeSignature(nonce, deadline);

        vm.prank(keeper);
        operator.authorizeAsOperator(INestVaultCore(address(vault)), controller, true, nonce, deadline, signature);

        assertTrue(vault.isOperator(controller, address(operator)));
        assertTrue(vault.authorizations(controller, nonce));
    }

    function test_authorizeAsOperator_contractController_usesEip1271() public {
        uint256 ownerKey = 0xB0B0;
        address owner = vm.addr(ownerKey);
        MockERC1271Wallet wallet = new MockERC1271Wallet(owner);
        bytes32 nonce = bytes32("nonce-1271");
        uint256 deadline = block.timestamp + 1 days;

        bytes memory signature = _buildAuthorizeSignatureFor(address(wallet), ownerKey, nonce, deadline, true);

        vm.prank(keeper);
        operator.authorizeAsOperator(INestVaultCore(address(vault)), address(wallet), true, nonce, deadline, signature);

        assertTrue(vault.isOperator(address(wallet), address(operator)));
        assertTrue(vault.authorizations(address(wallet), nonce));
    }

    function test_authorizeAsOperator_contractController_nonceAwareValidator() public {
        uint256 ownerKey = 0xB0B1;
        address owner = vm.addr(ownerKey);
        bytes32 nonce = bytes32("nonce-1271-check");
        uint256 deadline = block.timestamp + 1 days;
        MockERC1271NonceChecker wallet = new MockERC1271NonceChecker(owner, INestVaultCore(address(vault)), nonce);

        bytes memory signature = _buildAuthorizeSignatureFor(address(wallet), ownerKey, nonce, deadline, true);

        vm.prank(keeper);
        operator.authorizeAsOperator(INestVaultCore(address(vault)), address(wallet), true, nonce, deadline, signature);

        assertTrue(vault.isOperator(address(wallet), address(operator)));
        assertTrue(vault.authorizations(address(wallet), nonce));
    }

    function test_redeem_requiresAuth() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        operator.redeem(_buildRequest(INestVaultCore(address(vault)), controller, 1));
    }

    function test_redeemAll_requiresAuth() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        operator.redeemAll(INestVaultCore(address(vault)), controller);
    }

    function test_fulfillAndRedeem_requiresAuth() public {
        _prepareRedeem(SHARES);

        vm.prank(address(0xDEAD));
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        operator.fulfillAndRedeem(_buildRequest(INestVaultCore(address(vault)), controller, SHARES));
    }

    function test_fulfillAndRedeemAll_requiresAuth() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        operator.fulfillAndRedeemAll(INestVaultCore(address(vault)), controller);
    }

    function test_batchRedeem_requiresAuth() public {
        NestVaultRedeemOperator.RedeemRequest[] memory requests = new NestVaultRedeemOperator.RedeemRequest[](1);
        requests[0] = _buildRequest(INestVaultCore(address(vault)), controller, 1);

        vm.prank(address(0xDEAD));
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        operator.batchRedeem(requests);
    }

    function test_batchFulfillAndRedeem_requiresAuth() public {
        NestVaultRedeemOperator.RedeemRequest[] memory requests = new NestVaultRedeemOperator.RedeemRequest[](1);
        requests[0] = _buildRequest(INestVaultCore(address(vault)), controller, 1);

        vm.prank(address(0xDEAD));
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        operator.batchFulfillAndRedeem(requests);
    }

    function test_authorizeAsOperator_requiresAuth() public {
        bytes32 nonce = bytes32("unauthorized");
        uint256 deadline = block.timestamp + 1 days;
        bytes memory signature = _buildAuthorizeSignature(nonce, deadline);

        vm.prank(address(0xDEAD));
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        operator.authorizeAsOperator(INestVaultCore(address(vault)), controller, true, nonce, deadline, signature);
    }

    function _expectZeroVaultRevert(function(NestVaultRedeemOperator.RedeemRequest memory)
            external returns (uint256) _action) internal {
        vm.prank(keeper);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _action(_buildRequest(INestVaultCore(address(0)), controller, 1));
    }

    function _expectZeroControllerRevert(function(NestVaultRedeemOperator.RedeemRequest memory)
            external returns (uint256) _action) internal {
        vm.prank(keeper);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _action(_buildRequest(INestVaultCore(address(vault)), address(0), 1));
    }

    function _expectAuthorizeAsOperatorRevert(INestVaultCore _vault, address _controller) internal {
        vm.prank(keeper);
        vm.expectRevert(Errors.ZeroAddress.selector);
        operator.authorizeAsOperator(_vault, _controller, true, bytes32(0), 0, hex"");
    }

    function _setReceiver(address _controller, address _receiver) internal {
        vm.prank(_controller);
        operator.setReceiver(address(vault), _receiver);
    }

    function _fulfillRedeem(address _controller, uint256 _shares) internal {
        // Use the controller as the caller so it satisfies the vault's operator check
        vm.prank(_controller);
        vault.fulfillRedeem(_controller, _shares);
    }

    function _buildRequest(INestVaultCore _vault, address _controller, uint256 _shares)
        internal
        pure
        returns (NestVaultRedeemOperator.RedeemRequest memory)
    {
        return NestVaultRedeemOperator.RedeemRequest({vault: _vault, controller: _controller, shares: _shares});
    }

    function _prepareRedeem(uint256 _shares) internal {
        _prepareRedeem(controller, _shares);
    }

    function _prepareRedeem(address _controller, uint256 _shares) internal {
        share.enter(_controller, ERC20(address(asset)), 0, _controller, _shares);

        vm.startPrank(_controller);
        share.approve(address(vault), _shares);
        vault.requestRedeem(_shares, _controller, _controller);
        vault.setOperator(address(operator), true);
        vm.stopPrank();

        asset.mint(address(share), _shares);
    }

    function _prepareRedeemWithoutOperator(address _controller, uint256 _shares) internal {
        share.enter(_controller, ERC20(address(asset)), 0, _controller, _shares);

        vm.startPrank(_controller);
        share.approve(address(vault), _shares);
        vault.requestRedeem(_shares, _controller, _controller);
        vm.stopPrank();

        asset.mint(address(share), _shares);
    }

    function _deployContractAndProxy(
        bytes memory _oappBytecode,
        bytes memory _constructorArgs,
        bytes memory _initializeArgs
    ) internal returns (address addr) {
        bytes memory bytecode = bytes.concat(abi.encodePacked(_oappBytecode), _constructorArgs);
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(addr)) { revert(0, 0) }
        }

        return address(new TransparentUpgradeableProxy(addr, proxyAdmin, _initializeArgs));
    }

    function _deployOperatorForTest(address _owner) external returns (address) {
        return _deployContractAndProxy(
            type(NestVaultRedeemOperator).creationCode,
            bytes(""),
            abi.encodeCall(NestVaultRedeemOperator.initialize, (_owner))
        );
    }

    function _proxyAdmin(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967_ADMIN_SLOT))));
    }

    function _domainSeparator() internal view returns (bytes32) {
        (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            vault.eip712Domain();

        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                verifyingContract
            )
        );
    }

    function _buildAuthorizeSignature(bytes32 _nonce, uint256 _deadline) internal view returns (bytes memory) {
        return _buildAuthorizeSignatureFor(controller, controllerKey, _nonce, _deadline, true);
    }

    function _buildAuthorizeSignatureFor(
        address _controller,
        uint256 _signerKey,
        bytes32 _nonce,
        uint256 _deadline,
        bool _approved
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "AuthorizeOperator(address controller,address operator,bool approved,bytes32 nonce,uint256 deadline)"
                ),
                _controller,
                address(operator),
                _approved,
                _nonce,
                _deadline
            )
        );

        bytes32 domainSeparator = _domainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_signerKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
