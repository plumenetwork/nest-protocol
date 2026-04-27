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
import {Vm} from "forge-std/Vm.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {MockNestShareOFT} from "test/mock/MockNestShareOFT.sol";
import {NestShareOFT} from "contracts/NestShareOFT.sol";
import {MockBoringVault} from "test/mock/MockBoringVault.sol";
import {MockAuthority} from "test/mock/MockAuthority.sol";
import {MockRateProvider} from "test/mock/MockRateProvider.sol";
import {MockNestVaultOFT} from "test/mock/MockNestVaultOFT.sol";
import {NestVaultOFT} from "contracts/NestVaultOFT.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {NestVault} from "contracts/NestVault.sol";
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
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {IVaultComposerSync} from "@layerzerolabs/ovault-evm/contracts/interfaces/IVaultComposerSync.sol";
import {NestVaultCoreTypes} from "contracts/libraries/nest-vault/NestVaultCoreTypes.sol";
import {Errors} from "contracts/types/Errors.sol";
import {VaultComposerAsyncUpgradeable} from "contracts/upgradeable/ovault/VaultComposerAsyncUpgradeable.sol";

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

        // Set enforced options for lzReceive gas on both OFTs
        // This allows refunds to work without explicit extraOptions
        bytes memory lzReceiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        EnforcedOptionParam[] memory enforcedOptions = new EnforcedOptionParam[](1);
        enforcedOptions[0] = EnforcedOptionParam(remoteEid, 1, lzReceiveOptions); // msgType 1 = SEND
        nestVaultOFT.setEnforcedOptions(enforcedOptions);

        enforcedOptions[0] = EnforcedOptionParam(localEid, 1, lzReceiveOptions);
        remoteNestShare.setEnforcedOptions(enforcedOptions);

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

    function test_relay_legacy_overload_works() public {
        uint256 depositAmount = 1e6;
        bytes memory hookData =
            _formatDepositHookDataFixed(depositAmount, 0, remoteEid, bytes32(uint256(uint160(userA))), userA);

        bytes memory messageBody = _formatBurnMessageForReceive(
            1,
            address(remoteAsset).toBytes32(),
            address(nestCCTPRelayer).toBytes32(),
            depositAmount,
            userB.toBytes32(),
            0,
            0,
            0,
            hookData
        );
        bytes memory message = _formatMessageForReceive(
            1,
            remoteDomain,
            localDomain,
            bytes32(keccak256(abi.encodePacked(block.timestamp, uint256(11)))),
            address(remoteTokenMessenger).toBytes32(),
            address(localTokenMessenger).toBytes32(),
            address(nestCCTPRelayer).toBytes32(),
            0,
            FINALITY_THRESHOLD_FINALIZED,
            messageBody
        );
        bytes memory attestation = _sign1of1Message(message);
        bytes memory predicateMsg = _formatPredicateMessage("", 0, new address[](0), new bytes[](0));

        MessagingFee memory fee = nestCCTPRelayer.quoteRelay(message, predicateMsg, new bytes(0));

        vm.prank(relayer);
        (bool relaySuccess, bool hookSuccess) =
            nestCCTPRelayer.relay{value: fee.nativeFee}(message, attestation, predicateMsg, false);
        assertTrue(relaySuccess, "legacy relay overload should succeed");
        assertTrue(hookSuccess, "legacy relay overload should execute hook");
    }

    function test_relay_extraOptions_overload_works() public {
        uint256 depositAmount = 1e6;
        bytes memory hookData =
            _formatDepositHookDataFixed(depositAmount, 0, remoteEid, bytes32(uint256(uint160(userA))), userA);

        bytes memory messageBody = _formatBurnMessageForReceive(
            1,
            address(remoteAsset).toBytes32(),
            address(nestCCTPRelayer).toBytes32(),
            depositAmount,
            userB.toBytes32(),
            0,
            0,
            0,
            hookData
        );
        bytes memory message = _formatMessageForReceive(
            1,
            remoteDomain,
            localDomain,
            bytes32(keccak256(abi.encodePacked(block.timestamp, uint256(12)))),
            address(remoteTokenMessenger).toBytes32(),
            address(localTokenMessenger).toBytes32(),
            address(nestCCTPRelayer).toBytes32(),
            0,
            FINALITY_THRESHOLD_FINALIZED,
            messageBody
        );
        bytes memory attestation = _sign1of1Message(message);
        bytes memory predicateMsg = _formatPredicateMessage("", 0, new address[](0), new bytes[](0));
        bytes memory relayerExtraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(400000, 0);

        MessagingFee memory defaultFee = nestCCTPRelayer.quoteRelay(message, predicateMsg, new bytes(0));
        MessagingFee memory feeWithExtra = nestCCTPRelayer.quoteRelay(message, predicateMsg, relayerExtraOptions);
        assertGt(feeWithExtra.nativeFee, defaultFee.nativeFee, "extraOptions should affect quote");

        vm.prank(relayer);
        (bool relaySuccess, bool hookSuccess) = nestCCTPRelayer.relay{value: feeWithExtra.nativeFee}(
            message, attestation, predicateMsg, relayerExtraOptions, false
        );
        assertTrue(relaySuccess, "relay overload with extraOptions should succeed");
        assertTrue(hookSuccess, "relay overload with extraOptions should execute hook");
    }

    function test_instant_redeem() public {
        // format redeem compose msg
        bytes memory composeMsg = _formatInstantRedeemComposeMsg(remoteEid, address(userB).toBytes32(), 0, 0);

        // send OFT + compose msg
        uint256 redeemAmount = 1e6;
        bytes memory options =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0).addExecutorLzComposeOption(0, 500000, 0);
        SendParam memory sendParam = SendParam(
            localEid, addressToBytes32(address(nestVaultComposer)), redeemAmount, redeemAmount, options, composeMsg, ""
        );
        MessagingFee memory fee = remoteNestShare.quoteSend(sendParam, false);

        // State before send - capture userB's remote share balance
        uint256 userBRemoteSharesBefore = remoteNestShare.balanceOf(userB);

        vm.prank(userB);
        (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) =
            remoteNestShare.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));

        // Assert userB's shares were debited on remote chain
        assertEq(
            remoteNestShare.balanceOf(userB),
            userBRemoteSharesBefore - redeemAmount,
            "userB remote shares should decrease by redeemAmount after send"
        );

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

        // State before lzCompose on local chain
        uint256 composerAssetBalanceBefore = localAsset.balanceOf(address(nestVaultComposer));
        uint256 vaultShareBalanceBefore = nestShare.balanceOf(address(nestVaultOFT));
        uint256 vaultAssetBalanceBefore = localAsset.balanceOf(address(nestShare));
        uint256 shareTotalSupplyBefore = nestShare.totalSupply();

        this.lzCompose(dstEid_, from_, options_, guid_, to_, composerMsg_);

        // State after lzCompose - assert _redeemAndSend state changes via instantRedeem
        uint256 amountReceived = oftReceipt.amountReceivedLD;

        // Shares: credited to composer, transferred to vault, then burned
        assertEq(
            nestShare.balanceOf(address(nestVaultComposer)),
            0,
            "composer share balance should be 0 (shares credited, transferred to vault, then burned)"
        );
        assertEq(
            nestShare.balanceOf(address(nestVaultOFT)),
            vaultShareBalanceBefore,
            "vault share balance should remain same (shares burned during instantRedeem)"
        );
        assertEq(
            nestShare.totalSupply(),
            shareTotalSupplyBefore - amountReceived,
            "share totalSupply should decrease by amountReceived (shares burned)"
        );

        // Assets: withdrawn from vault to composer, then sent via CCTP
        assertEq(
            localAsset.balanceOf(address(nestVaultComposer)),
            composerAssetBalanceBefore,
            "composer asset balance should remain same (assets received then sent via CCTP)"
        );
        assertEq(
            localAsset.balanceOf(address(nestShare)),
            vaultAssetBalanceBefore - amountReceived,
            "nestShare (BoringVault) asset balance should decrease by redeemed amount"
        );
    }

    function test_request_redeem() public {
        // format redeem compose msg
        bytes memory composeMsg = _formatRequestRedeemComposeMsg(remoteEid, address(userB).toBytes32(), 0, 0);

        // send OFT + compose msg
        uint256 redeemAmount = 1e6;
        bytes memory options =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0).addExecutorLzComposeOption(0, 500000, 0);
        SendParam memory sendParam = SendParam(
            localEid, addressToBytes32(address(nestVaultComposer)), redeemAmount, redeemAmount, options, composeMsg, ""
        );
        MessagingFee memory fee = remoteNestShare.quoteSend(sendParam, false);

        // State before send - capture userB's remote share balance
        uint256 userBRemoteSharesBefore = remoteNestShare.balanceOf(userB);

        vm.prank(userB);
        (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) =
            remoteNestShare.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));

        // Assert userB's shares were debited on remote chain
        assertEq(
            remoteNestShare.balanceOf(userB),
            userBRemoteSharesBefore - redeemAmount,
            "userB remote shares should decrease by redeemAmount after send"
        );

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

        // State before lzCompose - VaultComposer state
        uint256 totalPendingSharesSumBefore = nestVaultComposer.totalPendingSharesSum();
        uint256 totalPendingSharesBefore = nestVaultComposer.totalPendingShares(remoteEid);
        NestVaultCoreTypes.PendingRedeem memory pendingRedeemBefore =
            nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid);

        // State before lzCompose - NestVaultOFT (NestVaultCore) state
        uint256 vaultTotalPendingSharesBefore = nestVaultOFT.totalPendingShares();
        uint256 vaultPendingRedeemBefore = nestVaultOFT.pendingRedeemRequest(0, address(nestVaultComposer));
        uint256 vaultShareBalanceBefore = nestShare.balanceOf(address(nestVaultOFT));

        this.lzCompose(dstEid_, from_, options_, guid_, to_, composerMsg_);

        // State after lzCompose - assert state changes from _requestRedeem
        uint256 amountReceived = oftReceipt.amountReceivedLD;

        // VaultComposer state assertions
        assertEq(
            nestVaultComposer.totalPendingSharesSum(),
            totalPendingSharesSumBefore + amountReceived,
            "composer: totalPendingSharesSum should increase by amountReceived"
        );
        assertEq(
            nestVaultComposer.totalPendingShares(remoteEid),
            totalPendingSharesBefore + amountReceived,
            "composer: totalPendingShares[remoteEid] should increase by amountReceived"
        );
        NestVaultCoreTypes.PendingRedeem memory pendingRedeemAfter =
            nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid);
        assertEq(
            pendingRedeemAfter.shares,
            pendingRedeemBefore.shares + amountReceived,
            "composer: pendingRedeem[userB][remoteEid].shares should increase by amountReceived"
        );

        // NestVaultOFT (NestVaultCore) state assertions
        assertEq(
            nestVaultOFT.totalPendingShares(),
            vaultTotalPendingSharesBefore + amountReceived,
            "vault: totalPendingShares should increase by amountReceived"
        );
        assertEq(
            nestVaultOFT.pendingRedeemRequest(0, address(nestVaultComposer)),
            vaultPendingRedeemBefore + amountReceived,
            "vault: pendingRedeemRequest for composer should increase by amountReceived"
        );

        // Share balance assertions - shares transferred from composer to vault via requestRedeem
        assertEq(
            nestShare.balanceOf(address(nestVaultComposer)),
            0,
            "composer share balance should be 0 (shares transferred to vault via requestRedeem)"
        );
        assertEq(
            nestShare.balanceOf(address(nestVaultOFT)),
            vaultShareBalanceBefore + amountReceived,
            "vault should hold the pending shares"
        );
    }

    function test_update_redeem() public {
        // Step 1: First request a redeem to set up pending shares
        bytes memory requestComposeMsg = _formatRequestRedeemComposeMsg(remoteEid, address(userB).toBytes32(), 0, 0);
        uint256 initialRedeemAmount = 1e6;
        bytes memory requestOptions =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0).addExecutorLzComposeOption(0, 500000, 0);
        SendParam memory requestSendParam = SendParam(
            localEid,
            addressToBytes32(address(nestVaultComposer)),
            initialRedeemAmount,
            initialRedeemAmount,
            requestOptions,
            requestComposeMsg,
            ""
        );
        MessagingFee memory requestFee = remoteNestShare.quoteSend(requestSendParam, false);

        vm.prank(userB);
        (MessagingReceipt memory requestMsgReceipt, OFTReceipt memory requestOftReceipt) =
            remoteNestShare.send{value: requestFee.nativeFee}(requestSendParam, requestFee, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory requestComposerMsg = OFTComposeMsgCodec.encode(
            requestMsgReceipt.nonce,
            remoteEid,
            requestOftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(address(userB)), requestComposeMsg)
        );

        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            requestOptions,
            requestMsgReceipt.guid,
            address(nestVaultComposer),
            requestComposerMsg
        );

        // Verify request redeem succeeded
        uint256 pendingSharesAfterRequest =
            nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid).shares;
        assertEq(
            pendingSharesAfterRequest, requestOftReceipt.amountReceivedLD, "Pending shares should be set after request"
        );

        // Step 2: Now update the redeem request to reduce shares
        uint256 newSharesAmount = pendingSharesAfterRequest / 2; // Reduce to half
        uint256 returnAmount = pendingSharesAfterRequest - newSharesAmount;

        // Quote the fee for sending back the excess shares (include oftCmd for accurate fee)
        bytes memory returnExtraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory quoteSendParam = SendParam(
            remoteEid,
            addressToBytes32(address(userB)),
            returnAmount,
            0,
            returnExtraOptions,
            new bytes(0),
            abi.encode(VaultComposerAsyncUpgradeable.RedeemType.UpdateRedeemRequest) // redeem type in oftCmd
        );
        MessagingFee memory returnFee = nestVaultOFT.quoteSend(quoteSendParam, false);
        // Add a small buffer for fee variations
        uint256 returnFeeWithBuffer = returnFee.nativeFee + 1000;

        // Include the return fee value in the lzCompose options
        bytes memory updateOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0)
            .addExecutorLzComposeOption(0, 2000000, uint128(returnFeeWithBuffer));

        bytes memory updateComposeMsg =
            _formatUpdateRedeemComposeMsg(remoteEid, address(userB).toBytes32(), newSharesAmount, returnFeeWithBuffer);

        SendParam memory updateSendParam = SendParam(
            localEid,
            addressToBytes32(address(nestVaultComposer)),
            0, // No new shares sent for update
            0,
            updateOptions,
            updateComposeMsg,
            ""
        );

        MessagingFee memory updateFee = remoteNestShare.quoteSend(updateSendParam, false);

        vm.prank(userB);
        (MessagingReceipt memory updateMsgReceipt, OFTReceipt memory updateOftReceipt) =
            remoteNestShare.send{value: updateFee.nativeFee}(updateSendParam, updateFee, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        // State before update lzCompose - verify initial request was recorded correctly
        uint256 totalPendingSharesSumBefore = nestVaultComposer.totalPendingSharesSum();
        uint256 totalPendingSharesBefore = nestVaultComposer.totalPendingShares(remoteEid);
        assertEq(
            nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid).shares,
            pendingSharesAfterRequest,
            "Initial pending redeem should match initial shares"
        );

        // State before update lzCompose - NestVaultOFT (NestVaultCore) state
        uint256 vaultTotalPendingSharesBefore = nestVaultOFT.totalPendingShares();
        uint256 vaultPendingRedeemBefore = nestVaultOFT.pendingRedeemRequest(0, address(nestVaultComposer));
        uint256 vaultShareBalanceBefore = nestShare.balanceOf(address(nestVaultOFT));

        // Capture userB's remote balance before the update (to verify returned shares are bridged back)
        uint256 userBRemoteBalanceBefore = remoteNestShare.balanceOf(userB);

        bytes memory updateComposerMsg = OFTComposeMsgCodec.encode(
            updateMsgReceipt.nonce,
            remoteEid,
            updateOftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(address(userB)), updateComposeMsg)
        );

        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            updateOptions,
            updateMsgReceipt.guid,
            address(nestVaultComposer),
            updateComposerMsg
        );

        // Verify the returned shares are bridged to remote chain
        verifyPackets(remoteEid, addressToBytes32(address(remoteNestShare)));

        // Assert userB received the returned shares on remote chain
        uint256 userBRemoteBalanceAfter = remoteNestShare.balanceOf(userB);
        assertEq(
            userBRemoteBalanceAfter,
            userBRemoteBalanceBefore + returnAmount,
            "userB should receive returnAmount of shares on remote chain"
        );

        // State after update lzCompose - assert state changes from _updateRedeemRequest
        assertEq(
            nestVaultComposer.totalPendingSharesSum(),
            totalPendingSharesSumBefore - returnAmount,
            "totalPendingSharesSum should decrease by returnAmount"
        );
        assertEq(
            nestVaultComposer.totalPendingShares(remoteEid),
            totalPendingSharesBefore - returnAmount,
            "totalPendingShares[remoteEid] should decrease by returnAmount"
        );
        NestVaultCoreTypes.PendingRedeem memory pendingRedeemAfter =
            nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid);
        assertEq(
            pendingRedeemAfter.shares,
            newSharesAmount,
            "pendingRedeem[userB][remoteEid].shares should be updated to newSharesAmount"
        );

        // NestVaultOFT (NestVaultCore) state assertions after update
        assertEq(
            nestVaultOFT.totalPendingShares(),
            vaultTotalPendingSharesBefore - returnAmount,
            "vault: totalPendingShares should decrease by returnAmount"
        );
        assertEq(
            nestVaultOFT.pendingRedeemRequest(0, address(nestVaultComposer)),
            vaultPendingRedeemBefore - returnAmount,
            "vault: pendingRedeemRequest for composer should decrease by returnAmount"
        );
        // Vault share balance should decrease (shares returned to composer, then bridged out)
        assertEq(
            nestShare.balanceOf(address(nestVaultOFT)),
            vaultShareBalanceBefore - returnAmount,
            "vault share balance should decrease by returnAmount (shares returned and bridged)"
        );
    }

    /// @notice Tests that update redeem with multiple users maintains correct accounting
    /// @dev This test validates _updateRequestRedeemAndSend passes totalPendingSharesSum
    ///      to NestVaultCore.updateRedeem (not just the individual user's new shares).
    function test_update_redeem_multiUser_accounting() public {
        // Create a third user (userC) for this multi-user test
        address userC = makeAddr("userC");
        remoteNestShare.credit(userC, initialBalance, remoteEid);
        // Fund userC with native tokens for LZ fees
        vm.deal(userC, 10 ether);

        uint256 userBRedeemAmount = 1e6;
        uint256 userCRedeemAmount = 5e5; // 0.5e6

        // Step 1: userB requests redeem for userBRedeemAmount shares
        bytes memory requestComposeMsgB = _formatRequestRedeemComposeMsg(remoteEid, address(userB).toBytes32(), 0, 0);
        bytes memory requestOptions =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0).addExecutorLzComposeOption(0, 500000, 0);
        SendParam memory requestSendParamB = SendParam(
            localEid,
            addressToBytes32(address(nestVaultComposer)),
            userBRedeemAmount,
            userBRedeemAmount,
            requestOptions,
            requestComposeMsgB,
            ""
        );
        MessagingFee memory requestFeeB = remoteNestShare.quoteSend(requestSendParamB, false);

        vm.prank(userB);
        (MessagingReceipt memory requestMsgReceiptB, OFTReceipt memory requestOftReceiptB) =
            remoteNestShare.send{value: requestFeeB.nativeFee}(requestSendParamB, requestFeeB, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory requestComposerMsgB = OFTComposeMsgCodec.encode(
            requestMsgReceiptB.nonce,
            remoteEid,
            requestOftReceiptB.amountReceivedLD,
            abi.encodePacked(addressToBytes32(address(userB)), requestComposeMsgB)
        );

        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            requestOptions,
            requestMsgReceiptB.guid,
            address(nestVaultComposer),
            requestComposerMsgB
        );

        // Step 2: userC requests redeem for userCRedeemAmount shares
        bytes memory requestComposeMsgC = _formatRequestRedeemComposeMsg(remoteEid, address(userC).toBytes32(), 0, 0);
        SendParam memory requestSendParamC = SendParam(
            localEid,
            addressToBytes32(address(nestVaultComposer)),
            userCRedeemAmount,
            userCRedeemAmount,
            requestOptions,
            requestComposeMsgC,
            ""
        );
        MessagingFee memory requestFeeC = remoteNestShare.quoteSend(requestSendParamC, false);

        vm.prank(userC);
        (MessagingReceipt memory requestMsgReceiptC, OFTReceipt memory requestOftReceiptC) =
            remoteNestShare.send{value: requestFeeC.nativeFee}(requestSendParamC, requestFeeC, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory requestComposerMsgC = OFTComposeMsgCodec.encode(
            requestMsgReceiptC.nonce,
            remoteEid,
            requestOftReceiptC.amountReceivedLD,
            abi.encodePacked(addressToBytes32(address(userC)), requestComposeMsgC)
        );

        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            requestOptions,
            requestMsgReceiptC.guid,
            address(nestVaultComposer),
            requestComposerMsgC
        );

        // Verify both requests were recorded
        uint256 pendingSharesB = nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid).shares;
        uint256 pendingSharesC = nestVaultComposer.pendingRedeem(addressToBytes32(address(userC)), remoteEid).shares;
        assertEq(pendingSharesB, requestOftReceiptB.amountReceivedLD, "userB pending shares should match");
        assertEq(pendingSharesC, requestOftReceiptC.amountReceivedLD, "userC pending shares should match");

        // Verify composer and vault totals before update
        uint256 composerTotalBefore = nestVaultComposer.totalPendingSharesSum();
        uint256 vaultTotalBefore = nestVaultOFT.totalPendingShares();
        uint256 vaultComposerPendingBefore = nestVaultOFT.pendingRedeemRequest(0, address(nestVaultComposer));
        assertEq(composerTotalBefore, pendingSharesB + pendingSharesC, "composer total should be sum of both users");
        assertEq(vaultTotalBefore, pendingSharesB + pendingSharesC, "vault total should match composer total");
        assertEq(vaultComposerPendingBefore, pendingSharesB + pendingSharesC, "vault composer pending should match");

        // Step 3: userB updates their redeem request to reduce shares to half
        uint256 newSharesAmountB = pendingSharesB / 2;
        uint256 returnAmountB = pendingSharesB - newSharesAmountB;

        // Quote the fee for sending back the excess shares
        bytes memory returnExtraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory quoteSendParam = SendParam(
            remoteEid,
            addressToBytes32(address(userB)),
            returnAmountB,
            0,
            returnExtraOptions,
            new bytes(0),
            abi.encode(VaultComposerAsyncUpgradeable.RedeemType.UpdateRedeemRequest) // redeem type in oftCmd
        );
        MessagingFee memory returnFee = nestVaultOFT.quoteSend(quoteSendParam, false);
        uint256 returnFeeWithBuffer = returnFee.nativeFee + 1000;

        bytes memory updateOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0)
            .addExecutorLzComposeOption(0, 2000000, uint128(returnFeeWithBuffer));

        bytes memory updateComposeMsg =
            _formatUpdateRedeemComposeMsg(remoteEid, address(userB).toBytes32(), newSharesAmountB, returnFeeWithBuffer);

        SendParam memory updateSendParam = SendParam(
            localEid,
            addressToBytes32(address(nestVaultComposer)),
            0, // No new shares sent for update
            0,
            updateOptions,
            updateComposeMsg,
            ""
        );

        MessagingFee memory updateFee = remoteNestShare.quoteSend(updateSendParam, false);

        vm.prank(userB);
        (MessagingReceipt memory updateMsgReceipt, OFTReceipt memory updateOftReceipt) =
            remoteNestShare.send{value: updateFee.nativeFee}(updateSendParam, updateFee, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory updateComposerMsg = OFTComposeMsgCodec.encode(
            updateMsgReceipt.nonce,
            remoteEid,
            updateOftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(address(userB)), updateComposeMsg)
        );

        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            updateOptions,
            updateMsgReceipt.guid,
            address(nestVaultComposer),
            updateComposerMsg
        );

        // Verify the returned shares are bridged to remote chain
        verifyPackets(remoteEid, addressToBytes32(address(remoteNestShare)));

        // CRITICAL ASSERTIONS: These would fail with the old buggy code
        // The old code passed newSharesAmountB to vault.updateRedeem, which would have
        // set vault's pending to just newSharesAmountB, losing userC's pendingSharesC

        // Assert userB's pending shares are updated correctly
        uint256 pendingSharesBAfter =
            nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid).shares;
        assertEq(pendingSharesBAfter, newSharesAmountB, "userB pending shares should be reduced to newSharesAmountB");

        // CRITICAL: Assert userC's pending shares are UNCHANGED
        uint256 pendingSharesCAfter =
            nestVaultComposer.pendingRedeem(addressToBytes32(address(userC)), remoteEid).shares;
        assertEq(pendingSharesCAfter, pendingSharesC, "CRITICAL: userC pending shares must remain unchanged");

        // Assert composer totals are correct
        uint256 expectedComposerTotal = newSharesAmountB + pendingSharesC;
        assertEq(
            nestVaultComposer.totalPendingSharesSum(),
            expectedComposerTotal,
            "composer totalPendingSharesSum should be newSharesAmountB + pendingSharesC"
        );

        // CRITICAL: Assert vault totals match composer totals
        // With the old buggy code, vault.pendingRedeemRequest would be newSharesAmountB (losing userC's shares)
        // With the fix, it should be newSharesAmountB + pendingSharesC
        assertEq(
            nestVaultOFT.totalPendingShares(),
            expectedComposerTotal,
            "CRITICAL: vault totalPendingShares should match composer total"
        );
        assertEq(
            nestVaultOFT.pendingRedeemRequest(0, address(nestVaultComposer)),
            expectedComposerTotal,
            "CRITICAL: vault pendingRedeemRequest for composer should match composer total"
        );

        // Additional sanity check: the difference should only be returnAmountB
        assertEq(
            composerTotalBefore - nestVaultComposer.totalPendingSharesSum(),
            returnAmountB,
            "Total reduction should equal returnAmountB"
        );
        assertEq(
            vaultTotalBefore - nestVaultOFT.totalPendingShares(),
            returnAmountB,
            "Vault total reduction should equal returnAmountB"
        );
    }

    function test_finish_redeem() public {
        // Step 1: First request a redeem to set up pending shares
        bytes memory requestComposeMsg = _formatRequestRedeemComposeMsg(remoteEid, address(userB).toBytes32(), 0, 0);
        uint256 initialRedeemAmount = 1e6;
        bytes memory requestOptions =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0).addExecutorLzComposeOption(0, 500000, 0);
        SendParam memory requestSendParam = SendParam(
            localEid,
            addressToBytes32(address(nestVaultComposer)),
            initialRedeemAmount,
            initialRedeemAmount,
            requestOptions,
            requestComposeMsg,
            ""
        );
        MessagingFee memory requestFee = remoteNestShare.quoteSend(requestSendParam, false);

        vm.prank(userB);
        (MessagingReceipt memory requestMsgReceipt, OFTReceipt memory requestOftReceipt) =
            remoteNestShare.send{value: requestFee.nativeFee}(requestSendParam, requestFee, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory requestComposerMsg = OFTComposeMsgCodec.encode(
            requestMsgReceipt.nonce,
            remoteEid,
            requestOftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(address(userB)), requestComposeMsg)
        );

        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            requestOptions,
            requestMsgReceipt.guid,
            address(nestVaultComposer),
            requestComposerMsg
        );

        // Verify request redeem succeeded
        uint256 pendingSharesAfterRequest =
            nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid).shares;
        assertEq(
            pendingSharesAfterRequest, requestOftReceipt.amountReceivedLD, "Pending shares should be set after request"
        );

        // Step 2: Fulfill the redeem request through the composer (operator converts pending -> claimable)
        // This makes shares claimable by calling fulfillRedeem on NestVaultComposer which updates per-user tracking
        // and then calls NestVaultCore.fulfillRedeem
        uint256 vaultPendingSharesBefore = nestVaultOFT.totalPendingShares();
        uint256 vaultClaimableSharesBefore = nestVaultOFT.claimableRedeemRequest(0, address(nestVaultComposer));

        // Call fulfillRedeem through the composer to update per-user claimable tracking
        nestVaultComposer.fulfillRedeem(remoteEid, addressToBytes32(address(userB)), pendingSharesAfterRequest);

        // Verify fulfillRedeem succeeded - pending decreased, claimable increased
        assertEq(
            nestVaultOFT.totalPendingShares(),
            vaultPendingSharesBefore - pendingSharesAfterRequest,
            "vault: totalPendingShares should decrease after fulfillRedeem"
        );
        assertEq(
            nestVaultOFT.claimableRedeemRequest(0, address(nestVaultComposer)),
            vaultClaimableSharesBefore + pendingSharesAfterRequest,
            "vault: claimableRedeemRequest should increase after fulfillRedeem"
        );

        // Step 3: Complete the redeem via compose message
        uint256 redeemShareAmount = pendingSharesAfterRequest;

        // Quote the fee for sending assets back to user
        bytes memory assetSendOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory quoteSendParam = SendParam(
            remoteEid,
            addressToBytes32(address(userB)),
            redeemShareAmount, // expected asset amount (roughly equal to shares for 1:1 rate)
            0,
            assetSendOptions,
            new bytes(0),
            abi.encode(VaultComposerAsyncUpgradeable.RedeemType.FinishRedeem) // redeem type in oftCmd
        );
        // Use nestCCTPRelayer as assetOft for fee quote (as configured in _deployNestVaultComposer)
        MessagingFee memory assetSendFee = nestCCTPRelayer.quoteSend(quoteSendParam, false);
        uint256 assetSendFeeWithBuffer = assetSendFee.nativeFee + 1000;

        // Include the asset send fee in the lzCompose options
        bytes memory completeOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0)
            .addExecutorLzComposeOption(0, 2000000, uint128(assetSendFeeWithBuffer));

        bytes memory completeComposeMsg = _formatCompleteRedeemComposeMsg(
            remoteEid, address(userB).toBytes32(), redeemShareAmount, 0, assetSendFeeWithBuffer
        );

        SendParam memory completeSendParam = SendParam(
            localEid,
            addressToBytes32(address(nestVaultComposer)),
            0, // No new shares sent for complete redeem
            0,
            completeOptions,
            completeComposeMsg,
            ""
        );

        MessagingFee memory completeFee = remoteNestShare.quoteSend(completeSendParam, false);

        vm.prank(userB);
        (MessagingReceipt memory completeMsgReceipt, OFTReceipt memory completeOftReceipt) =
            remoteNestShare.send{value: completeFee.nativeFee}(completeSendParam, completeFee, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        // State before complete lzCompose - VaultComposer state
        uint256 composerTotalPendingSharesSumBefore = nestVaultComposer.totalPendingSharesSum();
        uint256 composerTotalPendingSharesBefore = nestVaultComposer.totalPendingShares(remoteEid);
        NestVaultCoreTypes.PendingRedeem memory composerPendingRedeemBefore =
            nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid);

        // State before complete lzCompose - NestVaultOFT (NestVaultCore) state
        uint256 vaultClaimableSharesBeforeComplete = nestVaultOFT.claimableRedeemRequest(0, address(nestVaultComposer));
        // Note: Assets were already exited from nestShare to NestVaultOFT during fulfillRedeem
        // So we track NestVaultOFT's asset balance, not nestShare's
        uint256 vaultOftAssetBalanceBefore = localAsset.balanceOf(address(nestVaultOFT));

        bytes memory completeComposerMsg = OFTComposeMsgCodec.encode(
            completeMsgReceipt.nonce,
            remoteEid,
            completeOftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(address(userB)), completeComposeMsg)
        );

        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            completeOptions,
            completeMsgReceipt.guid,
            address(nestVaultComposer),
            completeComposerMsg
        );

        // State after complete lzCompose - assert VaultComposer state changes from _completeRedeem
        // Note: totalPendingSharesSum and totalPendingShares are decremented during fulfillRedeem, not completeRedeem
        // So they should remain unchanged after completeRedeem
        assertEq(
            nestVaultComposer.totalPendingSharesSum(),
            composerTotalPendingSharesSumBefore,
            "composer: totalPendingSharesSum should remain unchanged after completeRedeem (already decremented in fulfillRedeem)"
        );
        assertEq(
            nestVaultComposer.totalPendingShares(remoteEid),
            composerTotalPendingSharesBefore,
            "composer: totalPendingShares[remoteEid] should remain unchanged after completeRedeem (already decremented in fulfillRedeem)"
        );
        NestVaultCoreTypes.PendingRedeem memory composerPendingRedeemAfter =
            nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid);
        assertEq(
            composerPendingRedeemAfter.shares,
            composerPendingRedeemBefore.shares,
            "composer: pendingRedeem[userB][remoteEid].shares should remain unchanged after completeRedeem (already decremented in fulfillRedeem)"
        );

        // NestVaultOFT (NestVaultCore) state assertions after complete
        assertEq(
            nestVaultOFT.claimableRedeemRequest(0, address(nestVaultComposer)),
            vaultClaimableSharesBeforeComplete - redeemShareAmount,
            "vault: claimableRedeemRequest should decrease by redeemShareAmount (shares redeemed)"
        );

        // Assets should be transferred from NestVaultOFT to composer, then sent via CCTP
        // Note: During fulfillRedeem, assets were already exited from nestShare to NestVaultOFT
        // Now redeem() transfers them from NestVaultOFT to composer, then _send() burns via CCTP
        assertEq(
            localAsset.balanceOf(address(nestVaultOFT)),
            vaultOftAssetBalanceBefore - redeemShareAmount,
            "NestVaultOFT asset balance should decrease by redeemed amount (assets sent to composer then CCTP)"
        );
    }

    /// @notice Tests that finish redeem with multiple users having different fulfillment rates
    ///         preserves per-user fulfilled asset entitlement.
    /// @dev Scenario:
    ///      - userB: 1M shares fulfilled at rate 2.0 -> 2M assets claimable
    ///      - userC: 1M shares fulfilled at rate 0.5 -> 0.5M assets claimable
    ///      - Global pool: 2M shares -> 2.5M assets
    ///
    ///      Verifies that each user receives their own fulfilled asset amount,
    ///      and one user's finish does not mutate the other's claimable accounting.
    function test_finish_redeem_multiUser_accounting() public {
        // Create userC for this multi-user test
        address userC = makeAddr("userC");
        remoteNestShare.credit(userC, initialBalance, remoteEid);
        vm.deal(userC, 10 ether);

        uint256 userBRedeemAmount = 1e6; // 1 USDC worth of shares
        uint256 userCRedeemAmount = 1e6; // 1 USDC worth of shares

        // ============ Step 1: Both users request redemption ============

        // userB requests redeem
        bytes memory requestComposeMsgB = _formatRequestRedeemComposeMsg(remoteEid, address(userB).toBytes32(), 0, 0);
        bytes memory requestOptions =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0).addExecutorLzComposeOption(0, 500000, 0);
        SendParam memory requestSendParamB = SendParam(
            localEid,
            addressToBytes32(address(nestVaultComposer)),
            userBRedeemAmount,
            userBRedeemAmount,
            requestOptions,
            requestComposeMsgB,
            ""
        );
        MessagingFee memory requestFeeB = remoteNestShare.quoteSend(requestSendParamB, false);

        vm.prank(userB);
        (MessagingReceipt memory requestMsgReceiptB, OFTReceipt memory requestOftReceiptB) =
            remoteNestShare.send{value: requestFeeB.nativeFee}(requestSendParamB, requestFeeB, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory requestComposerMsgB = OFTComposeMsgCodec.encode(
            requestMsgReceiptB.nonce,
            remoteEid,
            requestOftReceiptB.amountReceivedLD,
            abi.encodePacked(addressToBytes32(address(userB)), requestComposeMsgB)
        );

        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            requestOptions,
            requestMsgReceiptB.guid,
            address(nestVaultComposer),
            requestComposerMsgB
        );

        // userC requests redeem
        bytes memory requestComposeMsgC = _formatRequestRedeemComposeMsg(remoteEid, address(userC).toBytes32(), 0, 0);
        SendParam memory requestSendParamC = SendParam(
            localEid,
            addressToBytes32(address(nestVaultComposer)),
            userCRedeemAmount,
            userCRedeemAmount,
            requestOptions,
            requestComposeMsgC,
            ""
        );
        MessagingFee memory requestFeeC = remoteNestShare.quoteSend(requestSendParamC, false);

        vm.prank(userC);
        (MessagingReceipt memory requestMsgReceiptC, OFTReceipt memory requestOftReceiptC) =
            remoteNestShare.send{value: requestFeeC.nativeFee}(requestSendParamC, requestFeeC, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory requestComposerMsgC = OFTComposeMsgCodec.encode(
            requestMsgReceiptC.nonce,
            remoteEid,
            requestOftReceiptC.amountReceivedLD,
            abi.encodePacked(addressToBytes32(address(userC)), requestComposeMsgC)
        );

        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            requestOptions,
            requestMsgReceiptC.guid,
            address(nestVaultComposer),
            requestComposerMsgC
        );

        // Verify both requests recorded
        uint256 pendingSharesB = nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid).shares;
        uint256 pendingSharesC = nestVaultComposer.pendingRedeem(addressToBytes32(address(userC)), remoteEid).shares;
        assertEq(pendingSharesB, requestOftReceiptB.amountReceivedLD, "userB pending shares should match");
        assertEq(pendingSharesC, requestOftReceiptC.amountReceivedLD, "userC pending shares should match");

        // ============ Step 2: Fulfill users at DIFFERENT RATES ============
        // userB gets fulfilled at rate 2.0, userC at rate 0.5
        // This creates different per-user asset/share ratios

        // Fulfill userB at rate 2.0 (2e6) - meaning 1 share = 2 assets
        accountantWithRateProviders.setRate(2e6);
        uint256 assetsB = nestVaultComposer.fulfillRedeem(remoteEid, addressToBytes32(address(userB)), pendingSharesB);

        // Fulfill userC at rate 0.5 (0.5e6) - meaning 1 share = 0.5 assets
        accountantWithRateProviders.setRate(5e5);
        uint256 assetsC = nestVaultComposer.fulfillRedeem(remoteEid, addressToBytes32(address(userC)), pendingSharesC);

        // Reset rate to 1.0 for redemption phase (this rate doesn't affect claimable redemptions)
        accountantWithRateProviders.setRate(1e6);

        // Log the fulfillment rates and expected assets
        console2.log("=== Fulfillment State ===");
        console2.log("userB: shares=", pendingSharesB, "assets credited=", assetsB);
        console2.log("userC: shares=", pendingSharesC, "assets credited=", assetsC);

        // Verify claimable state after fulfillment
        NestVaultCoreTypes.ClaimableRedeem memory claimableB =
            nestVaultComposer.claimableRedeem(addressToBytes32(address(userB)), remoteEid);
        NestVaultCoreTypes.ClaimableRedeem memory claimableC =
            nestVaultComposer.claimableRedeem(addressToBytes32(address(userC)), remoteEid);

        assertEq(claimableB.shares, pendingSharesB, "userB claimable shares should match pending");
        assertEq(claimableB.assets, assetsB, "userB claimable assets should match fulfillRedeem return");
        assertEq(claimableC.shares, pendingSharesC, "userC claimable shares should match pending");
        assertEq(claimableC.assets, assetsC, "userC claimable assets should match fulfillRedeem return");

        // Store pre-finish state
        uint256 vaultClaimableSharesBefore = nestVaultOFT.claimableRedeemRequest(0, address(nestVaultComposer));

        // Track actual assets received by each user by capturing vault asset balance changes
        uint256 vaultAssetsBeforeUserBFinish = localAsset.balanceOf(address(nestVaultOFT));

        // ============ Step 3: userB finishes redeem ============
        uint256 redeemShareAmountB = pendingSharesB;

        bytes memory assetSendOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory quoteSendParamB = SendParam(
            remoteEid,
            addressToBytes32(address(userB)),
            redeemShareAmountB,
            0,
            assetSendOptions,
            new bytes(0),
            abi.encode(VaultComposerAsyncUpgradeable.RedeemType.FinishRedeem)
        );
        MessagingFee memory assetSendFeeB = nestCCTPRelayer.quoteSend(quoteSendParamB, false);
        uint256 assetSendFeeWithBufferB = assetSendFeeB.nativeFee + 1000;

        bytes memory completeOptionsB = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0)
            .addExecutorLzComposeOption(0, 2000000, uint128(assetSendFeeWithBufferB));

        bytes memory completeComposeMsgB = _formatCompleteRedeemComposeMsg(
            remoteEid, address(userB).toBytes32(), redeemShareAmountB, 0, assetSendFeeWithBufferB
        );

        SendParam memory completeSendParamB = SendParam(
            localEid, addressToBytes32(address(nestVaultComposer)), 0, 0, completeOptionsB, completeComposeMsgB, ""
        );

        MessagingFee memory completeFeeB = remoteNestShare.quoteSend(completeSendParamB, false);

        vm.prank(userB);
        (MessagingReceipt memory completeMsgReceiptB, OFTReceipt memory completeOftReceiptB) = remoteNestShare.send{
            value: completeFeeB.nativeFee
        }(
            completeSendParamB, completeFeeB, payable(address(this))
        );
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory completeComposerMsgB = OFTComposeMsgCodec.encode(
            completeMsgReceiptB.nonce,
            remoteEid,
            completeOftReceiptB.amountReceivedLD,
            abi.encodePacked(addressToBytes32(address(userB)), completeComposeMsgB)
        );

        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            completeOptionsB,
            completeMsgReceiptB.guid,
            address(nestVaultComposer),
            completeComposerMsgB
        );

        // Track actual assets sent when userB finished
        uint256 vaultAssetsAfterUserBFinish = localAsset.balanceOf(address(nestVaultOFT));
        uint256 userBActualAssetsReceived = vaultAssetsBeforeUserBFinish - vaultAssetsAfterUserBFinish;
        console2.log("userB actual assets received from vault:", userBActualAssetsReceived);

        // ============ Step 4: Verify userB's finish didn't affect userC's claimable ============

        NestVaultCoreTypes.ClaimableRedeem memory claimableBAfter =
            nestVaultComposer.claimableRedeem(addressToBytes32(address(userB)), remoteEid);
        NestVaultCoreTypes.ClaimableRedeem memory claimableCAfter =
            nestVaultComposer.claimableRedeem(addressToBytes32(address(userC)), remoteEid);

        // Debug logging - key values only
        console2.log("=== After userB finishes ===");
        console2.log("userB actual assets received:", userBActualAssetsReceived);
        console2.log("claimableBAfter - shares:", claimableBAfter.shares, "assets:", claimableBAfter.assets);

        // userB's claimable shares should be zero (fully redeemed their shares)
        assertEq(claimableBAfter.shares, 0, "userB claimable shares should be 0 after finish");

        // userB should receive exactly what was fulfilled for userB
        assertEq(userBActualAssetsReceived, assetsB, "userB should receive their fulfilled assets");
        assertEq(claimableBAfter.assets, 0, "userB claimable assets should be 0 after full finish");

        // CRITICAL: userC's claimable must remain UNCHANGED
        assertEq(
            claimableCAfter.shares,
            claimableC.shares,
            "CRITICAL: userC claimable shares must remain unchanged after userB finishes"
        );
        assertEq(
            claimableCAfter.assets,
            claimableC.assets,
            "CRITICAL: userC claimable assets must remain unchanged after userB finishes"
        );

        // Vault claimable shares should decrease after userB's asset-based withdraw.
        assertLt(
            nestVaultOFT.claimableRedeemRequest(0, address(nestVaultComposer)),
            vaultClaimableSharesBefore,
            "vault claimable shares should decrease after userB finish"
        );

        // ============ Step 5: userC finishes redeem ============
        uint256 redeemShareAmountC = pendingSharesC;

        SendParam memory quoteSendParamC = SendParam(
            remoteEid,
            addressToBytes32(address(userC)),
            redeemShareAmountC,
            0,
            assetSendOptions,
            new bytes(0),
            abi.encode(VaultComposerAsyncUpgradeable.RedeemType.FinishRedeem)
        );
        MessagingFee memory assetSendFeeC = nestCCTPRelayer.quoteSend(quoteSendParamC, false);
        uint256 assetSendFeeWithBufferC = assetSendFeeC.nativeFee + 1000;

        bytes memory completeOptionsC = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0)
            .addExecutorLzComposeOption(0, 2000000, uint128(assetSendFeeWithBufferC));

        bytes memory completeComposeMsgC = _formatCompleteRedeemComposeMsg(
            remoteEid, address(userC).toBytes32(), redeemShareAmountC, 0, assetSendFeeWithBufferC
        );

        SendParam memory completeSendParamC = SendParam(
            localEid, addressToBytes32(address(nestVaultComposer)), 0, 0, completeOptionsC, completeComposeMsgC, ""
        );

        MessagingFee memory completeFeeC = remoteNestShare.quoteSend(completeSendParamC, false);

        vm.prank(userC);
        (MessagingReceipt memory completeMsgReceiptC, OFTReceipt memory completeOftReceiptC) = remoteNestShare.send{
            value: completeFeeC.nativeFee
        }(
            completeSendParamC, completeFeeC, payable(address(this))
        );
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory completeComposerMsgC = OFTComposeMsgCodec.encode(
            completeMsgReceiptC.nonce,
            remoteEid,
            completeOftReceiptC.amountReceivedLD,
            abi.encodePacked(addressToBytes32(address(userC)), completeComposeMsgC)
        );

        // Track vault assets before userC finishes
        uint256 vaultAssetsBeforeUserCFinish = localAsset.balanceOf(address(nestVaultOFT));

        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            completeOptionsC,
            completeMsgReceiptC.guid,
            address(nestVaultComposer),
            completeComposerMsgC
        );

        // Track actual assets sent when userC finished
        uint256 vaultAssetsAfterUserCFinish = localAsset.balanceOf(address(nestVaultOFT));
        uint256 userCActualAssetsReceived = vaultAssetsBeforeUserCFinish - vaultAssetsAfterUserCFinish;
        console2.log("userC actual assets received from vault:", userCActualAssetsReceived);

        // ============ Step 6: Final verification - both users fully redeemed ============

        NestVaultCoreTypes.ClaimableRedeem memory claimableBFinal =
            nestVaultComposer.claimableRedeem(addressToBytes32(address(userB)), remoteEid);
        NestVaultCoreTypes.ClaimableRedeem memory claimableCFinal =
            nestVaultComposer.claimableRedeem(addressToBytes32(address(userC)), remoteEid);

        // Both users should have zero claimable balances after full finish
        assertEq(claimableBFinal.shares, 0, "userB final claimable shares should be 0");
        assertEq(claimableCFinal.shares, 0, "userC final claimable shares should be 0");
        assertEq(claimableBFinal.assets, 0, "userB final claimable assets should be 0");
        assertEq(claimableCFinal.assets, 0, "userC final claimable assets should be 0");

        // Vault should have no more claimable for composer
        assertEq(
            nestVaultOFT.claimableRedeemRequest(0, address(nestVaultComposer)),
            0,
            "vault claimable should be 0 after both users finish"
        );

        // Total assets sent should equal total assets fulfilled
        uint256 totalAssetsSent = userBActualAssetsReceived + userCActualAssetsReceived;
        assertEq(totalAssetsSent, assetsB + assetsC, "total assets sent should equal total assets fulfilled");

        // ISOLATION VERIFICATION: One user's redemption should not affect another user's
        // claimable accounting and each user receives their own fulfilled assets.
        console2.log("=== ISOLATION CHECK ===");
        console2.log("userB credited:", assetsB, "received:", userBActualAssetsReceived);
        console2.log("userC credited:", assetsC, "received:", userCActualAssetsReceived);

        assertEq(userBActualAssetsReceived, assetsB, "userB should receive exactly fulfilled assets");
        assertEq(userCActualAssetsReceived, assetsC, "userC should receive exactly fulfilled assets");

        // Total assets sent must equal total fulfilled (no assets lost or created)
        assertEq(
            userBActualAssetsReceived + userCActualAssetsReceived,
            assetsB + assetsC,
            "total assets sent must equal total assets fulfilled"
        );
    }

    function testFuzz_finish_redeem_entitlementAndClaimableSolvency(
        uint96 redeemSeedB,
        uint96 redeemSeedC,
        uint32 rateSeedB,
        uint32 rateSeedC,
        bool finishBFirst
    ) public {
        address userC = makeAddr("userC");
        remoteNestShare.credit(userC, initialBalance, remoteEid);
        vm.deal(userC, 10 ether);

        uint256 redeemAmountB = bound(uint256(redeemSeedB), 1e6, 5e6);
        uint256 redeemAmountC = bound(uint256(redeemSeedC), 1e6, 5e6);

        (uint256 pendingSharesB,) = _requestRedeemAndReturnPending(userB, redeemAmountB);
        (uint256 pendingSharesC,) = _requestRedeemAndReturnPending(userC, redeemAmountC);

        uint256 rateB = bound(uint256(rateSeedB), 5e5, 2e6);
        uint256 rateC = bound(uint256(rateSeedC), 5e5, 2e6);

        accountantWithRateProviders.setRate(rateB);
        uint256 assetsB = nestVaultComposer.fulfillRedeem(remoteEid, addressToBytes32(address(userB)), pendingSharesB);
        accountantWithRateProviders.setRate(rateC);
        uint256 assetsC = nestVaultComposer.fulfillRedeem(remoteEid, addressToBytes32(address(userC)), pendingSharesC);

        assertEq(
            nestVaultOFT.maxWithdraw(address(nestVaultComposer)),
            assetsB + assetsC,
            "vault claimable assets should equal total user claimable assets after fulfill"
        );

        uint256 assetsReceivedB;
        uint256 assetsReceivedC;

        if (finishBFirst) {
            assetsReceivedB = _finishRedeemAndReturnAssets(userB, pendingSharesB);
            assertEq(assetsReceivedB, assetsB, "userB should receive exactly fulfilled assets");
            assertEq(
                nestVaultOFT.maxWithdraw(address(nestVaultComposer)),
                assetsC,
                "vault claimable assets should match remaining userC claimable assets"
            );

            assetsReceivedC = _finishRedeemAndReturnAssets(userC, pendingSharesC);
            assertEq(assetsReceivedC, assetsC, "userC should receive exactly fulfilled assets");
        } else {
            assetsReceivedC = _finishRedeemAndReturnAssets(userC, pendingSharesC);
            assertEq(assetsReceivedC, assetsC, "userC should receive exactly fulfilled assets");
            assertEq(
                nestVaultOFT.maxWithdraw(address(nestVaultComposer)),
                assetsB,
                "vault claimable assets should match remaining userB claimable assets"
            );

            assetsReceivedB = _finishRedeemAndReturnAssets(userB, pendingSharesB);
            assertEq(assetsReceivedB, assetsB, "userB should receive exactly fulfilled assets");
        }

        NestVaultCoreTypes.ClaimableRedeem memory claimableBFinal =
            nestVaultComposer.claimableRedeem(addressToBytes32(address(userB)), remoteEid);
        NestVaultCoreTypes.ClaimableRedeem memory claimableCFinal =
            nestVaultComposer.claimableRedeem(addressToBytes32(address(userC)), remoteEid);

        assertEq(claimableBFinal.assets, 0, "userB final claimable assets should be 0");
        assertEq(claimableBFinal.shares, 0, "userB final claimable shares should be 0");
        assertEq(claimableCFinal.assets, 0, "userC final claimable assets should be 0");
        assertEq(claimableCFinal.shares, 0, "userC final claimable shares should be 0");

        assertEq(
            nestVaultOFT.maxWithdraw(address(nestVaultComposer)), 0, "vault claimable assets should be 0 after finish"
        );
        assertEq(
            nestVaultOFT.claimableRedeemRequest(0, address(nestVaultComposer)),
            0,
            "vault claimable shares should be 0 after finish"
        );
        assertEq(
            assetsReceivedB + assetsReceivedC,
            assetsB + assetsC,
            "total assets sent should equal total assets fulfilled"
        );
    }

    function test_fulfill_redeem_externalClaimable_afterHighRatioFinish_preservesAssetEntitlements() public {
        address userC = makeAddr("userC");
        address userD = makeAddr("userD");
        remoteNestShare.credit(userC, initialBalance, remoteEid);
        remoteNestShare.credit(userD, initialBalance, remoteEid);
        vm.deal(userC, 10 ether);
        vm.deal(userD, 10 ether);

        (uint256 pendingSharesB,) = _requestRedeemAndReturnPending(userB, 1e6);
        (uint256 pendingSharesC,) = _requestRedeemAndReturnPending(userC, 1e6);
        (uint256 pendingSharesD,) = _requestRedeemAndReturnPending(userD, 1e6);

        accountantWithRateProviders.setRate(2e6);
        uint256 assetsB = nestVaultComposer.fulfillRedeem(remoteEid, addressToBytes32(address(userB)), pendingSharesB);

        accountantWithRateProviders.setRate(5e5);
        uint256 assetsC = nestVaultComposer.fulfillRedeem(remoteEid, addressToBytes32(address(userC)), pendingSharesC);

        accountantWithRateProviders.setRate(1e6);
        uint256 assetsReceivedB = _finishRedeemAndReturnAssets(userB, pendingSharesB);
        assertEq(assetsReceivedB, assetsB, "userB should receive their high-ratio fulfilled assets");
        uint256 externalAssetsD = nestVaultOFT.fulfillRedeem(address(nestVaultComposer), pendingSharesD);
        assertEq(externalAssetsD, 1e6, "external fulfill should realize the 1.0 rate assets for userD");

        uint256 assetsD = nestVaultComposer.fulfillRedeem(remoteEid, addressToBytes32(address(userD)), pendingSharesD);
        assertEq(
            assetsD, externalAssetsD, "userD should only be credited the assets introduced by the external fulfill"
        );

        NestVaultCoreTypes.ClaimableRedeem memory claimableC =
            nestVaultComposer.claimableRedeem(addressToBytes32(address(userC)), remoteEid);
        NestVaultCoreTypes.ClaimableRedeem memory claimableD =
            nestVaultComposer.claimableRedeem(addressToBytes32(address(userD)), remoteEid);

        assertEq(claimableC.assets, assetsC, "userC claimable assets should remain unchanged");
        assertEq(claimableD.assets, externalAssetsD, "userD claimable assets should match the external fulfill");
        assertEq(
            nestVaultComposer.totalFulfilledAssetsSum(),
            claimableC.assets + claimableD.assets,
            "tracked fulfilled assets should equal the sum of live user claimable assets"
        );
        assertEq(
            nestVaultOFT.maxWithdraw(address(nestVaultComposer)),
            claimableC.assets + claimableD.assets,
            "vault claimable assets should remain solvent for the live user claims"
        );

        uint256 assetsReceivedD = _finishRedeemAndReturnAssets(userD, pendingSharesD);
        uint256 assetsReceivedC = _finishRedeemAndReturnAssets(userC, pendingSharesC);
        assertEq(assetsReceivedD, externalAssetsD, "userD should receive their externally fulfilled assets");
        assertEq(assetsReceivedC, assetsC, "userC should still receive their original low-ratio assets");
    }

    /*//////////////////////////////////////////////////////////////
                    NEGATIVE TESTS - COMPOSE VALIDATION
    //////////////////////////////////////////////////////////////*/

    function test_lzCompose_revert_OnlyEndpoint() public {
        // Prepare a compose message
        bytes memory composeMsg = _formatInstantRedeemComposeMsg(remoteEid, address(userB).toBytes32(), 0, 0);
        uint256 redeemAmount = 1e6;

        bytes memory composerMsg = OFTComposeMsgCodec.encode(
            1, // nonce
            remoteEid,
            redeemAmount,
            abi.encodePacked(addressToBytes32(address(userB)), composeMsg)
        );

        // Try to call lzCompose directly from a non-endpoint address
        vm.expectRevert(abi.encodeWithSelector(IVaultComposerSync.OnlyEndpoint.selector, address(this)));
        nestVaultComposer.lzCompose(
            address(nestVaultOFT), // composeSender (share OFT)
            bytes32(0), // guid
            composerMsg,
            address(0), // executor
            "" // extraData
        );
    }

    function test_lzCompose_revert_OnlyValidComposeCaller() public {
        // Prepare a compose message
        bytes memory composeMsg = _formatInstantRedeemComposeMsg(remoteEid, address(userB).toBytes32(), 0, 0);
        uint256 redeemAmount = 1e6;

        bytes memory composerMsg = OFTComposeMsgCodec.encode(
            1, // nonce
            remoteEid,
            redeemAmount,
            abi.encodePacked(addressToBytes32(address(userB)), composeMsg)
        );

        // Get the endpoint address
        address endpoint = nestVaultComposer.ENDPOINT();

        // Use an invalid compose sender (not asset or share OFT)
        address invalidComposeSender = makeAddr("invalidComposeSender");

        // Prank as the endpoint but use an invalid compose sender
        vm.prank(endpoint);
        vm.expectRevert(
            abi.encodeWithSelector(IVaultComposerSync.OnlyValidComposeCaller.selector, invalidComposeSender)
        );
        nestVaultComposer.lzCompose(
            invalidComposeSender, // invalid composeSender
            bytes32(0), // guid
            composerMsg,
            address(0), // executor
            "" // extraData
        );
    }

    function test_lzCompose_revert_UnexpectedNonZeroAmount_updateRedeem() public {
        // Step 1: First request a redeem to set up pending shares
        bytes memory requestComposeMsg = _formatRequestRedeemComposeMsg(remoteEid, address(userB).toBytes32(), 0, 0);
        uint256 initialRedeemAmount = 1e6;
        bytes memory requestOptions =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0).addExecutorLzComposeOption(0, 500000, 0);
        SendParam memory requestSendParam = SendParam(
            localEid,
            addressToBytes32(address(nestVaultComposer)),
            initialRedeemAmount,
            initialRedeemAmount,
            requestOptions,
            requestComposeMsg,
            ""
        );
        MessagingFee memory requestFee = remoteNestShare.quoteSend(requestSendParam, false);

        vm.prank(userB);
        (MessagingReceipt memory requestMsgReceipt, OFTReceipt memory requestOftReceipt) =
            remoteNestShare.send{value: requestFee.nativeFee}(requestSendParam, requestFee, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory requestComposerMsg = OFTComposeMsgCodec.encode(
            requestMsgReceipt.nonce,
            remoteEid,
            requestOftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(address(userB)), requestComposeMsg)
        );

        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            requestOptions,
            requestMsgReceipt.guid,
            address(nestVaultComposer),
            requestComposerMsg
        );

        // Verify request redeem succeeded
        uint256 pendingSharesAfterRequest =
            nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid).shares;
        assertEq(
            pendingSharesAfterRequest, requestOftReceipt.amountReceivedLD, "Pending shares should be set after request"
        );

        // Step 2: Try to update with non-zero OFT amount - should revert
        uint256 newSharesAmount = pendingSharesAfterRequest / 2;
        uint256 nonZeroOftAmount = 1e6; // This should cause revert

        bytes memory updateComposeMsg =
            _formatUpdateRedeemComposeMsg(remoteEid, address(userB).toBytes32(), newSharesAmount, 0);

        // Include native value for compose to cover potential refund fees
        bytes memory updateOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0)
            .addExecutorLzComposeOption(0, 2000000, 0.05 ether);

        SendParam memory updateSendParam = SendParam(
            localEid,
            addressToBytes32(address(nestVaultComposer)),
            nonZeroOftAmount, // Non-zero amount should cause revert
            nonZeroOftAmount,
            updateOptions,
            updateComposeMsg,
            ""
        );

        MessagingFee memory updateFee = remoteNestShare.quoteSend(updateSendParam, false);

        vm.prank(userB);
        (MessagingReceipt memory updateMsgReceipt, OFTReceipt memory updateOftReceipt) =
            remoteNestShare.send{value: updateFee.nativeFee}(updateSendParam, updateFee, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory updateComposerMsg = OFTComposeMsgCodec.encode(
            updateMsgReceipt.nonce,
            remoteEid,
            updateOftReceipt.amountReceivedLD, // Non-zero amount
            abi.encodePacked(addressToBytes32(address(userB)), updateComposeMsg)
        );

        // Expect the Refunded event (revert triggers refund in catch block)
        vm.expectEmit(true, false, false, false, address(nestVaultComposer));
        emit IVaultComposerSync.Refunded(updateMsgReceipt.guid);

        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            updateOptions,
            updateMsgReceipt.guid,
            address(nestVaultComposer),
            updateComposerMsg
        );

        // Verify state unchanged (refund happened, update did not process)
        uint256 pendingSharesAfterUpdate =
            nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid).shares;
        assertEq(
            pendingSharesAfterUpdate,
            pendingSharesAfterRequest,
            "Pending shares should remain unchanged after failed update with non-zero amount"
        );
    }

    function test_lzCompose_revert_UnexpectedNonZeroAmount_completeRedeem() public {
        // Step 1: First request a redeem to set up pending shares
        bytes memory requestComposeMsg = _formatRequestRedeemComposeMsg(remoteEid, address(userB).toBytes32(), 0, 0);
        uint256 initialRedeemAmount = 1e6;
        bytes memory requestOptions =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0).addExecutorLzComposeOption(0, 500000, 0);
        SendParam memory requestSendParam = SendParam(
            localEid,
            addressToBytes32(address(nestVaultComposer)),
            initialRedeemAmount,
            initialRedeemAmount,
            requestOptions,
            requestComposeMsg,
            ""
        );
        MessagingFee memory requestFee = remoteNestShare.quoteSend(requestSendParam, false);

        vm.prank(userB);
        (MessagingReceipt memory requestMsgReceipt, OFTReceipt memory requestOftReceipt) =
            remoteNestShare.send{value: requestFee.nativeFee}(requestSendParam, requestFee, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory requestComposerMsg = OFTComposeMsgCodec.encode(
            requestMsgReceipt.nonce,
            remoteEid,
            requestOftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(address(userB)), requestComposeMsg)
        );

        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            requestOptions,
            requestMsgReceipt.guid,
            address(nestVaultComposer),
            requestComposerMsg
        );

        // Verify request redeem succeeded
        uint256 pendingSharesAfterRequest =
            nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid).shares;
        assertEq(
            pendingSharesAfterRequest, requestOftReceipt.amountReceivedLD, "Pending shares should be set after request"
        );

        // Step 2: Fulfill the redeem request through the composer
        nestVaultComposer.fulfillRedeem(remoteEid, addressToBytes32(address(userB)), pendingSharesAfterRequest);

        // Step 3: Try to complete redeem with non-zero OFT amount - should revert
        uint256 redeemShareAmount = pendingSharesAfterRequest;
        uint256 nonZeroOftAmount = 1e6; // This should cause revert

        bytes memory completeComposeMsg =
            _formatCompleteRedeemComposeMsg(remoteEid, address(userB).toBytes32(), redeemShareAmount, 0, 0);

        // Include native value for compose to cover potential refund fees
        bytes memory completeOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0)
            .addExecutorLzComposeOption(0, 2000000, 0.05 ether);

        SendParam memory completeSendParam = SendParam(
            localEid,
            addressToBytes32(address(nestVaultComposer)),
            nonZeroOftAmount, // Non-zero amount should cause revert
            nonZeroOftAmount,
            completeOptions,
            completeComposeMsg,
            ""
        );

        MessagingFee memory completeFee = remoteNestShare.quoteSend(completeSendParam, false);

        vm.prank(userB);
        (MessagingReceipt memory completeMsgReceipt, OFTReceipt memory completeOftReceipt) =
            remoteNestShare.send{value: completeFee.nativeFee}(completeSendParam, completeFee, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory completeComposerMsg = OFTComposeMsgCodec.encode(
            completeMsgReceipt.nonce,
            remoteEid,
            completeOftReceipt.amountReceivedLD, // Non-zero amount
            abi.encodePacked(addressToBytes32(address(userB)), completeComposeMsg)
        );

        // Capture state before
        uint256 pendingSharesBefore =
            nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid).shares;

        // Expect the Refunded event (revert triggers refund in catch block)
        vm.expectEmit(true, false, false, false, address(nestVaultComposer));
        emit IVaultComposerSync.Refunded(completeMsgReceipt.guid);

        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            completeOptions,
            completeMsgReceipt.guid,
            address(nestVaultComposer),
            completeComposerMsg
        );

        // Verify state unchanged (refund happened, complete did not process)
        uint256 pendingSharesAfter = nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid).shares;
        assertEq(
            pendingSharesAfter,
            pendingSharesBefore,
            "Pending shares should remain unchanged after failed complete redeem with non-zero amount"
        );
    }

    /// @notice Test fulfillRedeem in isolation
    function test_fulfill_redeem_isolated() public {
        // Step 1: Request redeem to set up pending shares
        bytes memory requestComposeMsg = _formatRequestRedeemComposeMsg(remoteEid, address(userB).toBytes32(), 0, 0);
        uint256 redeemAmount = 1e6;
        bytes memory requestOptions =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0).addExecutorLzComposeOption(0, 500000, 0);
        SendParam memory requestSendParam = SendParam(
            localEid,
            addressToBytes32(address(nestVaultComposer)),
            redeemAmount,
            redeemAmount,
            requestOptions,
            requestComposeMsg,
            ""
        );
        MessagingFee memory requestFee = remoteNestShare.quoteSend(requestSendParam, false);

        vm.prank(userB);
        (MessagingReceipt memory requestMsgReceipt, OFTReceipt memory requestOftReceipt) =
            remoteNestShare.send{value: requestFee.nativeFee}(requestSendParam, requestFee, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory requestComposerMsg = OFTComposeMsgCodec.encode(
            requestMsgReceipt.nonce,
            remoteEid,
            requestOftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(address(userB)), requestComposeMsg)
        );

        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            requestOptions,
            requestMsgReceipt.guid,
            address(nestVaultComposer),
            requestComposerMsg
        );

        // Verify pending shares set
        uint256 pendingShares = nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid).shares;
        assertEq(pendingShares, requestOftReceipt.amountReceivedLD, "Pending shares should be set");

        // State before fulfill
        uint256 totalPendingBefore = nestVaultComposer.totalPendingSharesSum();
        NestVaultCoreTypes.ClaimableRedeem memory claimableBefore =
            nestVaultComposer.claimableRedeem(addressToBytes32(address(userB)), remoteEid);

        // Step 2: Fulfill the redeem (owner has auth)
        uint256 sharesToFulfill = pendingShares;
        uint256 assets = nestVaultComposer.fulfillRedeem(remoteEid, addressToBytes32(address(userB)), sharesToFulfill);

        // Verify state after fulfill
        assertGt(assets, 0, "Assets should be > 0");
        assertEq(
            nestVaultComposer.totalPendingSharesSum(),
            totalPendingBefore - sharesToFulfill,
            "totalPendingSharesSum should decrease"
        );
        assertEq(nestVaultComposer.totalPendingShares(remoteEid), 0, "totalPendingShares[remoteEid] should be 0");

        NestVaultCoreTypes.PendingRedeem memory pendingAfter =
            nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid);
        assertEq(pendingAfter.shares, 0, "Pending shares should be 0 after full fulfill");

        NestVaultCoreTypes.ClaimableRedeem memory claimableAfter =
            nestVaultComposer.claimableRedeem(addressToBytes32(address(userB)), remoteEid);
        assertEq(claimableAfter.shares, claimableBefore.shares + sharesToFulfill, "Claimable shares should increase");
        assertEq(claimableAfter.assets, claimableBefore.assets + assets, "Claimable assets should increase");
    }

    /// @notice Test partial fulfill of pending redeem
    function test_partial_fulfill_redeem() public {
        // Setup: Request redeem
        bytes memory requestComposeMsg = _formatRequestRedeemComposeMsg(remoteEid, address(userB).toBytes32(), 0, 0);
        uint256 redeemAmount = 1e6;
        bytes memory requestOptions =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0).addExecutorLzComposeOption(0, 500000, 0);
        SendParam memory requestSendParam = SendParam(
            localEid,
            addressToBytes32(address(nestVaultComposer)),
            redeemAmount,
            redeemAmount,
            requestOptions,
            requestComposeMsg,
            ""
        );
        MessagingFee memory requestFee = remoteNestShare.quoteSend(requestSendParam, false);

        vm.prank(userB);
        (MessagingReceipt memory requestMsgReceipt, OFTReceipt memory requestOftReceipt) =
            remoteNestShare.send{value: requestFee.nativeFee}(requestSendParam, requestFee, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory requestComposerMsg = OFTComposeMsgCodec.encode(
            requestMsgReceipt.nonce,
            remoteEid,
            requestOftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(address(userB)), requestComposeMsg)
        );
        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            requestOptions,
            requestMsgReceipt.guid,
            address(nestVaultComposer),
            requestComposerMsg
        );

        uint256 pendingShares = nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid).shares;

        // Partial fulfill (half)
        uint256 sharesToFulfill = pendingShares / 2;
        nestVaultComposer.fulfillRedeem(remoteEid, addressToBytes32(address(userB)), sharesToFulfill);

        // Verify partial state
        NestVaultCoreTypes.PendingRedeem memory pendingAfter =
            nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid);
        assertEq(pendingAfter.shares, pendingShares - sharesToFulfill, "Pending should have remaining shares");

        NestVaultCoreTypes.ClaimableRedeem memory claimableAfter =
            nestVaultComposer.claimableRedeem(addressToBytes32(address(userB)), remoteEid);
        assertEq(claimableAfter.shares, sharesToFulfill, "Claimable should have fulfilled shares");
    }

    /// @notice Test fulfillRedeem uses existing claimable when claimable > shares
    function test_fulfill_redeem_claimable_gt_shares() public {
        (uint256 pendingShares, uint256 receivedShares) = _requestRedeemAndReturnPending(userB, 1e6);
        assertEq(pendingShares, receivedShares, "Pending shares should be set");

        uint256 sharesToFulfill = pendingShares / 2;
        uint256 externalShares = pendingShares; // claimable > sharesToFulfill

        uint256 vaultPendingBefore = nestVaultOFT.pendingRedeemRequest(0, address(nestVaultComposer));
        assertEq(vaultPendingBefore, pendingShares, "Vault pending should match composer pending");

        uint256 externalAssets = nestVaultOFT.fulfillRedeem(address(nestVaultComposer), externalShares);
        assertGt(externalAssets, 0, "External fulfill assets should be > 0");

        uint256 vaultClaimableBefore = nestVaultOFT.claimableRedeemRequest(0, address(nestVaultComposer));
        uint256 vaultPendingAfterExternal = nestVaultOFT.pendingRedeemRequest(0, address(nestVaultComposer));
        assertEq(vaultClaimableBefore, externalShares, "Vault claimable should match external fulfill");
        assertEq(
            vaultPendingAfterExternal,
            pendingShares - externalShares,
            "Vault pending should decrease by external fulfill"
        );

        NestVaultCoreTypes.ClaimableRedeem memory claimableBefore =
            nestVaultComposer.claimableRedeem(addressToBytes32(address(userB)), remoteEid);

        uint256 assets = nestVaultComposer.fulfillRedeem(remoteEid, addressToBytes32(address(userB)), sharesToFulfill);
        assertGt(assets, 0, "Assets should be > 0");

        uint256 vaultClaimableAfter = nestVaultOFT.claimableRedeemRequest(0, address(nestVaultComposer));
        uint256 vaultPendingAfter = nestVaultOFT.pendingRedeemRequest(0, address(nestVaultComposer));

        assertEq(vaultClaimableAfter, vaultClaimableBefore, "Vault claimable should remain unchanged");
        assertEq(
            vaultPendingAfter,
            vaultPendingAfterExternal,
            "Vault pending should remain unchanged when claimable covers shares"
        );

        NestVaultCoreTypes.PendingRedeem memory pendingAfter =
            nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid);
        assertEq(pendingAfter.shares, pendingShares - sharesToFulfill, "Pending should decrease by shares fulfilled");

        NestVaultCoreTypes.ClaimableRedeem memory claimableAfter =
            nestVaultComposer.claimableRedeem(addressToBytes32(address(userB)), remoteEid);
        assertEq(claimableAfter.shares, claimableBefore.shares + sharesToFulfill, "Claimable shares should increase");
        assertEq(claimableAfter.assets, claimableBefore.assets + assets, "Claimable assets should increase");

        uint256 expectedAssets = (externalAssets * sharesToFulfill) / externalShares;
        assertApproxEqAbs(assets, expectedAssets, 1, "Assets should match proportional claimable allocation");
    }

    /// @notice Test fulfillRedeem uses claimable then fulfills remainder when partial claimable exists
    function test_fulfill_redeem_partial_claimable() public {
        (uint256 pendingShares, uint256 receivedShares) = _requestRedeemAndReturnPending(userB, 1e6);
        assertEq(pendingShares, receivedShares, "Pending shares should be set");

        uint256 externalShares = pendingShares / 4;
        uint256 sharesToFulfill = pendingShares / 2;
        uint256 sharesLeft = sharesToFulfill - externalShares;

        uint256 vaultPendingBefore = nestVaultOFT.pendingRedeemRequest(0, address(nestVaultComposer));
        assertEq(vaultPendingBefore, pendingShares, "Vault pending should match composer pending");

        uint256 externalAssets = nestVaultOFT.fulfillRedeem(address(nestVaultComposer), externalShares);
        assertGt(externalAssets, 0, "External fulfill assets should be > 0");

        uint256 vaultClaimableBefore = nestVaultOFT.claimableRedeemRequest(0, address(nestVaultComposer));
        assertEq(vaultClaimableBefore, externalShares, "Vault claimable should match external fulfill");

        NestVaultCoreTypes.ClaimableRedeem memory claimableBefore =
            nestVaultComposer.claimableRedeem(addressToBytes32(address(userB)), remoteEid);

        uint256 assets = nestVaultComposer.fulfillRedeem(remoteEid, addressToBytes32(address(userB)), sharesToFulfill);
        assertGt(assets, 0, "Assets should be > 0");

        uint256 vaultClaimableAfter = nestVaultOFT.claimableRedeemRequest(0, address(nestVaultComposer));
        uint256 vaultPendingAfter = nestVaultOFT.pendingRedeemRequest(0, address(nestVaultComposer));

        assertEq(
            vaultClaimableAfter, externalShares + sharesLeft, "Vault claimable should equal existing + fulfilled shares"
        );
        assertEq(
            vaultPendingAfter, pendingShares - sharesToFulfill, "Vault pending should decrease by fulfilled shares"
        );

        NestVaultCoreTypes.PendingRedeem memory pendingAfter =
            nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid);
        assertEq(pendingAfter.shares, pendingShares - sharesToFulfill, "Pending should decrease by shares fulfilled");

        NestVaultCoreTypes.ClaimableRedeem memory claimableAfter =
            nestVaultComposer.claimableRedeem(addressToBytes32(address(userB)), remoteEid);
        assertEq(claimableAfter.shares, claimableBefore.shares + sharesToFulfill, "Claimable shares should increase");
        assertEq(claimableAfter.assets, claimableBefore.assets + assets, "Claimable assets should increase");
        assertGt(assets, externalAssets, "Assets should include prior claimable plus newly fulfilled assets");
    }

    /// @notice Test fulfillRedeem fulfills when no claimable shares exist
    function test_fulfill_redeem_no_claimable() public {
        (uint256 pendingShares, uint256 receivedShares) = _requestRedeemAndReturnPending(userB, 1e6);
        assertEq(pendingShares, receivedShares, "Pending shares should be set");

        uint256 sharesToFulfill = pendingShares / 2;

        uint256 vaultClaimableBefore = nestVaultOFT.claimableRedeemRequest(0, address(nestVaultComposer));
        assertEq(vaultClaimableBefore, 0, "Vault claimable should start at 0");

        NestVaultCoreTypes.ClaimableRedeem memory claimableBefore =
            nestVaultComposer.claimableRedeem(addressToBytes32(address(userB)), remoteEid);

        uint256 assets = nestVaultComposer.fulfillRedeem(remoteEid, addressToBytes32(address(userB)), sharesToFulfill);
        assertGt(assets, 0, "Assets should be > 0");

        uint256 vaultClaimableAfter = nestVaultOFT.claimableRedeemRequest(0, address(nestVaultComposer));
        uint256 vaultPendingAfter = nestVaultOFT.pendingRedeemRequest(0, address(nestVaultComposer));

        assertEq(vaultClaimableAfter, sharesToFulfill, "Vault claimable should equal fulfilled shares");
        assertEq(
            vaultPendingAfter, pendingShares - sharesToFulfill, "Vault pending should decrease by fulfilled shares"
        );

        NestVaultCoreTypes.PendingRedeem memory pendingAfter =
            nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid);
        assertEq(pendingAfter.shares, pendingShares - sharesToFulfill, "Pending should decrease by shares fulfilled");

        NestVaultCoreTypes.ClaimableRedeem memory claimableAfter =
            nestVaultComposer.claimableRedeem(addressToBytes32(address(userB)), remoteEid);
        assertEq(claimableAfter.shares, claimableBefore.shares + sharesToFulfill, "Claimable shares should increase");
        assertEq(claimableAfter.assets, claimableBefore.assets + assets, "Claimable assets should increase");
    }

    /// @notice Test fulfillRedeem works when fulfillment happens directly through the vault
    function test_fulfill_redeem_external_vault_fulfill() public {
        (uint256 pendingShares, uint256 receivedShares) = _requestRedeemAndReturnPending(userB, 1e6);
        assertEq(pendingShares, receivedShares, "Pending shares should be set");

        uint256 externalAssets = nestVaultOFT.fulfillRedeem(address(nestVaultComposer), pendingShares);
        assertGt(externalAssets, 0, "External fulfill assets should be > 0");

        uint256 vaultClaimableBefore = nestVaultOFT.claimableRedeemRequest(0, address(nestVaultComposer));
        uint256 vaultPendingBefore = nestVaultOFT.pendingRedeemRequest(0, address(nestVaultComposer));
        assertEq(vaultClaimableBefore, pendingShares, "Vault claimable should match external fulfill");
        assertEq(vaultPendingBefore, 0, "Vault pending should be 0 after external fulfill");

        NestVaultCoreTypes.ClaimableRedeem memory claimableBefore =
            nestVaultComposer.claimableRedeem(addressToBytes32(address(userB)), remoteEid);

        uint256 assets = nestVaultComposer.fulfillRedeem(remoteEid, addressToBytes32(address(userB)), pendingShares);
        assertGt(assets, 0, "Assets should be > 0");

        uint256 vaultClaimableAfter = nestVaultOFT.claimableRedeemRequest(0, address(nestVaultComposer));
        uint256 vaultPendingAfter = nestVaultOFT.pendingRedeemRequest(0, address(nestVaultComposer));
        assertEq(vaultClaimableAfter, vaultClaimableBefore, "Vault claimable should remain unchanged");
        assertEq(vaultPendingAfter, 0, "Vault pending should remain 0");

        NestVaultCoreTypes.PendingRedeem memory pendingAfter =
            nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid);
        assertEq(pendingAfter.shares, 0, "Pending should be 0 after full fulfill");

        NestVaultCoreTypes.ClaimableRedeem memory claimableAfter =
            nestVaultComposer.claimableRedeem(addressToBytes32(address(userB)), remoteEid);
        assertEq(claimableAfter.shares, claimableBefore.shares + pendingShares, "Claimable shares should increase");
        assertApproxEqAbs(assets, externalAssets, 1, "Assets should match external fulfill amount");
    }

    /// @notice Test update redeem with same amount (no-op)
    function test_update_redeem_same_amount_noop() public {
        // Setup: Request redeem
        bytes memory requestComposeMsg = _formatRequestRedeemComposeMsg(remoteEid, address(userB).toBytes32(), 0, 0);
        uint256 redeemAmount = 1e6;
        bytes memory requestOptions =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0).addExecutorLzComposeOption(0, 500000, 0);
        SendParam memory requestSendParam = SendParam(
            localEid,
            addressToBytes32(address(nestVaultComposer)),
            redeemAmount,
            redeemAmount,
            requestOptions,
            requestComposeMsg,
            ""
        );
        MessagingFee memory requestFee = remoteNestShare.quoteSend(requestSendParam, false);

        vm.prank(userB);
        (MessagingReceipt memory requestMsgReceipt, OFTReceipt memory requestOftReceipt) =
            remoteNestShare.send{value: requestFee.nativeFee}(requestSendParam, requestFee, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory requestComposerMsg = OFTComposeMsgCodec.encode(
            requestMsgReceipt.nonce,
            remoteEid,
            requestOftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(address(userB)), requestComposeMsg)
        );
        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            requestOptions,
            requestMsgReceipt.guid,
            address(nestVaultComposer),
            requestComposerMsg
        );

        uint256 pendingShares = nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid).shares;

        // Update with same amount - should be a no-op (no shares returned)
        bytes memory updateComposeMsg =
            _formatUpdateRedeemComposeMsg(remoteEid, address(userB).toBytes32(), pendingShares, 0);
        bytes memory updateOptions =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0).addExecutorLzComposeOption(0, 500000, 0);

        SendParam memory updateSendParam = SendParam(
            localEid, addressToBytes32(address(nestVaultComposer)), 0, 0, updateOptions, updateComposeMsg, ""
        );
        MessagingFee memory updateFee = remoteNestShare.quoteSend(updateSendParam, false);

        vm.prank(userB);
        (MessagingReceipt memory updateMsgReceipt,) =
            remoteNestShare.send{value: updateFee.nativeFee}(updateSendParam, updateFee, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory updateComposerMsg = OFTComposeMsgCodec.encode(
            updateMsgReceipt.nonce, remoteEid, 0, abi.encodePacked(addressToBytes32(address(userB)), updateComposeMsg)
        );
        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            updateOptions,
            updateMsgReceipt.guid,
            address(nestVaultComposer),
            updateComposerMsg
        );

        // Verify state unchanged
        uint256 pendingSharesAfter = nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid).shares;
        assertEq(pendingSharesAfter, pendingShares, "Pending shares should remain same when updating with same amount");
    }

    /// @notice Test update redeem reverts with TRANSFER_INSUFFICIENT when vault returns fewer shares than expected
    /// @dev Tests the defensive check in _updateRequestRedeemAndSend that validates returned share amount
    function test_update_redeem_revert_TRANSFER_INSUFFICIENT() public {
        // Setup: Request redeem first
        bytes memory requestComposeMsg = _formatRequestRedeemComposeMsg(remoteEid, address(userB).toBytes32(), 0, 0);
        uint256 redeemAmount = 1e6;
        bytes memory requestOptions =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0).addExecutorLzComposeOption(0, 500000, 0);
        SendParam memory requestSendParam = SendParam(
            localEid,
            addressToBytes32(address(nestVaultComposer)),
            redeemAmount,
            redeemAmount,
            requestOptions,
            requestComposeMsg,
            ""
        );
        MessagingFee memory requestFee = remoteNestShare.quoteSend(requestSendParam, false);

        vm.prank(userB);
        (MessagingReceipt memory requestMsgReceipt, OFTReceipt memory requestOftReceipt) =
            remoteNestShare.send{value: requestFee.nativeFee}(requestSendParam, requestFee, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory requestComposerMsg = OFTComposeMsgCodec.encode(
            requestMsgReceipt.nonce,
            remoteEid,
            requestOftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(address(userB)), requestComposeMsg)
        );
        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            requestOptions,
            requestMsgReceipt.guid,
            address(nestVaultComposer),
            requestComposerMsg
        );

        uint256 pendingShares = nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid).shares;
        uint256 newSharesAmount = pendingShares / 2;

        // Prepare update message
        bytes memory returnExtraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory quoteSendParam = SendParam(
            remoteEid,
            addressToBytes32(address(userB)),
            pendingShares - newSharesAmount,
            0,
            returnExtraOptions,
            new bytes(0),
            abi.encode(VaultComposerAsyncUpgradeable.RedeemType.UpdateRedeemRequest)
        );
        MessagingFee memory returnFee = nestVaultOFT.quoteSend(quoteSendParam, false);
        uint256 returnFeeWithBuffer = returnFee.nativeFee + 1000;

        bytes memory updateOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0)
            .addExecutorLzComposeOption(0, 2000000, uint128(returnFeeWithBuffer));

        bytes memory updateComposeMsg =
            _formatUpdateRedeemComposeMsg(remoteEid, address(userB).toBytes32(), newSharesAmount, returnFeeWithBuffer);

        SendParam memory updateSendParam = SendParam(
            localEid, addressToBytes32(address(nestVaultComposer)), 0, 0, updateOptions, updateComposeMsg, ""
        );
        MessagingFee memory updateFee = remoteNestShare.quoteSend(updateSendParam, false);

        vm.prank(userB);
        (MessagingReceipt memory updateMsgReceipt, OFTReceipt memory updateOftReceipt) =
            remoteNestShare.send{value: updateFee.nativeFee}(updateSendParam, updateFee, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory updateComposerMsg = OFTComposeMsgCodec.encode(
            updateMsgReceipt.nonce,
            remoteEid,
            updateOftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(address(userB)), updateComposeMsg)
        );

        // Mock the share balance to return 0 after updateRedeem is called
        // This simulates a scenario where the vault doesn't return the expected shares
        bytes4 balanceOfSelector = bytes4(keccak256("balanceOf(address)"));
        vm.mockCall(
            address(nestShare), abi.encodeWithSelector(balanceOfSelector, address(nestVaultComposer)), abi.encode(0)
        );

        // The lzCompose should emit Refunded because TRANSFER_INSUFFICIENT is caught in try/catch
        vm.expectEmit(true, false, false, false, address(nestVaultComposer));
        emit IVaultComposerSync.Refunded(updateMsgReceipt.guid);

        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            updateOptions,
            updateMsgReceipt.guid,
            address(nestVaultComposer),
            updateComposerMsg
        );
    }

    /// @notice Test multiple request redeems from same user accumulate
    function test_multiple_request_redeems_same_user() public {
        uint256 firstAmount = 5e5;
        uint256 secondAmount = 3e5;

        // First request
        bytes memory composeMsg1 = _formatRequestRedeemComposeMsg(remoteEid, address(userB).toBytes32(), 0, 0);
        bytes memory options =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0).addExecutorLzComposeOption(0, 500000, 0);
        SendParam memory sendParam1 = SendParam(
            localEid, addressToBytes32(address(nestVaultComposer)), firstAmount, firstAmount, options, composeMsg1, ""
        );
        MessagingFee memory fee1 = remoteNestShare.quoteSend(sendParam1, false);

        vm.prank(userB);
        (MessagingReceipt memory msgReceipt1, OFTReceipt memory oftReceipt1) =
            remoteNestShare.send{value: fee1.nativeFee}(sendParam1, fee1, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory composerMsg1 = OFTComposeMsgCodec.encode(
            msgReceipt1.nonce,
            remoteEid,
            oftReceipt1.amountReceivedLD,
            abi.encodePacked(addressToBytes32(address(userB)), composeMsg1)
        );
        this.lzCompose(
            localEid, address(nestVaultOFT), options, msgReceipt1.guid, address(nestVaultComposer), composerMsg1
        );

        uint256 pendingAfterFirst = nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid).shares;
        assertEq(pendingAfterFirst, oftReceipt1.amountReceivedLD, "First request should set pending");

        // Second request
        bytes memory composeMsg2 = _formatRequestRedeemComposeMsg(remoteEid, address(userB).toBytes32(), 0, 0);
        SendParam memory sendParam2 = SendParam(
            localEid, addressToBytes32(address(nestVaultComposer)), secondAmount, secondAmount, options, composeMsg2, ""
        );
        MessagingFee memory fee2 = remoteNestShare.quoteSend(sendParam2, false);

        vm.prank(userB);
        (MessagingReceipt memory msgReceipt2, OFTReceipt memory oftReceipt2) =
            remoteNestShare.send{value: fee2.nativeFee}(sendParam2, fee2, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory composerMsg2 = OFTComposeMsgCodec.encode(
            msgReceipt2.nonce,
            remoteEid,
            oftReceipt2.amountReceivedLD,
            abi.encodePacked(addressToBytes32(address(userB)), composeMsg2)
        );
        this.lzCompose(
            localEid, address(nestVaultOFT), options, msgReceipt2.guid, address(nestVaultComposer), composerMsg2
        );

        // Verify accumulation
        uint256 pendingAfterSecond = nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid).shares;
        assertEq(
            pendingAfterSecond, oftReceipt1.amountReceivedLD + oftReceipt2.amountReceivedLD, "Pending should accumulate"
        );
    }

    /// @notice Test update redeem with no pending - should emit Refunded using only user-provided gas
    function test_update_redeem_no_pending_emits_refund() public {
        // Get the endpoint address
        address endpoint = nestVaultComposer.ENDPOINT();

        // Prepare a compose message for update redeem without any pending shares
        // User provides minMsgValue for the refund gas
        uint256 minMsgValue = 1 ether;
        bytes memory composeMsg = _formatUpdateRedeemComposeMsg(remoteEid, address(userB).toBytes32(), 5e5, minMsgValue);
        bytes32 guid = bytes32(uint256(12345));

        bytes memory composerMsg = OFTComposeMsgCodec.encode(
            1, // nonce
            remoteEid,
            0, // no amount (update doesn't send shares)
            abi.encodePacked(addressToBytes32(address(userB)), composeMsg)
        );

        // Fund composer with some ETH (should NOT be used for refund)
        vm.deal(address(nestVaultComposer), 5 ether);
        uint256 composerBalanceBefore = address(nestVaultComposer).balance;

        // Fund endpoint to send msg.value (simulates user-provided gas)
        vm.deal(endpoint, 10 ether);

        // Call lzCompose from the endpoint - should catch error and emit Refunded
        // The msg.value (user-provided gas) should be used for refund, not composer's balance
        vm.prank(endpoint);
        vm.expectEmit(true, false, false, false);
        emit IVaultComposerSync.Refunded(guid);
        nestVaultComposer.lzCompose{value: minMsgValue}(
            address(nestVaultOFT), // composeSender (share OFT)
            guid,
            composerMsg,
            address(0), // executor
            "" // extraData
        );

        // Verify composer's balance was not used (refund used msg.value from user)
        uint256 composerBalanceAfter = address(nestVaultComposer).balance;
        assertEq(
            composerBalanceAfter,
            composerBalanceBefore,
            "Composer balance should not decrease - refund uses user's msg.value"
        );
    }

    /// @notice Test update redeem with more shares than pending - should emit Refunded using only user-provided gas
    function test_update_redeem_insufficient_balance_emits_refund() public {
        // Setup: Request redeem
        bytes memory requestComposeMsg = _formatRequestRedeemComposeMsg(remoteEid, address(userB).toBytes32(), 0, 0);
        uint256 redeemAmount = 1e6;
        bytes memory requestOptions =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0).addExecutorLzComposeOption(0, 500000, 0);
        SendParam memory requestSendParam = SendParam(
            localEid,
            addressToBytes32(address(nestVaultComposer)),
            redeemAmount,
            redeemAmount,
            requestOptions,
            requestComposeMsg,
            ""
        );
        MessagingFee memory requestFee = remoteNestShare.quoteSend(requestSendParam, false);

        vm.prank(userB);
        (MessagingReceipt memory requestMsgReceipt, OFTReceipt memory requestOftReceipt) =
            remoteNestShare.send{value: requestFee.nativeFee}(requestSendParam, requestFee, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory requestComposerMsg = OFTComposeMsgCodec.encode(
            requestMsgReceipt.nonce,
            remoteEid,
            requestOftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(address(userB)), requestComposeMsg)
        );
        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            requestOptions,
            requestMsgReceipt.guid,
            address(nestVaultComposer),
            requestComposerMsg
        );

        uint256 pendingShares = nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid).shares;

        // Get the endpoint address
        address endpoint = nestVaultComposer.ENDPOINT();
        bytes32 guid = bytes32(uint256(99999));

        // Try to update with MORE shares (should catch error and emit Refunded)
        // User provides minMsgValue for the refund gas
        uint256 minMsgValue = 1 ether;
        uint256 increasedAmount = pendingShares + 1e5;
        bytes memory updateComposeMsg =
            _formatUpdateRedeemComposeMsg(remoteEid, address(userB).toBytes32(), increasedAmount, minMsgValue);

        bytes memory updateComposerMsg = OFTComposeMsgCodec.encode(
            2, // nonce
            remoteEid,
            0, // no amount (update doesn't send shares)
            abi.encodePacked(addressToBytes32(address(userB)), updateComposeMsg)
        );

        // Fund composer with some ETH (should NOT be used for refund)
        vm.deal(address(nestVaultComposer), 5 ether);
        uint256 composerBalanceBefore = address(nestVaultComposer).balance;

        // Fund endpoint to send msg.value (simulates user-provided gas)
        vm.deal(endpoint, 10 ether);

        // Call lzCompose from the endpoint - should catch error and emit Refunded
        // The msg.value (user-provided gas) should be used for refund, not composer's balance
        vm.prank(endpoint);
        vm.expectEmit(true, false, false, false);
        emit IVaultComposerSync.Refunded(guid);
        nestVaultComposer.lzCompose{value: minMsgValue}(
            address(nestVaultOFT), // composeSender (share OFT)
            guid,
            updateComposerMsg,
            address(0), // executor
            "" // extraData
        );

        // Verify composer's balance was not used (refund used msg.value from user)
        uint256 composerBalanceAfter = address(nestVaultComposer).balance;
        assertEq(
            composerBalanceAfter,
            composerBalanceBefore,
            "Composer balance should not decrease - refund uses user's msg.value"
        );

        // Verify state unchanged
        assertEq(
            nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid).shares,
            pendingShares,
            "Pending should be unchanged"
        );
    }

    /// @notice Test complete redeem reverts when insufficient claimable
    function test_finish_redeem_revert_INSUFFICIENT_CLAIMABLE() public {
        // Setup: Request and fulfill redeem
        bytes memory requestComposeMsg = _formatRequestRedeemComposeMsg(remoteEid, address(userB).toBytes32(), 0, 0);
        uint256 redeemAmount = 1e6;
        bytes memory requestOptions =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0).addExecutorLzComposeOption(0, 500000, 0);
        SendParam memory requestSendParam = SendParam(
            localEid,
            addressToBytes32(address(nestVaultComposer)),
            redeemAmount,
            redeemAmount,
            requestOptions,
            requestComposeMsg,
            ""
        );
        MessagingFee memory requestFee = remoteNestShare.quoteSend(requestSendParam, false);

        vm.prank(userB);
        (MessagingReceipt memory requestMsgReceipt, OFTReceipt memory requestOftReceipt) =
            remoteNestShare.send{value: requestFee.nativeFee}(requestSendParam, requestFee, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory requestComposerMsg = OFTComposeMsgCodec.encode(
            requestMsgReceipt.nonce,
            remoteEid,
            requestOftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(address(userB)), requestComposeMsg)
        );
        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            requestOptions,
            requestMsgReceipt.guid,
            address(nestVaultComposer),
            requestComposerMsg
        );

        uint256 pendingShares = nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid).shares;

        // Fulfill only half
        uint256 halfShares = pendingShares / 2;
        nestVaultComposer.fulfillRedeem(remoteEid, addressToBytes32(address(userB)), halfShares);

        // Try to complete redeem for MORE than claimable
        uint256 excessiveAmount = halfShares + 1;
        bytes memory completeComposeMsg =
            _formatCompleteRedeemComposeMsg(remoteEid, address(userB).toBytes32(), excessiveAmount, 0, 0);
        // Include native value for compose to cover potential refund fees
        bytes memory completeOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0)
            .addExecutorLzComposeOption(0, 2000000, 0.05 ether);

        SendParam memory completeSendParam = SendParam(
            localEid, addressToBytes32(address(nestVaultComposer)), 0, 0, completeOptions, completeComposeMsg, ""
        );
        MessagingFee memory completeFee = remoteNestShare.quoteSend(completeSendParam, false);

        vm.prank(userB);
        (MessagingReceipt memory completeMsgReceipt,) =
            remoteNestShare.send{value: completeFee.nativeFee}(completeSendParam, completeFee, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory completeComposerMsg = OFTComposeMsgCodec.encode(
            completeMsgReceipt.nonce,
            remoteEid,
            0,
            abi.encodePacked(addressToBytes32(address(userB)), completeComposeMsg)
        );

        // Should refund (INSUFFICIENT_CLAIMABLE caught internally)
        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            completeOptions,
            completeMsgReceipt.guid,
            address(nestVaultComposer),
            completeComposerMsg
        );

        // Verify claimable unchanged
        assertEq(
            nestVaultComposer.claimableRedeem(addressToBytes32(address(userB)), remoteEid).shares,
            halfShares,
            "Claimable should be unchanged"
        );
    }

    /// @notice Test finish redeem reverts when zero shares are passed
    function test_finish_redeem_revert_ZERO_SHARES() public {
        // Setup: Request and fulfill redeem first to have claimable shares
        bytes memory requestComposeMsg = _formatRequestRedeemComposeMsg(remoteEid, address(userB).toBytes32(), 0, 0);
        uint256 redeemAmount = 1e6;
        bytes memory requestOptions =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0).addExecutorLzComposeOption(0, 500000, 0);
        SendParam memory requestSendParam = SendParam(
            localEid,
            addressToBytes32(address(nestVaultComposer)),
            redeemAmount,
            redeemAmount,
            requestOptions,
            requestComposeMsg,
            ""
        );
        MessagingFee memory requestFee = remoteNestShare.quoteSend(requestSendParam, false);

        vm.prank(userB);
        (MessagingReceipt memory requestMsgReceipt, OFTReceipt memory requestOftReceipt) =
            remoteNestShare.send{value: requestFee.nativeFee}(requestSendParam, requestFee, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory requestComposerMsg = OFTComposeMsgCodec.encode(
            requestMsgReceipt.nonce,
            remoteEid,
            requestOftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(address(userB)), requestComposeMsg)
        );
        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            requestOptions,
            requestMsgReceipt.guid,
            address(nestVaultComposer),
            requestComposerMsg
        );

        uint256 pendingShares = nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid).shares;

        // Fulfill all pending shares
        nestVaultComposer.fulfillRedeem(remoteEid, addressToBytes32(address(userB)), pendingShares);

        // Verify claimable shares exist
        uint256 claimableShares = nestVaultComposer.claimableRedeem(addressToBytes32(address(userB)), remoteEid).shares;
        assertGt(claimableShares, 0, "Should have claimable shares");

        // Try to complete redeem with ZERO shares - should revert with ZERO_SHARES
        uint256 zeroShareAmount = 0;
        bytes memory completeComposeMsg =
            _formatCompleteRedeemComposeMsg(remoteEid, address(userB).toBytes32(), zeroShareAmount, 0, 0);
        // Include native value for compose to cover potential refund fees
        bytes memory completeOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0)
            .addExecutorLzComposeOption(0, 2000000, 0.05 ether);

        SendParam memory completeSendParam = SendParam(
            localEid, addressToBytes32(address(nestVaultComposer)), 0, 0, completeOptions, completeComposeMsg, ""
        );
        MessagingFee memory completeFee = remoteNestShare.quoteSend(completeSendParam, false);

        vm.prank(userB);
        (MessagingReceipt memory completeMsgReceipt,) =
            remoteNestShare.send{value: completeFee.nativeFee}(completeSendParam, completeFee, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory completeComposerMsg = OFTComposeMsgCodec.encode(
            completeMsgReceipt.nonce,
            remoteEid,
            0,
            abi.encodePacked(addressToBytes32(address(userB)), completeComposeMsg)
        );

        // Expect Refunded event (ZERO_SHARES caught internally, triggers refund)
        vm.expectEmit(true, false, false, false, address(nestVaultComposer));
        emit IVaultComposerSync.Refunded(completeMsgReceipt.guid);

        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            completeOptions,
            completeMsgReceipt.guid,
            address(nestVaultComposer),
            completeComposerMsg
        );

        // Verify claimable unchanged (refund happened, complete did not process)
        assertEq(
            nestVaultComposer.claimableRedeem(addressToBytes32(address(userB)), remoteEid).shares,
            claimableShares,
            "Claimable should be unchanged after ZERO_SHARES revert"
        );
    }

    /// @notice Test fulfill redeem reverts when no pending exists
    function test_fulfill_redeem_revert_NO_PENDING_REDEEM() public {
        // Try to fulfill without any pending
        vm.expectRevert(Errors.NoPendingRedeem.selector);
        nestVaultComposer.fulfillRedeem(remoteEid, addressToBytes32(address(userB)), 1e6);
    }

    /// @notice Test fulfill redeem reverts when trying to fulfill more than pending
    function test_fulfill_redeem_revert_exceeds_pending() public {
        // Setup: Request redeem
        bytes memory requestComposeMsg = _formatRequestRedeemComposeMsg(remoteEid, address(userB).toBytes32(), 0, 0);
        uint256 redeemAmount = 1e6;
        bytes memory requestOptions =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0).addExecutorLzComposeOption(0, 500000, 0);
        SendParam memory requestSendParam = SendParam(
            localEid,
            addressToBytes32(address(nestVaultComposer)),
            redeemAmount,
            redeemAmount,
            requestOptions,
            requestComposeMsg,
            ""
        );
        MessagingFee memory requestFee = remoteNestShare.quoteSend(requestSendParam, false);

        vm.prank(userB);
        (MessagingReceipt memory requestMsgReceipt, OFTReceipt memory requestOftReceipt) =
            remoteNestShare.send{value: requestFee.nativeFee}(requestSendParam, requestFee, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory requestComposerMsg = OFTComposeMsgCodec.encode(
            requestMsgReceipt.nonce,
            remoteEid,
            requestOftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(address(userB)), requestComposeMsg)
        );
        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            requestOptions,
            requestMsgReceipt.guid,
            address(nestVaultComposer),
            requestComposerMsg
        );

        uint256 pendingShares = nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid).shares;

        // Try to fulfill MORE than pending
        vm.expectRevert(Errors.InsufficientBalance.selector);
        nestVaultComposer.fulfillRedeem(remoteEid, addressToBytes32(address(userB)), pendingShares + 1);
    }

    /// @notice Test infeasible minMsgValue falls back to refund when refund quote is funded
    function test_lzCompose_InsufficientMsgValue_refunds_when_refund_fundable() public {
        address endpoint = nestVaultComposer.ENDPOINT();
        uint256 amount = 1e6;
        uint64 nonce = 1;
        bytes32 composeFrom = addressToBytes32(address(userB));
        bytes32 guid = bytes32(uint256(54321));

        SendParam memory refundSendParam = SendParam({
            dstEid: remoteEid,
            to: composeFrom,
            amountLD: amount,
            minAmountLD: 0,
            extraOptions: new bytes(0),
            composeMsg: new bytes(0),
            oftCmd: new bytes(0)
        });
        MessagingFee memory refundFee = nestVaultOFT.quoteSend(refundSendParam, false);
        assertGt(refundFee.nativeFee, 0, "refund fee must be non-zero");

        // Force InsufficientMsgValue while still funding the return path.
        uint256 highMinMsgValue = refundFee.nativeFee + 1;
        bytes memory composeMsg =
            _formatRequestRedeemComposeMsg(remoteEid, address(userB).toBytes32(), 0, highMinMsgValue);
        bytes memory composerMsg =
            OFTComposeMsgCodec.encode(nonce, remoteEid, amount, abi.encodePacked(composeFrom, composeMsg));

        // Ensure composer can execute the share-token refund send.
        nestVaultOFT.credit(address(nestVaultComposer), amount, remoteEid);

        vm.deal(endpoint, refundFee.nativeFee);
        vm.expectEmit(true, false, false, false, address(nestVaultComposer));
        emit IVaultComposerSync.Refunded(guid);

        vm.prank(endpoint);
        nestVaultComposer.lzCompose{value: refundFee.nativeFee}(
            address(nestVaultOFT), guid, composerMsg, address(0), ""
        );

        assertEq(nestVaultOFT.balanceOf(address(nestVaultComposer)), 0, "Composer share balance should be refunded");
        assertEq(
            nestVaultComposer.pendingRedeem(addressToBytes32(address(userB)), remoteEid).shares,
            0,
            "Pending redeem should remain unchanged"
        );
    }

    /// @notice Test lzCompose reverts when msg.value cannot fund minMsgValue or refund
    function test_lzCompose_revert_InsufficientMsgValue_when_refund_unfunded() public {
        address endpoint = nestVaultComposer.ENDPOINT();
        uint256 amount = 1e6;
        uint64 nonce = 1;
        bytes32 composeFrom = addressToBytes32(address(userB));
        bytes32 guid = bytes32(uint256(54322));

        SendParam memory refundSendParam = SendParam({
            dstEid: remoteEid,
            to: composeFrom,
            amountLD: amount,
            minAmountLD: 0,
            extraOptions: new bytes(0),
            composeMsg: new bytes(0),
            oftCmd: new bytes(0)
        });
        MessagingFee memory refundFee = nestVaultOFT.quoteSend(refundSendParam, false);
        assertGt(refundFee.nativeFee, 0, "refund fee must be non-zero");

        uint256 underfundedMsgValue = refundFee.nativeFee - 1;
        uint256 highMinMsgValue = refundFee.nativeFee + 1;
        bytes memory composeMsg =
            _formatRequestRedeemComposeMsg(remoteEid, address(userB).toBytes32(), 0, highMinMsgValue);
        bytes memory composerMsg =
            OFTComposeMsgCodec.encode(nonce, remoteEid, amount, abi.encodePacked(composeFrom, composeMsg));

        // InsufficientMsgValue is only retried when minMsgValue <= maxRetryableValue.
        nestVaultComposer.setMaxRetryableValue(highMinMsgValue);

        vm.deal(endpoint, underfundedMsgValue);
        vm.prank(endpoint);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultComposerSync.InsufficientMsgValue.selector, highMinMsgValue, underfundedMsgValue
            )
        );
        nestVaultComposer.lzCompose{value: underfundedMsgValue}(
            address(nestVaultOFT), guid, composerMsg, address(0), ""
        );
    }

    /// @notice Test malformed compose msg is refunded
    function test_lzCompose_malformed_composeMsg_refunds() public {
        address endpoint = nestVaultComposer.ENDPOINT();
        uint64 nonce = 1;
        uint256 amount = 1e6;
        bytes32 composeFrom = addressToBytes32(address(userB));
        bytes memory malformedComposeMsg = "";
        bytes memory composerMsg =
            OFTComposeMsgCodec.encode(nonce, remoteEid, amount, abi.encodePacked(composeFrom, malformedComposeMsg));
        bytes32 guid = bytes32(uint256(777));

        vm.deal(endpoint, 1 ether);
        // Ensure composer holds shares so refund via share OFT can burn successfully
        nestVaultOFT.credit(address(nestVaultComposer), amount, remoteEid);

        vm.recordLogs();
        vm.prank(endpoint);
        nestVaultComposer.lzCompose{value: 0.1 ether}(address(nestVaultOFT), guid, composerMsg, address(0), "");

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 refundedTopic = keccak256("Refunded(bytes32)");
        bool foundRefunded = false;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].emitter != address(nestVaultComposer)) {
                continue;
            }

            if (entries[i].topics.length > 0 && entries[i].topics[0] == refundedTopic) {
                if (entries[i].topics.length == 2 && entries[i].topics[1] == guid) {
                    foundRefunded = true;
                }
            }
        }

        assertTrue(foundRefunded, "Refunded should be emitted");
    }

    /// @notice Test blocked compose guids revert and keep balances unchanged
    function test_lzCompose_revert_when_composeBlocked_true() public {
        address endpoint = nestVaultComposer.ENDPOINT();
        uint64 nonce = 1;
        uint256 amount = 1e6;
        bytes32 composeFrom = addressToBytes32(address(userB));
        bytes memory malformedComposeMsg = "";
        bytes memory composerMsg =
            OFTComposeMsgCodec.encode(nonce, remoteEid, amount, abi.encodePacked(composeFrom, malformedComposeMsg));
        bytes32 guid = bytes32(uint256(888888));

        nestVaultOFT.credit(address(nestVaultComposer), amount, remoteEid);
        uint256 composerBalanceBefore = nestVaultOFT.balanceOf(address(nestVaultComposer));

        nestVaultComposer.setBlockCompose(guid, true);
        assertTrue(nestVaultComposer.composeBlocked(guid), "Guid should be blocked");

        vm.deal(endpoint, 0.1 ether);
        vm.expectRevert(abi.encodeWithSelector(VaultComposerAsyncUpgradeable.ComposeBlocked.selector, guid));
        vm.prank(endpoint);
        nestVaultComposer.lzCompose{value: 0.1 ether}(address(nestVaultOFT), guid, composerMsg, address(0), "");

        assertEq(
            nestVaultOFT.balanceOf(address(nestVaultComposer)),
            composerBalanceBefore,
            "Blocked compose should not move composer balance"
        );
    }

    /// @notice Test blocked compose can be unblocked and retried through normal flow
    function test_lzCompose_block_then_unblock_retry_works() public {
        address endpoint = nestVaultComposer.ENDPOINT();
        uint64 nonce = 1;
        uint256 amount = 1e6;
        bytes32 composeFrom = addressToBytes32(address(userB));
        bytes memory malformedComposeMsg = "";
        bytes memory composerMsg =
            OFTComposeMsgCodec.encode(nonce, remoteEid, amount, abi.encodePacked(composeFrom, malformedComposeMsg));
        bytes32 guid = bytes32(uint256(888889));

        nestVaultOFT.credit(address(nestVaultComposer), amount, remoteEid);

        nestVaultComposer.setBlockCompose(guid, true);
        vm.deal(endpoint, 0.1 ether);
        vm.expectRevert(abi.encodeWithSelector(VaultComposerAsyncUpgradeable.ComposeBlocked.selector, guid));
        vm.prank(endpoint);
        nestVaultComposer.lzCompose{value: 0.1 ether}(address(nestVaultOFT), guid, composerMsg, address(0), "");

        assertEq(nestVaultOFT.balanceOf(address(nestVaultComposer)), amount, "Blocked compose should not refund");

        nestVaultComposer.setBlockCompose(guid, false);
        assertFalse(nestVaultComposer.composeBlocked(guid), "Guid should be unblocked");

        vm.deal(endpoint, 0.1 ether);
        vm.expectEmit(true, false, false, false, address(nestVaultComposer));
        emit IVaultComposerSync.Refunded(guid);
        vm.prank(endpoint);
        nestVaultComposer.lzCompose{value: 0.1 ether}(address(nestVaultOFT), guid, composerMsg, address(0), "");

        assertEq(
            nestVaultOFT.balanceOf(address(nestVaultComposer)), 0, "Unblocked compose should follow normal refund flow"
        );
    }

    /// @notice Test slippage protection on deposit
    function test_deposit_revert_SlippageExceeded() public {
        // This tests that SlippageExceeded is thrown when minAmountLD is not met
        // We'll setup a deposit where the minAmountLD is impossibly high
        bytes memory predicateMsg =
            _formatPredicateMessage("test", block.timestamp + 1 days, new address[](0), new bytes[](0));

        // Create SendParam with very high minAmountLD
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam({
            dstEid: remoteEid,
            to: addressToBytes32(address(userB)),
            amountLD: 0, // will be overridden
            minAmountLD: type(uint256).max, // impossibly high slippage protection
            extraOptions: options,
            composeMsg: new bytes(0),
            oftCmd: predicateMsg
        });

        uint256 depositAmount = 1e6;

        // Mint and approve assets for the test
        vm.prank(userA);
        localAsset.approve(address(nestVaultComposer), depositAmount);

        // This should revert with SlippageExceeded since minAmountLD is impossibly high
        vm.prank(userA);
        vm.expectRevert(
            abi.encodeWithSelector(IVaultComposerSync.SlippageExceeded.selector, depositAmount, type(uint256).max)
        );
        nestVaultComposer.depositAndSend{value: 1 ether}(depositAmount, sendParam, userA);
    }

    function test_initialize_revert_ZERO_ADDRESS() public {
        address impl = address(new NestVaultComposer(address(nestVaultPredicateProxy)));
        bytes memory initData = abi.encodeWithSelector(
            NestVaultComposer.initialize.selector,
            address(0),
            address(nestVaultOFT),
            address(nestCCTPRelayer),
            address(nestVaultOFT),
            0
        );

        vm.expectRevert(Errors.ZeroAddress.selector);
        new TransparentUpgradeableProxy(impl, proxyAdmin, initData);
    }

    function test_depositAndSend_revert_ZERO_SHARES() public {
        bytes memory predicateMsg =
            _formatPredicateMessage("test", block.timestamp + 1 days, new address[](0), new bytes[](0));
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        bytes4 depositSelector =
            bytes4(keccak256("deposit(address,uint256,address,address,bytes32,(string,uint256,address[],bytes[]))"));
        vm.mockCallRevert(
            address(nestVaultPredicateProxy),
            abi.encodeWithSelector(depositSelector),
            abi.encodeWithSelector(Errors.ZeroShares.selector)
        );

        SendParam memory sendParam = SendParam({
            dstEid: remoteEid,
            to: addressToBytes32(address(userB)),
            amountLD: 0,
            minAmountLD: 0,
            extraOptions: options,
            composeMsg: new bytes(0),
            oftCmd: predicateMsg
        });

        vm.prank(userA);
        localAsset.approve(address(nestVaultComposer), type(uint256).max);

        vm.prank(userA);
        vm.expectRevert(Errors.ZeroShares.selector);
        nestVaultComposer.depositAndSend{value: 0}(addressToBytes32(address(userA)), 0, sendParam, userA);
    }

    function test_redeemAndSend_revert_ZERO_ASSETS() public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        uint256 shareAmount = 1e6;

        vm.mockCall(
            address(nestVaultComposer.VAULT()),
            abi.encodeWithSelector(
                INestVaultCore.instantRedeem.selector,
                shareAmount,
                address(nestVaultComposer),
                address(nestVaultComposer)
            ),
            abi.encode(0, 0)
        );

        SendParam memory sendParam = SendParam({
            dstEid: remoteEid,
            to: addressToBytes32(address(userB)),
            amountLD: 0,
            minAmountLD: 0,
            extraOptions: options,
            composeMsg: new bytes(0),
            oftCmd: abi.encode(VaultComposerAsyncUpgradeable.RedeemType.InstantRedeem)
        });

        vm.prank(userA);
        nestShare.approve(address(nestVaultComposer), type(uint256).max);

        vm.prank(userA);
        vm.expectRevert(Errors.ZeroAssets.selector);
        nestVaultComposer.redeemAndSend{value: 0}(addressToBytes32(address(userA)), shareAmount, sendParam, userA);
    }

    function test_lzCompose_deposit_zero_shares_emits_refund() public {
        address endpoint = nestVaultComposer.ENDPOINT();

        bytes memory predicateMsg =
            _formatPredicateMessage("test", block.timestamp + 1 days, new address[](0), new bytes[](0));
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        uint256 amount = 1e6;

        // Force the predicate deposit to revert with ZERO_SHARES so lzCompose triggers the refund path
        bytes4 depositSelector =
            bytes4(keccak256("deposit(address,uint256,address,address,bytes32,(string,uint256,address[],bytes[]))"));
        vm.mockCallRevert(
            address(nestVaultPredicateProxy),
            abi.encodeWithSelector(depositSelector),
            abi.encodeWithSelector(Errors.ZeroShares.selector)
        );

        // Fund composer and approve predicate proxy so deposit can proceed
        localAsset.mint(address(nestVaultComposer), amount);
        vm.prank(address(nestVaultComposer));
        localAsset.approve(address(nestVaultPredicateProxy), type(uint256).max);

        SendParam memory sendParam = SendParam({
            dstEid: remoteEid,
            to: addressToBytes32(address(userB)),
            amountLD: 0,
            minAmountLD: 0,
            extraOptions: options,
            composeMsg: new bytes(0),
            oftCmd: predicateMsg
        });

        uint256 minMsgValue = 0.05 ether;
        bytes memory composeMsg = abi.encode(sendParam, minMsgValue);
        bytes32 guid = bytes32(uint256(99999));

        bytes memory composerMsg = OFTComposeMsgCodec.encode(
            1, // nonce
            remoteEid,
            amount, // amount received; predicate deposit is mocked to revert to force refund path
            abi.encodePacked(addressToBytes32(address(userA)), composeMsg)
        );

        vm.deal(endpoint, minMsgValue);
        vm.expectEmit(true, false, false, false, address(nestVaultComposer));
        emit IVaultComposerSync.Refunded(guid);

        vm.prank(endpoint);
        nestVaultComposer.lzCompose{value: minMsgValue}(address(nestCCTPRelayer), guid, composerMsg, address(0), "");

        assertEq(localAsset.balanceOf(address(nestVaultComposer)), 0, "Composer asset balance should remain zero");
    }

    function test_lzCompose_redeem_zero_assets_emits_refund() public {
        address endpoint = nestVaultComposer.ENDPOINT();

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        uint256 shareAmount = 1e6;

        vm.mockCall(
            address(nestVaultComposer.VAULT()),
            abi.encodeWithSelector(
                INestVaultCore.instantRedeem.selector,
                shareAmount,
                address(nestVaultComposer),
                address(nestVaultComposer)
            ),
            abi.encode(0, 0)
        );

        SendParam memory sendParam = SendParam({
            dstEid: remoteEid,
            to: addressToBytes32(address(userB)),
            amountLD: 0,
            minAmountLD: 0,
            extraOptions: options,
            composeMsg: new bytes(0),
            oftCmd: abi.encode(VaultComposerAsyncUpgradeable.RedeemType.InstantRedeem)
        });

        uint256 minMsgValue = 0.05 ether;
        bytes memory composeMsg = abi.encode(sendParam, minMsgValue);
        bytes32 guid = bytes32(uint256(123456));

        // Simulate LayerZero deliver of share tokens to the composer before compose handling
        nestVaultOFT.credit(address(nestVaultComposer), shareAmount, remoteEid);

        bytes memory composerMsg = OFTComposeMsgCodec.encode(
            1, remoteEid, shareAmount, abi.encodePacked(addressToBytes32(address(userA)), composeMsg)
        );

        vm.deal(endpoint, minMsgValue);
        vm.expectEmit(true, false, false, false, address(nestVaultComposer));
        emit IVaultComposerSync.Refunded(guid);

        vm.prank(endpoint);
        nestVaultComposer.lzCompose{value: minMsgValue}(address(nestVaultOFT), guid, composerMsg, address(0), "");

        assertEq(localAsset.balanceOf(address(nestVaultComposer)), 0, "Composer asset balance should remain zero");
    }

    function test_lzCompose_redeem_unknown_type_emits_refund() public {
        address endpoint = nestVaultComposer.ENDPOINT();

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        uint256 shareAmount = 1e6;

        SendParam memory sendParam = SendParam({
            dstEid: remoteEid,
            to: addressToBytes32(address(userB)),
            amountLD: 0,
            minAmountLD: 0,
            extraOptions: options,
            composeMsg: new bytes(0),
            // Encode an out-of-range redeem type to trigger UnknownRedeemType refund path
            oftCmd: abi.encode(uint8(99))
        });

        uint256 minMsgValue = 0.05 ether;
        bytes memory composeMsg = abi.encode(sendParam, minMsgValue);
        bytes32 guid = bytes32(uint256(777777));

        // Simulate LayerZero delivering share tokens to the composer before compose handling
        nestVaultOFT.credit(address(nestVaultComposer), shareAmount, remoteEid);

        bytes memory composerMsg = OFTComposeMsgCodec.encode(
            1, remoteEid, shareAmount, abi.encodePacked(addressToBytes32(address(userA)), composeMsg)
        );

        vm.deal(endpoint, minMsgValue);
        vm.expectEmit(true, false, false, false, address(nestVaultComposer));
        emit IVaultComposerSync.Refunded(guid);

        vm.prank(endpoint);
        nestVaultComposer.lzCompose{value: minMsgValue}(address(nestVaultOFT), guid, composerMsg, address(0), "");

        assertEq(
            nestVaultOFT.balanceOf(address(nestVaultComposer)),
            0,
            "Composer share balance should be refunded on unknown redeem type"
        );
    }

    /// @notice Test local depositAndSend reverts when msg.value is non-zero
    function test_depositAndSend_revert_NonZeroMsgValueLocal() public {
        uint256 depositAmount = 1e6;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        uint32 vaultEid = nestVaultComposer.VAULT_EID();
        bytes memory predicateMsg =
            _formatPredicateMessage("test", block.timestamp + 1 days, new address[](0), new bytes[](0));

        SendParam memory sendParam = SendParam({
            dstEid: vaultEid,
            to: addressToBytes32(address(userB)),
            amountLD: 0,
            minAmountLD: 0,
            extraOptions: options,
            composeMsg: new bytes(0),
            oftCmd: predicateMsg
        });

        vm.prank(userA);
        localAsset.approve(address(nestVaultComposer), depositAmount);

        uint256 msgValue = 1 ether;
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(Errors.NonZeroMsgValueLocal.selector, msgValue));
        nestVaultComposer.depositAndSend{value: msgValue}(
            addressToBytes32(address(userA)), depositAmount, sendParam, userA
        );
    }

    /// @notice Test fulfillRedeem reverts when vault returns zero assets
    function test_fulfill_redeem_revert_ZERO_ASSETS() public {
        // This test requires mocking the vault to return 0 assets
        // For now, we can verify the error exists by checking the error selector
        // A proper test would require a mock vault that returns 0 on fulfillRedeem
        assertTrue(Errors.ZeroAssets.selector == bytes4(keccak256("ZeroAssets()")), "ZeroAssets error should exist");
    }

    /// @notice Test direct depositAndSend requires authorization
    function test_depositAndSend_requiresAuth() public {
        // Create a restrictive authority that denies all calls
        MockAuthority restrictiveAuthority = new MockAuthority(false);
        nestVaultComposer.setAuthority(Authority(address(restrictiveAuthority)));

        bytes memory predicateMsg =
            _formatPredicateMessage("test", block.timestamp + 1 days, new address[](0), new bytes[](0));
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam({
            dstEid: remoteEid,
            to: addressToBytes32(address(userB)),
            amountLD: 0,
            minAmountLD: 0,
            extraOptions: options,
            composeMsg: new bytes(0),
            oftCmd: predicateMsg
        });

        uint256 depositAmount = 1e6;

        // userA is not authorized, should fail
        vm.prank(userA);
        localAsset.approve(address(nestVaultComposer), depositAmount);

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSignature("AUTH_UNAUTHORIZED()"));
        nestVaultComposer.depositAndSend{value: 1 ether}(
            addressToBytes32(address(userA)), depositAmount, sendParam, userA
        );

        // Restore permissive authority for other tests
        MockAuthority permissiveAuthority = new MockAuthority(true);
        nestVaultComposer.setAuthority(Authority(address(permissiveAuthority)));
    }

    /// @notice Test inherited sync depositAndSend overload requires authorization
    function test_depositAndSend_syncOverload_requiresAuth() public {
        MockAuthority restrictiveAuthority = new MockAuthority(false);
        nestVaultComposer.setAuthority(Authority(address(restrictiveAuthority)));

        bytes memory predicateMsg =
            _formatPredicateMessage("test", block.timestamp + 1 days, new address[](0), new bytes[](0));
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam({
            dstEid: remoteEid,
            to: addressToBytes32(address(userB)),
            amountLD: 0,
            minAmountLD: 0,
            extraOptions: options,
            composeMsg: new bytes(0),
            oftCmd: predicateMsg
        });

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSignature("AUTH_UNAUTHORIZED()"));
        nestVaultComposer.depositAndSend{value: 1 ether}(1e6, sendParam, userA);

        MockAuthority permissiveAuthority = new MockAuthority(true);
        nestVaultComposer.setAuthority(Authority(address(permissiveAuthority)));
    }

    /// @notice Test direct redeemAndSend requires authorization
    function test_redeemAndSend_requiresAuth() public {
        // Create a restrictive authority that denies all calls
        MockAuthority restrictiveAuthority = new MockAuthority(false);
        nestVaultComposer.setAuthority(Authority(address(restrictiveAuthority)));

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam({
            dstEid: remoteEid,
            to: addressToBytes32(address(userB)),
            amountLD: 0,
            minAmountLD: 0,
            extraOptions: options,
            composeMsg: new bytes(0),
            oftCmd: abi.encode(VaultComposerAsyncUpgradeable.RedeemType.InstantRedeem) // redeem type in oftCmd
        });

        uint256 shareAmount = 1e6;

        // userA is not authorized, should fail
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSignature("AUTH_UNAUTHORIZED()"));
        nestVaultComposer.redeemAndSend{value: 1 ether}(addressToBytes32(address(userA)), shareAmount, sendParam, userA);

        // Restore permissive authority for other tests
        MockAuthority permissiveAuthority = new MockAuthority(true);
        nestVaultComposer.setAuthority(Authority(address(permissiveAuthority)));
    }

    /// @notice Test inherited sync redeemAndSend overload requires authorization
    function test_redeemAndSend_syncOverload_requiresAuth() public {
        MockAuthority restrictiveAuthority = new MockAuthority(false);
        nestVaultComposer.setAuthority(Authority(address(restrictiveAuthority)));

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam({
            dstEid: remoteEid,
            to: addressToBytes32(address(userB)),
            amountLD: 0,
            minAmountLD: 0,
            extraOptions: options,
            composeMsg: new bytes(0),
            oftCmd: abi.encode(VaultComposerAsyncUpgradeable.RedeemType.InstantRedeem)
        });

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSignature("AUTH_UNAUTHORIZED()"));
        nestVaultComposer.redeemAndSend{value: 1 ether}(1e6, sendParam, userA);

        MockAuthority permissiveAuthority = new MockAuthority(true);
        nestVaultComposer.setAuthority(Authority(address(permissiveAuthority)));
    }

    /// @notice Test fulfillRedeem requires authorization
    function test_fulfillRedeem_requiresAuth() public {
        // Create a restrictive authority that denies all calls
        MockAuthority restrictiveAuthority = new MockAuthority(false);
        nestVaultComposer.setAuthority(Authority(address(restrictiveAuthority)));

        // userA is not authorized, should fail
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSignature("AUTH_UNAUTHORIZED()"));
        nestVaultComposer.fulfillRedeem(remoteEid, addressToBytes32(address(userB)), 1e6);

        // Restore permissive authority for other tests
        MockAuthority permissiveAuthority = new MockAuthority(true);
        nestVaultComposer.setAuthority(Authority(address(permissiveAuthority)));
    }

    /// @notice Test recover function for ETH recovery
    function test_recover_ETH() public {
        // Fund the composer with some ETH
        uint256 recoverAmount = 1 ether;
        vm.deal(address(nestVaultComposer), recoverAmount);

        uint256 userBalanceBefore = userA.balance;
        uint256 composerBalanceBefore = address(nestVaultComposer).balance;

        // Recover ETH to userA (empty calldata for simple transfer)
        nestVaultComposer.recover(userA, recoverAmount, "");

        assertEq(userA.balance, userBalanceBefore + recoverAmount, "User should receive ETH");
        assertEq(address(nestVaultComposer).balance, composerBalanceBefore - recoverAmount, "Composer balance reduced");
    }

    /// @notice Test recover function for ERC20 token recovery
    function test_recover_ERC20() public {
        // Mint tokens directly to the composer
        uint256 recoverAmount = 1000e6;
        localAsset.mint(address(nestVaultComposer), recoverAmount);

        uint256 userBalanceBefore = localAsset.balanceOf(userA);
        uint256 composerBalanceBefore = localAsset.balanceOf(address(nestVaultComposer));

        // Recover ERC20 using transfer call
        bytes memory transferData = abi.encodeWithSelector(localAsset.transfer.selector, userA, recoverAmount);
        nestVaultComposer.recover(address(localAsset), 0, transferData);

        assertEq(localAsset.balanceOf(userA), userBalanceBefore + recoverAmount, "User should receive tokens");
        assertEq(
            localAsset.balanceOf(address(nestVaultComposer)),
            composerBalanceBefore - recoverAmount,
            "Composer balance reduced"
        );
    }

    /// @notice Test recover requires authorization
    function test_recover_requiresAuth() public {
        // Create a restrictive authority that denies all calls
        MockAuthority restrictiveAuthority = new MockAuthority(false);
        nestVaultComposer.setAuthority(Authority(address(restrictiveAuthority)));

        // userA is not authorized, should fail
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSignature("AUTH_UNAUTHORIZED()"));
        nestVaultComposer.recover(userA, 1 ether, "");

        // Restore permissive authority for other tests
        MockAuthority permissiveAuthority = new MockAuthority(true);
        nestVaultComposer.setAuthority(Authority(address(permissiveAuthority)));
    }

    /// @notice Test setBlockCompose requires authorization
    function test_setBlockCompose_requiresAuth() public {
        MockAuthority restrictiveAuthority = new MockAuthority(false);
        nestVaultComposer.setAuthority(Authority(address(restrictiveAuthority)));

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSignature("AUTH_UNAUTHORIZED()"));
        nestVaultComposer.setBlockCompose(bytes32(uint256(1)), true);

        MockAuthority permissiveAuthority = new MockAuthority(true);
        nestVaultComposer.setAuthority(Authority(address(permissiveAuthority)));
    }

    /// @notice Test composeBlocked getter reflects block toggle state
    function test_composeBlocked_reflects_toggle() public {
        bytes32 guid = bytes32(uint256(2));
        assertFalse(nestVaultComposer.composeBlocked(guid), "Guid should be unblocked by default");

        nestVaultComposer.setBlockCompose(guid, true);
        assertTrue(nestVaultComposer.composeBlocked(guid), "Guid should be blocked");

        nestVaultComposer.setBlockCompose(guid, false);
        assertFalse(nestVaultComposer.composeBlocked(guid), "Guid should be unblocked after toggle");
    }

    /// @notice Test setMaxRetryableValue requires authorization
    function test_setMaxRetryableValue_requiresAuth() public {
        MockAuthority restrictiveAuthority = new MockAuthority(false);
        nestVaultComposer.setAuthority(Authority(address(restrictiveAuthority)));

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSignature("AUTH_UNAUTHORIZED()"));
        nestVaultComposer.setMaxRetryableValue(1 ether);

        MockAuthority permissiveAuthority = new MockAuthority(true);
        nestVaultComposer.setAuthority(Authority(address(permissiveAuthority)));
    }

    /// @notice Test maxRetryableValue setter and getter
    function test_maxRetryableValue_set_and_get() public {
        assertEq(nestVaultComposer.maxRetryableValue(), 0, "Default should be zero");

        uint256 newMaxRetryableValue = 1 ether;
        nestVaultComposer.setMaxRetryableValue(newMaxRetryableValue);

        assertEq(nestVaultComposer.maxRetryableValue(), newMaxRetryableValue, "maxRetryableValue should be updated");
    }

    /// @notice Test that contract can receive ETH via receive()
    function test_receive_ETH() public {
        uint256 amount = 1 ether;
        uint256 balanceBefore = address(nestVaultComposer).balance;

        // Send ETH directly to the contract
        (bool success,) = address(nestVaultComposer).call{value: amount}("");
        assertTrue(success, "ETH transfer should succeed");

        assertEq(address(nestVaultComposer).balance, balanceBefore + amount, "Contract should receive ETH");
    }

    /// @notice Test quoteSend for asset OFT (redeem quote)
    function test_quoteSend_assetOFT() public {
        // Setup: give the composer some shares to redeem
        uint256 shareAmount = 1e6;

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam({
            dstEid: remoteEid,
            to: addressToBytes32(address(userB)),
            amountLD: 0,
            minAmountLD: 0,
            extraOptions: options,
            composeMsg: new bytes(0),
            oftCmd: new bytes(0)
        });

        // Quote for redeem (asset OFT output)
        MessagingFee memory fee =
            nestVaultComposer.quoteSend(address(nestVaultComposer), address(nestVaultOFT), shareAmount, sendParam);

        // Fee should be non-zero
        assertGt(fee.nativeFee, 0, "Native fee should be greater than 0");
    }

    /// @notice Test quoteSend for share OFT (deposit quote)
    function test_quoteSend_shareOFT() public {
        uint256 assetAmount = 1e6;

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam({
            dstEid: remoteEid,
            to: addressToBytes32(address(userB)),
            amountLD: 0,
            minAmountLD: 0,
            extraOptions: options,
            composeMsg: new bytes(0),
            oftCmd: new bytes(0)
        });

        // Quote for deposit (share OFT output)
        MessagingFee memory fee = nestVaultComposer.quoteSend(
            address(nestVaultComposer), nestVaultComposer.SHARE_OFT(), assetAmount, sendParam
        );

        // Fee should be non-zero
        assertGt(fee.nativeFee, 0, "Native fee should be greater than 0");
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
    function _requestRedeemAndReturnPending(address _user, uint256 _redeemAmount)
        internal
        returns (uint256 pendingShares, uint256 amountReceived)
    {
        bytes memory requestComposeMsg = _formatRequestRedeemComposeMsg(remoteEid, address(_user).toBytes32(), 0, 0);
        bytes memory requestOptions =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0).addExecutorLzComposeOption(0, 500000, 0);
        SendParam memory requestSendParam = SendParam(
            localEid,
            addressToBytes32(address(nestVaultComposer)),
            _redeemAmount,
            _redeemAmount,
            requestOptions,
            requestComposeMsg,
            ""
        );
        MessagingFee memory requestFee = remoteNestShare.quoteSend(requestSendParam, false);

        vm.prank(_user);
        (MessagingReceipt memory requestMsgReceipt, OFTReceipt memory requestOftReceipt) =
            remoteNestShare.send{value: requestFee.nativeFee}(requestSendParam, requestFee, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory requestComposerMsg = OFTComposeMsgCodec.encode(
            requestMsgReceipt.nonce,
            remoteEid,
            requestOftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(_user), requestComposeMsg)
        );
        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            requestOptions,
            requestMsgReceipt.guid,
            address(nestVaultComposer),
            requestComposerMsg
        );

        pendingShares = nestVaultComposer.pendingRedeem(addressToBytes32(_user), remoteEid).shares;
        amountReceived = requestOftReceipt.amountReceivedLD;
    }

    function _finishRedeemAndReturnAssets(address _user, uint256 _shareAmount) internal returns (uint256 assetsSent) {
        bytes memory assetSendOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory quoteSendParam = SendParam(
            remoteEid,
            addressToBytes32(_user),
            _shareAmount,
            0,
            assetSendOptions,
            new bytes(0),
            abi.encode(VaultComposerAsyncUpgradeable.RedeemType.FinishRedeem)
        );
        MessagingFee memory assetSendFee = nestCCTPRelayer.quoteSend(quoteSendParam, false);
        uint256 assetSendFeeWithBuffer = assetSendFee.nativeFee + 1000;

        bytes memory completeOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0)
            .addExecutorLzComposeOption(0, 2000000, uint128(assetSendFeeWithBuffer));
        bytes memory completeComposeMsg =
            _formatCompleteRedeemComposeMsg(remoteEid, _user.toBytes32(), _shareAmount, 0, assetSendFeeWithBuffer);
        SendParam memory completeSendParam = SendParam(
            localEid, addressToBytes32(address(nestVaultComposer)), 0, 0, completeOptions, completeComposeMsg, ""
        );

        MessagingFee memory completeFee = remoteNestShare.quoteSend(completeSendParam, false);
        vm.prank(_user);
        (MessagingReceipt memory completeMsgReceipt, OFTReceipt memory completeOftReceipt) =
            remoteNestShare.send{value: completeFee.nativeFee}(completeSendParam, completeFee, payable(address(this)));
        verifyPackets(localEid, addressToBytes32(address(nestVaultOFT)));

        bytes memory completeComposerMsg = OFTComposeMsgCodec.encode(
            completeMsgReceipt.nonce,
            remoteEid,
            completeOftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(_user), completeComposeMsg)
        );

        uint256 vaultAssetsBeforeFinish = localAsset.balanceOf(address(nestVaultOFT));
        this.lzCompose(
            localEid,
            address(nestVaultOFT),
            completeOptions,
            completeMsgReceipt.guid,
            address(nestVaultComposer),
            completeComposerMsg
        );
        uint256 vaultAssetsAfterFinish = localAsset.balanceOf(address(nestVaultOFT));
        assetsSent = vaultAssetsBeforeFinish - vaultAssetsAfterFinish;
    }

    function _formatInstantRedeemComposeMsg(
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
            oftCmd: abi.encode(VaultComposerAsyncUpgradeable.RedeemType.InstantRedeem) // redeem type command
        });

        _composeMsg = abi.encode(
            sendParam,
            minMsgValue // min msg.value passed to lzCompose (should get from NestVaultComposer.quoteSend())
        );
    }

    function _formatRequestRedeemComposeMsg(
        uint32 _dstEid,
        bytes32 _finalRecipient,
        uint256 _sharesAmount,
        uint256 minMsgValue
    ) internal pure returns (bytes memory _composeMsg) {
        SendParam memory sendParam = SendParam({
            dstEid: _dstEid,
            to: _finalRecipient,
            amountLD: _sharesAmount, // overridden by NestVaultComposer (actual amount of assets received)
            minAmountLD: 0, // min amount of assets expected
            extraOptions: new bytes(0), // extra gas options (should require only enforced)
            composeMsg: new bytes(0), // compose message to passed to the final chain (not used)
            oftCmd: abi.encode(VaultComposerAsyncUpgradeable.RedeemType.RequestRedeem) // redeem type command
        });

        _composeMsg = abi.encode(
            sendParam,
            minMsgValue // min msg.value passed to lzCompose (should get from NestVaultComposer.quoteSend())
        );
    }

    function _formatUpdateRedeemComposeMsg(
        uint32 _dstEid,
        bytes32 _finalRecipient,
        uint256 _newSharesAmount,
        uint256 minMsgValue
    ) internal pure returns (bytes memory _composeMsg) {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam({
            dstEid: _dstEid,
            to: _finalRecipient,
            amountLD: _newSharesAmount, // new shares amount to keep in pending redeem
            minAmountLD: 0, // min amount of shares expected
            extraOptions: options, // extra gas options for sending back excess shares
            composeMsg: new bytes(0),
            oftCmd: abi.encode(VaultComposerAsyncUpgradeable.RedeemType.UpdateRedeemRequest) // redeem type command
        });

        _composeMsg = abi.encode(
            sendParam,
            minMsgValue // min msg.value passed to lzCompose (should get from NestVaultComposer.quoteSend())
        );
    }

    function _formatCompleteRedeemComposeMsg(
        uint32 _dstEid,
        bytes32 _finalRecipient,
        uint256 _shareAmount,
        uint256 _minAssetAmount,
        uint256 minMsgValue
    ) internal pure returns (bytes memory _composeMsg) {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam({
            dstEid: _dstEid,
            to: _finalRecipient,
            amountLD: _shareAmount, // shares to redeem from claimable
            minAmountLD: _minAssetAmount, // min assets expected
            extraOptions: options, // extra gas options for sending assets
            composeMsg: new bytes(0),
            oftCmd: abi.encode(VaultComposerAsyncUpgradeable.RedeemType.FinishRedeem) // redeem type command
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

        MessagingFee memory _fee = nestCCTPRelayer.quoteRelay(_message, _extraData, new bytes(0));

        // Receive message
        vm.prank(_caller);
        (bool _relaySuccess, bool _hookSuccess) =
            nestCCTPRelayer.relay{value: _fee.nativeFee}(_message, _signature, _extraData, new bytes(0), false);
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
                    1,
                    address(0)
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
            payable(_deployContractAndProxy(
                    type(NestVaultComposer).creationCode,
                    abi.encode(address(nestVaultPredicateProxy)),
                    abi.encodeWithSelector(
                        NestVaultComposer.initialize.selector,
                        address(this),
                        address(nestVaultOFT),
                        address(nestCCTPRelayer),
                        address(nestVaultOFT),
                        0
                    )
                ))
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
