// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

/// @title MockEmptyFallback
/// @notice A mock contract with a fallback that returns empty data.
///         Used to test that setAccountantWithRateProviders() rejects contracts
///         that appear to succeed on staticcall but return no meaningful data.
contract MockEmptyFallback {
    // Fallback accepts any call and returns empty data (success with 0 bytes)
    fallback() external payable {}

    receive() external payable {}
}

/// @title MockShortReturnData
/// @notice A mock contract that returns less than 32 bytes for totalPendingShares().
///         Uses assembly to bypass Solidity's ABI encoding which normally pads to 32 bytes.
///         Used to test that setAccountantWithRateProviders() validates return data length.
contract MockShortReturnData {
    // Returns only 16 bytes instead of the expected 32 bytes for uint256
    // Uses assembly to bypass ABI encoding padding
    function totalPendingShares() external pure {
        assembly {
            mstore(0, 0) // Store zero at memory position 0
            return(0, 16) // Return only 16 bytes
        }
    }
}
