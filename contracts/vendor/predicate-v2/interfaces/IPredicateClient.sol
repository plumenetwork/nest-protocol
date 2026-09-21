// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

/**
 * @notice error type for unauthorized access
 */
error PredicateClient__Unauthorized();

/**
 * @notice Interface for a PredicateClient-type contract to set policy, registry and validate tasks
 */
interface IPredicateClient {
    /**
     * @notice Sets a policy ID for the calling address
     * @param _policyID The policy identifier. Typically "x-{hash(policy)[:16]}" but can be any string
     * @dev This function enables clients to define execution rules or parameters for statements they submit.
     *      The policy ID governs how statements are validated, ensuring compliance with predefined rules.
     */
    function setPolicyID(string memory _policyID) external;

    /**
     * @notice Sets the Predicate Registry for the calling address
     * @param _registry address of the registry
     * @dev This function enables clients to set the Predicate Registry for the calling address
     * @dev Authorized only by the owner of the contract
     */
    function setRegistry(address _registry) external;

    /**
     * @notice Retrieves the policy ID for the calling address
     * @return policyID The policy identifier associated with the calling address
     */
    function getPolicyID() external view returns (string memory policyID);

    /**
     * @notice Function for getting the Predicate Registry
     * @return address of the registry
     */
    function getRegistry() external view returns (address);
}
