// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

// contracts
import {AuthUpgradeable, Authority} from "contracts/auth/AuthUpgradeable.sol";
import {PredicateClient} from "@predicate-v2/mixins/PredicateClient.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// interfaces
import {IComplianceHook} from "contracts/compliance/interfaces/IComplianceHook.sol";
import {IPredicateClient} from "@predicate-v2/interfaces/IPredicateClient.sol";
import {Attestation} from "@predicate-v2/interfaces/IPredicateRegistry.sol";

/// @title  PredicateV2Hook
/// @author plumenetwork
/// @notice IComplianceHook implementation backed by the Predicate V2 Registry.
/// @dev    Upgradeable. Decodes `_complianceData` as a Predicate V2 `Attestation` and validates it via the Registry.
contract PredicateV2Hook is Initializable, AuthUpgradeable, PredicateClient, IComplianceHook {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Error thrown when a zero address is provided.
    error PredicateV2Hook__ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                       CONSTRUCTOR & INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @dev Disables initializers on the implementation.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the hook with auth and the Predicate V2 registry configuration.
    /// @param _owner     address   The owner address for auth.
    /// @param _authority Authority The authority contract for role checks.
    /// @param _registry  address   The Predicate V2 Registry address for this chain.
    /// @param _policyID  string    The dashboard project's verification hash.
    function initialize(address _owner, Authority _authority, address _registry, string memory _policyID)
        external
        initializer
    {
        if (_owner == address(0) || _registry == address(0)) revert PredicateV2Hook__ZeroAddress();
        __Auth_init(_owner, _authority);
        _initPredicateClient(_registry, _policyID);
    }

    /// @notice Returns the version of the PredicateV2Hook contract.
    function version() public pure returns (string memory) {
        return "1.0.0";
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPredicateClient
    function setPolicyID(string memory _policyID) external requiresAuth {
        _setPolicyID(_policyID);
    }

    /// @inheritdoc IPredicateClient
    function setRegistry(address _registry) external requiresAuth {
        if (_registry == address(0)) revert PredicateV2Hook__ZeroAddress();
        _setRegistry(_registry);
    }

    /*//////////////////////////////////////////////////////////////
                            COMPLIANCE HOOK
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IComplianceHook
    /// @dev Restricted by Auth. The Registry reverts on expired/replayed/tampered attestations
    ///      and spends the UUID on success.
    function checkCompliance(address _sender, bytes calldata _payload, bytes calldata _complianceData)
        external
        requiresAuth
        returns (bool)
    {
        Attestation memory _attestation = abi.decode(_complianceData, (Attestation));
        return _authorizeTransaction(_attestation, _payload, _sender, 0);
    }
}
