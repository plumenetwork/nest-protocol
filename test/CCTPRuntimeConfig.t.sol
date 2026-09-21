// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployAndSetup} from "script/deploy/DeployAndSetup.s.sol";
import {ConfigReader, CCTPConfig} from "script/lib/ConfigReader.sol";
import {NestCCTPRelayer} from "contracts/integrations/cctp/NestCCTPRelayer.sol";

/// @dev Fee-switch messenger: exposes getMinFeeAmount like Plume's TokenMessengerV2.
contract MockFeeSwitchMessenger {
    function getMinFeeAmount(uint256) external pure returns (uint256) {
        return 0;
    }
}

/// @dev Messenger without the fee switch (Ethereum/Avalanche/World/Base impl): no getMinFeeAmount.
contract MockLegacyMessenger {}

contract MockCCTPRuntimeRelayer {
    address public immutable TOKEN_MESSENGER;
    uint256 private maxFeeBasisPoints;
    uint32 private finalityThreshold;

    uint256 public maxFeeSetCount;
    uint256 public finalitySetCount;

    constructor(address messenger, uint256 initialMaxFeeBasisPoints, uint32 initialFinalityThreshold) {
        TOKEN_MESSENGER = messenger;
        maxFeeBasisPoints = initialMaxFeeBasisPoints;
        finalityThreshold = initialFinalityThreshold;
    }

    function getMaxFeeBasisPoints() external view returns (uint256) {
        return maxFeeBasisPoints;
    }

    function getFinalityThreshold() external view returns (uint32) {
        return finalityThreshold;
    }

    function setMaxFeeBasisPoints(uint256 newMaxFeeBasisPoints) external {
        maxFeeBasisPoints = newMaxFeeBasisPoints;
        maxFeeSetCount++;
    }

    function setFinalityThreshold(uint32 newFinalityThreshold) external {
        finalityThreshold = newFinalityThreshold;
        finalitySetCount++;
    }
}

/// @dev Relayer impl carrying the getMinFeeAmount fallback: settable fee cap even on a legacy messenger.
contract MockFallbackRuntimeRelayer is MockCCTPRuntimeRelayer {
    constructor(address messenger, uint256 initialMaxFeeBasisPoints, uint32 initialFinalityThreshold)
        MockCCTPRuntimeRelayer(messenger, initialMaxFeeBasisPoints, initialFinalityThreshold)
    {}

    function getMinFeeAmount(uint256) external pure returns (uint256) {
        return 0;
    }
}

contract CCTPRuntimeConfigHarness is DeployAndSetup {
    function seedRuntimeConfig(uint256 chainId, address relayer) external {
        vaultConfig.deployChainId = chainId;
        vaultConfig.common.cctpRelayer = relayer;
    }

    function wireRuntimeConfig() external {
        _wireRelayerRuntimeConfig(NestCCTPRelayer(payable(vaultConfig.common.cctpRelayer)));
    }

    function readCctp(uint256 chainId) external view returns (CCTPConfig memory) {
        return ConfigReader.readCCTPConfig(chainId);
    }
}

