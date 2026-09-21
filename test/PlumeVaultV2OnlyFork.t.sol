// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployAndSetup} from "script/deploy/DeployAndSetup.s.sol";
import {ConfigReader, CommonContracts, VaultDeployConfig} from "script/lib/ConfigReader.sol";
import {Auth} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {NestVaultComposer} from "contracts/integrations/ovault/NestVaultComposer.sol";

/// @dev Opt-in Plume fork: a fresh vault opts into the live shared V2 stack on a chain that still runs V1.
///      Requires the configured CREATE3 deployer's PRIVATE_KEY and PLUME_RPC_URL.
contract PlumeVaultV2OnlyForkTest is Test {
    string constant SYMBOL = "nV2ONLYFORK";
    string constant VAULT_PATH = "script/deployment-config/vaults/nV2ONLYFORK.json";
    string constant OUTPUT_DIR = "script/output/nV2ONLYFORK";
    string constant COMMON_PATH = "script/deployment-config/common/98866.json";
    address constant V1_PROXY = 0xfC0c4222B3A0c9B060C0B959DEc62442036b9035;
    address constant SHARED_PROXY = 0xB65B65CfF0CA1f3cc12fe58a13110E43DfA999F1;
    bytes4 constant DEPOSIT = bytes4(keccak256("deposit(uint256,address)"));
    bytes4 constant MINT = bytes4(keccak256("mint(uint256,address)"));

    function test_plumeVaultOptsIntoSharedV2() public {
        if (!vm.envOr("RUN_PLUME_V2ONLY_FORK", false)) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(vm.envString("PLUME_RPC_URL"));
        vm.setEnv("CHAIN_ID", "98866");
        vm.setEnv("STEPS", "deploy,operator,composer,authority,l0,share");
        vm.deal(vm.addr(vm.envUint("PRIVATE_KEY")), 1000 ether);
        string memory originalCommon = vm.readFile(COMMON_PATH);
        vm.writeFile(VAULT_PATH, _vaultConfig());
        // Restore canonical inputs even if a script or assertion fails.
        try this.scenario() {
            _cleanup(originalCommon);
        } catch (bytes memory reason) {
            _cleanup(originalCommon);
            assembly ("memory-safe") {
                revert(add(reason, 32), mload(reason))
            }
        }
    }

    function scenario() external {
        require(msg.sender == address(this));
        CommonContracts memory common = ConfigReader.readCommonProxyConfig(98866);
        assertEq(common.predicateProxy, V1_PROXY);
        assertEq(common.complianceProxy, address(0)); // not recorded yet; the vault config overrides it

        new DeployAndSetup().run(SYMBOL);
        _assertVault();
        // A rerun is a no-op and still passes readiness with the composer bound to the shared proxy.
        new DeployAndSetup().run(SYMBOL);
        _assertVault();

        // The chain's V1 proxy and the canonical common config are untouched.
        assertEq(address(Auth(V1_PROXY).authority()), common.commonRolesAuthority);
        CommonContracts memory recorded = ConfigReader.readCommonProxyConfig(98866);
        assertEq(recorded.predicateProxy, V1_PROXY);
        assertEq(recorded.complianceProxy, address(0));
    }

    function _assertVault() internal view {
        VaultDeployConfig memory deployed = ConfigReader.readOutputConfig(98866, SYMBOL);
        assertTrue(deployed.compliance.v2Only);
        // readOutputConfig re-resolves `common` from the canonical chain file, so check the raw output.
        string memory raw = vm.readFile(string.concat(OUTPUT_DIR, "/98866-", SYMBOL, ".json"));
        assertEq(vm.parseJsonAddress(raw, ".common.complianceProxy"), SHARED_PROXY);
        assertEq(vm.parseJsonAddress(raw, ".common.predicateProxy"), V1_PROXY);
        address vault = deployed.vaults[0].addr;
        assertGt(vault.code.length, 0);
        RolesAuthority auth = RolesAuthority(deployed.contracts.rolesAuthority);
        assertTrue(auth.canCall(SHARED_PROXY, vault, DEPOSIT));
        assertTrue(auth.canCall(SHARED_PROXY, vault, MINT));
        assertFalse(auth.canCall(V1_PROXY, vault, DEPOSIT));
        assertFalse(auth.doesUserHaveRole(V1_PROXY, 7));
        assertFalse(auth.isCapabilityPublic(vault, DEPOSIT));
        assertFalse(auth.canCall(address(0x123), vault, DEPOSIT));
        string[4] memory redemptions = [
            "requestRedeem(uint256,address,address)",
            "instantRedeem(uint256,address,address)",
            "requestRedeemWithPermit2(uint256,address,address,uint256,uint256,bytes)",
            "instantRedeemWithPermit2(uint256,address,address,uint256,uint256,bytes)"
        ];
        for (uint256 i; i < redemptions.length; ++i) {
            bytes4 selector = bytes4(keccak256(bytes(redemptions[i])));
            assertTrue(auth.isCapabilityPublic(vault, selector), redemptions[i]);
        }
        address composer = deployed.vaults[0].composer;
        assertGt(composer.code.length, 0);
        assertEq(address(NestVaultComposer(payable(composer)).COMPLIANCE_PROXY()), SHARED_PROXY);
    }

    function _cleanup(string memory originalCommon) internal {
        vm.writeFile(COMMON_PATH, originalCommon);
        if (vm.exists(VAULT_PATH)) vm.removeFile(VAULT_PATH);
        if (vm.exists(OUTPUT_DIR)) vm.removeDir(OUTPUT_DIR, true);
        string[3] memory suffixes = ["", "-Schedule", "-Execute"];
        for (uint256 i; i < suffixes.length; ++i) {
            string memory path =
                string.concat("script/output/msig/98866-", SYMBOL, "-DeployAndSetup", suffixes[i], ".json");
            if (vm.exists(path)) vm.removeFile(path);
        }
    }

    /// @dev Single-chain NestVault cloned from nAXI with fresh addresses; V1 policy empty, V2-only set.
    function _vaultConfig() internal pure returns (string memory) {
        return string.concat(
            '{"symbol":"nV2ONLYFORK","owner":"0x8fAACdC65de5D78975dF4f9DC4B6548979cEb23A",',
            '"name":"Nest V2-only fork check","baseAssetSymbol":"USDC","vaultType":"NestVault",',
            '"accountantType":"NestHubAccountant",',
            '"contracts":{"share":"0x0000000000000000000000000000000000000000",',
            '"accountant":"0x0000000000000000000000000000000000000000",',
            '"rolesAuthority":"0x0000000000000000000000000000000000000000",',
            '"vaults":[{"assetSymbol":"USDC","chains":[98866],"address":"0x0000000000000000000000000000000000000000",',
            '"isPegged":true,"rateProvider":"0x0000000000000000000000000000000000000000",',
            '"composer":"0x0000000000000000000000000000000000000000"}]},',
            '"commonOverrides":{"complianceProxy":"0xB65B65CfF0CA1f3cc12fe58a13110E43DfA999F1",',
            '"nestAdapter":"0x000000000000000000000000000000000000dEaD",',
            '"nestBundler":"0x000000000000000000000000000000000000dEaD",',
            '"nestUnlooper":"0x000000000000000000000000000000000000dEaD"},',
            '"accountantParams":{"totalSharesLastUpdate":0,"payoutAddress":"0xa08A0Dc480BD60d1d56C8Eec6c722125eAfEa982",',
            '"startingExchangeRate":1000000,"allowedExchangeRateChangeUpper":1000500,',
            '"allowedExchangeRateChangeLower":999500,"minimumUpdateDelayInSeconds":3600,"managementFee":0,"performanceFee":0},',
            '"vaultFees":{"deposit":{"rate":0,"flat":0},"redemption":{"rate":0,"flat":0},"instantRedemption":{"rate":1500,"flat":0}},',
            '"vaultParams":{"minRate":1},',
            '"compliance":{"v1":{"policyID":""},"v2":{"verificationHash":""},"v2Only":true},',
            '"composerParams":{"maxRetryableValue":10000000000000000000},',
            '"roles":{"OWNER_ROLE":["0xa08A0Dc480BD60d1d56C8Eec6c722125eAfEa982"],',
            '"PAUSER_ROLE":["0xa08A0Dc480BD60d1d56C8Eec6c722125eAfEa982"],',
            '"KEEPER_ROLE":["0x450545F4cC7425DDe582091a7fe9E63471Af1045"],',
            '"UPDATE_EXCHANGE_RATE_ROLE":["0x450545F4cC7425DDe582091a7fe9E63471Af1045"],',
            '"MANAGER_ROLE":["0x4371e7eC29BbB60872E15C5123C3CaC948967Eb7"],',
            '"CAN_SOLVE_ROLE":["0x450545F4cC7425DDe582091a7fe9E63471Af1045"]},',
            '"peers":[98866,1]}'
        );
    }
}
