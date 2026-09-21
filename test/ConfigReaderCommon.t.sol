// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {CommonContracts, ConfigReader} from "script/lib/ConfigReader.sol";

/// @dev Octane V12: common config shape is detected by `.common` key existence, not predicateProxy value.
contract ConfigReaderCommonTest is Test {
    uint256 internal constant FLAT_CHAIN_ID = 999_999_999;
    uint256 internal constant NESTED_CHAIN_ID = 999_999_998;

    function _commonPath(uint256 chainId) internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/script/deployment-config/common/", vm.toString(chainId), ".json");
    }

    function test_flatPredicatelessCommonConfigParsesFlat() public {
        string memory path = _commonPath(FLAT_CHAIN_ID);
        vm.writeFile(
            path,
            '{"chainId":999999999,"operatorRegistry":"0x0000000000000000000000000000000000000001","seizer":"0x0000000000000000000000000000000000000002"}'
        );
        CommonContracts memory c = ConfigReader.readCommonProxyConfig(FLAT_CHAIN_ID);
        vm.removeFile(path);

        assertEq(c.predicateProxy, address(0), "predicateProxy");
        assertEq(c.operatorRegistry, address(1), "operatorRegistry");
        assertEq(c.seizer, address(2), "seizer");
    }

    function test_nestedCommonBlockParsesNested() public {
        string memory path = _commonPath(NESTED_CHAIN_ID);
        vm.writeFile(
            path,
            '{"chainId":999999998,"common":{"operatorRegistry":"0x0000000000000000000000000000000000000003","seizer":"0x0000000000000000000000000000000000000004"}}'
        );
        CommonContracts memory c = ConfigReader.readCommonProxyConfig(NESTED_CHAIN_ID);
        vm.removeFile(path);

        assertEq(c.predicateProxy, address(0), "predicateProxy");
        assertEq(c.operatorRegistry, address(3), "operatorRegistry");
        assertEq(c.seizer, address(4), "seizer");
    }

    function test_allCheckedInCommonConfigsParseFlat() public view {
        uint256[8] memory chainIds = [uint256(1), 56, 480, 8453, 9745, 42_161, 43_114, 98_866];
        for (uint256 i = 0; i < chainIds.length; i++) {
            CommonContracts memory c = ConfigReader.readCommonProxyConfig(chainIds[i]);
            assertTrue(c.predicateProxy != address(0), "predicateProxy zero");
            assertTrue(c.operatorRegistry != address(0), "operatorRegistry zero");
        }
    }
}
