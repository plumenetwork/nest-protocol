// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IOFT, SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {OFTAdapterUpgradeableMock} from "@layerzerolabs/oft-evm-upgradeable/test/mocks/OFTAdapterUpgradeableMock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {MessagingFee} from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTCoreUpgradeable.sol";
import {IVaultComposerSync} from "@layerzerolabs/ovault-evm/contracts/interfaces/IVaultComposerSync.sol";

import {MockMintBurnToken} from "test/mock/cctp/MockMintAndBurnToken.sol";
import {MockNestShareOFT} from "test/mock/MockNestShareOFT.sol";
import {NestShareOFT} from "contracts/NestShareOFT.sol";
import {MockNestVault} from "test/mock/MockNestVault.sol";
import {NestVault} from "contracts/NestVault.sol";
import {MockNestVaultOFT} from "test/mock/MockNestVaultOFT.sol";
import {NestVaultOFT} from "contracts/NestVaultOFT.sol";
import {MockBoringVault} from "test/mock/MockBoringVault.sol";
import {MockRateProvider} from "test/mock/MockRateProvider.sol";
import {MockAuthority} from "test/mock/MockAuthority.sol";
import {MockServiceManager} from "test/mock/MockServiceManager.sol";
import {NestVaultPredicateProxy, PredicateMessage} from "contracts/NestVaultPredicateProxy.sol";
import {NestVaultComposer} from "contracts/ovault/NestVaultComposer.sol";
import {NestVaultCoreTypes} from "contracts/libraries/nest-vault/NestVaultCoreTypes.sol";
import {Errors} from "contracts/types/Errors.sol";
import {Authority} from "@solmate/auth/Auth.sol";

abstract contract NestVaultComposerTestBase is TestHelperOz5 {
    address internal proxyAdmin;

    function _deployContractAndProxy(
        bytes memory _oappBytecode,
        bytes memory _constructorArgs,
        bytes memory _initializeArgs
    ) internal returns (address addr) {
        bytes memory bytecode = bytes.concat(abi.encodePacked(_oappBytecode), _constructorArgs);
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }

        return address(new TransparentUpgradeableProxy(addr, proxyAdmin, _initializeArgs));
    }

    function _formatPredicateMessage(
        string memory _taskId,
        uint256 _expireByTime,
        address[] memory _signerAddresses,
        bytes[] memory _signatures
    ) internal pure returns (bytes memory _message) {
        PredicateMessage memory _msg = PredicateMessage({
            taskId: _taskId, expireByTime: _expireByTime, signerAddresses: _signerAddresses, signatures: _signatures
        });

        _message = abi.encode(_msg);
    }
}

