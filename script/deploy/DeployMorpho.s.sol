// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {BaseConfigScript} from "script/lib/BaseConfigScript.sol";
import {ConfigReader, MorphoChainConfig} from "script/lib/ConfigReader.sol";
import {ICreateX} from "createx/ICreateX.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {NestAdapter} from "contracts/integrations/morpho/NestAdapter.sol";
import {NestBundler} from "contracts/integrations/morpho/NestBundler.sol";
import {NestUnlooper} from "contracts/integrations/morpho/NestUnlooper.sol";
import {console} from "forge-std/console.sol";

/// @title  DeployMorpho
/// @notice Deploys chain-wide common Morpho/Bundler3 infra: NestAdapter, NestBundler, NestUnlooper.
/// @dev    Direct broadcast only — runMsig is not supported because CREATE3 salts in BaseConfigScript
///         embed the deployer EOA and `directOrMsig(true)` does not serialize CreateX deploys into the
///         Safe batch.  Ownership of NestUnlooper is migrated post-deploy via TransferOwnership.s.sol.
///
///         Chain-level deployment — does not read any vault config; only `CHAIN_ID` is required.
///
///         Usage:
///           CHAIN_ID=98866 forge script script/deploy/DeployMorpho.s.sol \
///             --sig "runDirect()" --rpc-url $RPC --broadcast --ffi
contract DeployMorpho is BaseConfigScript {
    bool private parallelMigration;
    address private migrationOwner;

    /// @notice Deploy the V2 periphery alongside the active stack, without changing active config.
    function deployParallel(address complianceProxy, address governance) external returns (address, address, address) {
        setUp();
        parallelMigration = true;
        migrationOwner = governance;
        require(block.chainid == vaultConfig.deployChainId, "DeployMorpho: RPC chain mismatch");
        require(complianceProxy.code.length > 0, "DeployMorpho: compliance proxy missing");
        require(
            Auth(vaultConfig.common.commonRolesAuthority).owner() == governance, "DeployMorpho: governance mismatch"
        );
        vaultConfig.common.complianceProxy = complianceProxy;
        vaultConfig.common.nestAdapter = computeCreate3AddressCommon("NestAdapter-v3");
        vaultConfig.common.nestBundler = computeCreate3AddressCommon("NestBundler-v4");
        vaultConfig.common.nestUnlooper = computeCreate3AddressCommon("NestUnlooper-v5");

        MorphoChainConfig memory mc = ConfigReader.readMorphoConfig(vaultConfig.deployChainId);
        require(
            mc.morpho.code.length > 0 && mc.bundler3.code.length > 0 && mc.wrappedNative.code.length > 0,
            "DeployMorpho: core dependencies missing"
        );
        // Reference deployments run outside broadcast to compare runtime including immutables.
        _assertParallelCode(
            vaultConfig.common.nestAdapter, address(new NestAdapter(mc.bundler3, mc.morpho, mc.wrappedNative)).code
        );
        _assertParallelCode(
            vaultConfig.common.nestBundler,
            address(
                new NestBundler(
                    mc.morpho,
                    mc.bundler3,
                    vaultConfig.common.nestAdapter,
                    complianceProxy,
                    mc.legacyPredicateProxy,
                    mc.atomicSolver,
                    mc.atomicQueue
                )
            )
            .code
        );
        _assertParallelCode(
            vaultConfig.common.nestUnlooper,
            address(
                new NestUnlooper(
                    governance,
                    Authority(vaultConfig.common.commonRolesAuthority),
                    mc.morpho,
                    mc.bundler3,
                    vaultConfig.common.nestAdapter,
                    mc.atomicSolver,
                    mc.atomicQueue
                )
            )
            .code
        );
        if (vaultConfig.common.nestUnlooper.code.length > 0) {
            require(
                NestUnlooper(vaultConfig.common.nestUnlooper).owner() == governance
                    && address(NestUnlooper(vaultConfig.common.nestUnlooper).authority())
                        == vaultConfig.common.commonRolesAuthority,
                "DeployMorpho: unlooper governance mismatch"
            );
        }
        _deploy();
        return (vaultConfig.common.nestAdapter, vaultConfig.common.nestBundler, vaultConfig.common.nestUnlooper);
    }

    function _assertParallelCode(address target, bytes memory expected) private view {
        require(
            target.code.length == 0 || keccak256(target.code) == keccak256(expected),
            "DeployMorpho: occupied V2 salt has different code or dependencies"
        );
    }

    function setUp() public {
        uint256 chainId = vm.envUint("CHAIN_ID");
        // Load only the chain-level config required for common deployments.
        // `vaultConfig` is otherwise unused — this script never reads any vault file.
        commonConfig = ConfigReader.readCommonConfig(chainId);
        vaultConfig.deployChainId = chainId;
        vaultConfig.common = ConfigReader.readCommonProxyConfig(chainId);
        CREATEX = ICreateX(commonConfig.createx);
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        snapshotCommon();
    }

    function runDirect() external {
        _deploy();
        writeCommonConfigIfChanged();
    }

    function _deploy() internal {
        MorphoChainConfig memory mc = ConfigReader.readMorphoConfig(vaultConfig.deployChainId);
        require(mc.morpho != address(0) && mc.bundler3 != address(0), "DeployMorpho: morpho config missing");

        vm.startBroadcast(deployerPrivateKey);

        // 1. NestAdapter — chain-wide adapter wired to the canonical Morpho/Bundler3.
        if (needsDeploy(vaultConfig.common.nestAdapter)) {
            // v3: compliance-gated deposit/mint entrypoints (ComplianceProxy + opaque proof bytes
            // replace the V1 predicate proxy). Bump forces a fresh CREATE3 address.
            bytes32 salt = generateCreate3SaltCommon("NestAdapter-v3");
            vaultConfig.common.nestAdapter = CREATEX.deployCreate3(
                salt,
                abi.encodePacked(type(NestAdapter).creationCode, abi.encode(mc.bundler3, mc.morpho, mc.wrappedNative))
            );
            _logDeploy("NestAdapter", vaultConfig.common.nestAdapter);
        } else {
            _logExists("NestAdapter", vaultConfig.common.nestAdapter);
        }

        // 2. NestBundler — user-facing bundle helper bound to the adapter and compliance/predicate proxies.
        if (needsDeploy(vaultConfig.common.nestBundler)) {
            // The V1 predicateProxy no longer works here: modern deposit routes call
            // ComplianceProxy.genericUserCheck, which the V1 proxy does not expose.
            require(
                vaultConfig.common.complianceProxy != address(0),
                "DeployMorpho: complianceProxy required for NestBundler"
            );
            // v4: compliance-gated deposit routes (bytes complianceData API, wired to the V2
            // ComplianceProxy). Bump forces a fresh CREATE3 address.
            bytes32 salt = generateCreate3SaltCommon("NestBundler-v4");
            vaultConfig.common.nestBundler = CREATEX.deployCreate3(
                salt,
                abi.encodePacked(
                    type(NestBundler).creationCode,
                    abi.encode(
                        mc.morpho,
                        mc.bundler3,
                        vaultConfig.common.nestAdapter,
                        vaultConfig.common.complianceProxy,
                        mc.legacyPredicateProxy,
                        mc.atomicSolver,
                        mc.atomicQueue
                    )
                )
            );
            _logDeploy("NestBundler", vaultConfig.common.nestBundler);
        } else {
            _logExists("NestBundler", vaultConfig.common.nestBundler);
        }

        // 3. NestUnlooper — keeper-only async unloop executor; authority is the common RolesAuthority.
        if (needsDeploy(vaultConfig.common.nestUnlooper)) {
            Authority commonAuth = Authority(vaultConfig.common.commonRolesAuthority);
            if (
                address(commonAuth) == address(0) && vaultConfig.common.predicateProxy != address(0)
                    && vaultConfig.common.predicateProxy.code.length > 0
            ) {
                commonAuth = Auth(vaultConfig.common.predicateProxy).authority();
            }
            // v5: rebuilt against the compliance-refactored bundle libraries and the v3 adapter
            // (the unlooper encodes calls to the adapter address). Bump forces a fresh CREATE3 address.
            bytes32 salt = generateCreate3SaltCommon("NestUnlooper-v5");
            vaultConfig.common.nestUnlooper = CREATEX.deployCreate3(
                salt,
                abi.encodePacked(
                    type(NestUnlooper).creationCode,
                    abi.encode(
                        parallelMigration ? migrationOwner : deployer(),
                        commonAuth,
                        mc.morpho,
                        mc.bundler3,
                        vaultConfig.common.nestAdapter,
                        mc.atomicSolver,
                        mc.atomicQueue
                    )
                )
            );
            _logDeploy("NestUnlooper", vaultConfig.common.nestUnlooper);
        } else {
            _logExists("NestUnlooper", vaultConfig.common.nestUnlooper);
        }

        vm.stopBroadcast();

        console.log("=== Morpho Deployment Summary ===");
        console.log("NestAdapter: ", vaultConfig.common.nestAdapter);
        console.log("NestBundler: ", vaultConfig.common.nestBundler);
        console.log("NestUnlooper:", vaultConfig.common.nestUnlooper);
        console.log("=================================");
    }
}
