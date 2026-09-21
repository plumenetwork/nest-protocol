// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {NestCCTPRelayer} from "contracts/integrations/cctp/NestCCTPRelayer.sol";
import {Errors} from "contracts/integrations/cctp/types/Errors.sol";
import {MockMintBurnToken} from "test/mock/cctp/MockMintAndBurnToken.sol";

/// @dev Circle's pre-fee-switch build, still live on some networks: unknown selector, empty revert.
contract LegacyMessengerStub {}

/// @dev Circle's fee-switch build: minFee expressed out of MIN_FEE_MULTIPLIER = 1e7.
contract FeeSwitchMessengerStub {
    uint256 public immutable MIN_FEE;

    constructor(uint256 _minFee) {
        MIN_FEE = _minFee;
    }

    function getMinFeeAmount(uint256 amount) external view returns (uint256) {
        if (MIN_FEE == 0) return 0;
        require(amount > 1, "Amount too low");

        uint256 fee = (amount * MIN_FEE) / 10_000_000;

        return fee == 0 ? 1 : fee;
    }
}

contract CCTPFeeSwitchFallbackTest is Test {
    MockMintBurnToken private usdc;

    function setUp() public {
        usdc = new MockMintBurnToken("USD Coin", "USDC", 6);
    }

    function test_legacyMessenger_minFeeReadsAsZero() public {
        NestCCTPRelayer relayer = _relayer(address(new LegacyMessengerStub()));

        assertEq(relayer.getMinFeeAmount(1e6), 0, "absent fee switch means no minimum");
    }

    function test_legacyMessenger_feeCapIsSettableAndQuotes() public {
        NestCCTPRelayer relayer = _relayer(address(new LegacyMessengerStub()));

        relayer.setMaxFeeBasisPoints(2);

        assertEq(relayer.getMaxFeeBasisPoints(), 2);
        assertEq(relayer.getMaxFeeAmount(1e6, true), 200, "2 bps of 1 USDC");
    }

    function test_feeSwitchMessenger_minFeeStillFloorsTheCap() public {
        // minFee = 1e5 out of 1e7 => 1% => 100 bps
        NestCCTPRelayer relayer = _relayer(address(new FeeSwitchMessengerStub(1e5)));

        assertEq(relayer.getMinFeeAmount(1e6), 10_000, "1% of 1 USDC");

        vm.expectRevert(Errors.InvalidFee.selector);
        relayer.setMaxFeeBasisPoints(2);

        relayer.setMaxFeeBasisPoints(100);
        assertEq(relayer.getMaxFeeBasisPoints(), 100);
    }

    function test_feeSwitchMessenger_quoteRevertsBelowMinimum() public {
        NestCCTPRelayer relayer = _relayer(address(new FeeSwitchMessengerStub(1e5)));
        relayer.setMaxFeeBasisPoints(100);

        // 100 bps of 100 units rounds up to the messenger's 1-unit floor
        assertEq(relayer.getMaxFeeAmount(100, true), 1);

        vm.mockCall(
            address(relayer.TOKEN_MESSENGER()),
            abi.encodeWithSignature("getMinFeeAmount(uint256)", uint256(100)),
            abi.encode(uint256(2))
        );
        vm.expectRevert(Errors.InvalidFee.selector);
        relayer.getMaxFeeAmount(100, true);
    }

    function _relayer(address messenger) private returns (NestCCTPRelayer) {
        NestCCTPRelayer implementation = new NestCCTPRelayer(address(0xBEEF), messenger, address(0xE12D), address(usdc));
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(implementation), abi.encodeCall(NestCCTPRelayer.initialize, (address(this))));

        return NestCCTPRelayer(payable(address(proxy)));
    }
}