contract NestVaultComposerNestShareOFTTest is NestVaultComposerTestBase {
    using OptionsBuilder for bytes;

    uint32 internal constant LOCAL_EID = 1;
    uint32 internal constant REMOTE_EID = 2;
    string internal constant POLICY_ID = "TEST_POLICY_ID";

    MockRateProvider internal accountant;
    MockMintBurnToken internal asset;
    OFTAdapterUpgradeableMock internal assetOFT;
    MockNestShareOFT internal shareOFT;
    MockNestShareOFT internal remoteShareOFT;
    MockNestVault internal vault;
    NestVaultComposer internal composer;
    NestVaultPredicateProxy internal predicateProxy;
    MockServiceManager internal serviceManager;
    MockAuthority internal mockAuthority;

    address internal userA = makeAddr("userA");
    address internal userB = makeAddr("userB");

    function setUp() public virtual override {
        vm.deal(userA, 1000 ether);
        vm.deal(userB, 1000 ether);

        accountant = new MockRateProvider();
        accountant.setRate(1e6);

        asset = new MockMintBurnToken("USDC", "USDC", 6);

        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);

        proxyAdmin = makeAddr("proxyAdmin");

        shareOFT = MockNestShareOFT(
            _deployContractAndProxy(
                type(MockNestShareOFT).creationCode,
                abi.encode(address(endpoints[LOCAL_EID])),
                abi.encodeWithSelector(
                    NestShareOFT.initialize.selector, "Nest Share", "nSHARE", address(this), address(this)
                )
            )
        );

        remoteShareOFT = MockNestShareOFT(
            _deployContractAndProxy(
                type(MockNestShareOFT).creationCode,
                abi.encode(address(endpoints[REMOTE_EID])),
                abi.encodeWithSelector(
                    NestShareOFT.initialize.selector, "Nest Share", "nSHARE", address(this), address(this)
                )
            )
        );

        vault = MockNestVault(
            _deployContractAndProxy(
                type(MockNestVault).creationCode,
                abi.encode(payable(address(shareOFT))),
                abi.encodeWithSelector(
                    NestVault.initialize.selector, address(accountant), address(asset), address(this), 1, address(0)
                )
            )
        );

        assetOFT = OFTAdapterUpgradeableMock(
            _deployContractAndProxy(
                type(OFTAdapterUpgradeableMock).creationCode,
                abi.encode(address(asset), address(endpoints[LOCAL_EID])),
                abi.encodeWithSelector(OFTAdapterUpgradeableMock.initialize.selector, address(this))
            )
        );

        serviceManager = new MockServiceManager();
        serviceManager.setIsVerified(true);

        predicateProxy = NestVaultPredicateProxy(
            _deployContractAndProxy(
                type(NestVaultPredicateProxy).creationCode,
                bytes(""),
                abi.encodeWithSelector(
                    NestVaultPredicateProxy.initialize.selector, address(this), address(serviceManager), POLICY_ID
                )
            )
        );

        composer = NestVaultComposer(
            payable(_deployContractAndProxy(
                    type(NestVaultComposer).creationCode,
                    abi.encode(address(predicateProxy)),
                    abi.encodeWithSelector(
                        NestVaultComposer.initialize.selector,
                        address(this),
                        address(vault),
                        address(assetOFT),
                        address(shareOFT),
                        0
                    )
                ))
        );

        mockAuthority = new MockAuthority(true);
        shareOFT.setAuthority(Authority(address(mockAuthority)));
        remoteShareOFT.setAuthority(Authority(address(mockAuthority)));
        vault.setAuthority(Authority(address(mockAuthority)));
        predicateProxy.setAuthority(Authority(address(mockAuthority)));
        composer.setAuthority(Authority(address(mockAuthority)));

        address[] memory ofts = new address[](2);
        ofts[0] = address(shareOFT);
        ofts[1] = address(remoteShareOFT);
        this.wireOApps(ofts);
    }

    function test_unit_initialize_setsShareVaultApproval_whenShareOftIsNestShareOFT() public view {
        uint256 max = type(uint256).max;

        assertEq(composer.SHARE_OFT(), address(shareOFT));
        assertTrue(composer.SHARE_OFT() != address(vault));

        assertEq(IERC20(address(asset)).allowance(address(composer), address(predicateProxy)), max);
        assertEq(IERC20(address(asset)).allowance(address(composer), address(vault)), max);
        assertEq(IERC20(address(asset)).allowance(address(composer), address(assetOFT)), max);
        assertEq(IERC20(address(shareOFT)).allowance(address(composer), address(vault)), max);
        assertFalse(IOFT(address(shareOFT)).approvalRequired());
    }

    function test_integration_depositAndSend_local_mintsShares() public {
        uint256 depositAmount = 1e6;

        asset.mint(userA, depositAmount);

        vm.prank(userA);
        asset.approve(address(composer), depositAmount);

        bytes memory predicateMsg = _formatPredicateMessage("", 0, new address[](0), new bytes[](0));

        SendParam memory sendParam = SendParam({
            dstEid: composer.VAULT_EID(),
            to: addressToBytes32(userB),
            amountLD: 0,
            minAmountLD: 0,
            extraOptions: new bytes(0),
            composeMsg: new bytes(0),
            oftCmd: predicateMsg
        });

        uint256 expectedShares = vault.previewDeposit(depositAmount);

        vm.prank(userA);
        composer.depositAndSend(addressToBytes32(userA), depositAmount, sendParam, userA);

        assertEq(shareOFT.balanceOf(userB), expectedShares);
    }

    function test_integration_depositAndSend_remote_bridgesShares_withNestShareOFT() public {
        uint256 depositAmount = 1e6;

        asset.mint(userA, depositAmount);

        vm.prank(userA);
        asset.approve(address(composer), depositAmount);

        bytes memory predicateMsg = _formatPredicateMessage("", 0, new address[](0), new bytes[](0));
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        uint256 expectedShares = vault.previewDeposit(depositAmount);

        SendParam memory sendParam = SendParam({
            dstEid: REMOTE_EID,
            to: addressToBytes32(userB),
            amountLD: 1,
            minAmountLD: expectedShares,
            extraOptions: options,
            composeMsg: new bytes(0),
            oftCmd: predicateMsg
        });

        SendParam memory quoteParam = sendParam;
        quoteParam.amountLD = expectedShares;
        quoteParam.minAmountLD = 0;
        MessagingFee memory fee = shareOFT.quoteSend(quoteParam, false);

        vm.prank(userA);
        composer.depositAndSend{value: fee.nativeFee}(addressToBytes32(userA), depositAmount, sendParam, userA);

        verifyPackets(REMOTE_EID, addressToBytes32(address(remoteShareOFT)));

        assertEq(remoteShareOFT.balanceOf(userB), expectedShares);
    }

    function test_integration_depositAndSend_reverts_on_slippage_withNestShareOFT() public {
        uint256 depositAmount = 1e6;

        asset.mint(userA, depositAmount);

        vm.prank(userA);
        asset.approve(address(composer), depositAmount);

        bytes memory predicateMsg = _formatPredicateMessage("", 0, new address[](0), new bytes[](0));
        uint256 expectedShares = vault.previewDeposit(depositAmount);

        SendParam memory sendParam = SendParam({
            dstEid: composer.VAULT_EID(),
            to: addressToBytes32(userB),
            amountLD: 0,
            minAmountLD: expectedShares + 1,
            extraOptions: new bytes(0),
            composeMsg: new bytes(0),
            oftCmd: predicateMsg
        });

        vm.prank(userA);
        vm.expectRevert(
            abi.encodeWithSelector(IVaultComposerSync.SlippageExceeded.selector, expectedShares, expectedShares + 1)
        );
        composer.depositAndSend(addressToBytes32(userA), depositAmount, sendParam, userA);
    }

    function test_integration_redeemAndSend_instantRedeem_withNestShareOFT() public {
        uint256 depositAmount = 1e6;

        asset.mint(userA, depositAmount);

        vm.startPrank(userA);
        asset.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, userA);
        shareOFT.approve(address(composer), shares);
        vm.stopPrank();

        (uint256 expectedAssets,) = vault.previewInstantRedeem(shares);

        SendParam memory sendParam = SendParam({
            dstEid: composer.VAULT_EID(),
            to: addressToBytes32(userB),
            amountLD: 0,
            minAmountLD: 0,
            extraOptions: new bytes(0),
            composeMsg: new bytes(0),
            oftCmd: new bytes(0)
        });

        uint256 receiverBalanceBefore = asset.balanceOf(userB);

        vm.prank(userA);
        composer.redeemAndSend(addressToBytes32(userA), shares, sendParam, userA);

        assertEq(asset.balanceOf(userB) - receiverBalanceBefore, expectedAssets);
    }
}

