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
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {MockAuthority} from "test/mock/MockAuthority.sol";
import {MockNestShareOFT} from "test/mock/MockNestShareOFT.sol";
import {MockNestShareOFTV1} from "test/mock/MockNestShareOFTV1.sol";
import {NestShareOFT} from "contracts/NestShareOFT.sol";
import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {BlacklistHook} from "contracts/hooks/BlacklistHook.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {AuthUpgradeable} from "contracts/upgradeable/auth/AuthUpgradeable.sol";
import {Errors} from "contracts/types/Errors.sol";

contract NestShareOFTTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    uint32 aEid = 1;
    uint32 bEid = 2;
    uint32 cEid = 3;

    MockNestShareOFT aOFT;
    MockNestShareOFT bOFT;
    OFTAdapterUpgradeableMock cOFTAdapter;
    ERC20Mock cERC20Mock;

    OFTInspectorMock oAppInspector;

    address public userA = address(0x1);
    address public userB = address(0x2);
    address public userC = address(0x3);
    uint256 public initialBalance = 100 ether;

    uint256 internal permitOwnerKey;
    address internal permitOwner;

    address public proxyAdmin = makeAddr("proxyAdmin");

    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant ERC1967_ADMIN_SLOT = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);

    function setUp() public virtual override {
        vm.deal(userA, 1000 ether);
        vm.deal(userB, 1000 ether);
        vm.deal(userC, 1000 ether);

        super.setUp();
        setUpEndpoints(3, LibraryType.UltraLightNode);

        permitOwnerKey = 0xA11CE;
        permitOwner = vm.addr(permitOwnerKey);

        aOFT = MockNestShareOFT(
            _deployContractAndProxy(
                type(MockNestShareOFT).creationCode,
                abi.encode(address(endpoints[aEid])),
                abi.encodeWithSelector(NestShareOFT.initialize.selector, "aOFT", "aOFT", address(this), address(this))
            )
        );

        bOFT = MockNestShareOFT(
            _deployContractAndProxy(
                type(MockNestShareOFT).creationCode,
                abi.encode(address(endpoints[bEid])),
                abi.encodeWithSelector(NestShareOFT.initialize.selector, "bOFT", "bOFT", address(this), address(this))
            )
        );

        // set permissive mock authority functions public
        MockAuthority mockAuthority = new MockAuthority(true);
        aOFT.setAuthority(Authority(address(mockAuthority)));
        bOFT.setAuthority(Authority(address(mockAuthority)));

        cERC20Mock = new ERC20Mock("cToken", "cToken");
        cOFTAdapter = OFTAdapterUpgradeableMock(
            _deployContractAndProxy(
                type(OFTAdapterUpgradeableMock).creationCode,
                abi.encode(address(cERC20Mock), address(endpoints[cEid])),
                abi.encodeWithSelector(OFTAdapterUpgradeableMock.initialize.selector, address(this))
            )
        );

        // config and wire the ofts
        address[] memory ofts = new address[](3);
        ofts[0] = address(aOFT);
        ofts[1] = address(bOFT);
        ofts[2] = address(cOFTAdapter);
        this.wireOApps(ofts);

        // mint tokens
        aOFT.enter(address(0), ERC20(address(0)), 0, userA, initialBalance);
        aOFT.enter(address(0), ERC20(address(0)), 0, permitOwner, initialBalance);
        bOFT.enter(address(0), ERC20(address(0)), 0, userB, initialBalance);
        cERC20Mock.mint(userC, initialBalance);

        // deploy a universal inspector, can be used by each oft
        oAppInspector = new OFTInspectorMock();
    }

    function _deployContractAndProxy(
        bytes memory _oappBytecode,
        bytes memory _constructorArgs,
        bytes memory _initializeArgs
    ) internal virtual returns (address addr) {
        addr = _deployImplementation(_oappBytecode, _constructorArgs);
        return address(new TransparentUpgradeableProxy(addr, proxyAdmin, _initializeArgs));
    }

    function _deployImplementation(bytes memory _oappBytecode, bytes memory _constructorArgs)
        internal
        virtual
        returns (address addr)
    {
        bytes memory bytecode = bytes.concat(abi.encodePacked(_oappBytecode), _constructorArgs);
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
    }

    function _domainSeparator(address verifyingContract, string memory name_, string memory version_)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes(name_)),
                keccak256(bytes(version_)),
                block.chainid,
                verifyingContract
            )
        );
    }

    function _proxyAdmin(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967_ADMIN_SLOT))));
    }

    function _permitDigest(address owner, address spender, uint256 value, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));
        return keccak256(abi.encodePacked("\x19\x01", aOFT.DOMAIN_SEPARATOR(), structHash));
    }

    function _signPermit(address owner, uint256 ownerKey, address spender, uint256 value, uint256 deadline)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        uint256 nonce = aOFT.nonces(owner);
        bytes32 digest = _permitDigest(owner, spender, value, nonce, deadline);
        return vm.sign(ownerKey, digest);
    }

    function test_constructor() public view virtual {
        assertEq(aOFT.owner(), address(this));
        assertEq(bOFT.owner(), address(this));
        assertEq(cOFTAdapter.owner(), address(this));

        assertEq(aOFT.balanceOf(userA), initialBalance);
        assertEq(bOFT.balanceOf(userB), initialBalance);
        assertEq(IERC20(cOFTAdapter.token()).balanceOf(userC), initialBalance);

        assertEq(aOFT.token(), address(aOFT));
        assertEq(bOFT.token(), address(bOFT));
        assertEq(cOFTAdapter.token(), address(cERC20Mock));
    }

    function test_initialize_revertsWhenOwnerZero() public {
        address implementation =
            _deployImplementation(type(MockNestShareOFT).creationCode, abi.encode(address(endpoints[aEid])));
        vm.expectRevert(Errors.ZeroAddress.selector);
        new TransparentUpgradeableProxy(
            implementation,
            proxyAdmin,
            abi.encodeWithSelector(NestShareOFT.initialize.selector, "zOFT", "zOFT", address(0), address(this))
        );
    }

    function test_renounceOwnership_disabled() public {
        vm.expectRevert(Errors.RenounceOwnershipDisabled.selector);
        aOFT.renounceOwnership();
    }

    function test_initialize_reverts_when_name_empty() public {
        MockNestShareOFT uninitialized = MockNestShareOFT(
            _deployContractAndProxy(type(MockNestShareOFT).creationCode, abi.encode(address(endpoints[aEid])), "")
        );

        vm.expectRevert(Errors.EmptyNameOrSymbol.selector);
        uninitialized.initialize("", "aOFT", address(this), address(this));
    }

    function test_initialize_reverts_when_symbol_empty() public {
        MockNestShareOFT uninitialized = MockNestShareOFT(
            _deployContractAndProxy(type(MockNestShareOFT).creationCode, abi.encode(address(endpoints[aEid])), "")
        );

        vm.expectRevert(Errors.EmptyNameOrSymbol.selector);
        uninitialized.initialize("aOFT", "", address(this), address(this));
    }

    function test_setNameAndSymbol_updates_name_symbol_and_domain_separator() public {
        string memory newName = "Nest Share Renamed";
        string memory newSymbol = "nSHARE2";

        vm.expectEmit(false, false, false, true, address(aOFT));
        emit NestShareOFT.NameAndSymbolUpdated(newName, newSymbol, 2);
        aOFT.setNameAndSymbol(newName, newSymbol, 2);

        assertEq(aOFT.name(), newName);
        assertEq(aOFT.symbol(), newSymbol);
        assertEq(aOFT.DOMAIN_SEPARATOR(), _domainSeparator(address(aOFT), newName, "1"));
    }

    function test_setNameAndSymbol_reverts_when_unauthorized() public {
        aOFT.setAuthority(Authority(address(new MockAuthority(false))));

        vm.prank(userA);
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        aOFT.setNameAndSymbol("Nest Share Renamed", "nSHARE2", 2);
    }

    function test_setNameAndSymbol_reverts_when_name_empty() public {
        vm.expectRevert(Errors.EmptyNameOrSymbol.selector);
        aOFT.setNameAndSymbol("", "nSHARE2", 2);
    }

    function test_setNameAndSymbol_reverts_when_symbol_empty() public {
        vm.expectRevert(Errors.EmptyNameOrSymbol.selector);
        aOFT.setNameAndSymbol("Nest Share Renamed", "", 2);
    }

    function test_setNameAndSymbol_allows_multiple_calls_with_increasing_versions() public {
        aOFT.setNameAndSymbol("Nest Share Renamed", "nSHARE2", 2);
        aOFT.setNameAndSymbol("Nest Share Final", "nSHARE3", 3);

        assertEq(aOFT.name(), "Nest Share Final");
        assertEq(aOFT.symbol(), "nSHARE3");
        assertEq(aOFT.DOMAIN_SEPARATOR(), _domainSeparator(address(aOFT), "Nest Share Final", "1"));
    }

    function test_setNameAndSymbol_reverts_on_reused_version() public {
        aOFT.setNameAndSymbol("Nest Share Renamed", "nSHARE2", 2);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        aOFT.setNameAndSymbol("Nest Share Renamed Again", "nSHARE3", 2);
    }

    function test_setNameAndSymbol_reverts_on_version_1() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        aOFT.setNameAndSymbol("Nest Share Renamed", "nSHARE2", 1);
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
        uint256 amountToSendLD = 1 ether;
        uint256 minAmountToCreditLD = 1.00000001 ether;
        uint32 dstEid = aEid;

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
        uint256 amountToSendLD = 1 ether;
        uint256 minAmountToCreditLD = 1 ether;
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

    function test_oft_adapter_debit() public virtual {
        uint256 amountToSendLD = 1 ether;
        uint256 minAmountToCreditLD = 1 ether;
        uint32 dstEid = cEid;

        assertEq(cERC20Mock.balanceOf(userC), initialBalance);
        assertEq(cERC20Mock.balanceOf(address(cOFTAdapter)), 0);

        vm.prank(userC);
        vm.expectRevert(abi.encodeWithSelector(IOFT.SlippageExceeded.selector, amountToSendLD, minAmountToCreditLD + 1));
        cOFTAdapter.debitView(amountToSendLD, minAmountToCreditLD + 1, dstEid);

        vm.prank(userC);
        cERC20Mock.approve(address(cOFTAdapter), amountToSendLD);
        vm.prank(userC);
        (uint256 amountDebitedLD, uint256 amountToCreditLD) =
            cOFTAdapter.debit(amountToSendLD, minAmountToCreditLD, dstEid);

        assertEq(amountDebitedLD, amountToSendLD);
        assertEq(amountToCreditLD, amountToSendLD);

        assertEq(cERC20Mock.balanceOf(userC), initialBalance - amountToSendLD);
        assertEq(cERC20Mock.balanceOf(address(cOFTAdapter)), amountToSendLD);
    }

    function test_oft_adapter_credit() public {
        uint256 amountToCreditLD = 1 ether;
        uint32 srcEid = cEid;

        assertEq(cERC20Mock.balanceOf(userC), initialBalance);
        assertEq(cERC20Mock.balanceOf(address(cOFTAdapter)), 0);

        vm.prank(userC);
        cERC20Mock.transfer(address(cOFTAdapter), amountToCreditLD);

        uint256 amountReceived = cOFTAdapter.credit(userB, amountToCreditLD, srcEid);

        assertEq(cERC20Mock.balanceOf(userC), initialBalance - amountToCreditLD);
        assertEq(cERC20Mock.balanceOf(address(userB)), amountReceived);
        assertEq(cERC20Mock.balanceOf(address(cOFTAdapter)), 0);
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

    function test_permit_sets_allowance_and_increments_nonce() public {
        uint256 value = 1 ether;
        uint256 deadline = block.timestamp + 1 days;

        assertEq(aOFT.nonces(permitOwner), 0);
        assertEq(aOFT.allowance(permitOwner, userB), 0);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(permitOwner, permitOwnerKey, userB, value, deadline);
        aOFT.permit(permitOwner, userB, value, deadline, v, r, s);

        assertEq(aOFT.allowance(permitOwner, userB), value);
        assertEq(aOFT.nonces(permitOwner), 1);

        uint256 balanceBefore = aOFT.balanceOf(userB);
        vm.prank(userB);
        aOFT.transferFrom(permitOwner, userB, value);

        assertEq(aOFT.balanceOf(userB), balanceBefore + value);
        assertEq(aOFT.allowance(permitOwner, userB), 0);
    }

    function test_permit_invalid_signer_reverts() public {
        uint256 value = 1 ether;
        uint256 deadline = block.timestamp + 1 days;
        uint256 attackerKey = 0xBADC0DE;
        address attacker = vm.addr(attackerKey);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(permitOwner, attackerKey, userB, value, deadline);

        vm.expectRevert(
            abi.encodeWithSelector(ERC20PermitUpgradeable.ERC2612InvalidSigner.selector, attacker, permitOwner)
        );
        aOFT.permit(permitOwner, userB, value, deadline, v, r, s);
    }

    function test_permit_expired_deadline_reverts() public {
        uint256 value = 1 ether;
        uint256 deadline = block.timestamp + 1;

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(permitOwner, permitOwnerKey, userB, value, deadline);

        vm.warp(deadline + 1);
        vm.expectRevert(abi.encodeWithSelector(ERC20PermitUpgradeable.ERC2612ExpiredSignature.selector, deadline));
        aOFT.permit(permitOwner, userB, value, deadline, v, r, s);
    }

    function test_permit_replay_reverts_and_nonce_unchanged() public {
        uint256 value = 1 ether;
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(permitOwner, permitOwnerKey, userB, value, deadline);
        aOFT.permit(permitOwner, userB, value, deadline, v, r, s);
        assertEq(aOFT.nonces(permitOwner), 1);

        uint256 nonce = aOFT.nonces(permitOwner);
        bytes32 digest = _permitDigest(permitOwner, userB, value, nonce, deadline);
        address signer = ecrecover(digest, v, r, s);
        vm.expectRevert(
            abi.encodeWithSelector(ERC20PermitUpgradeable.ERC2612InvalidSigner.selector, signer, permitOwner)
        );
        aOFT.permit(permitOwner, userB, value, deadline, v, r, s);

        assertEq(aOFT.nonces(permitOwner), 1);
    }

    function test_permit_after_setNameAndSymbol_invalidates_old_signature_and_accepts_new_signature() public {
        uint256 deadline = block.timestamp + 1 days;
        uint256 valueBeforeRename = 1 ether;
        uint256 valueAfterRename = 2 ether;

        // Permit works before metadata update.
        (uint8 v0, bytes32 r0, bytes32 s0) =
            _signPermit(permitOwner, permitOwnerKey, userB, valueBeforeRename, deadline);
        aOFT.permit(permitOwner, userB, valueBeforeRename, deadline, v0, r0, s0);

        assertEq(aOFT.allowance(permitOwner, userB), valueBeforeRename);
        assertEq(aOFT.nonces(permitOwner), 1);

        // Prepare a signature using the current (old) domain separator at nonce=1.
        (uint8 vOld, bytes32 rOld, bytes32 sOld) =
            _signPermit(permitOwner, permitOwnerKey, userC, valueAfterRename, deadline);
        uint256 nonceBeforeRename = aOFT.nonces(permitOwner);

        // Change metadata, which changes the EIP712 name/domain.
        aOFT.setNameAndSymbol("Nest Share Renamed", "nSHARE2", 2);

        // Old-domain signature is now invalid and nonce remains unchanged.
        bytes32 digest = _permitDigest(permitOwner, userC, valueAfterRename, nonceBeforeRename, deadline);
        address signer = ecrecover(digest, vOld, rOld, sOld);
        vm.expectRevert(
            abi.encodeWithSelector(ERC20PermitUpgradeable.ERC2612InvalidSigner.selector, signer, permitOwner)
        );
        aOFT.permit(permitOwner, userC, valueAfterRename, deadline, vOld, rOld, sOld);

        assertEq(aOFT.nonces(permitOwner), nonceBeforeRename);
        assertEq(aOFT.allowance(permitOwner, userC), 0);

        // New signature using the new domain separator should succeed.
        (uint8 vNew, bytes32 rNew, bytes32 sNew) =
            _signPermit(permitOwner, permitOwnerKey, userC, valueAfterRename, deadline);
        aOFT.permit(permitOwner, userC, valueAfterRename, deadline, vNew, rNew, sNew);

        assertEq(aOFT.allowance(permitOwner, userC), valueAfterRename);
        assertEq(aOFT.nonces(permitOwner), nonceBeforeRename + 1);
    }

    function test_permit_after_upgrade_uses_standard_domain() public {
        MockNestShareOFTV1 legacyImpl = new MockNestShareOFTV1(address(endpoints[aEid]));
        bytes memory initData = abi.encodeWithSelector(
            MockNestShareOFTV1.initialize.selector, "legacyOFT", "legacyOFT", address(this), address(this)
        );
        address proxy = address(new TransparentUpgradeableProxy(address(legacyImpl), proxyAdmin, initData));

        MockNestShareOFT newImpl = new MockNestShareOFT(address(endpoints[aEid]));
        ProxyAdmin admin = ProxyAdmin(_proxyAdmin(proxy));
        vm.prank(proxyAdmin);
        admin.upgradeAndCall(ITransparentUpgradeableProxy(proxy), address(newImpl), "");

        MockNestShareOFT upgraded = MockNestShareOFT(proxy);
        upgraded.enter(address(0), ERC20(address(0)), 0, permitOwner, initialBalance);

        uint256 value = 1 ether;
        uint256 deadline = block.timestamp + 1 days;
        uint256 nonce = upgraded.nonces(permitOwner);
        bytes32 domainSeparator = _domainSeparator(address(upgraded), upgraded.name(), "1");
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, permitOwner, userB, value, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(permitOwnerKey, digest);

        assertEq(upgraded.DOMAIN_SEPARATOR(), domainSeparator);
        upgraded.permit(permitOwner, userB, value, deadline, v, r, s);
        assertEq(upgraded.allowance(permitOwner, userB), value);
    }

    function _setBlacklistHook() internal returns (BlacklistHook hook) {
        hook = new BlacklistHook(address(this), Authority(address(0)));
        aOFT.setBeforeTransferHook(address(hook));
    }

    function test_transfer_hook_blacklisted_from_reverts() public {
        BlacklistHook hook = _setBlacklistHook();
        hook.setBlacklisted(userA, true);

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(BlacklistHook.BlacklistHook__Blacklisted.selector, userA));
        aOFT.transfer(userB, 1 ether);
    }

    function test_transfer_hook_blacklisted_from_reverts_transferFrom() public {
        BlacklistHook hook = _setBlacklistHook();
        hook.setBlacklisted(userA, true);

        vm.prank(userA);
        aOFT.approve(userB, 1 ether);

        vm.prank(userB);
        vm.expectRevert(abi.encodeWithSelector(BlacklistHook.BlacklistHook__Blacklisted.selector, userA));
        aOFT.transferFrom(userA, userB, 1 ether);
    }

    function test_transfer_hook_paused_reverts() public {
        BlacklistHook hook = _setBlacklistHook();
        hook.pause();

        vm.prank(userA);
        vm.expectRevert(BlacklistHook.BlacklistHook__Paused.selector);
        aOFT.transfer(userB, 1 ether);
    }

    function test_transfer_hook_allows_to_blacklisted() public {
        BlacklistHook hook = _setBlacklistHook();
        hook.setBlacklisted(userB, true);

        vm.prank(userA);
        aOFT.transfer(userB, 1 ether);

        assertEq(aOFT.balanceOf(userA), initialBalance - 1 ether);
        assertEq(aOFT.balanceOf(userB), 1 ether);
    }

    function test_transfer_hook_blocks_send_from_blacklisted() public {
        BlacklistHook hook = _setBlacklistHook();
        hook.setBlacklisted(userA, true);

        uint256 tokensToSend = 1 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam =
            SendParam(bEid, addressToBytes32(userB), tokensToSend, tokensToSend, options, "", "");
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(BlacklistHook.BlacklistHook__Blacklisted.selector, userA));
        aOFT.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));
    }
}
