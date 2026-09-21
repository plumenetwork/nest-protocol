// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

/// @title  IComplianceHook
/// @author plumenetwork
/// @notice Pluggable compliance validator consulted by ComplianceProxy before forwarding a transaction.
/// @dev    Implementations wrap a specific provider (e.g. Predicate V2) and decode `_complianceData`
///         into its proof format; the caller owns the canonical `_payload` encoding.
interface IComplianceHook {
    /// @notice Validates that `_sender` is authorized to execute the operation described by `_payload`.
    /// @dev    Implementations whose proofs are spent on use MUST restrict callers, or third
    ///         parties can burn in-flight proofs observed in the mempool.
    /// @param  _sender         address The account the compliance proof must attest for.
    /// @param  _payload        bytes   Canonical operation payload the policy attests over
    ///                                 (e.g. `abi.encodeWithSignature("deposit()")`).
    /// @param  _complianceData bytes   Provider-specific proof (e.g. an abi-encoded Predicate V2 Attestation).
    /// @return bool `true` if authorized. Implementations may also revert on invalid proofs.
    function checkCompliance(address _sender, bytes calldata _payload, bytes calldata _complianceData)
        external
        returns (bool);
}