contract NestVaultComposerNestVaultOFTTest is NestVaultComposerTestBase {
    using OptionsBuilder for bytes;

    uint32 internal constant LOCAL_EID = 1;
    uint32 internal constant REMOTE_EID = 2;
    string internal constant POLICY_ID = "TEST_POLICY_ID";

    MockRateProvider internal accountant;
    MockMintBurnToken internal asset;
    OFTAdapterUpgradeableMock internal assetOFT;
    MockBoringVault internal share;
    MockBoringVault internal remoteShare;
    MockNestVaultOFT internal vaultOFT;
    MockNestVaultOFT internal remoteVaultOFT;
    NestVaultComposer internal composer;
    NestVaultPredicateProxy internal predicateProxy;
    MockServiceManager internal serviceManager;
    MockAuthority internal mockAuthority;

    address internal userA = makeAddr("userA");
    address internal userB = makeAddr("userB");

    function setUp() public virtual override {
        vm.deal(userA, 1000 ether);
        vm.deal(userB, 1000 ether);

        accountant = new MockRateProvider();
        accountant.setRate(1e6);

        asset = new MockMintBurnToken("USDC", "USDC", 6);
        share = new MockBoringVault("Boring Share", "bSHARE", 6);

        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);

        proxyAdmin = makeAddr("proxyAdmin");

        assetOFT = OFTAdapterUpgradeableMock(
            _deployContractAndProxy(
                type(OFTAdapterUpgradeableMock).creationCode,
                abi.encode(address(asset), address(endpoints[LOCAL_EID])),
                abi.encodeWithSelector(OFTAdapterUpgradeableMock.initialize.selector, address(this))
            )
        );

        vaultOFT = MockNestVaultOFT(
            _deployContractAndProxy(
                type(MockNestVaultOFT).creationCode,
                abi.encode(address(payable(share)), address(endpoints[LOCAL_EID])),
                abi.encodeWithSelector(
                    NestVaultOFT.initialize.selector,
                    address(accountant),
                    address(asset),
                    address(this),
                    address(this),
                    1,
                    address(0)
                )
            )
        );

        remoteShare = new MockBoringVault("Boring Share", "bSHARE", 6);

        remoteVaultOFT = MockNestVaultOFT(
            _deployContractAndProxy(
                type(MockNestVaultOFT).creationCode,
                abi.encode(address(payable(remoteShare)), address(endpoints[REMOTE_EID])),
                abi.encodeWithSelector(
                    NestVaultOFT.initialize.selector,
                    address(accountant),
                    address(asset),
                    address(this),
                    address(this),
                    1,
                    address(0)
                )
            )
        );

        serviceManager = new MockServiceManager();
        serviceManager.setIsVerified(true);

        predicateProxy = NestVaultPredicateProxy(
            _deployContractAndProxy(
                type(NestVaultPredicateProxy).creationCode,
                bytes(""),
                abi.encodeWithSelector(
                    NestVaultPredicateProxy.initialize.selector, address(this), address(serviceManager), POLICY_ID
                )
            )
        );

        composer = NestVaultComposer(
            payable(_deployContractAndProxy(
                    type(NestVaultComposer).creationCode,
                    abi.encode(address(predicateProxy)),
                    abi.encodeWithSelector(
                        NestVaultComposer.initialize.selector,
                        address(this),
                        address(vaultOFT),
                        address(assetOFT),
                        address(vaultOFT),
                        0
                    )
                ))
        );

        mockAuthority = new MockAuthority(true);
        vaultOFT.setAuthority(Authority(address(mockAuthority)));
        predicateProxy.setAuthority(Authority(address(mockAuthority)));
        composer.setAuthority(Authority(address(mockAuthority)));

        address[] memory ofts = new address[](2);
        ofts[0] = address(vaultOFT);
        ofts[1] = address(remoteVaultOFT);
        this.wireOApps(ofts);
    }

    function test_unit_initialize_setsShareVaultApproval_whenShareOftIsVault() public view {
        uint256 max = type(uint256).max;

        assertEq(composer.SHARE_OFT(), address(vaultOFT));

        address shareToken = IOFT(address(vaultOFT)).token();
        assertEq(IERC20(shareToken).allowance(address(composer), address(vaultOFT)), max);

        assertEq(IERC20(address(asset)).allowance(address(composer), address(predicateProxy)), max);
        assertEq(IERC20(address(asset)).allowance(address(composer), address(vaultOFT)), max);
        assertEq(IERC20(address(asset)).allowance(address(composer), address(assetOFT)), max);
    }

    function test_integration_redeemAndSend_instantRedeem_withBoringVault() public {
        uint256 depositAmount = 1e6;

        asset.mint(userA, depositAmount);

        vm.startPrank(userA);
        asset.approve(address(vaultOFT), depositAmount);
        uint256 shares = vaultOFT.deposit(depositAmount, userA);
        share.approve(address(composer), shares);
        vm.stopPrank();

        (uint256 expectedAssets,) = vaultOFT.previewInstantRedeem(shares);

        SendParam memory sendParam = SendParam({
            dstEid: composer.VAULT_EID(),
            to: addressToBytes32(userB),
            amountLD: 0,
            minAmountLD: 0,
            extraOptions: new bytes(0),
            composeMsg: new bytes(0),
            oftCmd: new bytes(0)
        });

        uint256 receiverBalanceBefore = asset.balanceOf(userB);

        vm.prank(userA);
        composer.redeemAndSend(addressToBytes32(userA), shares, sendParam, userA);

        assertEq(asset.balanceOf(userB) - receiverBalanceBefore, expectedAssets);
    }

    function test_integration_depositAndSend_remote_bridgesShares_withBoringVault() public {
        uint256 depositAmount = 1e6;

        asset.mint(userA, depositAmount);

        vm.prank(userA);
        asset.approve(address(composer), depositAmount);

        bytes memory predicateMsg = _formatPredicateMessage("", 0, new address[](0), new bytes[](0));
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        uint256 expectedShares = vaultOFT.previewDeposit(depositAmount);

        SendParam memory sendParam = SendParam({
            dstEid: REMOTE_EID,
            to: addressToBytes32(userB),
            amountLD: 1,
            minAmountLD: expectedShares,
            extraOptions: options,
            composeMsg: new bytes(0),
            oftCmd: predicateMsg
        });

        SendParam memory quoteParam = sendParam;
        quoteParam.amountLD = expectedShares;
        quoteParam.minAmountLD = 0;
        MessagingFee memory fee = IOFT(address(vaultOFT)).quoteSend(quoteParam, false);

        vm.prank(userA);
        composer.depositAndSend{value: fee.nativeFee}(addressToBytes32(userA), depositAmount, sendParam, userA);

        verifyPackets(REMOTE_EID, addressToBytes32(address(remoteVaultOFT)));

        assertEq(remoteShare.balanceOf(userB), expectedShares);
    }

    function test_integration_depositAndSend_reverts_on_slippage_withVaultOFT() public {
        uint256 depositAmount = 1e6;

        asset.mint(userA, depositAmount);

        vm.prank(userA);
        asset.approve(address(composer), depositAmount);

        bytes memory predicateMsg = _formatPredicateMessage("", 0, new address[](0), new bytes[](0));
        uint256 expectedShares = vaultOFT.previewDeposit(depositAmount);

        SendParam memory sendParam = SendParam({
            dstEid: composer.VAULT_EID(),
            to: addressToBytes32(userB),
            amountLD: 0,
            minAmountLD: expectedShares + 1,
            extraOptions: new bytes(0),
            composeMsg: new bytes(0),
            oftCmd: predicateMsg
        });

        vm.prank(userA);
        vm.expectRevert(
            abi.encodeWithSelector(IVaultComposerSync.SlippageExceeded.selector, expectedShares, expectedShares + 1)
        );
        composer.depositAndSend(addressToBytes32(userA), depositAmount, sendParam, userA);
    }
}

