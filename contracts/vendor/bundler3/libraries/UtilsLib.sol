// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @custom:security-contact security@morpho.org
/// @notice Utils library.
library UtilsLib {
    /// @dev Bubbles up the revert reason / custom error encoded in `returnData`.
    /// @dev Assumes `returnData` is the return data of any kind of failing CALL to a contract.
    function lowLevelRevert(bytes memory returnData) internal pure {
        assembly ("memory-safe") {
            revert(add(32, returnData), mload(returnData))
        }
    }
}
