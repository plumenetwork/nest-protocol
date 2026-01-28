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
                    NestVault.initialize.selector, address(accountant), address(asset), address(this), 1
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
                        address(shareOFT)
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
                    1
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
                    1
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
                        address(vaultOFT)
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