/// @dev Harness exposing the compose-only `_requestRedeem` so a pending bucket can be seeded directly.
///      Everything under test (`_updateRequestRedeemAndSend`, `_fulfillRedeem`) is the inherited code.
contract HarnessComposer is NestVaultComposer {
    constructor(address _predicateProxy) NestVaultComposer(_predicateProxy) {}

    function harnessRequestRedeem(uint32 _srcEid, bytes32 _redeemer, bytes32 _receiver, uint256 _shares) external {
        SendParam memory sp;
        sp.to = _receiver;
        _requestRedeem(_srcEid, _redeemer, sp, _shares);
    }
}

/// @notice Regression tests for the async-redeem update path: `_updateRequestRedeemAndSend` must drive
///         `updateRedeem` off the vault's LIVE pending, so a controller-level skew (direct external
///         vault.requestRedeem / fulfillRedeem) neither leaks shares to the pool nor over-returns, and
///         composer fulfilment keeps working afterward.
contract NestVaultComposerAsyncSkewTest is NestVaultComposerTestBase {
    uint32 internal constant LOCAL_EID = 1;
    string internal constant POLICY_ID = "TEST_POLICY_ID";

    MockRateProvider internal accountant;
    MockMintBurnToken internal asset;
    OFTAdapterUpgradeableMock internal assetOFT;
    MockNestShareOFT internal shareOFT;
    MockNestVault internal vault;
    HarnessComposer internal composer;
    NestVaultPredicateProxy internal predicateProxy;
    MockServiceManager internal serviceManager;
    MockAuthority internal mockAuthority;

    address internal userA = makeAddr("userA");
    address internal userB = makeAddr("userB");
    address internal attacker = makeAddr("attacker");

    bytes32 internal redeemerA;
    bytes32 internal redeemerB;

    function setUp() public virtual override {
        redeemerA = addressToBytes32(userA);
        redeemerB = addressToBytes32(userB);

        accountant = new MockRateProvider();
        accountant.setRate(1e6);
        asset = new MockMintBurnToken("USDC", "USDC", 6);

        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);
        proxyAdmin = makeAddr("proxyAdmin");

        shareOFT = MockNestShareOFT(
            _deployContractAndProxy(
                type(MockNestShareOFT).creationCode,
                abi.encode(address(endpoints[LOCAL_EID])),
                abi.encodeWithSelector(
                    NestShareOFT.initialize.selector, "Nest Share", "nSHARE", address(this), address(this)
                )
            )
        );

        vault = MockNestVault(
            _deployContractAndProxy(
                type(MockNestVault).creationCode,
                abi.encode(payable(address(shareOFT))),
                abi.encodeWithSelector(
                    NestVault.initialize.selector, address(accountant), address(asset), address(this), 1, address(0)
                )
            )
        );

        assetOFT = OFTAdapterUpgradeableMock(
            _deployContractAndProxy(
                type(OFTAdapterUpgradeableMock).creationCode,
                abi.encode(address(asset), address(endpoints[LOCAL_EID])),
                abi.encodeWithSelector(OFTAdapterUpgradeableMock.initialize.selector, address(this))
            )
        );

        serviceManager = new MockServiceManager();
        serviceManager.setIsVerified(true);

        predicateProxy = NestVaultPredicateProxy(
            _deployContractAndProxy(
                type(NestVaultPredicateProxy).creationCode,
                bytes(""),
                abi.encodeWithSelector(
                    NestVaultPredicateProxy.initialize.selector, address(this), address(serviceManager), POLICY_ID
                )
            )
        );

        composer = HarnessComposer(
            payable(_deployContractAndProxy(
                    type(HarnessComposer).creationCode,
                    abi.encode(address(predicateProxy)),
                    abi.encodeWithSelector(
                        NestVaultComposer.initialize.selector,
                        address(this),
                        address(vault),
                        address(assetOFT),
                        address(shareOFT),
                        0
                    )
                ))
        );

        mockAuthority = new MockAuthority(true);
        shareOFT.setAuthority(Authority(address(mockAuthority)));
        vault.setAuthority(Authority(address(mockAuthority)));
        predicateProxy.setAuthority(Authority(address(mockAuthority)));
        composer.setAuthority(Authority(address(mockAuthority)));
    }

    /// @dev Deposit `_assets` for `_user` and seed a composer pending bucket of the resulting shares.
    function _seedPending(address _user, bytes32 _redeemer, uint256 _assets) internal returns (uint256 shares) {
        asset.mint(_user, _assets);
        vm.startPrank(_user);
        asset.approve(address(vault), _assets);
        shares = vault.deposit(_assets, _user);
        // Composer must hold the shares before requestRedeem pulls them into the vault as pending.
        IERC20(address(shareOFT)).transfer(address(composer), shares);
        vm.stopPrank();
        composer.harnessRequestRedeem(LOCAL_EID, _redeemer, _redeemer, shares);
    }

    function _localSend(bytes32 _to, uint256 _amountLD) internal view returns (SendParam memory sp) {
        sp.dstEid = composer.VAULT_EID();
        sp.to = _to;
        sp.amountLD = _amountLD;
    }

    // Scenario A: livePending < totalPendingSharesSum (direct external vault.fulfillRedeem)

    /// @notice A full cancel after a direct external fulfill returns EXACTLY the bucket amount (no leak/over-return),
    ///         and B's composer fulfilment still attributes the externally-fulfilled claimable.
    function test_update_underDirectFulfillSkew_returnsExact_andFulfilmentStillWorks() public {
        uint256 sharesA = _seedPending(userA, redeemerA, 100e6);
        uint256 sharesB = _seedPending(userB, redeemerB, 100e6);

        uint256 pc = composer.totalPendingSharesSum();
        assertEq(pc, sharesA + sharesB, "pre: Pc == sum");
        assertEq(vault.pendingRedeemRequest(0, address(composer)), pc, "pre: synced Pv==Pc");

        // Direct external fulfill of `sharesA` worth: vault pending drops, composer aggregate stays stale => Pv < Pc.
        vault.fulfillRedeem(address(composer), sharesA);
        uint256 pv = vault.pendingRedeemRequest(0, address(composer));
        assertEq(pv, pc - sharesA, "skew: Pv == Pc - d");
        assertLt(pv, composer.totalPendingSharesSum(), "skew: Pv < Pc");

        // A fully cancels its bucket. pv (== sharesB == sharesA) covers the reduction, so it must NOT revert.
        uint256 balBefore = IERC20(address(shareOFT)).balanceOf(userA);
        composer.updateRequestRedeemAndSend(LOCAL_EID, redeemerA, _localSend(redeemerA, 0), userA);

        // A got back EXACTLY its bucket (sharesA), not r-D (leak) and not r+extra (over-return).
        assertEq(IERC20(address(shareOFT)).balanceOf(userA) - balBefore, sharesA, "A returned exactly bucket");
        assertEq(composer.pendingRedeem(redeemerA, redeemerA, LOCAL_EID).shares, 0, "A bucket cleared");

        // Composer fulfilment is NOT broken: B's fulfill picks up the unaccounted external claimable.
        composer.fulfillRedeem(LOCAL_EID, redeemerB, redeemerB, sharesB);
        NestVaultCoreTypes.ClaimableRedeem memory clB = composer.claimableRedeem(redeemerB, redeemerB, LOCAL_EID);
        assertEq(clB.shares, sharesB, "B claimable shares credited");
        assertGt(clB.assets, 0, "B claimable assets credited");

        // And B can finish end-to-end (assets delivered locally).
        uint256 assetBefore = asset.balanceOf(userB);
        composer.finishRedeemAndSend(LOCAL_EID, redeemerB, _localSend(redeemerB, sharesB), userB);
        assertEq(asset.balanceOf(userB) - assetBefore, clB.assets, "B received fulfilled assets");
    }

    /// @notice When a direct external fulfill drained the bucket's shares away, update fails closed (must claim),
    ///         leaving the bucket intact rather than leaking shares.
    function test_update_underDirectFulfillSkew_failsClosedWhenFulfilledAway() public {
        uint256 sharesA = _seedPending(userA, redeemerA, 100e6);

        // Fulfill ALL of A's pending directly: Pv == 0, but A's composer bucket still reads `sharesA`.
        vault.fulfillRedeem(address(composer), sharesA);
        assertEq(vault.pendingRedeemRequest(0, address(composer)), 0, "Pv drained to 0");

        // A tries to cancel: live pending can't honor it -> fail closed, bucket untouched.
        // Build the SendParam first so vm.expectRevert latches onto the update call, not the VAULT_EID() getter.
        SendParam memory sp = _localSend(redeemerA, 0);
        vm.expectRevert(abi.encodeWithSelector(Errors.PendingAlreadyFulfilled.selector, sharesA, 0));
        composer.updateRequestRedeemAndSend(LOCAL_EID, redeemerA, sp, userA);
        assertEq(composer.pendingRedeem(redeemerA, redeemerA, LOCAL_EID).shares, sharesA, "bucket intact after revert");

        // The redemption is recoverable via the claim path (fulfilment still works).
        composer.fulfillRedeem(LOCAL_EID, redeemerA, redeemerA, sharesA);
        assertGt(composer.claimableRedeem(redeemerA, redeemerA, LOCAL_EID).assets, 0, "A claimable via fulfil");
    }

    // Scenario B: livePending > totalPendingSharesSum (direct external vault.requestRedeem)

    /// @notice An external direct requestRedeem keyed to the composer inflates Pv above Pc. A partial cancel must
    ///         return EXACTLY the bucket reduction (not the inflated delta), leaving the external shares untouched.
    function test_update_underDirectRequestSkew_noOverReturn_andFulfilmentStillWorks() public {
        uint256 sharesA = _seedPending(userA, redeemerA, 100e6);
        uint256 pc = composer.totalPendingSharesSum();

        // Attacker deposits and directly requests redeem with controller == composer (bypassing composer bookkeeping).
        asset.mint(attacker, 50e6);
        vm.startPrank(attacker);
        asset.approve(address(vault), 50e6);
        uint256 sharesX = vault.deposit(50e6, attacker);
        IERC20(address(shareOFT)).approve(address(vault), sharesX);
        vault.requestRedeem(sharesX, address(composer), attacker);
        vm.stopPrank();

        uint256 pv = vault.pendingRedeemRequest(0, address(composer));
        assertEq(pv, pc + sharesX, "skew: Pv == Pc + x");
        assertGt(pv, composer.totalPendingSharesSum(), "skew: Pv > Pc");

        // A reduces its bucket by half. Must get back exactly r, NOT r + x.
        uint256 r = sharesA / 2;
        uint256 newBucket = sharesA - r;
        uint256 balBefore = IERC20(address(shareOFT)).balanceOf(userA);
        composer.updateRequestRedeemAndSend(LOCAL_EID, redeemerA, _localSend(redeemerA, newBucket), userA);

        assertEq(IERC20(address(shareOFT)).balanceOf(userA) - balBefore, r, "A returned exactly r (no over-return)");
        assertEq(composer.pendingRedeem(redeemerA, redeemerA, LOCAL_EID).shares, newBucket, "A bucket reduced by r");
        // Attacker's externally-requested shares remain in vault pending, untouched by A's update.
        assertEq(vault.pendingRedeemRequest(0, address(composer)), pv - r, "external extra preserved");

        // Composer fulfilment still works for A's remaining bucket.
        composer.fulfillRedeem(LOCAL_EID, redeemerA, redeemerA, newBucket);
        assertGt(composer.claimableRedeem(redeemerA, redeemerA, LOCAL_EID).assets, 0, "A claimable after fulfil");
    }
}

