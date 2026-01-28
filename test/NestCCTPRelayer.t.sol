// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import {MessagingFee, MessagingReceipt} from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTCoreUpgradeable.sol";
import {OFTInspectorMock} from "@layerzerolabs/oft-evm-upgradeable/test/mocks/OFTInspectorMock.sol";
import {
    IOAppOptionsType3,
    EnforcedOptionParam
} from "@layerzerolabs/oapp-evm-upgradeable/contracts/oapp/libs/OAppOptionsType3Upgradeable.sol";

import {OFTMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import {SendParam, OFTReceipt} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

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
import {NestVaultComposer} from "contracts/ovault/NestVaultComposer.sol";
import {NestCCTPRelayer} from "contracts/cctp/NestCCTPRelayer.sol";
import {MockMintBurnToken} from "test/mock/cctp/MockMintAndBurnToken.sol";
import {NestVaultPredicateProxy, PredicateMessage} from "contracts/NestVaultPredicateProxy.sol";
import {MockServiceManager} from "test/mock/MockServiceManager.sol";
import {MessageTransmitterV2} from "test/vendor/cctp/MessageTransmitterV2.sol";
import {TokenMessengerV2} from "test/vendor/cctp/TokenMessengerV2.sol";
import {TokenMinterV2} from "test/vendor/cctp/TokenMinterV2.sol";
import {FINALITY_THRESHOLD_FINALIZED} from "test/vendor/cctp/FinalityThresholds.sol";
import {TypedMemView} from "contracts/libraries/vendor/cctp/TypedMemView.sol";
import {BurnMessageV2} from "contracts/libraries/vendor/cctp/BurnMessageV2.sol";
import {AddressUtils} from "contracts/libraries/vendor/cctp/AddressUtils.sol";
import {MessageV2} from "contracts/libraries/vendor/cctp/MessageV2.sol";
import {INestVaultComposer} from "contracts/interfaces/ovault/INestVaultComposer.sol";

import "forge-std/console2.sol";

contract NestCCTPRelayerTest is TestHelperOz5 {
    using OptionsBuilder for bytes;
    using TypedMemView for bytes;
    using TypedMemView for bytes29;
    using BurnMessageV2 for bytes29;
    using MessageV2 for bytes29;
    using AddressUtils for address;
    using AddressUtils for bytes32;

    string constant POLICY_ID = "TEST_POLICY_ID";

    uint32 localEid = 1;
    uint32 remoteEid = 2;

    uint32 localDomain = 1001;
    uint32 remoteDomain = 2002;

    MessageTransmitterV2 localMessageTransmitter;
    TokenMessengerV2 localTokenMessenger;
    TokenMinterV2 localTokenMinter;

    address tokenController = makeAddr("tokenController");

    NestVaultComposer nestVaultComposer;
    NestCCTPRelayer nestCCTPRelayer;

    MockServiceManager mockServiceManager;
    NestVaultPredicateProxy nestVaultPredicateProxy;

    MockNestVaultOFT nestVaultOFT;

    MockRateProvider accountantWithRateProviders;
    MockBoringVault nestShare;
    MockNestShareOFT remoteNestShare;

    OFTInspectorMock oAppInspector;

    MockMintBurnToken localAsset;
    MockMintBurnToken remoteAsset;

    address feeRecipient = address(this);

    address userA = makeAddr("userA");
    address userB = makeAddr("userB");

    uint256 attesterPK = 1;
    address attester = vm.addr(attesterPK);

    address proxyAdmin = makeAddr("proxyAdmin");

    uint256 initialBalance = 100e6;

    address relayer = makeAddr("relayer");

    address remoteTokenMessenger = makeAddr("remoteTokenMessenger");

    function setUp() public virtual override {
        vm.deal(userA, 1000 ether);
        vm.deal(userB, 1000 ether);
        vm.deal(relayer, 1000 ether);

        accountantWithRateProviders = new MockRateProvider();
        accountantWithRateProviders.setRate(1e6);

        localAsset = new MockMintBurnToken("USDC Plume", "USDC", 6);
        remoteAsset = new MockMintBurnToken("USDC Solana", "USDC", 6);
        nestShare = new MockBoringVault("Nest Test Vault", "nTEST", 6);

        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);

        // deploy predicate proxy
        mockServiceManager = new MockServiceManager();
        // permissive service manager
        mockServiceManager.setIsVerified(true);

        _deployNestVaultPredicateProxy();

        // deploy nest vault
        _deployNestVaultOFT();

        address[] memory _attesters = new address[](1);
        _attesters[0] = address(attester);

        // deploy cctp protocol contracts
        (localTokenMinter, localTokenMessenger, localMessageTransmitter) = _deployCCTP(
            localDomain, remoteDomain, address(localAsset), address(remoteAsset), tokenController, _attesters
        );

        // (remoteTokenMinter, remoteTokenMessenger, remoteMessageTransmitter) = _deployCCTP(
        //     remoteDomain, localDomain, address(remoteAsset), address(localAsset), tokenController, _attesters
        // );

        // deploy nest cctp relayer
        _deployNestCCTPRelayer();
        console2.log("NestCCTPRelayer address:", address(nestCCTPRelayer));

        // deploy nest vault composer
        _deployNestVaultComposer();
        console2.log("NestVaultComposer address:", address(nestVaultComposer));

        // set up nest cctp relayer
        _setUpNestCCTPRelayer();

        // deploy remote oft
        _deployMockNestShareOFT();

        // set permissive mock authority functions public
        MockAuthority mockAuthority = new MockAuthority(true);
        nestVaultOFT.setAuthority(Authority(address(mockAuthority)));
        nestVaultPredicateProxy.setAuthority(Authority(address(mockAuthority)));
        nestCCTPRelayer.setAuthority(Authority(address(mockAuthority)));
        nestVaultComposer.setAuthority(Authority(address(mockAuthority)));

        // config and wire the ofts
        address[] memory ofts = new address[](2);
        ofts[0] = address(nestVaultOFT);
        ofts[1] = address(remoteNestShare);
        this.wireOApps(ofts);

        // mint tokens
        nestVaultOFT.credit(userA, initialBalance, localEid);
        remoteNestShare.credit(userB, initialBalance, remoteEid);
        localAsset.mint(userA, initialBalance);
        remoteAsset.mint(userB, initialBalance);
        localAsset.mint(address(nestShare), initialBalance);

        // deploy a universal inspector, can be used by each oft
        oAppInspector = new OFTInspectorMock();
    }

    // function test_constructor() public view virtual {
    //     assertEq(nestVaultOFT.owner(), address(this), "nestVaultOFT owner");
    //     assertEq(remoteNestShare.owner(), address(this), "remoteNestShare owner");

    //     assertEq(nestVaultOFT.balanceOf(userA), initialBalance);
    //     assertEq(remoteNestShare.balanceOf(userB), initialBalance);
    //     assertEq(localAsset.balanceOf(userA), initialBalance);
    //     assertEq(remoteAsset.balanceOf(userB), initialBalance);

    //     assertEq(nestVaultOFT.token(), address(nestShare));
    //     assertEq(remoteNestShare.token(), address(remoteNestShare));
    //     assertEq(nestCCTPRelayer.token(), address(localAsset));
    // }

    function test_deposit() public {
        uint256 _depositAmount = 1e6;
        uint256 _minAmountReceived = 0;

        // format deposit hook data
        bytes memory _hookData = _formatDepositHookDataFixed(
            _depositAmount, _minAmountReceived, remoteEid, bytes32(uint256(uint160(userA))), userA
        );

        // format msgBody (_formatBurnMessageForReceive)
        bytes memory _messageBody = _formatBurnMessageForReceive(
            1, // version
            address(remoteAsset).toBytes32(), // burnToken
            address(nestCCTPRelayer).toBytes32(), // mintRecipient
            _depositAmount, // amount
            userB.toBytes32(), // messageSender
            0, // maxFee
            0, // feeExecuted
            0, // expirationBlock
            _hookData // hookData
        );

        // format full message (_formatMessageForReceive)
        bytes memory _message = _formatMessageForReceive(
            1, // version
            remoteDomain, // sourceDomain
            localDomain, // destinationDomain
            bytes32(keccak256(abi.encodePacked(block.timestamp))), // nonce
            address(remoteTokenMessenger).toBytes32(), // sender
            address(localTokenMessenger).toBytes32(), // recipient
            address(nestCCTPRelayer).toBytes32(), // destinationCaller
            0, // minFinalityThreshold
            FINALITY_THRESHOLD_FINALIZED, // finalityThresholdExecuted
            _messageBody // messageBody
        );

        // sign message (_sign1of1Message)
        bytes memory _attestation = _sign1of1Message(_message);

        // get predicate msg
        bytes memory _predicateMsg = _formatPredicateMessage("", 0, new address[](0), new bytes[](0));

        console2.log("Remote TokenMessengerV2", address(remoteTokenMessenger));
        console2.log("TokenMessengerV2", address(localTokenMessenger));
        console2.log("MessageTransmitterV2", address(localMessageTransmitter));
        console2.log("TokenMinterV2", address(localTokenMinter));
        console2.log("NestCCTPRelayer", address(nestCCTPRelayer));
        console2.log("NestVaultComposer", address(nestVaultComposer));
        console2.log("userA", userA);
        console2.log("userB", userB);
        console2.log("relayer", relayer);
        console2.log("localAsset", address(localAsset));
        console2.log("remoteAsset", address(remoteAsset));
        console2.log("nestShare", address(nestShare));
        console2.log("remoteNestShare", address(remoteNestShare));
        console2.log("nestVaultOFT", address(nestVaultOFT));
        console2.log("nestVaultPredicateProxy", address(nestVaultPredicateProxy));

        // receive message (_receiveMessage)
        _receiveMessage(_message, _attestation, _predicateMsg, address(relayer));

        // get msg sent to lzEndpoint

        // receive on destination chain
    }

    function test_redeem() public {
        // format redeem compose msg
        bytes memory composeMsg = _formatRedeemComposeMsg(remoteEid, address(userB).toBytes32(), 0, 0);

        // send OFT + compose msg
        uint256 redeemAmount = 1e6;
        bytes memory options =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0).addExecutorLzComposeOption(0, 500000, 0);
        SendParam memory sendParam = SendParam(
            localEid, addressToBytes32(address(nestVaultComposer)), redeemAmount, redeemAmount, options, composeMsg, ""
        );
        MessagingFee memory fee = remoteNestShare.quoteSend(sendParam, false);

        vm.prank(userB);
        (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) =
            remoteNestShare.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        uint32 dstEid_ = localEid;
        address from_ = address(nestVaultOFT);
        bytes memory options_ = options;
        bytes32 guid_ = msgReceipt.guid;
        address to_ = address(nestVaultComposer);
        bytes memory composerMsg_ = OFTComposeMsgCodec.encode(
            msgReceipt.nonce,
            remoteEid,
            oftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(address(userB)), composeMsg)
        );
        this.lzCompose(dstEid_, from_, options_, guid_, to_, composerMsg_);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT HELPERS
    //////////////////////////////////////////////////////////////*/
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

    function _formatDepositHookDataFixed(
        uint256 _amount,
        uint256 _minAmountReceived,
        uint32 _dstEid,
        bytes32 _finalRecipient,
        address _refundAddress
    ) internal view returns (bytes memory _hookData) {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        SendParam memory sendParam = SendParam({
            dstEid: _dstEid,
            to: _finalRecipient,
            amountLD: 0, // overridden by NestVaultComposer (actual amount of shares received)
            minAmountLD: _minAmountReceived, // min amount of shares expected
            extraOptions: options, // extra gas options (should require only enforced)
            composeMsg: new bytes(0), // compose message to passed to the final chain (not used)
            oftCmd: new bytes(0) // oft command to be used by the OFT adapter (not used)
        });

        bytes memory callData = abi.encode(_finalRecipient, _amount, sendParam, _refundAddress);

        _hookData =
            abi.encodePacked(address(nestVaultComposer), bytes4(INestVaultComposer.depositAndSend.selector), callData);
    }

    function _formatDepositHookData(
        address _composer,
        bytes4 _selector,
        uint256 _amount,
        uint256 _minAmountReceived,
        uint32 _dstEid,
        bytes32 _finalRecipient,
        address _refundAddress
    ) internal pure returns (bytes memory _hookData) {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        SendParam memory sendParam = SendParam({
            dstEid: _dstEid, // final chain eid
            to: _finalRecipient, // user address on final chain
            amountLD: 0, // overridden by NestVaultComposer (actual amount of shares received)
            minAmountLD: _minAmountReceived, // min amount of shares expected
            extraOptions: options, // extra gas options (should require only enforced)
            composeMsg: new bytes(0), // compose message to passed to the final chain (not used)
            oftCmd: new bytes(0) // oft command to be used by the OFT adapter (not used)
        });

        bytes memory callData = abi.encode(_finalRecipient, _amount, sendParam, _refundAddress);

        _hookData = abi.encodePacked(_composer, _selector, callData);
    }

    /*//////////////////////////////////////////////////////////////
                        REDEEM HELPERS
    //////////////////////////////////////////////////////////////*/
    function _formatRedeemComposeMsg(
        uint32 _dstEid,
        bytes32 _finalRecipient,
        uint256 _minAmountReceived,
        uint256 minMsgValue
    ) internal pure returns (bytes memory _composeMsg) {
        SendParam memory sendParam = SendParam({
            dstEid: _dstEid,
            to: _finalRecipient,
            amountLD: 0, // overridden by NestVaultComposer (actual amount of assets received)
            minAmountLD: _minAmountReceived, // min amount of assets expected
            extraOptions: new bytes(0), // extra gas options (should require only enforced)
            composeMsg: new bytes(0), // compose message to passed to the final chain (not used)
            oftCmd: new bytes(0) // oft command to be used by the OFT adapter (not used)
        });

        _composeMsg = abi.encode(
            sendParam,
            minMsgValue // min msg.value passed to lzCompose (should get from NestVaultComposer.quoteSend())
        );
    }

    /*//////////////////////////////////////////////////////////////
                        CCTP HELPERS
    //////////////////////////////////////////////////////////////*/

    function _formatMessageForReceive(
        uint32 _version,
        uint32 _sourceDomain,
        uint32 _destinationDomain,
        bytes32 _nonce,
        bytes32 _sender,
        bytes32 _recipient,
        bytes32 _destinationCaller,
        uint32 _minFinalityThreshold,
        uint32 _finalityThresholdExecuted,
        bytes memory _messageBody
    ) internal pure returns (bytes memory _message) {
        _message = abi.encodePacked(
            _version,
            _sourceDomain,
            _destinationDomain,
            _nonce,
            _sender,
            _recipient,
            _destinationCaller,
            _minFinalityThreshold,
            _finalityThresholdExecuted,
            _messageBody
        );
    }

    function _formatBurnMessageForReceive(
        uint32 _version,
        bytes32 _burnToken,
        bytes32 _mintRecipient,
        uint256 _amount,
        bytes32 _messageSender,
        uint256 _maxFee,
        uint256 _feeExecuted,
        uint256 _expirationBlock,
        bytes memory _hookData
    ) internal pure returns (bytes memory _messageBody) {
        _messageBody = abi.encodePacked(
            _version,
            _burnToken,
            _mintRecipient,
            _amount,
            _messageSender,
            _maxFee,
            _feeExecuted,
            _expirationBlock,
            _hookData
        );
    }

    function _receiveMessage(bytes memory _message, bytes memory _signature, bytes memory _extraData, address _caller)
        internal
    {
        bytes29 _msg = _message.ref(0);

        MessagingFee memory _fee = nestCCTPRelayer.quoteRelay(_message, _extraData);

        // Receive message
        vm.prank(_caller);
        (bool _relaySuccess, bool _hookSuccess) =
            nestCCTPRelayer.relay{value: _fee.nativeFee}(_message, _signature, _extraData, false);
        assertTrue(_relaySuccess);
        assertTrue(_hookSuccess);
        vm.stopPrank();

        // Check that the nonce is now used
        assertEq(localMessageTransmitter.usedNonces(_msg._getNonce()), localMessageTransmitter.NONCE_USED());
    }

    function _sign1of1Message(bytes memory _message) internal view returns (bytes memory) {
        uint256[] memory _privateKeys = new uint256[](1);
        _privateKeys[0] = attesterPK;
        return _signMessage(_message, _privateKeys);
    }

    function _signMessage(bytes memory _message, uint256[] memory _privKeys)
        internal
        pure
        returns (bytes memory _attestations)
    {
        bytes memory _signaturesConcatenated = "";

        for (uint256 i = 0; i < _privKeys.length; i++) {
            uint256 _privKey = _privKeys[i];
            bytes32 _digest = keccak256(_message);
            (uint8 _v, bytes32 _r, bytes32 _s) = vm.sign(_privKey, _digest);
            bytes memory _signature = abi.encodePacked(_r, _s, _v);

            _signaturesConcatenated = abi.encodePacked(_signaturesConcatenated, _signature);
        }

        return _signaturesConcatenated;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPLOYMENT HELPERS
    //////////////////////////////////////////////////////////////*/

    function _deployMockNestShareOFT() internal {
        remoteNestShare = MockNestShareOFT(
            _deployContractAndProxy(
                type(MockNestShareOFT).creationCode,
                abi.encode(address(endpoints[remoteEid])),
                abi.encodeWithSelector(NestShareOFT.initialize.selector, "Nest Test Vault", "nTEST", address(this))
            )
        );
    }

    function _deployNestVaultOFT() internal {
        nestVaultOFT = MockNestVaultOFT(
            _deployContractAndProxy(
                type(MockNestVaultOFT).creationCode,
                abi.encode(address(payable(nestShare)), address(endpoints[localEid])),
                abi.encodeWithSelector(
                    NestVaultOFT.initialize.selector,
                    accountantWithRateProviders,
                    address(localAsset),
                    address(this),
                    address(this),
                    1
                )
            )
        );
    }

    function _deployNestVaultPredicateProxy() internal {
        // deploy nest vault predicate proxy
        nestVaultPredicateProxy = NestVaultPredicateProxy(
            _deployContractAndProxy(
                type(NestVaultPredicateProxy).creationCode,
                bytes(""),
                abi.encodeWithSelector(
                    NestVaultPredicateProxy.initialize.selector, address(this), address(mockServiceManager), POLICY_ID
                )
            )
        );
    }

    function _deployNestVaultComposer() internal {
        // deploy nest vault composer
        nestVaultComposer = NestVaultComposer(
            _deployContractAndProxy(
                type(NestVaultComposer).creationCode,
                abi.encode(address(nestVaultPredicateProxy)),
                abi.encodeWithSelector(
                    NestVaultComposer.initialize.selector,
                    address(this),
                    address(nestVaultOFT),
                    address(nestCCTPRelayer),
                    address(nestVaultOFT)
                )
            )
        );
    }

    function _deployNestCCTPRelayer() internal {
        // deploy nest cctp relayer
        nestCCTPRelayer = NestCCTPRelayer(
            _deployContractAndProxy(
                type(NestCCTPRelayer).creationCode,
                abi.encode(
                    address(localMessageTransmitter),
                    address(localTokenMessenger),
                    address(endpoints[localEid]),
                    address(localAsset)
                ),
                abi.encodeWithSelector(
                    NestCCTPRelayer.initialize.selector,
                    address(this) // owner
                )
            )
        );
    }

    function _setUpNestCCTPRelayer() internal {
        // set nest vault composer
        nestCCTPRelayer.setComposer(address(nestVaultComposer), true);

        // set eid to domain
        nestCCTPRelayer.setEidToDomain(localEid, localDomain);
        nestCCTPRelayer.setEidToDomain(remoteEid, remoteDomain);

        // set finality threshold
        nestCCTPRelayer.setFinalityThreshold(2000);
    }

    function _deployCCTP(
        uint32 _localDomain,
        uint32 _remoteDomain,
        address _localAsset,
        address _remoteAsset,
        address _tokenController,
        address[] memory _attesters
    )
        internal
        returns (
            TokenMinterV2 _tokenMinterV2,
            TokenMessengerV2 _tokenMessengerV2,
            MessageTransmitterV2 _messageTransmitterV2
        )
    {
        _tokenMinterV2 = new TokenMinterV2(_tokenController);

        // deploy mock cctp contracts
        _messageTransmitterV2 = MessageTransmitterV2(
            _deployContractAndProxy(
                type(MessageTransmitterV2).creationCode,
                abi.encode(
                    _localDomain,
                    1 // version
                ),
                abi.encodeWithSelector(
                    MessageTransmitterV2.initialize.selector,
                    address(this), // pauser
                    address(this), // rescuer
                    address(this), // attesterManager
                    _attesters, // initialAttester
                    1, // signatureThreshold
                    8 * 2 ** 10 // maxMessageBodySize (8 KB)
                )
            )
        );

        TokenMessengerV2.TokenMessengerV2Roles memory roles = TokenMessengerV2.TokenMessengerV2Roles({
            owner: address(this),
            rescuer: address(this),
            feeRecipient: address(this),
            denylister: address(this),
            tokenMinter: address(_tokenMinterV2),
            minFeeController: address(this)
        });

        (uint32[] memory _remoteDomains, bytes32[] memory _remoteTokenMessengers) = _defaultRemoteTokenMessengers();

        _tokenMessengerV2 = TokenMessengerV2(
            _deployContractAndProxy(
                type(TokenMessengerV2).creationCode,
                abi.encode(
                    address(_messageTransmitterV2),
                    uint32(1) // message body version
                ),
                abi.encodeWithSelector(
                    TokenMessengerV2.initialize.selector,
                    roles,
                    uint256(0), // minFee
                    _remoteDomains,
                    _remoteTokenMessengers
                )
            )
        );

        _tokenMinterV2.addLocalTokenMessenger(address(_tokenMessengerV2));

        vm.startPrank(_tokenController);
        _tokenMinterV2.linkTokenPair(_localAsset, _remoteDomain, OFTMsgCodec.addressToBytes32(_remoteAsset));
        _tokenMinterV2.setMaxBurnAmountPerMessage(_localAsset, type(uint256).max);
        vm.stopPrank();
    }

    function _defaultRemoteTokenMessengers()
        internal
        view
        returns (uint32[] memory _remoteDomains, bytes32[] memory _remoteTokenMessengers)
    {
        _remoteDomains = new uint32[](1);
        _remoteDomains[0] = remoteDomain;

        _remoteTokenMessengers = new bytes32[](1);
        _remoteTokenMessengers[0] = OFTMsgCodec.addressToBytes32(address(remoteTokenMessenger));
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
}