/// @dev Each test writes its own synthetic config/cctp/<id>.json (tests run in parallel) and removes it.
contract CCTPRuntimeConfigTest is Test {
    string private constant POLICY = ',"maxFeeBasisPoints":2,"finalityThreshold":1000';

    CCTPRuntimeConfigHarness private harness;

    function setUp() public {
        harness = new CCTPRuntimeConfigHarness();
    }

    function test_supportedConfigsParseWithoutRuntimeKeys() public view {
        uint256[5] memory supportedChainIds = [uint256(1), 43114, 480, 8453, 98866];
        for (uint256 i = 0; i < supportedChainIds.length; i++) {
            CCTPConfig memory config = ConfigReader.readCCTPConfig(supportedChainIds[i]);
            assertEq(config.maxFeeBasisPoints, 0, "committed configs carry no fee policy");
            assertEq(config.finalityThreshold, 0, "committed configs carry no finality policy");
        }
    }

    function test_wireRuntimeConfigConvergesAndThenSkips() public {
        uint256 chainId = 999_999_987;
        string memory path = _write(chainId, POLICY);
        MockCCTPRuntimeRelayer relayer = new MockCCTPRuntimeRelayer(address(new MockFeeSwitchMessenger()), 17, 2000);
        harness.seedRuntimeConfig(chainId, address(relayer));

        harness.wireRuntimeConfig();
        assertEq(relayer.getMaxFeeBasisPoints(), 2);
        assertEq(relayer.getFinalityThreshold(), 1000);
        assertEq(relayer.maxFeeSetCount(), 1);
        assertEq(relayer.finalitySetCount(), 1);

        harness.wireRuntimeConfig();
        assertEq(relayer.maxFeeSetCount(), 1, "fee policy should already be converged");
        assertEq(relayer.finalitySetCount(), 1, "finality policy should already be converged");
        vm.removeFile(path);
    }

    function test_wireRuntimeConfigSkipsFeeCapWithoutFeeSwitch() public {
        uint256 chainId = 999_999_986;
        string memory path = _write(chainId, POLICY);
        MockCCTPRuntimeRelayer relayer = new MockCCTPRuntimeRelayer(address(new MockLegacyMessenger()), 0, 0);
        harness.seedRuntimeConfig(chainId, address(relayer));

        harness.wireRuntimeConfig();
        assertEq(relayer.maxFeeSetCount(), 0, "fee cap must not be set without getMinFeeAmount");
        assertEq(relayer.finalitySetCount(), 1, "finality converges independently");
        vm.removeFile(path);
    }

    function test_wireRuntimeConfigSetsFeeCapWithFallbackRelayer() public {
        uint256 chainId = 999_999_983;
        string memory path = _write(chainId, POLICY);
        MockFallbackRuntimeRelayer relayer = new MockFallbackRuntimeRelayer(address(new MockLegacyMessenger()), 0, 0);
        harness.seedRuntimeConfig(chainId, address(relayer));

        harness.wireRuntimeConfig();
        assertEq(relayer.getMaxFeeBasisPoints(), 2, "fallback relayer converges on a legacy messenger");
        assertEq(relayer.maxFeeSetCount(), 1);
        assertEq(relayer.finalitySetCount(), 1);
        vm.removeFile(path);
    }

    function test_wireRuntimeConfigLeavesLiveValuesWhenUnconfigured() public {
        uint256 chainId = 999_999_985;
        string memory path = _write(chainId, "");
        MockCCTPRuntimeRelayer relayer = new MockCCTPRuntimeRelayer(address(new MockFeeSwitchMessenger()), 0, 0);
        harness.seedRuntimeConfig(chainId, address(relayer));

        harness.wireRuntimeConfig();
        assertEq(relayer.maxFeeSetCount(), 0, "no key: warn only");
        assertEq(relayer.finalitySetCount(), 0, "no key: warn only");
        vm.removeFile(path);
    }

    function test_wireRuntimeConfigRevertsWithoutChainConfig() public {
        MockCCTPRuntimeRelayer relayer = new MockCCTPRuntimeRelayer(address(new MockFeeSwitchMessenger()), 2, 2000);
        harness.seedRuntimeConfig(999_999_988, address(relayer));

        vm.expectRevert("DeployAndSetup: CCTP config required for active relayer");
        harness.wireRuntimeConfig();
    }

    function test_parserRejectsOutOfRangePolicy() public {
        uint256 chainId = 999_999_984;
        string memory path = _write(chainId, ',"maxFeeBasisPoints":1001,"finalityThreshold":1000');
        vm.expectRevert("ConfigReader: CCTP maxFeeBasisPoints must be 0..1000");
        harness.readCctp(chainId);

        _write(chainId, ',"maxFeeBasisPoints":2,"finalityThreshold":1500');
        vm.expectRevert("ConfigReader: CCTP finalityThreshold must be 1000 or 2000");
        harness.readCctp(chainId);
        vm.removeFile(path);
    }

    function _write(uint256 chainId, string memory extra) internal returns (string memory path) {
        path = string.concat(vm.projectRoot(), "/config/cctp/", vm.toString(chainId), ".json");
        vm.writeFile(
            path,
            string.concat(
                '{"messageTransmitter":"0x0000000000000000000000000000000000000001",',
                '"tokenMessenger":"0x0000000000000000000000000000000000000002",',
                '"tokenMinter":"0x0000000000000000000000000000000000000003","domain":99',
                extra,
                "}"
            )
        );
    }
}
