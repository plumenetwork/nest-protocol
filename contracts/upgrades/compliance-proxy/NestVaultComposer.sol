// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {NestVaultComposer as BaseNestVaultComposer} from "contracts/integrations/ovault/NestVaultComposer.sol";

/// @notice Upgrade implementation for existing composers switching to ComplianceProxy.
/// @dev Adds no storage. New deployments use the default NestVaultComposer.
contract NestVaultComposer is BaseNestVaultComposer {
    constructor(address _complianceProxy) BaseNestVaultComposer(_complianceProxy) {}

    /// @notice Approves the immutable ComplianceProxy after upgrading an existing composer proxy.
    /// @dev Must be executed atomically with the implementation upgrade because the original initializer
    ///      approved the legacy predicate proxy embedded in the previous implementation. Version 3 is
    ///      intentional: early live Composer proxies already consumed reinitializer version 2.
    function initializeComplianceProxy() external reinitializer(3) {
        __NestVaultComposer_init();
    }
}