/// @notice Regression tests for the receiver-width guard in `_send` (NEST-36 / NEST-42): a 32-byte identity that
///         does not fit a 20-byte address must be rejected before it truncates on an address-sized destination
///         (local or remote-EVM), while a non-address-sized destination still accepts the full bytes32.
contract NestVaultComposerReceiverWidthTest is NestVaultComposerAsyncSkewTest {
    uint32 internal constant REMOTE_EVM_EID = 2;
    uint32 internal constant REMOTE_NON_EVM_EID = 3;

    /// @dev Builds a non-address-sized identity (high 12 bytes non-zero) whose low 20 bytes are `_addr`.
    function _nonEvm(address _addr) internal pure returns (bytes32) {
        return bytes32((uint256(1) << 160) | uint256(uint160(_addr)));
    }

    /// @dev Deposit -> move shares to composer -> open a pending bucket for the (redeemer, receiver) pair.
    function _seedRequest(address _funder, bytes32 _redeemer, bytes32 _receiver, uint256 _assets)
        internal
        returns (uint256 shares)
    {
        asset.mint(_funder, _assets);
        vm.startPrank(_funder);
        asset.approve(address(vault), _assets);
        shares = vault.deposit(_assets, _funder);
        IERC20(address(shareOFT)).transfer(address(composer), shares);
        vm.stopPrank();
        composer.harnessRequestRedeem(LOCAL_EID, _redeemer, _receiver, shares);
    }

    /// @dev Seed a request and fulfill it so the pair has claimable assets ready for finish.
    function _seedFulfilled(address _funder, bytes32 _redeemer, bytes32 _receiver, uint256 _assets)
        internal
        returns (uint256 shares)
    {
        shares = _seedRequest(_funder, _redeemer, _receiver, _assets);
        composer.fulfillRedeem(LOCAL_EID, _redeemer, _receiver, shares);
    }

    /// @notice NEST-42: local finish to a non-address-sized receiver reverts instead of paying the low 20 bytes.
    function test_finishLocal_nonEvmReceiver_reverts() public {
        bytes32 nonEvm = _nonEvm(userA);
        uint256 shares = _seedFulfilled(userA, redeemerA, nonEvm, 100e6);

        SendParam memory sp = _localSend(nonEvm, shares);
        vm.expectRevert(Errors.InvalidReceiver.selector);
        composer.finishRedeemAndSend(LOCAL_EID, redeemerA, sp, userA);
    }

    /// @notice Normal redemption is not blocked: a canonical EVM receiver finishes locally and is paid in full.
    function test_finishLocal_evmReceiver_succeeds() public {
        uint256 shares = _seedFulfilled(userA, redeemerA, redeemerA, 100e6);
        uint256 claimable = composer.claimableRedeem(redeemerA, redeemerA, LOCAL_EID).assets;

        uint256 before = asset.balanceOf(userA);
        composer.finishRedeemAndSend(LOCAL_EID, redeemerA, _localSend(redeemerA, shares), userA);
        assertEq(asset.balanceOf(userA) - before, claimable, "EVM receiver paid in full");
    }

    /// @notice Remote-EVM gap: an EVM peer (address-sized) + non-address-sized receiver reverts before the
    ///         destination OFT could truncate the payout on arrival.
    function test_finishRemoteEvmPeer_nonEvmReceiver_reverts() public {
        // Canonical peer => destination is address-sized (EVM).
        assetOFT.setPeer(REMOTE_EVM_EID, addressToBytes32(makeAddr("remoteEvmOFT")));

        bytes32 nonEvm = _nonEvm(userA);
        uint256 shares = _seedFulfilled(userA, redeemerA, nonEvm, 100e6);

        SendParam memory sp;
        sp.dstEid = REMOTE_EVM_EID;
        sp.to = nonEvm;
        sp.amountLD = shares;
        vm.expectRevert(Errors.InvalidReceiver.selector);
        composer.finishRedeemAndSend(LOCAL_EID, redeemerA, sp, userA);
    }

    /// @notice NEST-36: local update returns shares to the redeemer; a non-address-sized redeemer reverts.
    function test_updateLocal_nonEvmRedeemer_reverts() public {
        bytes32 nonEvmRedeemer = _nonEvm(userA);
        // Bucket key uses (redeemer, receiver); receiver is canonical so the request itself is fine.
        _seedRequest(userA, nonEvmRedeemer, redeemerB, 100e6);

        // amountLD 0 fully cancels; update overrides SendParam.to to the (non-EVM) redeemer before sending.
        SendParam memory sp = _localSend(redeemerB, 0);
        vm.expectRevert(Errors.InvalidReceiver.selector);
        composer.updateRequestRedeemAndSend(LOCAL_EID, nonEvmRedeemer, sp, userA);
    }

    /// @notice Non-address-sized destination (Solana-style peer) still accepts a full bytes32 receiver: the guard
    ///         must NOT fire, so it can never break legitimate non-EVM redemptions. (The unwired remote send
    ///         reverts downstream, which is expected and distinct from the guard.)
    function test_finishRemoteNonEvmPeer_nonEvmReceiver_guardPasses() public {
        // Non-address-sized peer => destination keeps full bytes32 identities.
        assetOFT.setPeer(REMOTE_NON_EVM_EID, _nonEvm(makeAddr("solanaStore")));

        bytes32 nonEvm = _nonEvm(userA);
        uint256 shares = _seedFulfilled(userA, redeemerA, nonEvm, 100e6);

        SendParam memory sp;
        sp.dstEid = REMOTE_NON_EVM_EID;
        sp.to = nonEvm;
        sp.amountLD = shares;

        (bool ok, bytes memory err) = address(composer)
            .call(abi.encodeWithSelector(composer.finishRedeemAndSend.selector, LOCAL_EID, redeemerA, sp, userA));
        assertFalse(ok, "unwired remote send reverts downstream");
        assertTrue(bytes4(err) != Errors.InvalidReceiver.selector, "guard must not reject non-EVM dest");
    }

    /// @notice Unregistered EID (peers() == bytes32(0)) is not address-typed: a non-EVM receiver must NOT be
    ///         rejected with InvalidReceiver. The real "peer not set" revert surfaces downstream instead.
    function test_finishRemoteUnregisteredEid_nonEvmReceiver_guardPasses() public {
        uint32 unregisteredEid = 999; // peers(unregisteredEid) == bytes32(0)

        bytes32 nonEvm = _nonEvm(userA);
        uint256 shares = _seedFulfilled(userA, redeemerA, nonEvm, 100e6);

        SendParam memory sp;
        sp.dstEid = unregisteredEid;
        sp.to = nonEvm;
        sp.amountLD = shares;

        (bool ok, bytes memory err) = address(composer)
            .call(abi.encodeWithSelector(composer.finishRedeemAndSend.selector, LOCAL_EID, redeemerA, sp, userA));
        assertFalse(ok, "unregistered remote send reverts downstream");
        assertTrue(bytes4(err) != Errors.InvalidReceiver.selector, "guard must not reject unregistered EID");
    }
}
