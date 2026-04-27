// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import {MessagingFee, MessagingReceipt} from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTCoreUpgradeable.sol";
import {OFTAdapterUpgradeableMock} from "@layerzerolabs/oft-evm-upgradeable/test/mocks/OFTAdapterUpgradeableMock.sol";
import {ERC20Mock} from "@layerzerolabs/oft-evm-upgradeable/test/mocks/ERC20Mock.sol";
import {OFTComposerMock} from "@layerzerolabs/oft-evm-upgradeable/test/mocks/OFTComposerMock.sol";
import {OFTInspectorMock, IOAppMsgInspector} from "@layerzerolabs/oft-evm-upgradeable/test/mocks/OFTInspectorMock.sol";
import {
    IOAppOptionsType3,
    EnforcedOptionParam
} from "@layerzerolabs/oapp-evm-upgradeable/contracts/oapp/libs/OAppOptionsType3Upgradeable.sol";

import {OFTMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import {IOFT, SendParam, OFTReceipt} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "forge-std/console.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {MockNestShareOFT} from "test/mock/MockNestShareOFT.sol";
import {NestShareOFT} from "contracts/NestShareOFT.sol";
import {MockBoringVault} from "test/mock/MockBoringVault.sol";
import {MockAuthority} from "test/mock/MockAuthority.sol";
import {MockRateProvider} from "test/mock/MockRateProvider.sol";
import {MockNestVaultOFT} from "test/mock/MockNestVaultOFT.sol";
import {NestVaultOFT} from "contracts/NestVaultOFT.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {Errors} from "contracts/types/Errors.sol";

contract NestVaultOFTTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    uint32 aEid = 1;
    uint32 bEid = 2;
    uint32 cEid = 3;

    MockNestVaultOFT aOFT;
    MockNestVaultOFT bOFT;

    ERC20Mock cERC20Mock;
    MockBoringVault share;

    OFTInspectorMock oAppInspector;

    address public userA = address(0x1);
    address public userB = address(0x2);
    address public userC = address(0x3);
    uint256 public initialBalance = 100 ether;

    address public proxyAdmin = makeAddr("proxyAdmin");

    function setUp() public virtual override {
        vm.deal(userA, 1000 ether);
        vm.deal(userB, 1000 ether);
        vm.deal(userC, 1000 ether);

        MockRateProvider accountantWithRateProviders = new MockRateProvider();
        accountantWithRateProviders.setRate(1e6);
        cERC20Mock = new ERC20Mock("cToken", "cToken");
        share = new MockBoringVault("Share", "SHARE", 6);

        super.setUp();
        setUpEndpoints(3, LibraryType.UltraLightNode);

        aOFT = MockNestVaultOFT(
            _deployContractAndProxy(
                type(MockNestVaultOFT).creationCode,
                abi.encode(address(payable(share)), address(endpoints[aEid])),
                abi.encodeWithSelector(
                    NestVaultOFT.initialize.selector,
                    accountantWithRateProviders,
                    address(cERC20Mock),
                    address(this),
                    address(this),
                    1,
                    address(0)
                )
            )
        );

        bOFT = MockNestVaultOFT(
            _deployContractAndProxy(
                type(MockNestVaultOFT).creationCode,
                abi.encode(address(payable(share)), address(endpoints[bEid])),
                abi.encodeWithSelector(
                    NestVaultOFT.initialize.selector,
                    accountantWithRateProviders,
                    address(cERC20Mock),
                    address(this),
                    address(this),
                    1,
                    address(0)
                )
            )
        );

        // set permissive mock authority functions public
        MockAuthority mockAuthority = new MockAuthority(true);
        aOFT.setAuthority(Authority(address(mockAuthority)));
        bOFT.setAuthority(Authority(address(mockAuthority)));

        // config and wire the ofts
        address[] memory ofts = new address[](2);
        ofts[0] = address(aOFT);
        ofts[1] = address(bOFT);
        this.wireOApps(ofts);

        // mint tokens
        aOFT.credit(userA, initialBalance, aEid);
        bOFT.credit(userB, initialBalance, bEid);

        // deploy a universal inspector, can be used by each oft
        oAppInspector = new OFTInspectorMock();
    }

    function _deployContractAndProxy(
        bytes memory _oappBytecode,
        bytes memory _constructorArgs,
        bytes memory _initializeArgs
    ) internal virtual returns (address addr) {
        bytes memory bytecode = bytes.concat(abi.encodePacked(_oappBytecode), _constructorArgs);
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }

        return address(new TransparentUpgradeableProxy(addr, proxyAdmin, _initializeArgs));
    }

    function test_constructor() public view virtual {
        assertEq(aOFT.owner(), address(this));
        assertEq(bOFT.owner(), address(this));

        assertEq(aOFT.balanceOf(userA), initialBalance);
        assertEq(bOFT.balanceOf(userB), initialBalance);

        assertEq(aOFT.token(), address(share));
        assertEq(bOFT.token(), address(share));
    }

    function test_renounceOwnership_disabled() public {
        vm.expectRevert(Errors.RenounceOwnershipDisabled.selector);
        aOFT.renounceOwnership();
    }

    function test_oftVersion() public view {
        (bytes4 interfaceId,) = aOFT.oftVersion();
        bytes4 expectedId = 0x02e49c2c;
        assertEq(interfaceId, expectedId);
    }

    function test_send_oft() public virtual {
        uint256 tokensToSend = 1 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam =
            SendParam(bEid, addressToBytes32(userB), tokensToSend, tokensToSend, options, "", "");
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        assertEq(aOFT.balanceOf(userA), initialBalance);
        assertEq(bOFT.balanceOf(userB), initialBalance);

        vm.prank(userA);
        aOFT.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));
        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        assertEq(aOFT.balanceOf(userA), initialBalance - tokensToSend);
        assertEq(bOFT.balanceOf(userB), initialBalance + tokensToSend);
    }

    function test_send_oft_compose_msg() public virtual {
        uint256 tokensToSend = 1 ether;

        OFTComposerMock composer = new OFTComposerMock();

        bytes memory options =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0).addExecutorLzComposeOption(0, 500000, 0);
        bytes memory composeMsg = hex"1234";
        SendParam memory sendParam =
            SendParam(bEid, addressToBytes32(address(composer)), tokensToSend, tokensToSend, options, composeMsg, "");
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        assertEq(aOFT.balanceOf(userA), initialBalance);
        assertEq(bOFT.balanceOf(address(composer)), 0);

        vm.prank(userA);
        (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) =
            aOFT.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));
        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        // lzCompose params
        uint32 dstEid_ = bEid;
        address from_ = address(bOFT);
        bytes memory options_ = options;
        bytes32 guid_ = msgReceipt.guid;
        address to_ = address(composer);
        bytes memory composerMsg_ = OFTComposeMsgCodec.encode(
            msgReceipt.nonce, aEid, oftReceipt.amountReceivedLD, abi.encodePacked(addressToBytes32(userA), composeMsg)
        );
        this.lzCompose(dstEid_, from_, options_, guid_, to_, composerMsg_);

        assertEq(aOFT.balanceOf(userA), initialBalance - tokensToSend);
        assertEq(bOFT.balanceOf(address(composer)), tokensToSend);

        assertEq(composer.from(), from_);
        assertEq(composer.guid(), guid_);
        assertEq(composer.message(), composerMsg_);
        assertEq(composer.executor(), address(this));
        assertEq(composer.extraData(), composerMsg_); // default to setting the extraData to the message as well to test
    }

    function test_oft_compose_codec() public view {
        uint64 nonce = 1;
        uint32 srcEid = 2;
        uint256 amountCreditLD = 3;
        bytes memory composeMsg = hex"1234";

        bytes memory message = OFTComposeMsgCodec.encode(
            nonce, srcEid, amountCreditLD, abi.encodePacked(addressToBytes32(msg.sender), composeMsg)
        );
        (uint64 nonce_, uint32 srcEid_, uint256 amountCreditLD_, bytes32 composeFrom_, bytes memory composeMsg_) =
            this.decodeOFTComposeMsgCodec(message);

        assertEq(nonce_, nonce);
        assertEq(srcEid_, srcEid);
        assertEq(amountCreditLD_, amountCreditLD);
        assertEq(composeFrom_, addressToBytes32(msg.sender));
        assertEq(composeMsg_, composeMsg);
    }

    function decodeOFTComposeMsgCodec(bytes calldata message)
        public
        pure
        returns (uint64 nonce, uint32 srcEid, uint256 amountCreditLD, bytes32 composeFrom, bytes memory composeMsg)
    {
        nonce = OFTComposeMsgCodec.nonce(message);
        srcEid = OFTComposeMsgCodec.srcEid(message);
        amountCreditLD = OFTComposeMsgCodec.amountLD(message);
        composeFrom = OFTComposeMsgCodec.composeFrom(message);
        composeMsg = OFTComposeMsgCodec.composeMsg(message);
    }

    function test_debit_slippage_removeDust() public virtual {
        uint256 amountToSendLD = 1.234567890123456789 ether;
        uint256 minAmountToCreditLD = amountToSendLD + 1;
        uint32 dstEid = aEid;

        // NestVault local decimals and share decimals are both 6
        assertEq(aOFT.removeDust(amountToSendLD), 1.234567890123456789 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IOFT.SlippageExceeded.selector, aOFT.removeDust(amountToSendLD), minAmountToCreditLD)
        );
        aOFT.debit(amountToSendLD, minAmountToCreditLD, dstEid);
    }

    function test_debit_slippage_minAmountToCreditLD() public virtual {
        uint256 amountToSendLD = 1e6;
        uint256 minAmountToCreditLD = 1e6 + 1;
        uint32 dstEid = aEid;

        console.log(aOFT.balanceOf(userA));
        console.log(aOFT.balanceOf(address(this)));

        vm.expectRevert(abi.encodeWithSelector(IOFT.SlippageExceeded.selector, amountToSendLD, minAmountToCreditLD));
        aOFT.debit(amountToSendLD, minAmountToCreditLD, dstEid);
    }

    function test_toLD() public view {
        uint64 amountSD = 1000;
        assertEq(amountSD * aOFT.decimalConversionRate(), aOFT.toLD(uint64(amountSD)));
    }

    function test_toSD() public view {
        uint256 amountLD = 1000000;
        assertEq(amountLD / aOFT.decimalConversionRate(), aOFT.toSD(amountLD));
    }

    function test_oft_debit() public virtual {
        uint256 amountToSendLD = 1e6;
        uint256 minAmountToCreditLD = 1e6;
        uint32 dstEid = aEid;

        assertEq(aOFT.balanceOf(userA), initialBalance);
        assertEq(aOFT.balanceOf(address(this)), 0);

        vm.prank(userA);
        (uint256 amountDebitedLD, uint256 amountToCreditLD) = aOFT.debit(amountToSendLD, minAmountToCreditLD, dstEid);

        assertEq(amountDebitedLD, amountToSendLD);
        assertEq(amountToCreditLD, amountToSendLD);

        assertEq(aOFT.balanceOf(userA), initialBalance - amountToSendLD);
        assertEq(aOFT.balanceOf(address(this)), 0);
    }

    function test_oft_credit() public virtual {
        uint256 amountToCreditLD = 1 ether;
        uint32 srcEid = aEid;

        assertEq(aOFT.balanceOf(userA), initialBalance);
        assertEq(aOFT.balanceOf(address(this)), 0);

        vm.prank(userA);
        uint256 amountReceived = aOFT.credit(userA, amountToCreditLD, srcEid);

        assertEq(aOFT.balanceOf(userA), initialBalance + amountReceived);
        assertEq(aOFT.balanceOf(address(this)), 0);
    }

    function decodeOFTMsgCodec(bytes calldata message)
        public
        pure
        returns (bool isComposed, bytes32 sendTo, uint64 amountSD, bytes memory composeMsg)
    {
        isComposed = OFTMsgCodec.isComposed(message);
        sendTo = OFTMsgCodec.sendTo(message);
        amountSD = OFTMsgCodec.amountSD(message);
        composeMsg = OFTMsgCodec.composeMsg(message);
    }

    function test_oft_build_msg() public view {
        uint32 dstEid = bEid;
        bytes32 to = addressToBytes32(userA);
        uint256 amountToSendLD = 1.23456789 ether;
        uint256 minAmountToCreditLD = aOFT.removeDust(amountToSendLD);

        // params for buildMsgAndOptions
        bytes memory extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        bytes memory composeMsg = hex"1234";
        SendParam memory sendParam =
            SendParam(dstEid, to, amountToSendLD, minAmountToCreditLD, extraOptions, composeMsg, "");
        uint256 amountToCreditLD = minAmountToCreditLD;

        (bytes memory message,) = aOFT.buildMsgAndOptions(sendParam, amountToCreditLD);

        (bool isComposed_, bytes32 sendTo_, uint64 amountSD_, bytes memory composeMsg_) =
            this.decodeOFTMsgCodec(message);

        assertEq(isComposed_, true);
        assertEq(sendTo_, to);
        assertEq(amountSD_, aOFT.toSD(amountToCreditLD));
        bytes memory expectedComposeMsg = abi.encodePacked(addressToBytes32(address(this)), composeMsg);
        assertEq(composeMsg_, expectedComposeMsg);
    }

    function test_oft_build_msg_no_compose_msg() public view {
        uint32 dstEid = bEid;
        bytes32 to = addressToBytes32(userA);
        uint256 amountToSendLD = 1.23456789 ether;
        uint256 minAmountToCreditLD = aOFT.removeDust(amountToSendLD);

        // params for buildMsgAndOptions
        bytes memory extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        bytes memory composeMsg = "";
        SendParam memory sendParam =
            SendParam(dstEid, to, amountToSendLD, minAmountToCreditLD, extraOptions, composeMsg, "");
        uint256 amountToCreditLD = minAmountToCreditLD;

        (bytes memory message,) = aOFT.buildMsgAndOptions(sendParam, amountToCreditLD);

        (bool isComposed_, bytes32 sendTo_, uint64 amountSD_, bytes memory composeMsg_) =
            this.decodeOFTMsgCodec(message);

        assertEq(isComposed_, false);
        assertEq(sendTo_, to);
        assertEq(amountSD_, aOFT.toSD(amountToCreditLD));
        assertEq(composeMsg_, "");
    }

    function test_set_enforced_options() public {
        uint32 eid = 1;

        bytes memory optionsTypeOne = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        bytes memory optionsTypeTwo = OptionsBuilder.newOptions().addExecutorLzReceiveOption(250000, 0);

        EnforcedOptionParam[] memory enforcedOptions = new EnforcedOptionParam[](2);
        enforcedOptions[0] = EnforcedOptionParam(eid, 1, optionsTypeOne);
        enforcedOptions[1] = EnforcedOptionParam(eid, 2, optionsTypeTwo);

        aOFT.setEnforcedOptions(enforcedOptions);

        assertEq(aOFT.enforcedOptions(eid, 1), optionsTypeOne);
        assertEq(aOFT.enforcedOptions(eid, 2), optionsTypeTwo);
    }

    function test_assert_options_type3_revert() public {
        uint32 eid = 1;
        EnforcedOptionParam[] memory enforcedOptions = new EnforcedOptionParam[](1);

        enforcedOptions[0] = EnforcedOptionParam(eid, 1, hex"0004"); // not type 3
        vm.expectRevert(abi.encodeWithSelector(IOAppOptionsType3.InvalidOptions.selector, hex"0004"));
        aOFT.setEnforcedOptions(enforcedOptions);

        enforcedOptions[0] = EnforcedOptionParam(eid, 1, hex"0002"); // not type 3
        vm.expectRevert(abi.encodeWithSelector(IOAppOptionsType3.InvalidOptions.selector, hex"0002"));
        aOFT.setEnforcedOptions(enforcedOptions);

        enforcedOptions[0] = EnforcedOptionParam(eid, 1, hex"0001"); // not type 3
        vm.expectRevert(abi.encodeWithSelector(IOAppOptionsType3.InvalidOptions.selector, hex"0001"));
        aOFT.setEnforcedOptions(enforcedOptions);

        enforcedOptions[0] = EnforcedOptionParam(eid, 1, hex"0003"); // IS type 3
        aOFT.setEnforcedOptions(enforcedOptions); // doesnt revert cus option type 3
    }

    function test_combine_options() public {
        uint32 eid = 1;
        uint16 msgType = 1;

        bytes memory enforcedOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        EnforcedOptionParam[] memory enforcedOptionsArray = new EnforcedOptionParam[](1);
        enforcedOptionsArray[0] = EnforcedOptionParam(eid, msgType, enforcedOptions);
        aOFT.setEnforcedOptions(enforcedOptionsArray);

        bytes memory extraOptions =
            OptionsBuilder.newOptions().addExecutorNativeDropOption(1.2345 ether, addressToBytes32(userA));

        bytes memory expectedOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0)
            .addExecutorNativeDropOption(1.2345 ether, addressToBytes32(userA));

        bytes memory combinedOptions = aOFT.combineOptions(eid, msgType, extraOptions);
        assertEq(combinedOptions, expectedOptions);
    }

    function test_combine_options_no_extra_options() public {
        uint32 eid = 1;
        uint16 msgType = 1;

        bytes memory enforcedOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        EnforcedOptionParam[] memory enforcedOptionsArray = new EnforcedOptionParam[](1);
        enforcedOptionsArray[0] = EnforcedOptionParam(eid, msgType, enforcedOptions);
        aOFT.setEnforcedOptions(enforcedOptionsArray);

        bytes memory expectedOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        bytes memory combinedOptions = aOFT.combineOptions(eid, msgType, "");
        assertEq(combinedOptions, expectedOptions);
    }

    function test_combine_options_no_enforced_options() public view {
        uint32 eid = 1;
        uint16 msgType = 1;

        bytes memory extraOptions =
            OptionsBuilder.newOptions().addExecutorNativeDropOption(1.2345 ether, addressToBytes32(userA));

        bytes memory expectedOptions =
            OptionsBuilder.newOptions().addExecutorNativeDropOption(1.2345 ether, addressToBytes32(userA));

        bytes memory combinedOptions = aOFT.combineOptions(eid, msgType, extraOptions);
        assertEq(combinedOptions, expectedOptions);
    }

    function test_oapp_inspector_inspect() public {
        uint32 dstEid = bEid;
        bytes32 to = addressToBytes32(userA);
        uint256 amountToSendLD = 1.23456789 ether;
        uint256 minAmountToCreditLD = aOFT.removeDust(amountToSendLD);

        // params for buildMsgAndOptions
        bytes memory extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        bytes memory composeMsg = "";
        SendParam memory sendParam =
            SendParam(dstEid, to, amountToSendLD, minAmountToCreditLD, extraOptions, composeMsg, "");
        uint256 amountToCreditLD = minAmountToCreditLD;

        // doesnt revert
        (bytes memory message,) = aOFT.buildMsgAndOptions(sendParam, amountToCreditLD);

        // deploy a universal inspector, it automatically reverts
        oAppInspector = new OFTInspectorMock();
        // set the inspector
        aOFT.setMsgInspector(address(oAppInspector));

        // does revert because inspector is set
        vm.expectRevert(abi.encodeWithSelector(IOAppMsgInspector.InspectionFailed.selector, message, extraOptions));
        (message,) = aOFT.buildMsgAndOptions(sendParam, amountToCreditLD);
    }
}
