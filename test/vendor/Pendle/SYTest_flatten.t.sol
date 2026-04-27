// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity <0.9.0 >=0.4.22 >=0.6.0 >=0.6.2 ^0.8.0 ^0.8.1 ^0.8.2 ^0.8.28;
pragma experimental ABIEncoderV2;

// node_modules/@openzeppelin/contracts/utils/Address.sol

// OpenZeppelin Contracts (last updated v4.9.0) (utils/Address.sol)

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     *
     * Furthermore, `isContract` will also return true if the target contract within
     * the same transaction is already scheduled for destruction by `SELFDESTRUCT`,
     * which only has an effect at the end of a transaction.
     * ====
     *
     * [IMPORTANT]
     * ====
     * You shouldn't rely on `isContract` to protect against flash loan attacks!
     *
     * Preventing calls from contracts is highly discouraged. It breaks composability, breaks support for smart wallets
     * like Gnosis Safe, and does not provide security since it can be circumvented by calling from a contract
     * constructor.
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.8.0/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success,) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data, string memory errorMessage)
        internal
        returns (bytes memory)
    {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage)
        internal
        returns (bytes memory)
    {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data, string memory errorMessage)
        internal
        view
        returns (bytes memory)
    {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data, string memory errorMessage)
        internal
        returns (bytes memory)
    {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and revert (either by bubbling
     * the revert reason or using the provided one) in case of unsuccessful call or if target was not a contract.
     *
     * _Available since v4.8._
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        if (success) {
            if (returndata.length == 0) {
                // only check isContract if the call was successful and the return data is empty
                // otherwise we already know that it was a contract
                require(isContract(target), "Address: call to non-contract");
            }
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason or using the provided one.
     *
     * _Available since v4.3._
     */
    function verifyCallResult(bool success, bytes memory returndata, string memory errorMessage)
        internal
        pure
        returns (bytes memory)
    {
        if (success) {
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    function _revert(bytes memory returndata, string memory errorMessage) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            /// @solidity memory-safe-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert(errorMessage);
        }
    }
}

// node_modules/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol

// OpenZeppelin Contracts (last updated v4.9.0) (utils/Address.sol)

/**
 * @dev Collection of functions related to the address type
 */
library AddressUpgradeable {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     *
     * Furthermore, `isContract` will also return true if the target contract within
     * the same transaction is already scheduled for destruction by `SELFDESTRUCT`,
     * which only has an effect at the end of a transaction.
     * ====
     *
     * [IMPORTANT]
     * ====
     * You shouldn't rely on `isContract` to protect against flash loan attacks!
     *
     * Preventing calls from contracts is highly discouraged. It breaks composability, breaks support for smart wallets
     * like Gnosis Safe, and does not provide security since it can be circumvented by calling from a contract
     * constructor.
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.8.0/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success,) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data, string memory errorMessage)
        internal
        returns (bytes memory)
    {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage)
        internal
        returns (bytes memory)
    {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data, string memory errorMessage)
        internal
        view
        returns (bytes memory)
    {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data, string memory errorMessage)
        internal
        returns (bytes memory)
    {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and revert (either by bubbling
     * the revert reason or using the provided one) in case of unsuccessful call or if target was not a contract.
     *
     * _Available since v4.8._
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        if (success) {
            if (returndata.length == 0) {
                // only check isContract if the call was successful and the return data is empty
                // otherwise we already know that it was a contract
                require(isContract(target), "Address: call to non-contract");
            }
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason or using the provided one.
     *
     * _Available since v4.3._
     */
    function verifyCallResult(bool success, bytes memory returndata, string memory errorMessage)
        internal
        pure
        returns (bytes memory)
    {
        if (success) {
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    function _revert(bytes memory returndata, string memory errorMessage) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            /// @solidity memory-safe-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert(errorMessage);
        }
    }
}

// test/helpers/ArrayHelpers.sol

abstract contract ArrayHelpers {
    function erase(address[] memory arr, address value) internal pure {
        uint256 keepCnt = 0;
        for (uint256 i = 0; i < arr.length; ++i) {
            if (arr[i] == value) continue;
            arr[keepCnt++] = arr[i];
        }
        assembly ("memory-safe") {
            mstore(arr, keepCnt)
        }
    }

    function toArray(address a) internal pure returns (address[] memory res) {
        res = new address[](1);
        res[0] = a;
    }

    function toArray(address a, address b) internal pure returns (address[] memory res) {
        res = new address[](2);
        res[0] = a;
        res[1] = b;
    }

    function toArray(bool a) internal pure returns (bool[] memory res) {
        res = new bool[](1);
        res[0] = a;
    }
}

// node_modules/@openzeppelin/contracts/proxy/beacon/IBeacon.sol

// OpenZeppelin Contracts v4.4.1 (proxy/beacon/IBeacon.sol)

/**
 * @dev This is the interface that {BeaconProxy} expects of its beacon.
 */
interface IBeacon {
    /**
     * @dev Must return an address that can be used as a delegate call target.
     *
     * {BeaconProxy} will check that this address is a contract.
     */
    function implementation() external view returns (address);
}

// node_modules/@openzeppelin/contracts/interfaces/IERC1967.sol

// OpenZeppelin Contracts (last updated v4.9.0) (interfaces/IERC1967.sol)

/**
 * @dev ERC-1967: Proxy Storage Slots. This interface contains the events defined in the ERC.
 *
 * _Available since v4.8.3._
 */
interface IERC1967 {
    /**
     * @dev Emitted when the implementation is upgraded.
     */
    event Upgraded(address indexed implementation);

    /**
     * @dev Emitted when the admin account has changed.
     */
    event AdminChanged(address previousAdmin, address newAdmin);

    /**
     * @dev Emitted when the beacon is changed.
     */
    event BeaconUpgraded(address indexed beacon);
}

// node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol

// OpenZeppelin Contracts (last updated v4.9.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// node_modules/@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol

// OpenZeppelin Contracts (last updated v4.9.4) (token/ERC20/extensions/IERC20Permit.sol)

/**
 * @dev Interface of the ERC20 Permit extension allowing approvals to be made via signatures, as defined in
 * https://eips.ethereum.org/EIPS/eip-2612[EIP-2612].
 *
 * Adds the {permit} method, which can be used to change an account's ERC20 allowance (see {IERC20-allowance}) by
 * presenting a message signed by the account. By not relying on {IERC20-approve}, the token holder account doesn't
 * need to send a transaction, and thus is not required to hold Ether at all.
 *
 * ==== Security Considerations
 *
 * There are two important considerations concerning the use of `permit`. The first is that a valid permit signature
 * expresses an allowance, and it should not be assumed to convey additional meaning. In particular, it should not be
 * considered as an intention to spend the allowance in any specific way. The second is that because permits have
 * built-in replay protection and can be submitted by anyone, they can be frontrun. A protocol that uses permits should
 * take this into consideration and allow a `permit` call to fail. Combining these two aspects, a pattern that may be
 * generally recommended is:
 *
 * ```solidity
 * function doThingWithPermit(..., uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public {
 *     try token.permit(msg.sender, address(this), value, deadline, v, r, s) {} catch {}
 *     doThing(..., value);
 * }
 *
 * function doThing(..., uint256 value) public {
 *     token.safeTransferFrom(msg.sender, address(this), value);
 *     ...
 * }
 * ```
 *
 * Observe that: 1) `msg.sender` is used as the owner, leaving no ambiguity as to the signer intent, and 2) the use of
 * `try/catch` allows the permit to fail and makes the code tolerant to frontrunning. (See also
 * {SafeERC20-safeTransferFrom}).
 *
 * Additionally, note that smart contract wallets (such as Argent or Safe) are not able to produce permit signatures, so
 * contracts should have entry points that don't rely on permit.
 */
interface IERC20Permit {
    /**
     * @dev Sets `value` as the allowance of `spender` over ``owner``'s tokens,
     * given ``owner``'s signed approval.
     *
     * IMPORTANT: The same issues {IERC20-approve} has related to transaction
     * ordering also apply here.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `deadline` must be a timestamp in the future.
     * - `v`, `r` and `s` must be a valid `secp256k1` signature from `owner`
     * over the EIP712-formatted function arguments.
     * - the signature must use ``owner``'s current nonce (see {nonces}).
     *
     * For more information on the signature format, see the
     * https://eips.ethereum.org/EIPS/eip-2612#specification[relevant EIP
     * section].
     *
     * CAUTION: See Security Considerations above.
     */
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;

    /**
     * @dev Returns the current nonce for `owner`. This value must be
     * included whenever a signature is generated for {permit}.
     *
     * Every successful call to {permit} increases ``owner``'s nonce by one. This
     * prevents a signature from being used multiple times.
     */
    function nonces(address owner) external view returns (uint256);

    /**
     * @dev Returns the domain separator used in the encoding of the signature for {permit}, as defined by {EIP712}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

// lib/forge-std/src/interfaces/IMulticall3.sol

interface IMulticall3 {
    struct Call {
        address target;
        bytes callData;
    }

    struct Call3 {
        address target;
        bool allowFailure;
        bytes callData;
    }

    struct Call3Value {
        address target;
        bool allowFailure;
        uint256 value;
        bytes callData;
    }

    struct Result {
        bool success;
        bytes returnData;
    }

    function aggregate(Call[] calldata calls) external payable returns (uint256 blockNumber, bytes[] memory returnData);

    function aggregate3(Call3[] calldata calls) external payable returns (Result[] memory returnData);

    function aggregate3Value(Call3Value[] calldata calls) external payable returns (Result[] memory returnData);

    function blockAndAggregate(Call[] calldata calls)
        external
        payable
        returns (uint256 blockNumber, bytes32 blockHash, Result[] memory returnData);

    function getBasefee() external view returns (uint256 basefee);

    function getBlockHash(uint256 blockNumber) external view returns (bytes32 blockHash);

    function getBlockNumber() external view returns (uint256 blockNumber);

    function getChainId() external view returns (uint256 chainid);

    function getCurrentBlockCoinbase() external view returns (address coinbase);

    function getCurrentBlockDifficulty() external view returns (uint256 difficulty);

    function getCurrentBlockGasLimit() external view returns (uint256 gaslimit);

    function getCurrentBlockTimestamp() external view returns (uint256 timestamp);

    function getEthBalance(address addr) external view returns (uint256 balance);

    function getLastBlockHash() external view returns (bytes32 blockHash);

    function tryAggregate(bool requireSuccess, Call[] calldata calls)
        external
        payable
        returns (Result[] memory returnData);

    function tryBlockAndAggregate(bool requireSuccess, Call[] calldata calls)
        external
        payable
        returns (uint256 blockNumber, bytes32 blockHash, Result[] memory returnData);
}

// lib/pendle-sy/contracts/interfaces/IPTokenWithSupplyCap.sol

interface IPTokenWithSupplyCap {
    function getAbsoluteSupplyCap() external view returns (uint256);

    function getAbsoluteTotalSupply() external view returns (uint256);
}

// node_modules/@openzeppelin/contracts/utils/math/Math.sol

// OpenZeppelin Contracts (last updated v4.9.0) (utils/math/Math.sol)

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
    enum Rounding {
        Down, // Toward negative infinity
        Up, // Toward infinity
        Zero // Toward zero
    }

    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow.
        return (a & b) + (a ^ b) / 2;
    }

    /**
     * @dev Returns the ceiling of the division of two numbers.
     *
     * This differs from standard division with `/` in that it rounds up instead
     * of rounding down.
     */
    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b - 1) / b can overflow on addition, so we distribute.
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    /**
     * @notice Calculates floor(x * y / denominator) with full precision. Throws if result overflows a uint256 or denominator == 0
     * @dev Original credit to Remco Bloemen under MIT license (https://xn--2-umb.com/21/muldiv)
     * with further edits by Uniswap Labs also under MIT license.
     */
    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            // 512-bit multiply [prod1 prod0] = x * y. Compute the product mod 2^256 and mod 2^256 - 1, then use
            // use the Chinese Remainder Theorem to reconstruct the 512 bit result. The result is stored in two 256
            // variables such that product = prod1 * 2^256 + prod0.
            uint256 prod0; // Least significant 256 bits of the product
            uint256 prod1; // Most significant 256 bits of the product
            assembly {
                let mm := mulmod(x, y, not(0))
                prod0 := mul(x, y)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            // Handle non-overflow cases, 256 by 256 division.
            if (prod1 == 0) {
                // Solidity will revert if denominator == 0, unlike the div opcode on its own.
                // The surrounding unchecked block does not change this fact.
                // See https://docs.soliditylang.org/en/latest/control-structures.html#checked-or-unchecked-arithmetic.
                return prod0 / denominator;
            }

            // Make sure the result is less than 2^256. Also prevents denominator == 0.
            require(denominator > prod1, "Math: mulDiv overflow");

            ///////////////////////////////////////////////
            // 512 by 256 division.
            ///////////////////////////////////////////////

            // Make division exact by subtracting the remainder from [prod1 prod0].
            uint256 remainder;
            assembly {
                // Compute remainder using mulmod.
                remainder := mulmod(x, y, denominator)

                // Subtract 256 bit number from 512 bit number.
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            // Factor powers of two out of denominator and compute largest power of two divisor of denominator. Always >= 1.
            // See https://cs.stackexchange.com/q/138556/92363.

            // Does not overflow because the denominator cannot be zero at this stage in the function.
            uint256 twos = denominator & (~denominator + 1);
            assembly {
                // Divide denominator by twos.
                denominator := div(denominator, twos)

                // Divide [prod1 prod0] by twos.
                prod0 := div(prod0, twos)

                // Flip twos such that it is 2^256 / twos. If twos is zero, then it becomes one.
                twos := add(div(sub(0, twos), twos), 1)
            }

            // Shift in bits from prod1 into prod0.
            prod0 |= prod1 * twos;

            // Invert denominator mod 2^256. Now that denominator is an odd number, it has an inverse modulo 2^256 such
            // that denominator * inv = 1 mod 2^256. Compute the inverse by starting with a seed that is correct for
            // four bits. That is, denominator * inv = 1 mod 2^4.
            uint256 inverse = (3 * denominator) ^ 2;

            // Use the Newton-Raphson iteration to improve the precision. Thanks to Hensel's lifting lemma, this also works
            // in modular arithmetic, doubling the correct bits in each step.
            inverse *= 2 - denominator * inverse; // inverse mod 2^8
            inverse *= 2 - denominator * inverse; // inverse mod 2^16
            inverse *= 2 - denominator * inverse; // inverse mod 2^32
            inverse *= 2 - denominator * inverse; // inverse mod 2^64
            inverse *= 2 - denominator * inverse; // inverse mod 2^128
            inverse *= 2 - denominator * inverse; // inverse mod 2^256

            // Because the division is now exact we can divide by multiplying with the modular inverse of denominator.
            // This will give us the correct result modulo 2^256. Since the preconditions guarantee that the outcome is
            // less than 2^256, this is the final result. We don't need to compute the high bits of the result and prod1
            // is no longer required.
            result = prod0 * inverse;
            return result;
        }
    }

    /**
     * @notice Calculates x * y / denominator with full precision, following the selected rounding direction.
     */
    function mulDiv(uint256 x, uint256 y, uint256 denominator, Rounding rounding) internal pure returns (uint256) {
        uint256 result = mulDiv(x, y, denominator);
        if (rounding == Rounding.Up && mulmod(x, y, denominator) > 0) {
            result += 1;
        }
        return result;
    }

    /**
     * @dev Returns the square root of a number. If the number is not a perfect square, the value is rounded down.
     *
     * Inspired by Henry S. Warren, Jr.'s "Hacker's Delight" (Chapter 11).
     */
    function sqrt(uint256 a) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        // For our first guess, we get the biggest power of 2 which is smaller than the square root of the target.
        //
        // We know that the "msb" (most significant bit) of our target number `a` is a power of 2 such that we have
        // `msb(a) <= a < 2*msb(a)`. This value can be written `msb(a)=2**k` with `k=log2(a)`.
        //
        // This can be rewritten `2**log2(a) <= a < 2**(log2(a) + 1)`
        // → `sqrt(2**k) <= sqrt(a) < sqrt(2**(k+1))`
        // → `2**(k/2) <= sqrt(a) < 2**((k+1)/2) <= 2**(k/2 + 1)`
        //
        // Consequently, `2**(log2(a) / 2)` is a good first approximation of `sqrt(a)` with at least 1 correct bit.
        uint256 result = 1 << (log2(a) >> 1);

        // At this point `result` is an estimation with one bit of precision. We know the true value is a uint128,
        // since it is the square root of a uint256. Newton's method converges quadratically (precision doubles at
        // every iteration). We thus need at most 7 iteration to turn our partial result with one bit of precision
        // into the expected uint128 result.
        unchecked {
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            return min(result, a / result);
        }
    }

    /**
     * @notice Calculates sqrt(a), following the selected rounding direction.
     */
    function sqrt(uint256 a, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = sqrt(a);
            return result + (rounding == Rounding.Up && result * result < a ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 2, rounded down, of a positive value.
     * Returns 0 if given 0.
     */
    function log2(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 128;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 64;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 32;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 16;
            }
            if (value >> 8 > 0) {
                value >>= 8;
                result += 8;
            }
            if (value >> 4 > 0) {
                value >>= 4;
                result += 4;
            }
            if (value >> 2 > 0) {
                value >>= 2;
                result += 2;
            }
            if (value >> 1 > 0) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 2, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log2(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log2(value);
            return result + (rounding == Rounding.Up && 1 << result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 10, rounded down, of a positive value.
     * Returns 0 if given 0.
     */
    function log10(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >= 10 ** 64) {
                value /= 10 ** 64;
                result += 64;
            }
            if (value >= 10 ** 32) {
                value /= 10 ** 32;
                result += 32;
            }
            if (value >= 10 ** 16) {
                value /= 10 ** 16;
                result += 16;
            }
            if (value >= 10 ** 8) {
                value /= 10 ** 8;
                result += 8;
            }
            if (value >= 10 ** 4) {
                value /= 10 ** 4;
                result += 4;
            }
            if (value >= 10 ** 2) {
                value /= 10 ** 2;
                result += 2;
            }
            if (value >= 10 ** 1) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 10, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log10(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log10(value);
            return result + (rounding == Rounding.Up && 10 ** result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 256, rounded down, of a positive value.
     * Returns 0 if given 0.
     *
     * Adding one to the result gives the number of pairs of hex symbols needed to represent `value` as a hex string.
     */
    function log256(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 16;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 8;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 4;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 2;
            }
            if (value >> 8 > 0) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 256, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log256(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log256(value);
            return result + (rounding == Rounding.Up && 1 << (result << 3) < value ? 1 : 0);
        }
    }
}

// lib/pendle-core/contracts/core/libraries/math/PMath.sol

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

/* solhint-disable private-vars-leading-underscore, reason-string */

library PMath_0 {
    uint256 internal constant ONE = 1e18; // 18 decimal places
    int256 internal constant IONE = 1e18; // 18 decimal places

    function subMax0(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            return (a >= b ? a - b : 0);
        }
    }

    function subNoNeg(int256 a, int256 b) internal pure returns (int256) {
        require(a >= b, "negative");
        return a - b; // no unchecked since if b is very negative, a - b might overflow
    }

    function mulDown(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 product = a * b;
        unchecked {
            return product / ONE;
        }
    }

    function mulDown(int256 a, int256 b) internal pure returns (int256) {
        int256 product = a * b;
        unchecked {
            return product / IONE;
        }
    }

    function divDown(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 aInflated = a * ONE;
        unchecked {
            return aInflated / b;
        }
    }

    function divDown(int256 a, int256 b) internal pure returns (int256) {
        int256 aInflated = a * IONE;
        unchecked {
            return aInflated / b;
        }
    }

    function rawDivUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a + b - 1) / b;
    }

    function rawDivUp(int256 a, int256 b) internal pure returns (int256) {
        return (a + b - 1) / b;
    }

    function tweakUp(uint256 a, uint256 factor) internal pure returns (uint256) {
        return mulDown(a, ONE + factor);
    }

    function tweakDown(uint256 a, uint256 factor) internal pure returns (uint256) {
        return mulDown(a, ONE - factor);
    }

    /// @return res = min(a + b, bound)
    /// @dev This function should handle arithmetic operation and bound check without overflow/underflow
    function addWithUpperBound(uint256 a, uint256 b, uint256 bound) internal pure returns (uint256 res) {
        unchecked {
            if (type(uint256).max - b < a) res = bound;
            else res = min(bound, a + b);
        }
    }

    /// @return res = max(a - b, bound)
    /// @dev This function should handle arithmetic operation and bound check without overflow/underflow
    function subWithLowerBound(uint256 a, uint256 b, uint256 bound) internal pure returns (uint256 res) {
        unchecked {
            if (b > a) res = bound;
            else res = max(a - b, bound);
        }
    }

    function clamp(uint256 x, uint256 lower, uint256 upper) internal pure returns (uint256 res) {
        res = x;
        if (x < lower) res = lower;
        else if (x > upper) res = upper;
    }

    // @author Uniswap
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function square(uint256 x) internal pure returns (uint256) {
        return x * x;
    }

    function squareDown(uint256 x) internal pure returns (uint256) {
        return mulDown(x, x);
    }

    function abs(int256 x) internal pure returns (uint256) {
        return uint256(x > 0 ? x : -x);
    }

    function neg(int256 x) internal pure returns (int256) {
        return x * (-1);
    }

    function neg(uint256 x) internal pure returns (int256) {
        return Int(x) * (-1);
    }

    function max(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x > y ? x : y);
    }

    function max(int256 x, int256 y) internal pure returns (int256) {
        return (x > y ? x : y);
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x < y ? x : y);
    }

    function min(int256 x, int256 y) internal pure returns (int256) {
        return (x < y ? x : y);
    }

    /*///////////////////////////////////////////////////////////////
                               SIGNED CASTS
    //////////////////////////////////////////////////////////////*/

    function Int(uint256 x) internal pure returns (int256) {
        require(x <= uint256(type(int256).max));
        return int256(x);
    }

    function Int128(int256 x) internal pure returns (int128) {
        require(type(int128).min <= x && x <= type(int128).max);
        return int128(x);
    }

    function Int128(uint256 x) internal pure returns (int128) {
        return Int128(Int(x));
    }

    /*///////////////////////////////////////////////////////////////
                               UNSIGNED CASTS
    //////////////////////////////////////////////////////////////*/

    function Uint(int256 x) internal pure returns (uint256) {
        require(x >= 0);
        return uint256(x);
    }

    function Uint32(uint256 x) internal pure returns (uint32) {
        require(x <= type(uint32).max);
        return uint32(x);
    }

    function Uint64(uint256 x) internal pure returns (uint64) {
        require(x <= type(uint64).max);
        return uint64(x);
    }

    function Uint112(uint256 x) internal pure returns (uint112) {
        require(x <= type(uint112).max);
        return uint112(x);
    }

    function Uint96(uint256 x) internal pure returns (uint96) {
        require(x <= type(uint96).max);
        return uint96(x);
    }

    function Uint128(uint256 x) internal pure returns (uint128) {
        require(x <= type(uint128).max);
        return uint128(x);
    }

    function Uint192(uint256 x) internal pure returns (uint192) {
        require(x <= type(uint192).max);
        return uint192(x);
    }

    function Uint80(uint256 x) internal pure returns (uint80) {
        require(x <= type(uint80).max);
        return uint80(x);
    }

    function isAApproxB(uint256 a, uint256 b, uint256 eps) internal pure returns (bool) {
        return mulDown(b, ONE - eps) <= a && a <= mulDown(b, ONE + eps);
    }

    function isAGreaterApproxB(uint256 a, uint256 b, uint256 eps) internal pure returns (bool) {
        return a >= b && a <= mulDown(b, ONE + eps);
    }

    function isASmallerApproxB(uint256 a, uint256 b, uint256 eps) internal pure returns (bool) {
        return a <= b && a >= mulDown(b, ONE - eps);
    }
}

// lib/pendle-sy/contracts/core/libraries/math/PMath.sol

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

/* solhint-disable private-vars-leading-underscore, reason-string */

library PMath_1 {
    uint256 internal constant ONE = 1e18; // 18 decimal places
    int256 internal constant IONE = 1e18; // 18 decimal places

    function subMax0(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            return (a >= b ? a - b : 0);
        }
    }

    function subNoNeg(int256 a, int256 b) internal pure returns (int256) {
        require(a >= b, "negative");
        return a - b; // no unchecked since if b is very negative, a - b might overflow
    }

    function mulDown(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 product = a * b;
        unchecked {
            return product / ONE;
        }
    }

    function mulDown(int256 a, int256 b) internal pure returns (int256) {
        int256 product = a * b;
        unchecked {
            return product / IONE;
        }
    }

    function divDown(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 aInflated = a * ONE;
        unchecked {
            return aInflated / b;
        }
    }

    function divDown(int256 a, int256 b) internal pure returns (int256) {
        int256 aInflated = a * IONE;
        unchecked {
            return aInflated / b;
        }
    }

    function rawDivUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a + b - 1) / b;
    }

    function rawDivUp(int256 a, int256 b) internal pure returns (int256) {
        return (a + b - 1) / b;
    }

    function tweakUp(uint256 a, uint256 factor) internal pure returns (uint256) {
        return mulDown(a, ONE + factor);
    }

    function tweakDown(uint256 a, uint256 factor) internal pure returns (uint256) {
        return mulDown(a, ONE - factor);
    }

    /// @return res = min(a + b, bound)
    /// @dev This function should handle arithmetic operation and bound check without overflow/underflow
    function addWithUpperBound(uint256 a, uint256 b, uint256 bound) internal pure returns (uint256 res) {
        unchecked {
            if (type(uint256).max - b < a) res = bound;
            else res = min(bound, a + b);
        }
    }

    /// @return res = max(a - b, bound)
    /// @dev This function should handle arithmetic operation and bound check without overflow/underflow
    function subWithLowerBound(uint256 a, uint256 b, uint256 bound) internal pure returns (uint256 res) {
        unchecked {
            if (b > a) res = bound;
            else res = max(a - b, bound);
        }
    }

    function clamp(uint256 x, uint256 lower, uint256 upper) internal pure returns (uint256 res) {
        res = x;
        if (x < lower) res = lower;
        else if (x > upper) res = upper;
    }

    // @author Uniswap
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function square(uint256 x) internal pure returns (uint256) {
        return x * x;
    }

    function squareDown(uint256 x) internal pure returns (uint256) {
        return mulDown(x, x);
    }

    function abs(int256 x) internal pure returns (uint256) {
        return uint256(x > 0 ? x : -x);
    }

    function neg(int256 x) internal pure returns (int256) {
        return x * (-1);
    }

    function neg(uint256 x) internal pure returns (int256) {
        return Int(x) * (-1);
    }

    function max(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x > y ? x : y);
    }

    function max(int256 x, int256 y) internal pure returns (int256) {
        return (x > y ? x : y);
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x < y ? x : y);
    }

    function min(int256 x, int256 y) internal pure returns (int256) {
        return (x < y ? x : y);
    }

    /*///////////////////////////////////////////////////////////////
                               SIGNED CASTS
    //////////////////////////////////////////////////////////////*/

    function Int(uint256 x) internal pure returns (int256) {
        require(x <= uint256(type(int256).max));
        return int256(x);
    }

    function Int128(int256 x) internal pure returns (int128) {
        require(type(int128).min <= x && x <= type(int128).max);
        return int128(x);
    }

    function Int128(uint256 x) internal pure returns (int128) {
        return Int128(Int(x));
    }

    /*///////////////////////////////////////////////////////////////
                               UNSIGNED CASTS
    //////////////////////////////////////////////////////////////*/

    function Uint(int256 x) internal pure returns (uint256) {
        require(x >= 0);
        return uint256(x);
    }

    function Uint32(uint256 x) internal pure returns (uint32) {
        require(x <= type(uint32).max);
        return uint32(x);
    }

    function Uint64(uint256 x) internal pure returns (uint64) {
        require(x <= type(uint64).max);
        return uint64(x);
    }

    function Uint112(uint256 x) internal pure returns (uint112) {
        require(x <= type(uint112).max);
        return uint112(x);
    }

    function Uint96(uint256 x) internal pure returns (uint96) {
        require(x <= type(uint96).max);
        return uint96(x);
    }

    function Uint128(uint256 x) internal pure returns (uint128) {
        require(x <= type(uint128).max);
        return uint128(x);
    }

    function Uint192(uint256 x) internal pure returns (uint192) {
        require(x <= type(uint192).max);
        return uint192(x);
    }

    function isAApproxB(uint256 a, uint256 b, uint256 eps) internal pure returns (bool) {
        return mulDown(b, ONE - eps) <= a && a <= mulDown(b, ONE + eps);
    }

    function isAGreaterApproxB(uint256 a, uint256 b, uint256 eps) internal pure returns (bool) {
        return a >= b && a <= mulDown(b, ONE + eps);
    }

    function isASmallerApproxB(uint256 a, uint256 b, uint256 eps) internal pure returns (bool) {
        return a <= b && a >= mulDown(b, ONE - eps);
    }
}

// node_modules/@openzeppelin/contracts/proxy/Proxy.sol

// OpenZeppelin Contracts (last updated v4.6.0) (proxy/Proxy.sol)

/**
 * @dev This abstract contract provides a fallback function that delegates all calls to another contract using the EVM
 * instruction `delegatecall`. We refer to the second contract as the _implementation_ behind the proxy, and it has to
 * be specified by overriding the virtual {_implementation} function.
 *
 * Additionally, delegation to the implementation can be triggered manually through the {_fallback} function, or to a
 * different contract through the {_delegate} function.
 *
 * The success and return data of the delegated call will be returned back to the caller of the proxy.
 */
abstract contract Proxy {
    /**
     * @dev Delegates the current call to `implementation`.
     *
     * This function does not return to its internal call site, it will return directly to the external caller.
     */
    function _delegate(address implementation) internal virtual {
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    /**
     * @dev This is a virtual function that should be overridden so it returns the address to which the fallback function
     * and {_fallback} should delegate.
     */
    function _implementation() internal view virtual returns (address);

    /**
     * @dev Delegates the current call to the address returned by `_implementation()`.
     *
     * This function does not return to its internal call site, it will return directly to the external caller.
     */
    function _fallback() internal virtual {
        _beforeFallback();
        _delegate(_implementation());
    }

    /**
     * @dev Fallback function that delegates calls to the address returned by `_implementation()`. Will run if no other
     * function in the contract matches the call data.
     */
    fallback() external payable virtual {
        _fallback();
    }

    /**
     * @dev Fallback function that delegates calls to the address returned by `_implementation()`. Will run if call data
     * is empty.
     */
    receive() external payable virtual {
        _fallback();
    }

    /**
     * @dev Hook that is called before falling back to the implementation. Can happen as part of a manual `_fallback`
     * call, or as part of the Solidity `fallback` or `receive` functions.
     *
     * If overridden should call `super._beforeFallback()`.
     */
    function _beforeFallback() internal virtual {}
}

// node_modules/@openzeppelin/contracts/utils/math/SignedMath.sol

// OpenZeppelin Contracts (last updated v4.8.0) (utils/math/SignedMath.sol)

/**
 * @dev Standard signed math utilities missing in the Solidity language.
 */
library SignedMath {
    /**
     * @dev Returns the largest of two signed numbers.
     */
    function max(int256 a, int256 b) internal pure returns (int256) {
        return a > b ? a : b;
    }

    /**
     * @dev Returns the smallest of two signed numbers.
     */
    function min(int256 a, int256 b) internal pure returns (int256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two signed numbers without overflow.
     * The result is rounded towards zero.
     */
    function average(int256 a, int256 b) internal pure returns (int256) {
        // Formula from the book "Hacker's Delight"
        int256 x = (a & b) + ((a ^ b) >> 1);
        return x + (int256(uint256(x) >> 255) & (a ^ b));
    }

    /**
     * @dev Returns the absolute unsigned value of a signed value.
     */
    function abs(int256 n) internal pure returns (uint256) {
        unchecked {
            // must be unchecked in order to support `n = type(int256).min`
            return uint256(n >= 0 ? n : -n);
        }
    }
}

// lib/forge-std/src/StdError.sol

// Panics work for versions >=0.8.0, but we lowered the pragma to make this compatible with Test

library stdError {
    bytes public constant assertionError = abi.encodeWithSignature("Panic(uint256)", 0x01);
    bytes public constant arithmeticError = abi.encodeWithSignature("Panic(uint256)", 0x11);
    bytes public constant divisionError = abi.encodeWithSignature("Panic(uint256)", 0x12);
    bytes public constant enumConversionError = abi.encodeWithSignature("Panic(uint256)", 0x21);
    bytes public constant encodeStorageError = abi.encodeWithSignature("Panic(uint256)", 0x22);
    bytes public constant popError = abi.encodeWithSignature("Panic(uint256)", 0x31);
    bytes public constant indexOOBError = abi.encodeWithSignature("Panic(uint256)", 0x32);
    bytes public constant memOverflowError = abi.encodeWithSignature("Panic(uint256)", 0x41);
    bytes public constant zeroVarError = abi.encodeWithSignature("Panic(uint256)", 0x51);
}

// lib/forge-std/src/StdInvariant.sol

abstract contract StdInvariant {
    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    struct FuzzArtifactSelector {
        string artifact;
        bytes4[] selectors;
    }

    struct FuzzInterface {
        address addr;
        string[] artifacts;
    }

    address[] private _excludedContracts;
    address[] private _excludedSenders;
    address[] private _targetedContracts;
    address[] private _targetedSenders;

    string[] private _excludedArtifacts;
    string[] private _targetedArtifacts;

    FuzzArtifactSelector[] private _targetedArtifactSelectors;

    FuzzSelector[] private _excludedSelectors;
    FuzzSelector[] private _targetedSelectors;

    FuzzInterface[] private _targetedInterfaces;

    // Functions for users:
    // These are intended to be called in tests.

    function excludeContract(address newExcludedContract_) internal {
        _excludedContracts.push(newExcludedContract_);
    }

    function excludeSelector(FuzzSelector memory newExcludedSelector_) internal {
        _excludedSelectors.push(newExcludedSelector_);
    }

    function excludeSender(address newExcludedSender_) internal {
        _excludedSenders.push(newExcludedSender_);
    }

    function excludeArtifact(string memory newExcludedArtifact_) internal {
        _excludedArtifacts.push(newExcludedArtifact_);
    }

    function targetArtifact(string memory newTargetedArtifact_) internal {
        _targetedArtifacts.push(newTargetedArtifact_);
    }

    function targetArtifactSelector(FuzzArtifactSelector memory newTargetedArtifactSelector_) internal {
        _targetedArtifactSelectors.push(newTargetedArtifactSelector_);
    }

    function targetContract(address newTargetedContract_) internal {
        _targetedContracts.push(newTargetedContract_);
    }

    function targetSelector(FuzzSelector memory newTargetedSelector_) internal {
        _targetedSelectors.push(newTargetedSelector_);
    }

    function targetSender(address newTargetedSender_) internal {
        _targetedSenders.push(newTargetedSender_);
    }

    function targetInterface(FuzzInterface memory newTargetedInterface_) internal {
        _targetedInterfaces.push(newTargetedInterface_);
    }

    // Functions for forge:
    // These are called by forge to run invariant tests and don't need to be called in tests.

    function excludeArtifacts() public view returns (string[] memory excludedArtifacts_) {
        excludedArtifacts_ = _excludedArtifacts;
    }

    function excludeContracts() public view returns (address[] memory excludedContracts_) {
        excludedContracts_ = _excludedContracts;
    }

    function excludeSelectors() public view returns (FuzzSelector[] memory excludedSelectors_) {
        excludedSelectors_ = _excludedSelectors;
    }

    function excludeSenders() public view returns (address[] memory excludedSenders_) {
        excludedSenders_ = _excludedSenders;
    }

    function targetArtifacts() public view returns (string[] memory targetedArtifacts_) {
        targetedArtifacts_ = _targetedArtifacts;
    }

    function targetArtifactSelectors() public view returns (FuzzArtifactSelector[] memory targetedArtifactSelectors_) {
        targetedArtifactSelectors_ = _targetedArtifactSelectors;
    }

    function targetContracts() public view returns (address[] memory targetedContracts_) {
        targetedContracts_ = _targetedContracts;
    }

    function targetSelectors() public view returns (FuzzSelector[] memory targetedSelectors_) {
        targetedSelectors_ = _targetedSelectors;
    }

    function targetSenders() public view returns (address[] memory targetedSenders_) {
        targetedSenders_ = _targetedSenders;
    }

    function targetInterfaces() public view returns (FuzzInterface[] memory targetedInterfaces_) {
        targetedInterfaces_ = _targetedInterfaces;
    }
}

// lib/forge-std/src/StdMath.sol

library stdMath {
    int256 private constant INT256_MIN = -57896044618658097711785492504343953926634992332820282019728792003956564819968;

    function abs(int256 a) internal pure returns (uint256) {
        // Required or it will fail when `a = type(int256).min`
        if (a == INT256_MIN) {
            return 57896044618658097711785492504343953926634992332820282019728792003956564819968;
        }

        return uint256(a > 0 ? a : -a);
    }

    function delta(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function delta(int256 a, int256 b) internal pure returns (uint256) {
        // a and b are of the same sign
        // this works thanks to two's complement, the left-most bit is the sign bit
        if ((a ^ b) > -1) {
            return delta(abs(a), abs(b));
        }

        // a and b are of opposite signs
        return abs(a) + abs(b);
    }

    function percentDelta(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 absDelta = delta(a, b);

        return (absDelta * 1e18) / b;
    }

    function percentDelta(int256 a, int256 b) internal pure returns (uint256) {
        uint256 absDelta = delta(a, b);
        uint256 absB = abs(b);

        return (absDelta * 1e18) / absB;
    }
}

// node_modules/@openzeppelin/contracts/utils/StorageSlot.sol

// OpenZeppelin Contracts (last updated v4.9.0) (utils/StorageSlot.sol)
// This file was procedurally generated from scripts/generate/templates/StorageSlot.js.

/**
 * @dev Library for reading and writing primitive types to specific storage slots.
 *
 * Storage slots are often used to avoid storage conflict when dealing with upgradeable contracts.
 * This library helps with reading and writing to such slots without the need for inline assembly.
 *
 * The functions in this library return Slot structs that contain a `value` member that can be used to read or write.
 *
 * Example usage to set ERC1967 implementation slot:
 * ```solidity
 * contract ERC1967 {
 *     bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
 *
 *     function _getImplementation() internal view returns (address) {
 *         return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
 *     }
 *
 *     function _setImplementation(address newImplementation) internal {
 *         require(Address.isContract(newImplementation), "ERC1967: new implementation is not a contract");
 *         StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
 *     }
 * }
 * ```
 *
 * _Available since v4.1 for `address`, `bool`, `bytes32`, `uint256`._
 * _Available since v4.9 for `string`, `bytes`._
 */
library StorageSlot {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint256Slot {
        uint256 value;
    }

    struct StringSlot {
        string value;
    }

    struct BytesSlot {
        bytes value;
    }

    /**
     * @dev Returns an `AddressSlot` with member `value` located at `slot`.
     */
    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BooleanSlot` with member `value` located at `slot`.
     */
    function getBooleanSlot(bytes32 slot) internal pure returns (BooleanSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `Bytes32Slot` with member `value` located at `slot`.
     */
    function getBytes32Slot(bytes32 slot) internal pure returns (Bytes32Slot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `Uint256Slot` with member `value` located at `slot`.
     */
    function getUint256Slot(bytes32 slot) internal pure returns (Uint256Slot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `StringSlot` with member `value` located at `slot`.
     */
    function getStringSlot(bytes32 slot) internal pure returns (StringSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `StringSlot` representation of the string storage pointer `store`.
     */
    function getStringSlot(string storage store) internal pure returns (StringSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := store.slot
        }
    }

    /**
     * @dev Returns an `BytesSlot` with member `value` located at `slot`.
     */
    function getBytesSlot(bytes32 slot) internal pure returns (BytesSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BytesSlot` representation of the bytes storage pointer `store`.
     */
    function getBytesSlot(bytes storage store) internal pure returns (BytesSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := store.slot
        }
    }
}

// lib/forge-std/src/Vm.sol
// Automatically @generated by scripts/vm.py. Do not modify manually.

/// The `VmSafe` interface does not allow manipulation of the EVM state or other actions that may
/// result in Script simulations differing from on-chain execution. It is recommended to only use
/// these cheats in scripts.
interface VmSafe {
    /// A modification applied to either `msg.sender` or `tx.origin`. Returned by `readCallers`.
    enum CallerMode {
        // No caller modification is currently active.
        None,
        // A one time broadcast triggered by a `vm.broadcast()` call is currently active.
        Broadcast,
        // A recurrent broadcast triggered by a `vm.startBroadcast()` call is currently active.
        RecurrentBroadcast,
        // A one time prank triggered by a `vm.prank()` call is currently active.
        Prank,
        // A recurrent prank triggered by a `vm.startPrank()` call is currently active.
        RecurrentPrank
    }

    /// The kind of account access that occurred.
    enum AccountAccessKind {
        // The account was called.
        Call,
        // The account was called via delegatecall.
        DelegateCall,
        // The account was called via callcode.
        CallCode,
        // The account was called via staticcall.
        StaticCall,
        // The account was created.
        Create,
        // The account was selfdestructed.
        SelfDestruct,
        // Synthetic access indicating the current context has resumed after a previous sub-context (AccountAccess).
        Resume,
        // The account's balance was read.
        Balance,
        // The account's codesize was read.
        Extcodesize,
        // The account's codehash was read.
        Extcodehash,
        // The account's code was copied.
        Extcodecopy
    }

    /// Forge execution contexts.
    enum ForgeContext {
        // Test group execution context (test, coverage or snapshot).
        TestGroup,
        // `forge test` execution context.
        Test,
        // `forge coverage` execution context.
        Coverage,
        // `forge snapshot` execution context.
        Snapshot,
        // Script group execution context (dry run, broadcast or resume).
        ScriptGroup,
        // `forge script` execution context.
        ScriptDryRun,
        // `forge script --broadcast` execution context.
        ScriptBroadcast,
        // `forge script --resume` execution context.
        ScriptResume,
        // Unknown `forge` execution context.
        Unknown
    }

    /// The transaction type (`txType`) of the broadcast.
    enum BroadcastTxType {
        // Represents a CALL broadcast tx.
        Call,
        // Represents a CREATE broadcast tx.
        Create,
        // Represents a CREATE2 broadcast tx.
        Create2
    }

    /// An Ethereum log. Returned by `getRecordedLogs`.
    struct Log {
        // The topics of the log, including the signature, if any.
        bytes32[] topics;
        // The raw data of the log.
        bytes data;
        // The address of the log's emitter.
        address emitter;
    }

    /// An RPC URL and its alias. Returned by `rpcUrlStructs`.
    struct Rpc {
        // The alias of the RPC URL.
        string key;
        // The RPC URL.
        string url;
    }

    /// An RPC log object. Returned by `eth_getLogs`.
    struct EthGetLogs {
        // The address of the log's emitter.
        address emitter;
        // The topics of the log, including the signature, if any.
        bytes32[] topics;
        // The raw data of the log.
        bytes data;
        // The block hash.
        bytes32 blockHash;
        // The block number.
        uint64 blockNumber;
        // The transaction hash.
        bytes32 transactionHash;
        // The transaction index in the block.
        uint64 transactionIndex;
        // The log index.
        uint256 logIndex;
        // Whether the log was removed.
        bool removed;
    }

    /// A single entry in a directory listing. Returned by `readDir`.
    struct DirEntry {
        // The error message, if any.
        string errorMessage;
        // The path of the entry.
        string path;
        // The depth of the entry.
        uint64 depth;
        // Whether the entry is a directory.
        bool isDir;
        // Whether the entry is a symlink.
        bool isSymlink;
    }

    /// Metadata information about a file.
    /// This structure is returned from the `fsMetadata` function and represents known
    /// metadata about a file such as its permissions, size, modification
    /// times, etc.
    struct FsMetadata {
        // True if this metadata is for a directory.
        bool isDir;
        // True if this metadata is for a symlink.
        bool isSymlink;
        // The size of the file, in bytes, this metadata is for.
        uint256 length;
        // True if this metadata is for a readonly (unwritable) file.
        bool readOnly;
        // The last modification time listed in this metadata.
        uint256 modified;
        // The last access time of this metadata.
        uint256 accessed;
        // The creation time listed in this metadata.
        uint256 created;
    }

    /// A wallet with a public and private key.
    struct Wallet {
        // The wallet's address.
        address addr;
        // The wallet's public key `X`.
        uint256 publicKeyX;
        // The wallet's public key `Y`.
        uint256 publicKeyY;
        // The wallet's private key.
        uint256 privateKey;
    }

    /// The result of a `tryFfi` call.
    struct FfiResult {
        // The exit code of the call.
        int32 exitCode;
        // The optionally hex-decoded `stdout` data.
        bytes stdout;
        // The `stderr` data.
        bytes stderr;
    }

    /// Information on the chain and fork.
    struct ChainInfo {
        // The fork identifier. Set to zero if no fork is active.
        uint256 forkId;
        // The chain ID of the current fork.
        uint256 chainId;
    }

    /// Information about a blockchain.
    struct Chain {
        // The chain name.
        string name;
        // The chain's Chain ID.
        uint256 chainId;
        // The chain's alias. (i.e. what gets specified in `foundry.toml`).
        string chainAlias;
        // A default RPC endpoint for this chain.
        string rpcUrl;
    }

    /// The result of a `stopAndReturnStateDiff` call.
    struct AccountAccess {
        // The chain and fork the access occurred.
        ChainInfo chainInfo;
        // The kind of account access that determines what the account is.
        // If kind is Call, DelegateCall, StaticCall or CallCode, then the account is the callee.
        // If kind is Create, then the account is the newly created account.
        // If kind is SelfDestruct, then the account is the selfdestruct recipient.
        // If kind is a Resume, then account represents a account context that has resumed.
        AccountAccessKind kind;
        // The account that was accessed.
        // It's either the account created, callee or a selfdestruct recipient for CREATE, CALL or SELFDESTRUCT.
        address account;
        // What accessed the account.
        address accessor;
        // If the account was initialized or empty prior to the access.
        // An account is considered initialized if it has code, a
        // non-zero nonce, or a non-zero balance.
        bool initialized;
        // The previous balance of the accessed account.
        uint256 oldBalance;
        // The potential new balance of the accessed account.
        // That is, all balance changes are recorded here, even if reverts occurred.
        uint256 newBalance;
        // Code of the account deployed by CREATE.
        bytes deployedCode;
        // Value passed along with the account access
        uint256 value;
        // Input data provided to the CREATE or CALL
        bytes data;
        // If this access reverted in either the current or parent context.
        bool reverted;
        // An ordered list of storage accesses made during an account access operation.
        StorageAccess[] storageAccesses;
        // Call depth traversed during the recording of state differences
        uint64 depth;
        // The previous nonce of the accessed account.
        uint64 oldNonce;
        // The new nonce of the accessed account.
        uint64 newNonce;
    }

    /// The storage accessed during an `AccountAccess`.
    struct StorageAccess {
        // The account whose storage was accessed.
        address account;
        // The slot that was accessed.
        bytes32 slot;
        // If the access was a write.
        bool isWrite;
        // The previous value of the slot.
        bytes32 previousValue;
        // The new value of the slot.
        bytes32 newValue;
        // If the access was reverted.
        bool reverted;
    }

    /// Gas used. Returned by `lastCallGas`.
    struct Gas {
        // The gas limit of the call.
        uint64 gasLimit;
        // The total gas used.
        uint64 gasTotalUsed;
        // DEPRECATED: The amount of gas used for memory expansion. Ref: <https://github.com/foundry-rs/foundry/pull/7934#pullrequestreview-2069236939>
        uint64 gasMemoryUsed;
        // The amount of gas refunded.
        int64 gasRefunded;
        // The amount of gas remaining.
        uint64 gasRemaining;
    }

    /// The result of the `stopDebugTraceRecording` call
    struct DebugStep {
        // The stack before executing the step of the run.
        // stack\[0\] represents the top of the stack.
        // and only stack data relevant to the opcode execution is contained.
        uint256[] stack;
        // The memory input data before executing the step of the run.
        // only input data relevant to the opcode execution is contained.
        // e.g. for MLOAD, it will have memory\[offset:offset+32\] copied here.
        // the offset value can be get by the stack data.
        bytes memoryInput;
        // The opcode that was accessed.
        uint8 opcode;
        // The call depth of the step.
        uint64 depth;
        // Whether the call end up with out of gas error.
        bool isOutOfGas;
        // The contract address where the opcode is running
        address contractAddr;
    }

    /// Represents a transaction's broadcast details.
    struct BroadcastTxSummary {
        // The hash of the transaction that was broadcasted
        bytes32 txHash;
        // Represent the type of transaction among CALL, CREATE, CREATE2
        BroadcastTxType txType;
        // The address of the contract that was called or created.
        // This is address of the contract that is created if the txType is CREATE or CREATE2.
        address contractAddress;
        // The block number the transaction landed in.
        uint64 blockNumber;
        // Status of the transaction, retrieved from the transaction receipt.
        bool success;
    }

    /// Holds a signed EIP-7702 authorization for an authority account to delegate to an implementation.
    struct SignedDelegation {
        // The y-parity of the recovered secp256k1 signature (0 or 1).
        uint8 v;
        // First 32 bytes of the signature.
        bytes32 r;
        // Second 32 bytes of the signature.
        bytes32 s;
        // The current nonce of the authority account at signing time.
        // Used to ensure signature can't be replayed after account nonce changes.
        uint64 nonce;
        // Address of the contract implementation that will be delegated to.
        // Gets encoded into delegation code: 0xef0100 || implementation.
        address implementation;
    }

    /// Represents a "potential" revert reason from a single subsequent call when using `vm.assumeNoReverts`.
    /// Reverts that match will result in a FOUNDRY::ASSUME rejection, whereas unmatched reverts will be surfaced
    /// as normal.
    struct PotentialRevert {
        // The allowed origin of the revert opcode; address(0) allows reverts from any address
        address reverter;
        // When true, only matches on the beginning of the revert data, otherwise, matches on entire revert data
        bool partialMatch;
        // The data to use to match encountered reverts
        bytes revertData;
    }

    /// An EIP-2930 access list item.
    struct AccessListItem {
        // The address to be added in access list.
        address target;
        // The storage keys to be added in access list.
        bytes32[] storageKeys;
    }

    // ======== Crypto ========

    /// Derives a private key from the name, labels the account with that name, and returns the wallet.
    function createWallet(string calldata walletLabel) external returns (Wallet memory wallet);

    /// Generates a wallet from the private key and returns the wallet.
    function createWallet(uint256 privateKey) external returns (Wallet memory wallet);

    /// Generates a wallet from the private key, labels the account with that name, and returns the wallet.
    function createWallet(uint256 privateKey, string calldata walletLabel) external returns (Wallet memory wallet);

    /// Derive a private key from a provided mnemonic string (or mnemonic file path)
    /// at the derivation path `m/44'/60'/0'/0/{index}`.
    function deriveKey(string calldata mnemonic, uint32 index) external pure returns (uint256 privateKey);

    /// Derive a private key from a provided mnemonic string (or mnemonic file path)
    /// at `{derivationPath}{index}`.
    function deriveKey(string calldata mnemonic, string calldata derivationPath, uint32 index)
        external
        pure
        returns (uint256 privateKey);

    /// Derive a private key from a provided mnemonic string (or mnemonic file path) in the specified language
    /// at the derivation path `m/44'/60'/0'/0/{index}`.
    function deriveKey(string calldata mnemonic, uint32 index, string calldata language)
        external
        pure
        returns (uint256 privateKey);

    /// Derive a private key from a provided mnemonic string (or mnemonic file path) in the specified language
    /// at `{derivationPath}{index}`.
    function deriveKey(string calldata mnemonic, string calldata derivationPath, uint32 index, string calldata language)
        external
        pure
        returns (uint256 privateKey);

    /// Derives secp256r1 public key from the provided `privateKey`.
    function publicKeyP256(uint256 privateKey) external pure returns (uint256 publicKeyX, uint256 publicKeyY);

    /// Adds a private key to the local forge wallet and returns the address.
    function rememberKey(uint256 privateKey) external returns (address keyAddr);

    /// Derive a set number of wallets from a mnemonic at the derivation path `m/44'/60'/0'/0/{0..count}`.
    /// The respective private keys are saved to the local forge wallet for later use and their addresses are returned.
    function rememberKeys(string calldata mnemonic, string calldata derivationPath, uint32 count)
        external
        returns (address[] memory keyAddrs);

    /// Derive a set number of wallets from a mnemonic in the specified language at the derivation path `m/44'/60'/0'/0/{0..count}`.
    /// The respective private keys are saved to the local forge wallet for later use and their addresses are returned.
    function rememberKeys(
        string calldata mnemonic,
        string calldata derivationPath,
        string calldata language,
        uint32 count
    ) external returns (address[] memory keyAddrs);

    /// Signs data with a `Wallet`.
    /// Returns a compact signature (`r`, `vs`) as per EIP-2098, where `vs` encodes both the
    /// signature's `s` value, and the recovery id `v` in a single bytes32.
    /// This format reduces the signature size from 65 to 64 bytes.
    function signCompact(Wallet calldata wallet, bytes32 digest) external returns (bytes32 r, bytes32 vs);

    /// Signs `digest` with `privateKey` using the secp256k1 curve.
    /// Returns a compact signature (`r`, `vs`) as per EIP-2098, where `vs` encodes both the
    /// signature's `s` value, and the recovery id `v` in a single bytes32.
    /// This format reduces the signature size from 65 to 64 bytes.
    function signCompact(uint256 privateKey, bytes32 digest) external pure returns (bytes32 r, bytes32 vs);

    /// Signs `digest` with signer provided to script using the secp256k1 curve.
    /// Returns a compact signature (`r`, `vs`) as per EIP-2098, where `vs` encodes both the
    /// signature's `s` value, and the recovery id `v` in a single bytes32.
    /// This format reduces the signature size from 65 to 64 bytes.
    /// If `--sender` is provided, the signer with provided address is used, otherwise,
    /// if exactly one signer is provided to the script, that signer is used.
    /// Raises error if signer passed through `--sender` does not match any unlocked signers or
    /// if `--sender` is not provided and not exactly one signer is passed to the script.
    function signCompact(bytes32 digest) external pure returns (bytes32 r, bytes32 vs);

    /// Signs `digest` with signer provided to script using the secp256k1 curve.
    /// Returns a compact signature (`r`, `vs`) as per EIP-2098, where `vs` encodes both the
    /// signature's `s` value, and the recovery id `v` in a single bytes32.
    /// This format reduces the signature size from 65 to 64 bytes.
    /// Raises error if none of the signers passed into the script have provided address.
    function signCompact(address signer, bytes32 digest) external pure returns (bytes32 r, bytes32 vs);

    /// Signs `digest` with `privateKey` using the secp256r1 curve.
    function signP256(uint256 privateKey, bytes32 digest) external pure returns (bytes32 r, bytes32 s);

    /// Signs data with a `Wallet`.
    function sign(Wallet calldata wallet, bytes32 digest) external returns (uint8 v, bytes32 r, bytes32 s);

    /// Signs `digest` with `privateKey` using the secp256k1 curve.
    function sign(uint256 privateKey, bytes32 digest) external pure returns (uint8 v, bytes32 r, bytes32 s);

    /// Signs `digest` with signer provided to script using the secp256k1 curve.
    /// If `--sender` is provided, the signer with provided address is used, otherwise,
    /// if exactly one signer is provided to the script, that signer is used.
    /// Raises error if signer passed through `--sender` does not match any unlocked signers or
    /// if `--sender` is not provided and not exactly one signer is passed to the script.
    function sign(bytes32 digest) external pure returns (uint8 v, bytes32 r, bytes32 s);

    /// Signs `digest` with signer provided to script using the secp256k1 curve.
    /// Raises error if none of the signers passed into the script have provided address.
    function sign(address signer, bytes32 digest) external pure returns (uint8 v, bytes32 r, bytes32 s);

    // ======== Environment ========

    /// Gets the environment variable `name` and parses it as `address`.
    /// Reverts if the variable was not found or could not be parsed.
    function envAddress(string calldata name) external view returns (address value);

    /// Gets the environment variable `name` and parses it as an array of `address`, delimited by `delim`.
    /// Reverts if the variable was not found or could not be parsed.
    function envAddress(string calldata name, string calldata delim) external view returns (address[] memory value);

    /// Gets the environment variable `name` and parses it as `bool`.
    /// Reverts if the variable was not found or could not be parsed.
    function envBool(string calldata name) external view returns (bool value);

    /// Gets the environment variable `name` and parses it as an array of `bool`, delimited by `delim`.
    /// Reverts if the variable was not found or could not be parsed.
    function envBool(string calldata name, string calldata delim) external view returns (bool[] memory value);

    /// Gets the environment variable `name` and parses it as `bytes32`.
    /// Reverts if the variable was not found or could not be parsed.
    function envBytes32(string calldata name) external view returns (bytes32 value);

    /// Gets the environment variable `name` and parses it as an array of `bytes32`, delimited by `delim`.
    /// Reverts if the variable was not found or could not be parsed.
    function envBytes32(string calldata name, string calldata delim) external view returns (bytes32[] memory value);

    /// Gets the environment variable `name` and parses it as `bytes`.
    /// Reverts if the variable was not found or could not be parsed.
    function envBytes(string calldata name) external view returns (bytes memory value);

    /// Gets the environment variable `name` and parses it as an array of `bytes`, delimited by `delim`.
    /// Reverts if the variable was not found or could not be parsed.
    function envBytes(string calldata name, string calldata delim) external view returns (bytes[] memory value);

    /// Gets the environment variable `name` and returns true if it exists, else returns false.
    function envExists(string calldata name) external view returns (bool result);

    /// Gets the environment variable `name` and parses it as `int256`.
    /// Reverts if the variable was not found or could not be parsed.
    function envInt(string calldata name) external view returns (int256 value);

    /// Gets the environment variable `name` and parses it as an array of `int256`, delimited by `delim`.
    /// Reverts if the variable was not found or could not be parsed.
    function envInt(string calldata name, string calldata delim) external view returns (int256[] memory value);

    /// Gets the environment variable `name` and parses it as `bool`.
    /// Reverts if the variable could not be parsed.
    /// Returns `defaultValue` if the variable was not found.
    function envOr(string calldata name, bool defaultValue) external view returns (bool value);

    /// Gets the environment variable `name` and parses it as `uint256`.
    /// Reverts if the variable could not be parsed.
    /// Returns `defaultValue` if the variable was not found.
    function envOr(string calldata name, uint256 defaultValue) external view returns (uint256 value);

    /// Gets the environment variable `name` and parses it as an array of `address`, delimited by `delim`.
    /// Reverts if the variable could not be parsed.
    /// Returns `defaultValue` if the variable was not found.
    function envOr(string calldata name, string calldata delim, address[] calldata defaultValue)
        external
        view
        returns (address[] memory value);

    /// Gets the environment variable `name` and parses it as an array of `bytes32`, delimited by `delim`.
    /// Reverts if the variable could not be parsed.
    /// Returns `defaultValue` if the variable was not found.
    function envOr(string calldata name, string calldata delim, bytes32[] calldata defaultValue)
        external
        view
        returns (bytes32[] memory value);

    /// Gets the environment variable `name` and parses it as an array of `string`, delimited by `delim`.
    /// Reverts if the variable could not be parsed.
    /// Returns `defaultValue` if the variable was not found.
    function envOr(string calldata name, string calldata delim, string[] calldata defaultValue)
        external
        view
        returns (string[] memory value);

    /// Gets the environment variable `name` and parses it as an array of `bytes`, delimited by `delim`.
    /// Reverts if the variable could not be parsed.
    /// Returns `defaultValue` if the variable was not found.
    function envOr(string calldata name, string calldata delim, bytes[] calldata defaultValue)
        external
        view
        returns (bytes[] memory value);

    /// Gets the environment variable `name` and parses it as `int256`.
    /// Reverts if the variable could not be parsed.
    /// Returns `defaultValue` if the variable was not found.
    function envOr(string calldata name, int256 defaultValue) external view returns (int256 value);

    /// Gets the environment variable `name` and parses it as `address`.
    /// Reverts if the variable could not be parsed.
    /// Returns `defaultValue` if the variable was not found.
    function envOr(string calldata name, address defaultValue) external view returns (address value);

    /// Gets the environment variable `name` and parses it as `bytes32`.
    /// Reverts if the variable could not be parsed.
    /// Returns `defaultValue` if the variable was not found.
    function envOr(string calldata name, bytes32 defaultValue) external view returns (bytes32 value);

    /// Gets the environment variable `name` and parses it as `string`.
    /// Reverts if the variable could not be parsed.
    /// Returns `defaultValue` if the variable was not found.
    function envOr(string calldata name, string calldata defaultValue) external view returns (string memory value);

    /// Gets the environment variable `name` and parses it as `bytes`.
    /// Reverts if the variable could not be parsed.
    /// Returns `defaultValue` if the variable was not found.
    function envOr(string calldata name, bytes calldata defaultValue) external view returns (bytes memory value);

    /// Gets the environment variable `name` and parses it as an array of `bool`, delimited by `delim`.
    /// Reverts if the variable could not be parsed.
    /// Returns `defaultValue` if the variable was not found.
    function envOr(string calldata name, string calldata delim, bool[] calldata defaultValue)
        external
        view
        returns (bool[] memory value);

    /// Gets the environment variable `name` and parses it as an array of `uint256`, delimited by `delim`.
    /// Reverts if the variable could not be parsed.
    /// Returns `defaultValue` if the variable was not found.
    function envOr(string calldata name, string calldata delim, uint256[] calldata defaultValue)
        external
        view
        returns (uint256[] memory value);

    /// Gets the environment variable `name` and parses it as an array of `int256`, delimited by `delim`.
    /// Reverts if the variable could not be parsed.
    /// Returns `defaultValue` if the variable was not found.
    function envOr(string calldata name, string calldata delim, int256[] calldata defaultValue)
        external
        view
        returns (int256[] memory value);

    /// Gets the environment variable `name` and parses it as `string`.
    /// Reverts if the variable was not found or could not be parsed.
    function envString(string calldata name) external view returns (string memory value);

    /// Gets the environment variable `name` and parses it as an array of `string`, delimited by `delim`.
    /// Reverts if the variable was not found or could not be parsed.
    function envString(string calldata name, string calldata delim) external view returns (string[] memory value);

    /// Gets the environment variable `name` and parses it as `uint256`.
    /// Reverts if the variable was not found or could not be parsed.
    function envUint(string calldata name) external view returns (uint256 value);

    /// Gets the environment variable `name` and parses it as an array of `uint256`, delimited by `delim`.
    /// Reverts if the variable was not found or could not be parsed.
    function envUint(string calldata name, string calldata delim) external view returns (uint256[] memory value);

    /// Returns true if `forge` command was executed in given context.
    function isContext(ForgeContext context) external view returns (bool result);

    /// Resolves the env variable placeholders of a given input string.
    function resolveEnv(string calldata input) external returns (string memory);

    /// Sets environment variables.
    function setEnv(string calldata name, string calldata value) external;

    // ======== EVM ========

    /// Gets all accessed reads and write slot from a `vm.record` session, for a given address.
    function accesses(address target) external view returns (bytes32[] memory readSlots, bytes32[] memory writeSlots);

    /// Gets the address for a given private key.
    function addr(uint256 privateKey) external pure returns (address keyAddr);

    /// Gets all the logs according to specified filter.
    function eth_getLogs(uint256 fromBlock, uint256 toBlock, address target, bytes32[] calldata topics)
        external
        view
        returns (EthGetLogs[] memory logs);

    /// Gets the current `block.blobbasefee`.
    /// You should use this instead of `block.blobbasefee` if you use `vm.blobBaseFee`, as `block.blobbasefee` is assumed to be constant across a transaction,
    /// and as a result will get optimized out by the compiler.
    /// See https://github.com/foundry-rs/foundry/issues/6180
    function getBlobBaseFee() external view returns (uint256 blobBaseFee);

    /// Gets the current `block.number`.
    /// You should use this instead of `block.number` if you use `vm.roll`, as `block.number` is assumed to be constant across a transaction,
    /// and as a result will get optimized out by the compiler.
    /// See https://github.com/foundry-rs/foundry/issues/6180
    function getBlockNumber() external view returns (uint256 height);

    /// Gets the current `block.timestamp`.
    /// You should use this instead of `block.timestamp` if you use `vm.warp`, as `block.timestamp` is assumed to be constant across a transaction,
    /// and as a result will get optimized out by the compiler.
    /// See https://github.com/foundry-rs/foundry/issues/6180
    function getBlockTimestamp() external view returns (uint256 timestamp);

    /// Gets the current `block.chainid` of the currently selected environment.
    /// You should use this instead of `block.chainid` if you use `vm.selectFork` or `vm.createSelectFork`, as `block.chainid` could be assumed
    /// to be constant across a transaction, and as a result will get optimized out by the compiler.
    /// See https://github.com/foundry-rs/foundry/issues/6180
    function getChainId() external view returns (uint256 blockChainId);

    /// Gets the map key and parent of a mapping at a given slot, for a given address.
    function getMappingKeyAndParentOf(address target, bytes32 elementSlot)
        external
        view
        returns (bool found, bytes32 key, bytes32 parent);

    /// Gets the number of elements in the mapping at the given slot, for a given address.
    function getMappingLength(address target, bytes32 mappingSlot) external view returns (uint256 length);

    /// Gets the elements at index idx of the mapping at the given slot, for a given address. The
    /// index must be less than the length of the mapping (i.e. the number of keys in the mapping).
    function getMappingSlotAt(address target, bytes32 mappingSlot, uint256 idx) external view returns (bytes32 value);

    /// Gets the nonce of an account.
    function getNonce(address account) external view returns (uint64 nonce);

    /// Get the nonce of a `Wallet`.
    function getNonce(Wallet calldata wallet) external view returns (uint64 nonce);

    /// Gets the RLP encoded block header for a given block number.
    /// Returns the block header in the same format as `cast block <block_number> --raw`.
    function getRawBlockHeader(uint256 blockNumber) external view returns (bytes memory rlpHeader);

    /// Gets all the recorded logs.
    function getRecordedLogs() external view returns (Log[] memory logs);

    /// Returns state diffs from current `vm.startStateDiffRecording` session.
    function getStateDiff() external view returns (string memory diff);

    /// Returns state diffs from current `vm.startStateDiffRecording` session, in json format.
    function getStateDiffJson() external view returns (string memory diff);

    /// Returns an array of `StorageAccess` from current `vm.stateStateDiffRecording` session
    function getStorageAccesses() external view returns (StorageAccess[] memory storageAccesses);

    /// Gets the gas used in the last call from the callee perspective.
    function lastCallGas() external view returns (Gas memory gas);

    /// Loads a storage slot from an address.
    function load(address target, bytes32 slot) external view returns (bytes32 data);

    /// Pauses gas metering (i.e. gas usage is not counted). Noop if already paused.
    function pauseGasMetering() external;

    /// Records all storage reads and writes. Use `accesses` to get the recorded data.
    /// Subsequent calls to `record` will clear the previous data.
    function record() external;

    /// Record all the transaction logs.
    function recordLogs() external;

    /// Reset gas metering (i.e. gas usage is set to gas limit).
    function resetGasMetering() external;

    /// Resumes gas metering (i.e. gas usage is counted again). Noop if already on.
    function resumeGasMetering() external;

    /// Performs an Ethereum JSON-RPC request to the current fork URL.
    function rpc(string calldata method, string calldata params) external returns (bytes memory data);

    /// Performs an Ethereum JSON-RPC request to the given endpoint.
    function rpc(string calldata urlOrAlias, string calldata method, string calldata params)
        external
        returns (bytes memory data);

    /// Records the debug trace during the run.
    function startDebugTraceRecording() external;

    /// Starts recording all map SSTOREs for later retrieval.
    function startMappingRecording() external;

    /// Record all account accesses as part of CREATE, CALL or SELFDESTRUCT opcodes in order,
    /// along with the context of the calls
    function startStateDiffRecording() external;

    /// Stop debug trace recording and returns the recorded debug trace.
    function stopAndReturnDebugTraceRecording() external returns (DebugStep[] memory step);

    /// Returns an ordered array of all account accesses from a `vm.startStateDiffRecording` session.
    function stopAndReturnStateDiff() external returns (AccountAccess[] memory accountAccesses);

    /// Stops recording all map SSTOREs for later retrieval and clears the recorded data.
    function stopMappingRecording() external;

    /// Stops recording storage reads and writes.
    function stopRecord() external;

    // ======== Filesystem ========

    /// Closes file for reading, resetting the offset and allowing to read it from beginning with readLine.
    /// `path` is relative to the project root.
    function closeFile(string calldata path) external;

    /// Copies the contents of one file to another. This function will **overwrite** the contents of `to`.
    /// On success, the total number of bytes copied is returned and it is equal to the length of the `to` file as reported by `metadata`.
    /// Both `from` and `to` are relative to the project root.
    function copyFile(string calldata from, string calldata to) external returns (uint64 copied);

    /// Creates a new, empty directory at the provided path.
    /// This cheatcode will revert in the following situations, but is not limited to just these cases:
    /// - User lacks permissions to modify `path`.
    /// - A parent of the given path doesn't exist and `recursive` is false.
    /// - `path` already exists and `recursive` is false.
    /// `path` is relative to the project root.
    function createDir(string calldata path, bool recursive) external;

    /// Deploys a contract from an artifact file. Takes in the relative path to the json file or the path to the
    /// artifact in the form of <path>:<contract>:<version> where <contract> and <version> parts are optional.
    function deployCode(string calldata artifactPath) external returns (address deployedAddress);

    /// Deploys a contract from an artifact file. Takes in the relative path to the json file or the path to the
    /// artifact in the form of <path>:<contract>:<version> where <contract> and <version> parts are optional.
    /// Additionally accepts abi-encoded constructor arguments.
    function deployCode(string calldata artifactPath, bytes calldata constructorArgs)
        external
        returns (address deployedAddress);

    /// Deploys a contract from an artifact file. Takes in the relative path to the json file or the path to the
    /// artifact in the form of <path>:<contract>:<version> where <contract> and <version> parts are optional.
    /// Additionally accepts `msg.value`.
    function deployCode(string calldata artifactPath, uint256 value) external returns (address deployedAddress);

    /// Deploys a contract from an artifact file. Takes in the relative path to the json file or the path to the
    /// artifact in the form of <path>:<contract>:<version> where <contract> and <version> parts are optional.
    /// Additionally accepts abi-encoded constructor arguments and `msg.value`.
    function deployCode(string calldata artifactPath, bytes calldata constructorArgs, uint256 value)
        external
        returns (address deployedAddress);

    /// Deploys a contract from an artifact file, using the CREATE2 salt. Takes in the relative path to the json file or the path to the
    /// artifact in the form of <path>:<contract>:<version> where <contract> and <version> parts are optional.
    function deployCode(string calldata artifactPath, bytes32 salt) external returns (address deployedAddress);

    /// Deploys a contract from an artifact file, using the CREATE2 salt. Takes in the relative path to the json file or the path to the
    /// artifact in the form of <path>:<contract>:<version> where <contract> and <version> parts are optional.
    /// Additionally accepts abi-encoded constructor arguments.
    function deployCode(string calldata artifactPath, bytes calldata constructorArgs, bytes32 salt)
        external
        returns (address deployedAddress);

    /// Deploys a contract from an artifact file, using the CREATE2 salt. Takes in the relative path to the json file or the path to the
    /// artifact in the form of <path>:<contract>:<version> where <contract> and <version> parts are optional.
    /// Additionally accepts `msg.value`.
    function deployCode(string calldata artifactPath, uint256 value, bytes32 salt)
        external
        returns (address deployedAddress);

    /// Deploys a contract from an artifact file, using the CREATE2 salt. Takes in the relative path to the json file or the path to the
    /// artifact in the form of <path>:<contract>:<version> where <contract> and <version> parts are optional.
    /// Additionally accepts abi-encoded constructor arguments and `msg.value`.
    function deployCode(string calldata artifactPath, bytes calldata constructorArgs, uint256 value, bytes32 salt)
        external
        returns (address deployedAddress);

    /// Returns true if the given path points to an existing entity, else returns false.
    function exists(string calldata path) external view returns (bool result);

    /// Performs a foreign function call via the terminal.
    function ffi(string[] calldata commandInput) external returns (bytes memory result);

    /// Given a path, query the file system to get information about a file, directory, etc.
    function fsMetadata(string calldata path) external view returns (FsMetadata memory metadata);

    /// Gets the artifact path from code (aka. creation code).
    function getArtifactPathByCode(bytes calldata code) external view returns (string memory path);

    /// Gets the artifact path from deployed code (aka. runtime code).
    function getArtifactPathByDeployedCode(bytes calldata deployedCode) external view returns (string memory path);

    /// Returns the most recent broadcast for the given contract on `chainId` matching `txType`.
    /// For example:
    /// The most recent deployment can be fetched by passing `txType` as `CREATE` or `CREATE2`.
    /// The most recent call can be fetched by passing `txType` as `CALL`.
    function getBroadcast(string calldata contractName, uint64 chainId, BroadcastTxType txType)
        external
        view
        returns (BroadcastTxSummary memory);

    /// Returns all broadcasts for the given contract on `chainId` with the specified `txType`.
    /// Sorted such that the most recent broadcast is the first element, and the oldest is the last. i.e descending order of BroadcastTxSummary.blockNumber.
    function getBroadcasts(string calldata contractName, uint64 chainId, BroadcastTxType txType)
        external
        view
        returns (BroadcastTxSummary[] memory);

    /// Returns all broadcasts for the given contract on `chainId`.
    /// Sorted such that the most recent broadcast is the first element, and the oldest is the last. i.e descending order of BroadcastTxSummary.blockNumber.
    function getBroadcasts(string calldata contractName, uint64 chainId)
        external
        view
        returns (BroadcastTxSummary[] memory);

    /// Gets the creation bytecode from an artifact file. Takes in the relative path to the json file or the path to the
    /// artifact in the form of <path>:<contract>:<version> where <contract> and <version> parts are optional.
    function getCode(string calldata artifactPath) external view returns (bytes memory creationBytecode);

    /// Gets the deployed bytecode from an artifact file. Takes in the relative path to the json file or the path to the
    /// artifact in the form of <path>:<contract>:<version> where <contract> and <version> parts are optional.
    function getDeployedCode(string calldata artifactPath) external view returns (bytes memory runtimeBytecode);

    /// Returns the most recent deployment for the current `chainId`.
    function getDeployment(string calldata contractName) external view returns (address deployedAddress);

    /// Returns the most recent deployment for the given contract on `chainId`
    function getDeployment(string calldata contractName, uint64 chainId) external view returns (address deployedAddress);

    /// Returns all deployments for the given contract on `chainId`
    /// Sorted in descending order of deployment time i.e descending order of BroadcastTxSummary.blockNumber.
    /// The most recent deployment is the first element, and the oldest is the last.
    function getDeployments(string calldata contractName, uint64 chainId)
        external
        view
        returns (address[] memory deployedAddresses);

    /// Returns true if the path exists on disk and is pointing at a directory, else returns false.
    function isDir(string calldata path) external view returns (bool result);

    /// Returns true if the path exists on disk and is pointing at a regular file, else returns false.
    function isFile(string calldata path) external view returns (bool result);

    /// Get the path of the current project root.
    function projectRoot() external view returns (string memory path);

    /// Prompts the user for a string value in the terminal.
    function prompt(string calldata promptText) external returns (string memory input);

    /// Prompts the user for an address in the terminal.
    function promptAddress(string calldata promptText) external returns (address);

    /// Prompts the user for a hidden string value in the terminal.
    function promptSecret(string calldata promptText) external returns (string memory input);

    /// Prompts the user for hidden uint256 in the terminal (usually pk).
    function promptSecretUint(string calldata promptText) external returns (uint256);

    /// Prompts the user for uint256 in the terminal.
    function promptUint(string calldata promptText) external returns (uint256);

    /// Reads the directory at the given path recursively, up to `maxDepth`.
    /// `maxDepth` defaults to 1, meaning only the direct children of the given directory will be returned.
    /// Follows symbolic links if `followLinks` is true.
    function readDir(string calldata path) external view returns (DirEntry[] memory entries);

    /// See `readDir(string)`.
    function readDir(string calldata path, uint64 maxDepth) external view returns (DirEntry[] memory entries);

    /// See `readDir(string)`.
    function readDir(string calldata path, uint64 maxDepth, bool followLinks)
        external
        view
        returns (DirEntry[] memory entries);

    /// Reads the entire content of file to string. `path` is relative to the project root.
    function readFile(string calldata path) external view returns (string memory data);

    /// Reads the entire content of file as binary. `path` is relative to the project root.
    function readFileBinary(string calldata path) external view returns (bytes memory data);

    /// Reads next line of file to string.
    function readLine(string calldata path) external view returns (string memory line);

    /// Reads a symbolic link, returning the path that the link points to.
    /// This cheatcode will revert in the following situations, but is not limited to just these cases:
    /// - `path` is not a symbolic link.
    /// - `path` does not exist.
    function readLink(string calldata linkPath) external view returns (string memory targetPath);

    /// Removes a directory at the provided path.
    /// This cheatcode will revert in the following situations, but is not limited to just these cases:
    /// - `path` doesn't exist.
    /// - `path` isn't a directory.
    /// - User lacks permissions to modify `path`.
    /// - The directory is not empty and `recursive` is false.
    /// `path` is relative to the project root.
    function removeDir(string calldata path, bool recursive) external;

    /// Removes a file from the filesystem.
    /// This cheatcode will revert in the following situations, but is not limited to just these cases:
    /// - `path` points to a directory.
    /// - The file doesn't exist.
    /// - The user lacks permissions to remove the file.
    /// `path` is relative to the project root.
    function removeFile(string calldata path) external;

    /// Performs a foreign function call via terminal and returns the exit code, stdout, and stderr.
    function tryFfi(string[] calldata commandInput) external returns (FfiResult memory result);

    /// Returns the time since unix epoch in milliseconds.
    function unixTime() external view returns (uint256 milliseconds);

    /// Writes data to file, creating a file if it does not exist, and entirely replacing its contents if it does.
    /// `path` is relative to the project root.
    function writeFile(string calldata path, string calldata data) external;

    /// Writes binary data to a file, creating a file if it does not exist, and entirely replacing its contents if it does.
    /// `path` is relative to the project root.
    function writeFileBinary(string calldata path, bytes calldata data) external;

    /// Writes line to file, creating a file if it does not exist.
    /// `path` is relative to the project root.
    function writeLine(string calldata path, string calldata data) external;

    // ======== JSON ========

    /// Checks if `key` exists in a JSON object.
    function keyExistsJson(string calldata json, string calldata key) external view returns (bool);

    /// Parses a string of JSON data at `key` and coerces it to `address`.
    function parseJsonAddress(string calldata json, string calldata key) external pure returns (address);

    /// Parses a string of JSON data at `key` and coerces it to `address[]`.
    function parseJsonAddressArray(string calldata json, string calldata key) external pure returns (address[] memory);

    /// Parses a string of JSON data at `key` and coerces it to `bool`.
    function parseJsonBool(string calldata json, string calldata key) external pure returns (bool);

    /// Parses a string of JSON data at `key` and coerces it to `bool[]`.
    function parseJsonBoolArray(string calldata json, string calldata key) external pure returns (bool[] memory);

    /// Parses a string of JSON data at `key` and coerces it to `bytes`.
    function parseJsonBytes(string calldata json, string calldata key) external pure returns (bytes memory);

    /// Parses a string of JSON data at `key` and coerces it to `bytes32`.
    function parseJsonBytes32(string calldata json, string calldata key) external pure returns (bytes32);

    /// Parses a string of JSON data at `key` and coerces it to `bytes32[]`.
    function parseJsonBytes32Array(string calldata json, string calldata key) external pure returns (bytes32[] memory);

    /// Parses a string of JSON data at `key` and coerces it to `bytes[]`.
    function parseJsonBytesArray(string calldata json, string calldata key) external pure returns (bytes[] memory);

    /// Parses a string of JSON data at `key` and coerces it to `int256`.
    function parseJsonInt(string calldata json, string calldata key) external pure returns (int256);

    /// Parses a string of JSON data at `key` and coerces it to `int256[]`.
    function parseJsonIntArray(string calldata json, string calldata key) external pure returns (int256[] memory);

    /// Returns an array of all the keys in a JSON object.
    function parseJsonKeys(string calldata json, string calldata key) external pure returns (string[] memory keys);

    /// Parses a string of JSON data at `key` and coerces it to `string`.
    function parseJsonString(string calldata json, string calldata key) external pure returns (string memory);

    /// Parses a string of JSON data at `key` and coerces it to `string[]`.
    function parseJsonStringArray(string calldata json, string calldata key) external pure returns (string[] memory);

    /// Parses a string of JSON data at `key` and coerces it to type array corresponding to `typeDescription`.
    function parseJsonTypeArray(string calldata json, string calldata key, string calldata typeDescription)
        external
        pure
        returns (bytes memory);

    /// Parses a string of JSON data and coerces it to type corresponding to `typeDescription`.
    function parseJsonType(string calldata json, string calldata typeDescription) external pure returns (bytes memory);

    /// Parses a string of JSON data at `key` and coerces it to type corresponding to `typeDescription`.
    function parseJsonType(string calldata json, string calldata key, string calldata typeDescription)
        external
        pure
        returns (bytes memory);

    /// Parses a string of JSON data at `key` and coerces it to `uint256`.
    function parseJsonUint(string calldata json, string calldata key) external pure returns (uint256);

    /// Parses a string of JSON data at `key` and coerces it to `uint256[]`.
    function parseJsonUintArray(string calldata json, string calldata key) external pure returns (uint256[] memory);

    /// ABI-encodes a JSON object.
    function parseJson(string calldata json) external pure returns (bytes memory abiEncodedData);

    /// ABI-encodes a JSON object at `key`.
    function parseJson(string calldata json, string calldata key) external pure returns (bytes memory abiEncodedData);

    /// See `serializeJson`.
    function serializeAddress(string calldata objectKey, string calldata valueKey, address value)
        external
        returns (string memory json);

    /// See `serializeJson`.
    function serializeAddress(string calldata objectKey, string calldata valueKey, address[] calldata values)
        external
        returns (string memory json);

    /// See `serializeJson`.
    function serializeBool(string calldata objectKey, string calldata valueKey, bool value)
        external
        returns (string memory json);

    /// See `serializeJson`.
    function serializeBool(string calldata objectKey, string calldata valueKey, bool[] calldata values)
        external
        returns (string memory json);

    /// See `serializeJson`.
    function serializeBytes32(string calldata objectKey, string calldata valueKey, bytes32 value)
        external
        returns (string memory json);

    /// See `serializeJson`.
    function serializeBytes32(string calldata objectKey, string calldata valueKey, bytes32[] calldata values)
        external
        returns (string memory json);

    /// See `serializeJson`.
    function serializeBytes(string calldata objectKey, string calldata valueKey, bytes calldata value)
        external
        returns (string memory json);

    /// See `serializeJson`.
    function serializeBytes(string calldata objectKey, string calldata valueKey, bytes[] calldata values)
        external
        returns (string memory json);

    /// See `serializeJson`.
    function serializeInt(string calldata objectKey, string calldata valueKey, int256 value)
        external
        returns (string memory json);

    /// See `serializeJson`.
    function serializeInt(string calldata objectKey, string calldata valueKey, int256[] calldata values)
        external
        returns (string memory json);

    /// Serializes a key and value to a JSON object stored in-memory that can be later written to a file.
    /// Returns the stringified version of the specific JSON file up to that moment.
    function serializeJson(string calldata objectKey, string calldata value) external returns (string memory json);

    /// See `serializeJson`.
    function serializeJsonType(string calldata typeDescription, bytes calldata value)
        external
        pure
        returns (string memory json);

    /// See `serializeJson`.
    function serializeJsonType(
        string calldata objectKey,
        string calldata valueKey,
        string calldata typeDescription,
        bytes calldata value
    ) external returns (string memory json);

    /// See `serializeJson`.
    function serializeString(string calldata objectKey, string calldata valueKey, string calldata value)
        external
        returns (string memory json);

    /// See `serializeJson`.
    function serializeString(string calldata objectKey, string calldata valueKey, string[] calldata values)
        external
        returns (string memory json);

    /// See `serializeJson`.
    function serializeUintToHex(string calldata objectKey, string calldata valueKey, uint256 value)
        external
        returns (string memory json);

    /// See `serializeJson`.
    function serializeUint(string calldata objectKey, string calldata valueKey, uint256 value)
        external
        returns (string memory json);

    /// See `serializeJson`.
    function serializeUint(string calldata objectKey, string calldata valueKey, uint256[] calldata values)
        external
        returns (string memory json);

    /// Write a serialized JSON object to a file. If the file exists, it will be overwritten.
    function writeJson(string calldata json, string calldata path) external;

    /// Write a serialized JSON object to an **existing** JSON file, replacing a value with key = <value_key.>
    /// This is useful to replace a specific value of a JSON file, without having to parse the entire thing.
    /// This cheatcode will create new keys if they didn't previously exist.
    function writeJson(string calldata json, string calldata path, string calldata valueKey) external;

    /// Checks if `key` exists in a JSON object
    /// `keyExists` is being deprecated in favor of `keyExistsJson`. It will be removed in future versions.
    function keyExists(string calldata json, string calldata key) external view returns (bool);

    // ======== Scripting ========

    /// Attach an EIP-4844 blob to the next call
    function attachBlob(bytes calldata blob) external;

    /// Designate the next call as an EIP-7702 transaction
    function attachDelegation(SignedDelegation calldata signedDelegation) external;

    /// Designate the next call as an EIP-7702 transaction, with optional cross-chain validity.
    function attachDelegation(SignedDelegation calldata signedDelegation, bool crossChain) external;

    /// Takes a signed transaction and broadcasts it to the network.
    function broadcastRawTransaction(bytes calldata data) external;

    /// Has the next call (at this call depth only) create transactions that can later be signed and sent onchain.
    /// Broadcasting address is determined by checking the following in order:
    /// 1. If `--sender` argument was provided, that address is used.
    /// 2. If exactly one signer (e.g. private key, hw wallet, keystore) is set when `forge broadcast` is invoked, that signer is used.
    /// 3. Otherwise, default foundry sender (1804c8AB1F12E6bbf3894d4083f33e07309d1f38) is used.
    function broadcast() external;

    /// Has the next call (at this call depth only) create a transaction with the address provided
    /// as the sender that can later be signed and sent onchain.
    function broadcast(address signer) external;

    /// Has the next call (at this call depth only) create a transaction with the private key
    /// provided as the sender that can later be signed and sent onchain.
    function broadcast(uint256 privateKey) external;

    /// Returns addresses of available unlocked wallets in the script environment.
    function getWallets() external view returns (address[] memory wallets);

    /// Sign an EIP-7702 authorization and designate the next call as an EIP-7702 transaction
    function signAndAttachDelegation(address implementation, uint256 privateKey)
        external
        returns (SignedDelegation memory signedDelegation);

    /// Sign an EIP-7702 authorization and designate the next call as an EIP-7702 transaction for specific nonce
    function signAndAttachDelegation(address implementation, uint256 privateKey, uint64 nonce)
        external
        returns (SignedDelegation memory signedDelegation);

    /// Sign an EIP-7702 authorization and designate the next call as an EIP-7702 transaction, with optional cross-chain validity.
    function signAndAttachDelegation(address implementation, uint256 privateKey, bool crossChain)
        external
        returns (SignedDelegation memory signedDelegation);

    /// Sign an EIP-7702 authorization for delegation
    function signDelegation(address implementation, uint256 privateKey)
        external
        returns (SignedDelegation memory signedDelegation);

    /// Sign an EIP-7702 authorization for delegation for specific nonce
    function signDelegation(address implementation, uint256 privateKey, uint64 nonce)
        external
        returns (SignedDelegation memory signedDelegation);

    /// Sign an EIP-7702 authorization for delegation, with optional cross-chain validity.
    function signDelegation(address implementation, uint256 privateKey, bool crossChain)
        external
        returns (SignedDelegation memory signedDelegation);

    /// Has all subsequent calls (at this call depth only) create transactions that can later be signed and sent onchain.
    /// Broadcasting address is determined by checking the following in order:
    /// 1. If `--sender` argument was provided, that address is used.
    /// 2. If exactly one signer (e.g. private key, hw wallet, keystore) is set when `forge broadcast` is invoked, that signer is used.
    /// 3. Otherwise, default foundry sender (1804c8AB1F12E6bbf3894d4083f33e07309d1f38) is used.
    function startBroadcast() external;

    /// Has all subsequent calls (at this call depth only) create transactions with the address
    /// provided that can later be signed and sent onchain.
    function startBroadcast(address signer) external;

    /// Has all subsequent calls (at this call depth only) create transactions with the private key
    /// provided that can later be signed and sent onchain.
    function startBroadcast(uint256 privateKey) external;

    /// Stops collecting onchain transactions.
    function stopBroadcast() external;

    // ======== String ========

    /// Returns true if `search` is found in `subject`, false otherwise.
    function contains(string calldata subject, string calldata search) external pure returns (bool result);

    /// Returns the index of the first occurrence of a `key` in an `input` string.
    /// Returns `NOT_FOUND` (i.e. `type(uint256).max`) if the `key` is not found.
    /// Returns 0 in case of an empty `key`.
    function indexOf(string calldata input, string calldata key) external pure returns (uint256);

    /// Parses the given `string` into an `address`.
    function parseAddress(string calldata stringifiedValue) external pure returns (address parsedValue);

    /// Parses the given `string` into a `bool`.
    function parseBool(string calldata stringifiedValue) external pure returns (bool parsedValue);

    /// Parses the given `string` into `bytes`.
    function parseBytes(string calldata stringifiedValue) external pure returns (bytes memory parsedValue);

    /// Parses the given `string` into a `bytes32`.
    function parseBytes32(string calldata stringifiedValue) external pure returns (bytes32 parsedValue);

    /// Parses the given `string` into a `int256`.
    function parseInt(string calldata stringifiedValue) external pure returns (int256 parsedValue);

    /// Parses the given `string` into a `uint256`.
    function parseUint(string calldata stringifiedValue) external pure returns (uint256 parsedValue);

    /// Replaces occurrences of `from` in the given `string` with `to`.
    function replace(string calldata input, string calldata from, string calldata to)
        external
        pure
        returns (string memory output);

    /// Splits the given `string` into an array of strings divided by the `delimiter`.
    function split(string calldata input, string calldata delimiter) external pure returns (string[] memory outputs);

    /// Converts the given `string` value to Lowercase.
    function toLowercase(string calldata input) external pure returns (string memory output);

    /// Converts the given value to a `string`.
    function toString(address value) external pure returns (string memory stringifiedValue);

    /// Converts the given value to a `string`.
    function toString(bytes calldata value) external pure returns (string memory stringifiedValue);

    /// Converts the given value to a `string`.
    function toString(bytes32 value) external pure returns (string memory stringifiedValue);

    /// Converts the given value to a `string`.
    function toString(bool value) external pure returns (string memory stringifiedValue);

    /// Converts the given value to a `string`.
    function toString(uint256 value) external pure returns (string memory stringifiedValue);

    /// Converts the given value to a `string`.
    function toString(int256 value) external pure returns (string memory stringifiedValue);

    /// Converts the given `string` value to Uppercase.
    function toUppercase(string calldata input) external pure returns (string memory output);

    /// Trims leading and trailing whitespace from the given `string` value.
    function trim(string calldata input) external pure returns (string memory output);

    // ======== Testing ========

    /// Compares two `uint256` values. Expects difference to be less than or equal to `maxDelta`.
    /// Formats values with decimals in failure message.
    function assertApproxEqAbsDecimal(uint256 left, uint256 right, uint256 maxDelta, uint256 decimals) external pure;

    /// Compares two `uint256` values. Expects difference to be less than or equal to `maxDelta`.
    /// Formats values with decimals in failure message. Includes error message into revert string on failure.
    function assertApproxEqAbsDecimal(
        uint256 left,
        uint256 right,
        uint256 maxDelta,
        uint256 decimals,
        string calldata error
    ) external pure;

    /// Compares two `int256` values. Expects difference to be less than or equal to `maxDelta`.
    /// Formats values with decimals in failure message.
    function assertApproxEqAbsDecimal(int256 left, int256 right, uint256 maxDelta, uint256 decimals) external pure;

    /// Compares two `int256` values. Expects difference to be less than or equal to `maxDelta`.
    /// Formats values with decimals in failure message. Includes error message into revert string on failure.
    function assertApproxEqAbsDecimal(
        int256 left,
        int256 right,
        uint256 maxDelta,
        uint256 decimals,
        string calldata error
    ) external pure;

    /// Compares two `uint256` values. Expects difference to be less than or equal to `maxDelta`.
    function assertApproxEqAbs(uint256 left, uint256 right, uint256 maxDelta) external pure;

    /// Compares two `uint256` values. Expects difference to be less than or equal to `maxDelta`.
    /// Includes error message into revert string on failure.
    function assertApproxEqAbs(uint256 left, uint256 right, uint256 maxDelta, string calldata error) external pure;

    /// Compares two `int256` values. Expects difference to be less than or equal to `maxDelta`.
    function assertApproxEqAbs(int256 left, int256 right, uint256 maxDelta) external pure;

    /// Compares two `int256` values. Expects difference to be less than or equal to `maxDelta`.
    /// Includes error message into revert string on failure.
    function assertApproxEqAbs(int256 left, int256 right, uint256 maxDelta, string calldata error) external pure;

    /// Compares two `uint256` values. Expects relative difference in percents to be less than or equal to `maxPercentDelta`.
    /// `maxPercentDelta` is an 18 decimal fixed point number, where 1e18 == 100%
    /// Formats values with decimals in failure message.
    function assertApproxEqRelDecimal(uint256 left, uint256 right, uint256 maxPercentDelta, uint256 decimals)
        external
        pure;

    /// Compares two `uint256` values. Expects relative difference in percents to be less than or equal to `maxPercentDelta`.
    /// `maxPercentDelta` is an 18 decimal fixed point number, where 1e18 == 100%
    /// Formats values with decimals in failure message. Includes error message into revert string on failure.
    function assertApproxEqRelDecimal(
        uint256 left,
        uint256 right,
        uint256 maxPercentDelta,
        uint256 decimals,
        string calldata error
    ) external pure;

    /// Compares two `int256` values. Expects relative difference in percents to be less than or equal to `maxPercentDelta`.
    /// `maxPercentDelta` is an 18 decimal fixed point number, where 1e18 == 100%
    /// Formats values with decimals in failure message.
    function assertApproxEqRelDecimal(int256 left, int256 right, uint256 maxPercentDelta, uint256 decimals)
        external
        pure;

    /// Compares two `int256` values. Expects relative difference in percents to be less than or equal to `maxPercentDelta`.
    /// `maxPercentDelta` is an 18 decimal fixed point number, where 1e18 == 100%
    /// Formats values with decimals in failure message. Includes error message into revert string on failure.
    function assertApproxEqRelDecimal(
        int256 left,
        int256 right,
        uint256 maxPercentDelta,
        uint256 decimals,
        string calldata error
    ) external pure;

    /// Compares two `uint256` values. Expects relative difference in percents to be less than or equal to `maxPercentDelta`.
    /// `maxPercentDelta` is an 18 decimal fixed point number, where 1e18 == 100%
    function assertApproxEqRel(uint256 left, uint256 right, uint256 maxPercentDelta) external pure;

    /// Compares two `uint256` values. Expects relative difference in percents to be less than or equal to `maxPercentDelta`.
    /// `maxPercentDelta` is an 18 decimal fixed point number, where 1e18 == 100%
    /// Includes error message into revert string on failure.
    function assertApproxEqRel(uint256 left, uint256 right, uint256 maxPercentDelta, string calldata error)
        external
        pure;

    /// Compares two `int256` values. Expects relative difference in percents to be less than or equal to `maxPercentDelta`.
    /// `maxPercentDelta` is an 18 decimal fixed point number, where 1e18 == 100%
    function assertApproxEqRel(int256 left, int256 right, uint256 maxPercentDelta) external pure;

    /// Compares two `int256` values. Expects relative difference in percents to be less than or equal to `maxPercentDelta`.
    /// `maxPercentDelta` is an 18 decimal fixed point number, where 1e18 == 100%
    /// Includes error message into revert string on failure.
    function assertApproxEqRel(int256 left, int256 right, uint256 maxPercentDelta, string calldata error) external pure;

    /// Asserts that two `uint256` values are equal, formatting them with decimals in failure message.
    function assertEqDecimal(uint256 left, uint256 right, uint256 decimals) external pure;

    /// Asserts that two `uint256` values are equal, formatting them with decimals in failure message.
    /// Includes error message into revert string on failure.
    function assertEqDecimal(uint256 left, uint256 right, uint256 decimals, string calldata error) external pure;

    /// Asserts that two `int256` values are equal, formatting them with decimals in failure message.
    function assertEqDecimal(int256 left, int256 right, uint256 decimals) external pure;

    /// Asserts that two `int256` values are equal, formatting them with decimals in failure message.
    /// Includes error message into revert string on failure.
    function assertEqDecimal(int256 left, int256 right, uint256 decimals, string calldata error) external pure;

    /// Asserts that two `bool` values are equal.
    function assertEq(bool left, bool right) external pure;

    /// Asserts that two `bool` values are equal and includes error message into revert string on failure.
    function assertEq(bool left, bool right, string calldata error) external pure;

    /// Asserts that two `string` values are equal.
    function assertEq(string calldata left, string calldata right) external pure;

    /// Asserts that two `string` values are equal and includes error message into revert string on failure.
    function assertEq(string calldata left, string calldata right, string calldata error) external pure;

    /// Asserts that two `bytes` values are equal.
    function assertEq(bytes calldata left, bytes calldata right) external pure;

    /// Asserts that two `bytes` values are equal and includes error message into revert string on failure.
    function assertEq(bytes calldata left, bytes calldata right, string calldata error) external pure;

    /// Asserts that two arrays of `bool` values are equal.
    function assertEq(bool[] calldata left, bool[] calldata right) external pure;

    /// Asserts that two arrays of `bool` values are equal and includes error message into revert string on failure.
    function assertEq(bool[] calldata left, bool[] calldata right, string calldata error) external pure;

    /// Asserts that two arrays of `uint256 values are equal.
    function assertEq(uint256[] calldata left, uint256[] calldata right) external pure;

    /// Asserts that two arrays of `uint256` values are equal and includes error message into revert string on failure.
    function assertEq(uint256[] calldata left, uint256[] calldata right, string calldata error) external pure;

    /// Asserts that two arrays of `int256` values are equal.
    function assertEq(int256[] calldata left, int256[] calldata right) external pure;

    /// Asserts that two arrays of `int256` values are equal and includes error message into revert string on failure.
    function assertEq(int256[] calldata left, int256[] calldata right, string calldata error) external pure;

    /// Asserts that two `uint256` values are equal.
    function assertEq(uint256 left, uint256 right) external pure;

    /// Asserts that two arrays of `address` values are equal.
    function assertEq(address[] calldata left, address[] calldata right) external pure;

    /// Asserts that two arrays of `address` values are equal and includes error message into revert string on failure.
    function assertEq(address[] calldata left, address[] calldata right, string calldata error) external pure;

    /// Asserts that two arrays of `bytes32` values are equal.
    function assertEq(bytes32[] calldata left, bytes32[] calldata right) external pure;

    /// Asserts that two arrays of `bytes32` values are equal and includes error message into revert string on failure.
    function assertEq(bytes32[] calldata left, bytes32[] calldata right, string calldata error) external pure;

    /// Asserts that two arrays of `string` values are equal.
    function assertEq(string[] calldata left, string[] calldata right) external pure;

    /// Asserts that two arrays of `string` values are equal and includes error message into revert string on failure.
    function assertEq(string[] calldata left, string[] calldata right, string calldata error) external pure;

    /// Asserts that two arrays of `bytes` values are equal.
    function assertEq(bytes[] calldata left, bytes[] calldata right) external pure;

    /// Asserts that two arrays of `bytes` values are equal and includes error message into revert string on failure.
    function assertEq(bytes[] calldata left, bytes[] calldata right, string calldata error) external pure;

    /// Asserts that two `uint256` values are equal and includes error message into revert string on failure.
    function assertEq(uint256 left, uint256 right, string calldata error) external pure;

    /// Asserts that two `int256` values are equal.
    function assertEq(int256 left, int256 right) external pure;

    /// Asserts that two `int256` values are equal and includes error message into revert string on failure.
    function assertEq(int256 left, int256 right, string calldata error) external pure;

    /// Asserts that two `address` values are equal.
    function assertEq(address left, address right) external pure;

    /// Asserts that two `address` values are equal and includes error message into revert string on failure.
    function assertEq(address left, address right, string calldata error) external pure;

    /// Asserts that two `bytes32` values are equal.
    function assertEq(bytes32 left, bytes32 right) external pure;

    /// Asserts that two `bytes32` values are equal and includes error message into revert string on failure.
    function assertEq(bytes32 left, bytes32 right, string calldata error) external pure;

    /// Asserts that the given condition is false.
    function assertFalse(bool condition) external pure;

    /// Asserts that the given condition is false and includes error message into revert string on failure.
    function assertFalse(bool condition, string calldata error) external pure;

    /// Compares two `uint256` values. Expects first value to be greater than or equal to second.
    /// Formats values with decimals in failure message.
    function assertGeDecimal(uint256 left, uint256 right, uint256 decimals) external pure;

    /// Compares two `uint256` values. Expects first value to be greater than or equal to second.
    /// Formats values with decimals in failure message. Includes error message into revert string on failure.
    function assertGeDecimal(uint256 left, uint256 right, uint256 decimals, string calldata error) external pure;

    /// Compares two `int256` values. Expects first value to be greater than or equal to second.
    /// Formats values with decimals in failure message.
    function assertGeDecimal(int256 left, int256 right, uint256 decimals) external pure;

    /// Compares two `int256` values. Expects first value to be greater than or equal to second.
    /// Formats values with decimals in failure message. Includes error message into revert string on failure.
    function assertGeDecimal(int256 left, int256 right, uint256 decimals, string calldata error) external pure;

    /// Compares two `uint256` values. Expects first value to be greater than or equal to second.
    function assertGe(uint256 left, uint256 right) external pure;

    /// Compares two `uint256` values. Expects first value to be greater than or equal to second.
    /// Includes error message into revert string on failure.
    function assertGe(uint256 left, uint256 right, string calldata error) external pure;

    /// Compares two `int256` values. Expects first value to be greater than or equal to second.
    function assertGe(int256 left, int256 right) external pure;

    /// Compares two `int256` values. Expects first value to be greater than or equal to second.
    /// Includes error message into revert string on failure.
    function assertGe(int256 left, int256 right, string calldata error) external pure;

    /// Compares two `uint256` values. Expects first value to be greater than second.
    /// Formats values with decimals in failure message.
    function assertGtDecimal(uint256 left, uint256 right, uint256 decimals) external pure;

    /// Compares two `uint256` values. Expects first value to be greater than second.
    /// Formats values with decimals in failure message. Includes error message into revert string on failure.
    function assertGtDecimal(uint256 left, uint256 right, uint256 decimals, string calldata error) external pure;

    /// Compares two `int256` values. Expects first value to be greater than second.
    /// Formats values with decimals in failure message.
    function assertGtDecimal(int256 left, int256 right, uint256 decimals) external pure;

    /// Compares two `int256` values. Expects first value to be greater than second.
    /// Formats values with decimals in failure message. Includes error message into revert string on failure.
    function assertGtDecimal(int256 left, int256 right, uint256 decimals, string calldata error) external pure;

    /// Compares two `uint256` values. Expects first value to be greater than second.
    function assertGt(uint256 left, uint256 right) external pure;

    /// Compares two `uint256` values. Expects first value to be greater than second.
    /// Includes error message into revert string on failure.
    function assertGt(uint256 left, uint256 right, string calldata error) external pure;

    /// Compares two `int256` values. Expects first value to be greater than second.
    function assertGt(int256 left, int256 right) external pure;

    /// Compares two `int256` values. Expects first value to be greater than second.
    /// Includes error message into revert string on failure.
    function assertGt(int256 left, int256 right, string calldata error) external pure;

    /// Compares two `uint256` values. Expects first value to be less than or equal to second.
    /// Formats values with decimals in failure message.
    function assertLeDecimal(uint256 left, uint256 right, uint256 decimals) external pure;

    /// Compares two `uint256` values. Expects first value to be less than or equal to second.
    /// Formats values with decimals in failure message. Includes error message into revert string on failure.
    function assertLeDecimal(uint256 left, uint256 right, uint256 decimals, string calldata error) external pure;

    /// Compares two `int256` values. Expects first value to be less than or equal to second.
    /// Formats values with decimals in failure message.
    function assertLeDecimal(int256 left, int256 right, uint256 decimals) external pure;

    /// Compares two `int256` values. Expects first value to be less than or equal to second.
    /// Formats values with decimals in failure message. Includes error message into revert string on failure.
    function assertLeDecimal(int256 left, int256 right, uint256 decimals, string calldata error) external pure;

    /// Compares two `uint256` values. Expects first value to be less than or equal to second.
    function assertLe(uint256 left, uint256 right) external pure;

    /// Compares two `uint256` values. Expects first value to be less than or equal to second.
    /// Includes error message into revert string on failure.
    function assertLe(uint256 left, uint256 right, string calldata error) external pure;

    /// Compares two `int256` values. Expects first value to be less than or equal to second.
    function assertLe(int256 left, int256 right) external pure;

    /// Compares two `int256` values. Expects first value to be less than or equal to second.
    /// Includes error message into revert string on failure.
    function assertLe(int256 left, int256 right, string calldata error) external pure;

    /// Compares two `uint256` values. Expects first value to be less than second.
    /// Formats values with decimals in failure message.
    function assertLtDecimal(uint256 left, uint256 right, uint256 decimals) external pure;

    /// Compares two `uint256` values. Expects first value to be less than second.
    /// Formats values with decimals in failure message. Includes error message into revert string on failure.
    function assertLtDecimal(uint256 left, uint256 right, uint256 decimals, string calldata error) external pure;

    /// Compares two `int256` values. Expects first value to be less than second.
    /// Formats values with decimals in failure message.
    function assertLtDecimal(int256 left, int256 right, uint256 decimals) external pure;

    /// Compares two `int256` values. Expects first value to be less than second.
    /// Formats values with decimals in failure message. Includes error message into revert string on failure.
    function assertLtDecimal(int256 left, int256 right, uint256 decimals, string calldata error) external pure;

    /// Compares two `uint256` values. Expects first value to be less than second.
    function assertLt(uint256 left, uint256 right) external pure;

    /// Compares two `uint256` values. Expects first value to be less than second.
    /// Includes error message into revert string on failure.
    function assertLt(uint256 left, uint256 right, string calldata error) external pure;

    /// Compares two `int256` values. Expects first value to be less than second.
    function assertLt(int256 left, int256 right) external pure;

    /// Compares two `int256` values. Expects first value to be less than second.
    /// Includes error message into revert string on failure.
    function assertLt(int256 left, int256 right, string calldata error) external pure;

    /// Asserts that two `uint256` values are not equal, formatting them with decimals in failure message.
    function assertNotEqDecimal(uint256 left, uint256 right, uint256 decimals) external pure;

    /// Asserts that two `uint256` values are not equal, formatting them with decimals in failure message.
    /// Includes error message into revert string on failure.
    function assertNotEqDecimal(uint256 left, uint256 right, uint256 decimals, string calldata error) external pure;

    /// Asserts that two `int256` values are not equal, formatting them with decimals in failure message.
    function assertNotEqDecimal(int256 left, int256 right, uint256 decimals) external pure;

    /// Asserts that two `int256` values are not equal, formatting them with decimals in failure message.
    /// Includes error message into revert string on failure.
    function assertNotEqDecimal(int256 left, int256 right, uint256 decimals, string calldata error) external pure;

    /// Asserts that two `bool` values are not equal.
    function assertNotEq(bool left, bool right) external pure;

    /// Asserts that two `bool` values are not equal and includes error message into revert string on failure.
    function assertNotEq(bool left, bool right, string calldata error) external pure;

    /// Asserts that two `string` values are not equal.
    function assertNotEq(string calldata left, string calldata right) external pure;

    /// Asserts that two `string` values are not equal and includes error message into revert string on failure.
    function assertNotEq(string calldata left, string calldata right, string calldata error) external pure;

    /// Asserts that two `bytes` values are not equal.
    function assertNotEq(bytes calldata left, bytes calldata right) external pure;

    /// Asserts that two `bytes` values are not equal and includes error message into revert string on failure.
    function assertNotEq(bytes calldata left, bytes calldata right, string calldata error) external pure;

    /// Asserts that two arrays of `bool` values are not equal.
    function assertNotEq(bool[] calldata left, bool[] calldata right) external pure;

    /// Asserts that two arrays of `bool` values are not equal and includes error message into revert string on failure.
    function assertNotEq(bool[] calldata left, bool[] calldata right, string calldata error) external pure;

    /// Asserts that two arrays of `uint256` values are not equal.
    function assertNotEq(uint256[] calldata left, uint256[] calldata right) external pure;

    /// Asserts that two arrays of `uint256` values are not equal and includes error message into revert string on failure.
    function assertNotEq(uint256[] calldata left, uint256[] calldata right, string calldata error) external pure;

    /// Asserts that two arrays of `int256` values are not equal.
    function assertNotEq(int256[] calldata left, int256[] calldata right) external pure;

    /// Asserts that two arrays of `int256` values are not equal and includes error message into revert string on failure.
    function assertNotEq(int256[] calldata left, int256[] calldata right, string calldata error) external pure;

    /// Asserts that two `uint256` values are not equal.
    function assertNotEq(uint256 left, uint256 right) external pure;

    /// Asserts that two arrays of `address` values are not equal.
    function assertNotEq(address[] calldata left, address[] calldata right) external pure;

    /// Asserts that two arrays of `address` values are not equal and includes error message into revert string on failure.
    function assertNotEq(address[] calldata left, address[] calldata right, string calldata error) external pure;

    /// Asserts that two arrays of `bytes32` values are not equal.
    function assertNotEq(bytes32[] calldata left, bytes32[] calldata right) external pure;

    /// Asserts that two arrays of `bytes32` values are not equal and includes error message into revert string on failure.
    function assertNotEq(bytes32[] calldata left, bytes32[] calldata right, string calldata error) external pure;

    /// Asserts that two arrays of `string` values are not equal.
    function assertNotEq(string[] calldata left, string[] calldata right) external pure;

    /// Asserts that two arrays of `string` values are not equal and includes error message into revert string on failure.
    function assertNotEq(string[] calldata left, string[] calldata right, string calldata error) external pure;

    /// Asserts that two arrays of `bytes` values are not equal.
    function assertNotEq(bytes[] calldata left, bytes[] calldata right) external pure;

    /// Asserts that two arrays of `bytes` values are not equal and includes error message into revert string on failure.
    function assertNotEq(bytes[] calldata left, bytes[] calldata right, string calldata error) external pure;

    /// Asserts that two `uint256` values are not equal and includes error message into revert string on failure.
    function assertNotEq(uint256 left, uint256 right, string calldata error) external pure;

    /// Asserts that two `int256` values are not equal.
    function assertNotEq(int256 left, int256 right) external pure;

    /// Asserts that two `int256` values are not equal and includes error message into revert string on failure.
    function assertNotEq(int256 left, int256 right, string calldata error) external pure;

    /// Asserts that two `address` values are not equal.
    function assertNotEq(address left, address right) external pure;

    /// Asserts that two `address` values are not equal and includes error message into revert string on failure.
    function assertNotEq(address left, address right, string calldata error) external pure;

    /// Asserts that two `bytes32` values are not equal.
    function assertNotEq(bytes32 left, bytes32 right) external pure;

    /// Asserts that two `bytes32` values are not equal and includes error message into revert string on failure.
    function assertNotEq(bytes32 left, bytes32 right, string calldata error) external pure;

    /// Asserts that the given condition is true.
    function assertTrue(bool condition) external pure;

    /// Asserts that the given condition is true and includes error message into revert string on failure.
    function assertTrue(bool condition, string calldata error) external pure;

    /// If the condition is false, discard this run's fuzz inputs and generate new ones.
    function assume(bool condition) external pure;

    /// Discard this run's fuzz inputs and generate new ones if next call reverted.
    function assumeNoRevert() external pure;

    /// Discard this run's fuzz inputs and generate new ones if next call reverts with the potential revert parameters.
    function assumeNoRevert(PotentialRevert calldata potentialRevert) external pure;

    /// Discard this run's fuzz inputs and generate new ones if next call reverts with the any of the potential revert parameters.
    function assumeNoRevert(PotentialRevert[] calldata potentialReverts) external pure;

    /// Writes a breakpoint to jump to in the debugger.
    function breakpoint(string calldata char) external pure;

    /// Writes a conditional breakpoint to jump to in the debugger.
    function breakpoint(string calldata char, bool value) external pure;

    /// Returns true if the current Foundry version is greater than or equal to the given version.
    /// The given version string must be in the format `major.minor.patch`.
    /// This is equivalent to `foundryVersionCmp(version) >= 0`.
    function foundryVersionAtLeast(string calldata version) external view returns (bool);

    /// Compares the current Foundry version with the given version string.
    /// The given version string must be in the format `major.minor.patch`.
    /// Returns:
    /// -1 if current Foundry version is less than the given version
    /// 0 if current Foundry version equals the given version
    /// 1 if current Foundry version is greater than the given version
    /// This result can then be used with a comparison operator against `0`.
    /// For example, to check if the current Foundry version is greater than or equal to `1.0.0`:
    /// `if (foundryVersionCmp("1.0.0") >= 0) { ... }`
    function foundryVersionCmp(string calldata version) external view returns (int256);

    /// Returns a Chain struct for specific alias
    function getChain(string calldata chainAlias) external view returns (Chain memory chain);

    /// Returns a Chain struct for specific chainId
    function getChain(uint256 chainId) external view returns (Chain memory chain);

    /// Returns the Foundry version.
    /// Format: <cargo_version>-<tag>+<git_sha_short>.<unix_build_timestamp>.<profile>
    /// Sample output: 0.3.0-nightly+3cb96bde9b.1737036656.debug
    /// Note: Build timestamps may vary slightly across platforms due to separate CI jobs.
    /// For reliable version comparisons, use UNIX format (e.g., >= 1700000000)
    /// to compare timestamps while ignoring minor time differences.
    function getFoundryVersion() external view returns (string memory version);

    /// Returns the RPC url for the given alias.
    function rpcUrl(string calldata rpcAlias) external view returns (string memory json);

    /// Returns all rpc urls and their aliases as structs.
    function rpcUrlStructs() external view returns (Rpc[] memory urls);

    /// Returns all rpc urls and their aliases `[alias, url][]`.
    function rpcUrls() external view returns (string[2][] memory urls);

    /// Suspends execution of the main thread for `duration` milliseconds.
    function sleep(uint256 duration) external;

    // ======== Toml ========

    /// Checks if `key` exists in a TOML table.
    function keyExistsToml(string calldata toml, string calldata key) external view returns (bool);

    /// Parses a string of TOML data at `key` and coerces it to `address`.
    function parseTomlAddress(string calldata toml, string calldata key) external pure returns (address);

    /// Parses a string of TOML data at `key` and coerces it to `address[]`.
    function parseTomlAddressArray(string calldata toml, string calldata key) external pure returns (address[] memory);

    /// Parses a string of TOML data at `key` and coerces it to `bool`.
    function parseTomlBool(string calldata toml, string calldata key) external pure returns (bool);

    /// Parses a string of TOML data at `key` and coerces it to `bool[]`.
    function parseTomlBoolArray(string calldata toml, string calldata key) external pure returns (bool[] memory);

    /// Parses a string of TOML data at `key` and coerces it to `bytes`.
    function parseTomlBytes(string calldata toml, string calldata key) external pure returns (bytes memory);

    /// Parses a string of TOML data at `key` and coerces it to `bytes32`.
    function parseTomlBytes32(string calldata toml, string calldata key) external pure returns (bytes32);

    /// Parses a string of TOML data at `key` and coerces it to `bytes32[]`.
    function parseTomlBytes32Array(string calldata toml, string calldata key) external pure returns (bytes32[] memory);

    /// Parses a string of TOML data at `key` and coerces it to `bytes[]`.
    function parseTomlBytesArray(string calldata toml, string calldata key) external pure returns (bytes[] memory);

    /// Parses a string of TOML data at `key` and coerces it to `int256`.
    function parseTomlInt(string calldata toml, string calldata key) external pure returns (int256);

    /// Parses a string of TOML data at `key` and coerces it to `int256[]`.
    function parseTomlIntArray(string calldata toml, string calldata key) external pure returns (int256[] memory);

    /// Returns an array of all the keys in a TOML table.
    function parseTomlKeys(string calldata toml, string calldata key) external pure returns (string[] memory keys);

    /// Parses a string of TOML data at `key` and coerces it to `string`.
    function parseTomlString(string calldata toml, string calldata key) external pure returns (string memory);

    /// Parses a string of TOML data at `key` and coerces it to `string[]`.
    function parseTomlStringArray(string calldata toml, string calldata key) external pure returns (string[] memory);

    /// Parses a string of TOML data at `key` and coerces it to type array corresponding to `typeDescription`.
    function parseTomlTypeArray(string calldata toml, string calldata key, string calldata typeDescription)
        external
        pure
        returns (bytes memory);

    /// Parses a string of TOML data and coerces it to type corresponding to `typeDescription`.
    function parseTomlType(string calldata toml, string calldata typeDescription) external pure returns (bytes memory);

    /// Parses a string of TOML data at `key` and coerces it to type corresponding to `typeDescription`.
    function parseTomlType(string calldata toml, string calldata key, string calldata typeDescription)
        external
        pure
        returns (bytes memory);

    /// Parses a string of TOML data at `key` and coerces it to `uint256`.
    function parseTomlUint(string calldata toml, string calldata key) external pure returns (uint256);

    /// Parses a string of TOML data at `key` and coerces it to `uint256[]`.
    function parseTomlUintArray(string calldata toml, string calldata key) external pure returns (uint256[] memory);

    /// ABI-encodes a TOML table.
    function parseToml(string calldata toml) external pure returns (bytes memory abiEncodedData);

    /// ABI-encodes a TOML table at `key`.
    function parseToml(string calldata toml, string calldata key) external pure returns (bytes memory abiEncodedData);

    /// Takes serialized JSON, converts to TOML and write a serialized TOML to a file.
    function writeToml(string calldata json, string calldata path) external;

    /// Takes serialized JSON, converts to TOML and write a serialized TOML table to an **existing** TOML file, replacing a value with key = <value_key.>
    /// This is useful to replace a specific value of a TOML file, without having to parse the entire thing.
    /// This cheatcode will create new keys if they didn't previously exist.
    function writeToml(string calldata json, string calldata path, string calldata valueKey) external;

    // ======== Utilities ========

    /// Returns an uint256 value bounded in given range and different from the current one.
    function bound(uint256 current, uint256 min, uint256 max) external view returns (uint256);

    /// Returns an int256 value bounded in given range and different from the current one.
    function bound(int256 current, int256 min, int256 max) external view returns (int256);

    /// Compute the address of a contract created with CREATE2 using the given CREATE2 deployer.
    function computeCreate2Address(bytes32 salt, bytes32 initCodeHash, address deployer) external pure returns (address);

    /// Compute the address of a contract created with CREATE2 using the default CREATE2 deployer.
    function computeCreate2Address(bytes32 salt, bytes32 initCodeHash) external pure returns (address);

    /// Compute the address a contract will be deployed at for a given deployer address and nonce.
    function computeCreateAddress(address deployer, uint256 nonce) external pure returns (address);

    /// Utility cheatcode to copy storage of `from` contract to another `to` contract.
    function copyStorage(address from, address to) external;

    /// Generates the struct hash of the canonical EIP-712 type representation and its abi-encoded data.
    /// Supports 2 different inputs:
    /// 1. Name of the type (i.e. "PermitSingle"):
    /// * requires previous binding generation with `forge bind-json`.
    /// * bindings will be retrieved from the path configured in `foundry.toml`.
    /// 2. String representation of the type (i.e. "Foo(Bar bar) Bar(uint256 baz)").
    /// * Note: the cheatcode will use the canonical type even if the input is malformated
    /// with the wrong order of elements or with extra whitespaces.
    function eip712HashStruct(string calldata typeNameOrDefinition, bytes calldata abiEncodedData)
        external
        pure
        returns (bytes32 typeHash);

    /// Generates the struct hash of the canonical EIP-712 type representation and its abi-encoded data.
    /// Requires previous binding generation with `forge bind-json`.
    /// Params:
    /// * `bindingsPath`: path where the output of `forge bind-json` is stored.
    /// * `typeName`: Name of the type (i.e. "PermitSingle").
    /// * `abiEncodedData`: ABI-encoded data for the struct that is being hashed.
    function eip712HashStruct(string calldata bindingsPath, string calldata typeName, bytes calldata abiEncodedData)
        external
        pure
        returns (bytes32 typeHash);

    /// Generates the hash of the canonical EIP-712 type representation.
    /// Supports 2 different inputs:
    /// 1. Name of the type (i.e. "Transaction"):
    /// * requires previous binding generation with `forge bind-json`.
    /// * bindings will be retrieved from the path configured in `foundry.toml`.
    /// 2. String representation of the type (i.e. "Foo(Bar bar) Bar(uint256 baz)").
    /// * Note: the cheatcode will output the canonical type even if the input is malformated
    /// with the wrong order of elements or with extra whitespaces.
    function eip712HashType(string calldata typeNameOrDefinition) external pure returns (bytes32 typeHash);

    /// Generates the hash of the canonical EIP-712 type representation.
    /// Requires previous binding generation with `forge bind-json`.
    /// Params:
    /// * `bindingsPath`: path where the output of `forge bind-json` is stored.
    /// * `typeName`: Name of the type (i.e. "Transaction").
    function eip712HashType(string calldata bindingsPath, string calldata typeName)
        external
        pure
        returns (bytes32 typeHash);

    /// Generates a ready-to-sign digest of human-readable typed data following the EIP-712 standard.
    function eip712HashTypedData(string calldata jsonData) external pure returns (bytes32 digest);

    /// Returns ENS namehash for provided string.
    function ensNamehash(string calldata name) external pure returns (bytes32);

    /// Gets the label for the specified address.
    function getLabel(address account) external view returns (string memory currentLabel);

    /// Labels an address in call traces.
    function label(address account, string calldata newLabel) external;

    /// Pauses collection of call traces. Useful in cases when you want to skip tracing of
    /// complex calls which are not useful for debugging.
    function pauseTracing() external view;

    /// Returns a random `address`.
    function randomAddress() external view returns (address);

    /// Returns a random `bool`.
    function randomBool() external view returns (bool);

    /// Returns a random byte array value of the given length.
    function randomBytes(uint256 len) external view returns (bytes memory);

    /// Returns a random fixed-size byte array of length 4.
    function randomBytes4() external view returns (bytes4);

    /// Returns a random fixed-size byte array of length 8.
    function randomBytes8() external view returns (bytes8);

    /// Returns a random `int256` value.
    function randomInt() external view returns (int256);

    /// Returns a random `int256` value of given bits.
    function randomInt(uint256 bits) external view returns (int256);

    /// Returns a random uint256 value.
    function randomUint() external view returns (uint256);

    /// Returns random uint256 value between the provided range (=min..=max).
    function randomUint(uint256 min, uint256 max) external view returns (uint256);

    /// Returns a random `uint256` value of given bits.
    function randomUint(uint256 bits) external view returns (uint256);

    /// Unpauses collection of call traces.
    function resumeTracing() external view;

    /// Utility cheatcode to set arbitrary storage for given target address.
    function setArbitraryStorage(address target) external;

    /// Utility cheatcode to set arbitrary storage for given target address and overwrite
    /// any storage slots that have been previously set.
    function setArbitraryStorage(address target, bool overwrite) external;

    /// Set RNG seed.
    function setSeed(uint256 seed) external;

    /// Randomly shuffles an array.
    function shuffle(uint256[] calldata array) external returns (uint256[] memory);

    /// Sorts an array in ascending order.
    function sort(uint256[] calldata array) external returns (uint256[] memory);

    /// Encodes a `bytes` value to a base64url string.
    function toBase64URL(bytes calldata data) external pure returns (string memory);

    /// Encodes a `string` value to a base64url string.
    function toBase64URL(string calldata data) external pure returns (string memory);

    /// Encodes a `bytes` value to a base64 string.
    function toBase64(bytes calldata data) external pure returns (string memory);

    /// Encodes a `string` value to a base64 string.
    function toBase64(string calldata data) external pure returns (string memory);
}

/// The `Vm` interface does allow manipulation of the EVM state. These are all intended to be used
/// in tests, but it is not recommended to use these cheats in scripts.
interface Vm is VmSafe {
    // ======== EVM ========

    /// Utility cheatcode to set an EIP-2930 access list for all subsequent transactions.
    function accessList(AccessListItem[] calldata access) external;

    /// Returns the identifier of the currently active fork. Reverts if no fork is currently active.
    function activeFork() external view returns (uint256 forkId);

    /// In forking mode, explicitly grant the given address cheatcode access.
    function allowCheatcodes(address account) external;

    /// Sets `block.blobbasefee`
    function blobBaseFee(uint256 newBlobBaseFee) external;

    /// Sets the blobhashes in the transaction.
    /// Not available on EVM versions before Cancun.
    /// If used on unsupported EVM versions it will revert.
    function blobhashes(bytes32[] calldata hashes) external;

    /// Sets `block.chainid`.
    function chainId(uint256 newChainId) external;

    /// Clears all mocked calls.
    function clearMockedCalls() external;

    /// Clones a source account code, state, balance and nonce to a target account and updates in-memory EVM state.
    function cloneAccount(address source, address target) external;

    /// Sets `block.coinbase`.
    function coinbase(address newCoinbase) external;

    /// Marks the slots of an account and the account address as cold.
    function cool(address target) external;

    /// Utility cheatcode to mark specific storage slot as cold, simulating no prior read.
    function coolSlot(address target, bytes32 slot) external;

    /// Creates a new fork with the given endpoint and the _latest_ block and returns the identifier of the fork.
    function createFork(string calldata urlOrAlias) external returns (uint256 forkId);

    /// Creates a new fork with the given endpoint and block and returns the identifier of the fork.
    function createFork(string calldata urlOrAlias, uint256 blockNumber) external returns (uint256 forkId);

    /// Creates a new fork with the given endpoint and at the block the given transaction was mined in,
    /// replays all transaction mined in the block before the transaction, and returns the identifier of the fork.
    function createFork(string calldata urlOrAlias, bytes32 txHash) external returns (uint256 forkId);

    /// Creates and also selects a new fork with the given endpoint and the latest block and returns the identifier of the fork.
    function createSelectFork(string calldata urlOrAlias) external returns (uint256 forkId);

    /// Creates and also selects a new fork with the given endpoint and block and returns the identifier of the fork.
    function createSelectFork(string calldata urlOrAlias, uint256 blockNumber) external returns (uint256 forkId);

    /// Creates and also selects new fork with the given endpoint and at the block the given transaction was mined in,
    /// replays all transaction mined in the block before the transaction, returns the identifier of the fork.
    function createSelectFork(string calldata urlOrAlias, bytes32 txHash) external returns (uint256 forkId);

    /// Sets an address' balance.
    function deal(address account, uint256 newBalance) external;

    /// Removes the snapshot with the given ID created by `snapshot`.
    /// Takes the snapshot ID to delete.
    /// Returns `true` if the snapshot was successfully deleted.
    /// Returns `false` if the snapshot does not exist.
    function deleteStateSnapshot(uint256 snapshotId) external returns (bool success);

    /// Removes _all_ snapshots previously created by `snapshot`.
    function deleteStateSnapshots() external;

    /// Sets `block.difficulty`.
    /// Not available on EVM versions from Paris onwards. Use `prevrandao` instead.
    /// Reverts if used on unsupported EVM versions.
    function difficulty(uint256 newDifficulty) external;

    /// Dump a genesis JSON file's `allocs` to disk.
    function dumpState(string calldata pathToStateJson) external;

    /// Sets an address' code.
    function etch(address target, bytes calldata newRuntimeBytecode) external;

    /// Sets `block.basefee`.
    function fee(uint256 newBasefee) external;

    /// Gets the blockhashes from the current transaction.
    /// Not available on EVM versions before Cancun.
    /// If used on unsupported EVM versions it will revert.
    function getBlobhashes() external view returns (bytes32[] memory hashes);

    /// Returns true if the account is marked as persistent.
    function isPersistent(address account) external view returns (bool persistent);

    /// Load a genesis JSON file's `allocs` into the in-memory EVM state.
    function loadAllocs(string calldata pathToAllocsJson) external;

    /// Marks that the account(s) should use persistent storage across fork swaps in a multifork setup
    /// Meaning, changes made to the state of this account will be kept when switching forks.
    function makePersistent(address account) external;

    /// See `makePersistent(address)`.
    function makePersistent(address account0, address account1) external;

    /// See `makePersistent(address)`.
    function makePersistent(address account0, address account1, address account2) external;

    /// See `makePersistent(address)`.
    function makePersistent(address[] calldata accounts) external;

    /// Reverts a call to an address with specified revert data.
    function mockCallRevert(address callee, bytes calldata data, bytes calldata revertData) external;

    /// Reverts a call to an address with a specific `msg.value`, with specified revert data.
    function mockCallRevert(address callee, uint256 msgValue, bytes calldata data, bytes calldata revertData) external;

    /// Reverts a call to an address with specified revert data.
    /// Overload to pass the function selector directly `token.approve.selector` instead of `abi.encodeWithSelector(token.approve.selector)`.
    function mockCallRevert(address callee, bytes4 data, bytes calldata revertData) external;

    /// Reverts a call to an address with a specific `msg.value`, with specified revert data.
    /// Overload to pass the function selector directly `token.approve.selector` instead of `abi.encodeWithSelector(token.approve.selector)`.
    function mockCallRevert(address callee, uint256 msgValue, bytes4 data, bytes calldata revertData) external;

    /// Mocks a call to an address, returning specified data.
    /// Calldata can either be strict or a partial match, e.g. if you only
    /// pass a Solidity selector to the expected calldata, then the entire Solidity
    /// function will be mocked.
    function mockCall(address callee, bytes calldata data, bytes calldata returnData) external;

    /// Mocks a call to an address with a specific `msg.value`, returning specified data.
    /// Calldata match takes precedence over `msg.value` in case of ambiguity.
    function mockCall(address callee, uint256 msgValue, bytes calldata data, bytes calldata returnData) external;

    /// Mocks a call to an address, returning specified data.
    /// Calldata can either be strict or a partial match, e.g. if you only
    /// pass a Solidity selector to the expected calldata, then the entire Solidity
    /// function will be mocked.
    /// Overload to pass the function selector directly `token.approve.selector` instead of `abi.encodeWithSelector(token.approve.selector)`.
    function mockCall(address callee, bytes4 data, bytes calldata returnData) external;

    /// Mocks a call to an address with a specific `msg.value`, returning specified data.
    /// Calldata match takes precedence over `msg.value` in case of ambiguity.
    /// Overload to pass the function selector directly `token.approve.selector` instead of `abi.encodeWithSelector(token.approve.selector)`.
    function mockCall(address callee, uint256 msgValue, bytes4 data, bytes calldata returnData) external;

    /// Mocks multiple calls to an address, returning specified data for each call.
    function mockCalls(address callee, bytes calldata data, bytes[] calldata returnData) external;

    /// Mocks multiple calls to an address with a specific `msg.value`, returning specified data for each call.
    function mockCalls(address callee, uint256 msgValue, bytes calldata data, bytes[] calldata returnData) external;

    /// Whenever a call is made to `callee` with calldata `data`, this cheatcode instead calls
    /// `target` with the same calldata. This functionality is similar to a delegate call made to
    /// `target` contract from `callee`.
    /// Can be used to substitute a call to a function with another implementation that captures
    /// the primary logic of the original function but is easier to reason about.
    /// If calldata is not a strict match then partial match by selector is attempted.
    function mockFunction(address callee, address target, bytes calldata data) external;

    /// Utility cheatcode to remove any EIP-2930 access list set by `accessList` cheatcode.
    function noAccessList() external;

    /// Sets the *next* call's `msg.sender` to be the input address.
    function prank(address msgSender) external;

    /// Sets the *next* call's `msg.sender` to be the input address, and the `tx.origin` to be the second input.
    function prank(address msgSender, address txOrigin) external;

    /// Sets the *next* delegate call's `msg.sender` to be the input address.
    function prank(address msgSender, bool delegateCall) external;

    /// Sets the *next* delegate call's `msg.sender` to be the input address, and the `tx.origin` to be the second input.
    function prank(address msgSender, address txOrigin, bool delegateCall) external;

    /// Sets `block.prevrandao`.
    /// Not available on EVM versions before Paris. Use `difficulty` instead.
    /// If used on unsupported EVM versions it will revert.
    function prevrandao(bytes32 newPrevrandao) external;

    /// Sets `block.prevrandao`.
    /// Not available on EVM versions before Paris. Use `difficulty` instead.
    /// If used on unsupported EVM versions it will revert.
    function prevrandao(uint256 newPrevrandao) external;

    /// Reads the current `msg.sender` and `tx.origin` from state and reports if there is any active caller modification.
    function readCallers() external view returns (CallerMode callerMode, address msgSender, address txOrigin);

    /// Resets the nonce of an account to 0 for EOAs and 1 for contract accounts.
    function resetNonce(address account) external;

    /// Revert the state of the EVM to a previous snapshot
    /// Takes the snapshot ID to revert to.
    /// Returns `true` if the snapshot was successfully reverted.
    /// Returns `false` if the snapshot does not exist.
    /// **Note:** This does not automatically delete the snapshot. To delete the snapshot use `deleteStateSnapshot`.
    function revertToState(uint256 snapshotId) external returns (bool success);

    /// Revert the state of the EVM to a previous snapshot and automatically deletes the snapshots
    /// Takes the snapshot ID to revert to.
    /// Returns `true` if the snapshot was successfully reverted and deleted.
    /// Returns `false` if the snapshot does not exist.
    function revertToStateAndDelete(uint256 snapshotId) external returns (bool success);

    /// Revokes persistent status from the address, previously added via `makePersistent`.
    function revokePersistent(address account) external;

    /// See `revokePersistent(address)`.
    function revokePersistent(address[] calldata accounts) external;

    /// Sets `block.height`.
    function roll(uint256 newHeight) external;

    /// Updates the currently active fork to given block number
    /// This is similar to `roll` but for the currently active fork.
    function rollFork(uint256 blockNumber) external;

    /// Updates the currently active fork to given transaction. This will `rollFork` with the number
    /// of the block the transaction was mined in and replays all transaction mined before it in the block.
    function rollFork(bytes32 txHash) external;

    /// Updates the given fork to given block number.
    function rollFork(uint256 forkId, uint256 blockNumber) external;

    /// Updates the given fork to block number of the given transaction and replays all transaction mined before it in the block.
    function rollFork(uint256 forkId, bytes32 txHash) external;

    /// Takes a fork identifier created by `createFork` and sets the corresponding forked state as active.
    function selectFork(uint256 forkId) external;

    /// Set blockhash for the current block.
    /// It only sets the blockhash for blocks where `block.number - 256 <= number < block.number`.
    function setBlockhash(uint256 blockNumber, bytes32 blockHash) external;

    /// Sets the nonce of an account. Must be higher than the current nonce of the account.
    function setNonce(address account, uint64 newNonce) external;

    /// Sets the nonce of an account to an arbitrary value.
    function setNonceUnsafe(address account, uint64 newNonce) external;

    /// Snapshot capture the gas usage of the last call by name from the callee perspective.
    function snapshotGasLastCall(string calldata name) external returns (uint256 gasUsed);

    /// Snapshot capture the gas usage of the last call by name in a group from the callee perspective.
    function snapshotGasLastCall(string calldata group, string calldata name) external returns (uint256 gasUsed);

    /// Snapshot the current state of the evm.
    /// Returns the ID of the snapshot that was created.
    /// To revert a snapshot use `revertToState`.
    function snapshotState() external returns (uint256 snapshotId);

    /// Snapshot capture an arbitrary numerical value by name.
    /// The group name is derived from the contract name.
    function snapshotValue(string calldata name, uint256 value) external;

    /// Snapshot capture an arbitrary numerical value by name in a group.
    function snapshotValue(string calldata group, string calldata name, uint256 value) external;

    /// Sets all subsequent calls' `msg.sender` to be the input address until `stopPrank` is called.
    function startPrank(address msgSender) external;

    /// Sets all subsequent calls' `msg.sender` to be the input address until `stopPrank` is called, and the `tx.origin` to be the second input.
    function startPrank(address msgSender, address txOrigin) external;

    /// Sets all subsequent delegate calls' `msg.sender` to be the input address until `stopPrank` is called.
    function startPrank(address msgSender, bool delegateCall) external;

    /// Sets all subsequent delegate calls' `msg.sender` to be the input address until `stopPrank` is called, and the `tx.origin` to be the second input.
    function startPrank(address msgSender, address txOrigin, bool delegateCall) external;

    /// Start a snapshot capture of the current gas usage by name.
    /// The group name is derived from the contract name.
    function startSnapshotGas(string calldata name) external;

    /// Start a snapshot capture of the current gas usage by name in a group.
    function startSnapshotGas(string calldata group, string calldata name) external;

    /// Resets subsequent calls' `msg.sender` to be `address(this)`.
    function stopPrank() external;

    /// Stop the snapshot capture of the current gas by latest snapshot name, capturing the gas used since the start.
    function stopSnapshotGas() external returns (uint256 gasUsed);

    /// Stop the snapshot capture of the current gas usage by name, capturing the gas used since the start.
    /// The group name is derived from the contract name.
    function stopSnapshotGas(string calldata name) external returns (uint256 gasUsed);

    /// Stop the snapshot capture of the current gas usage by name in a group, capturing the gas used since the start.
    function stopSnapshotGas(string calldata group, string calldata name) external returns (uint256 gasUsed);

    /// Stores a value to an address' storage slot.
    function store(address target, bytes32 slot, bytes32 value) external;

    /// Fetches the given transaction from the active fork and executes it on the current state.
    function transact(bytes32 txHash) external;

    /// Fetches the given transaction from the given fork and executes it on the current state.
    function transact(uint256 forkId, bytes32 txHash) external;

    /// Sets `tx.gasprice`.
    function txGasPrice(uint256 newGasPrice) external;

    /// Utility cheatcode to mark specific storage slot as warm, simulating a prior read.
    function warmSlot(address target, bytes32 slot) external;

    /// Sets `block.timestamp`.
    function warp(uint256 newTimestamp) external;

    /// `deleteSnapshot` is being deprecated in favor of `deleteStateSnapshot`. It will be removed in future versions.
    function deleteSnapshot(uint256 snapshotId) external returns (bool success);

    /// `deleteSnapshots` is being deprecated in favor of `deleteStateSnapshots`. It will be removed in future versions.
    function deleteSnapshots() external;

    /// `revertToAndDelete` is being deprecated in favor of `revertToStateAndDelete`. It will be removed in future versions.
    function revertToAndDelete(uint256 snapshotId) external returns (bool success);

    /// `revertTo` is being deprecated in favor of `revertToState`. It will be removed in future versions.
    function revertTo(uint256 snapshotId) external returns (bool success);

    /// `snapshot` is being deprecated in favor of `snapshotState`. It will be removed in future versions.
    function snapshot() external returns (uint256 snapshotId);

    // ======== Testing ========

    /// Expect a call to an address with the specified `msg.value` and calldata, and a *minimum* amount of gas.
    function expectCallMinGas(address callee, uint256 msgValue, uint64 minGas, bytes calldata data) external;

    /// Expect given number of calls to an address with the specified `msg.value` and calldata, and a *minimum* amount of gas.
    function expectCallMinGas(address callee, uint256 msgValue, uint64 minGas, bytes calldata data, uint64 count)
        external;

    /// Expects a call to an address with the specified calldata.
    /// Calldata can either be a strict or a partial match.
    function expectCall(address callee, bytes calldata data) external;

    /// Expects given number of calls to an address with the specified calldata.
    function expectCall(address callee, bytes calldata data, uint64 count) external;

    /// Expects a call to an address with the specified `msg.value` and calldata.
    function expectCall(address callee, uint256 msgValue, bytes calldata data) external;

    /// Expects given number of calls to an address with the specified `msg.value` and calldata.
    function expectCall(address callee, uint256 msgValue, bytes calldata data, uint64 count) external;

    /// Expect a call to an address with the specified `msg.value`, gas, and calldata.
    function expectCall(address callee, uint256 msgValue, uint64 gas, bytes calldata data) external;

    /// Expects given number of calls to an address with the specified `msg.value`, gas, and calldata.
    function expectCall(address callee, uint256 msgValue, uint64 gas, bytes calldata data, uint64 count) external;

    /// Expects the deployment of the specified bytecode by the specified address using the CREATE opcode
    function expectCreate(bytes calldata bytecode, address deployer) external;

    /// Expects the deployment of the specified bytecode by the specified address using the CREATE2 opcode
    function expectCreate2(bytes calldata bytecode, address deployer) external;

    /// Prepare an expected anonymous log with (bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData.).
    /// Call this function, then emit an anonymous event, then call a function. Internally after the call, we check if
    /// logs were emitted in the expected order with the expected topics and data (as specified by the booleans).
    function expectEmitAnonymous(bool checkTopic0, bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData)
        external;

    /// Same as the previous method, but also checks supplied address against emitting contract.
    function expectEmitAnonymous(
        bool checkTopic0,
        bool checkTopic1,
        bool checkTopic2,
        bool checkTopic3,
        bool checkData,
        address emitter
    ) external;

    /// Prepare an expected anonymous log with all topic and data checks enabled.
    /// Call this function, then emit an anonymous event, then call a function. Internally after the call, we check if
    /// logs were emitted in the expected order with the expected topics and data.
    function expectEmitAnonymous() external;

    /// Same as the previous method, but also checks supplied address against emitting contract.
    function expectEmitAnonymous(address emitter) external;

    /// Prepare an expected log with (bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData.).
    /// Call this function, then emit an event, then call a function. Internally after the call, we check if
    /// logs were emitted in the expected order with the expected topics and data (as specified by the booleans).
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData) external;

    /// Same as the previous method, but also checks supplied address against emitting contract.
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData, address emitter) external;

    /// Prepare an expected log with all topic and data checks enabled.
    /// Call this function, then emit an event, then call a function. Internally after the call, we check if
    /// logs were emitted in the expected order with the expected topics and data.
    function expectEmit() external;

    /// Same as the previous method, but also checks supplied address against emitting contract.
    function expectEmit(address emitter) external;

    /// Expect a given number of logs with the provided topics.
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData, uint64 count) external;

    /// Expect a given number of logs from a specific emitter with the provided topics.
    function expectEmit(
        bool checkTopic1,
        bool checkTopic2,
        bool checkTopic3,
        bool checkData,
        address emitter,
        uint64 count
    ) external;

    /// Expect a given number of logs with all topic and data checks enabled.
    function expectEmit(uint64 count) external;

    /// Expect a given number of logs from a specific emitter with all topic and data checks enabled.
    function expectEmit(address emitter, uint64 count) external;

    /// Expects an error on next call that starts with the revert data.
    function expectPartialRevert(bytes4 revertData) external;

    /// Expects an error on next call to reverter address, that starts with the revert data.
    function expectPartialRevert(bytes4 revertData, address reverter) external;

    /// Expects an error on next call with any revert data.
    function expectRevert() external;

    /// Expects an error on next call that exactly matches the revert data.
    function expectRevert(bytes4 revertData) external;

    /// Expects a `count` number of reverts from the upcoming calls from the reverter address that match the revert data.
    function expectRevert(bytes4 revertData, address reverter, uint64 count) external;

    /// Expects a `count` number of reverts from the upcoming calls from the reverter address that exactly match the revert data.
    function expectRevert(bytes calldata revertData, address reverter, uint64 count) external;

    /// Expects an error on next call that exactly matches the revert data.
    function expectRevert(bytes calldata revertData) external;

    /// Expects an error with any revert data on next call to reverter address.
    function expectRevert(address reverter) external;

    /// Expects an error from reverter address on next call, with any revert data.
    function expectRevert(bytes4 revertData, address reverter) external;

    /// Expects an error from reverter address on next call, that exactly matches the revert data.
    function expectRevert(bytes calldata revertData, address reverter) external;

    /// Expects a `count` number of reverts from the upcoming calls with any revert data or reverter.
    function expectRevert(uint64 count) external;

    /// Expects a `count` number of reverts from the upcoming calls that match the revert data.
    function expectRevert(bytes4 revertData, uint64 count) external;

    /// Expects a `count` number of reverts from the upcoming calls that exactly match the revert data.
    function expectRevert(bytes calldata revertData, uint64 count) external;

    /// Expects a `count` number of reverts from the upcoming calls from the reverter address.
    function expectRevert(address reverter, uint64 count) external;

    /// Only allows memory writes to offsets [0x00, 0x60) ∪ [min, max) in the current subcontext. If any other
    /// memory is written to, the test will fail. Can be called multiple times to add more ranges to the set.
    function expectSafeMemory(uint64 min, uint64 max) external;

    /// Only allows memory writes to offsets [0x00, 0x60) ∪ [min, max) in the next created subcontext.
    /// If any other memory is written to, the test will fail. Can be called multiple times to add more ranges
    /// to the set.
    function expectSafeMemoryCall(uint64 min, uint64 max) external;

    /// Marks a test as skipped. Must be called at the top level of a test.
    function skip(bool skipTest) external;

    /// Marks a test as skipped with a reason. Must be called at the top level of a test.
    function skip(bool skipTest, string calldata reason) external;

    /// Stops all safe memory expectation in the current subcontext.
    function stopExpectSafeMemory() external;

    // ======== Utilities ========

    /// Causes the next contract creation (via new) to fail and return its initcode in the returndata buffer.
    /// This allows type-safe access to the initcode payload that would be used for contract creation.
    /// Example usage:
    /// vm.interceptInitcode();
    /// bytes memory initcode;
    /// try new MyContract(param1, param2) { assert(false); }
    /// catch (bytes memory interceptedInitcode) { initcode = interceptedInitcode; }
    function interceptInitcode() external;
}

// lib/forge-std/src/console.sol

library console {
    address constant CONSOLE_ADDRESS = 0x000000000000000000636F6e736F6c652e6c6f67;

    function _sendLogPayloadImplementation(bytes memory payload) internal view {
        address consoleAddress = CONSOLE_ADDRESS;
        /// @solidity memory-safe-assembly
        assembly {
            pop(staticcall(gas(), consoleAddress, add(payload, 32), mload(payload), 0, 0))
        }
    }

    function _castToPure(function(bytes memory) internal view fnIn)
        internal
        pure
        returns (function(bytes memory) pure fnOut)
    {
        assembly {
            fnOut := fnIn
        }
    }

    function _sendLogPayload(bytes memory payload) internal pure {
        _castToPure(_sendLogPayloadImplementation)(payload);
    }

    function log() internal pure {
        _sendLogPayload(abi.encodeWithSignature("log()"));
    }

    function logInt(int256 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(int256)", p0));
    }

    function logUint(uint256 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256)", p0));
    }

    function logString(string memory p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string)", p0));
    }

    function logBool(bool p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool)", p0));
    }

    function logAddress(address p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address)", p0));
    }

    function logBytes(bytes memory p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes)", p0));
    }

    function logBytes1(bytes1 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes1)", p0));
    }

    function logBytes2(bytes2 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes2)", p0));
    }

    function logBytes3(bytes3 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes3)", p0));
    }

    function logBytes4(bytes4 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes4)", p0));
    }

    function logBytes5(bytes5 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes5)", p0));
    }

    function logBytes6(bytes6 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes6)", p0));
    }

    function logBytes7(bytes7 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes7)", p0));
    }

    function logBytes8(bytes8 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes8)", p0));
    }

    function logBytes9(bytes9 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes9)", p0));
    }

    function logBytes10(bytes10 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes10)", p0));
    }

    function logBytes11(bytes11 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes11)", p0));
    }

    function logBytes12(bytes12 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes12)", p0));
    }

    function logBytes13(bytes13 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes13)", p0));
    }

    function logBytes14(bytes14 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes14)", p0));
    }

    function logBytes15(bytes15 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes15)", p0));
    }

    function logBytes16(bytes16 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes16)", p0));
    }

    function logBytes17(bytes17 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes17)", p0));
    }

    function logBytes18(bytes18 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes18)", p0));
    }

    function logBytes19(bytes19 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes19)", p0));
    }

    function logBytes20(bytes20 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes20)", p0));
    }

    function logBytes21(bytes21 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes21)", p0));
    }

    function logBytes22(bytes22 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes22)", p0));
    }

    function logBytes23(bytes23 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes23)", p0));
    }

    function logBytes24(bytes24 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes24)", p0));
    }

    function logBytes25(bytes25 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes25)", p0));
    }

    function logBytes26(bytes26 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes26)", p0));
    }

    function logBytes27(bytes27 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes27)", p0));
    }

    function logBytes28(bytes28 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes28)", p0));
    }

    function logBytes29(bytes29 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes29)", p0));
    }

    function logBytes30(bytes30 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes30)", p0));
    }

    function logBytes31(bytes31 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes31)", p0));
    }

    function logBytes32(bytes32 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes32)", p0));
    }

    function log(uint256 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256)", p0));
    }

    function log(int256 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(int256)", p0));
    }

    function log(string memory p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string)", p0));
    }

    function log(bool p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool)", p0));
    }

    function log(address p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address)", p0));
    }

    function log(uint256 p0, uint256 p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256)", p0, p1));
    }

    function log(uint256 p0, string memory p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string)", p0, p1));
    }

    function log(uint256 p0, bool p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool)", p0, p1));
    }

    function log(uint256 p0, address p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address)", p0, p1));
    }

    function log(string memory p0, uint256 p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256)", p0, p1));
    }

    function log(string memory p0, int256 p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,int256)", p0, p1));
    }

    function log(string memory p0, string memory p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string)", p0, p1));
    }

    function log(string memory p0, bool p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool)", p0, p1));
    }

    function log(string memory p0, address p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address)", p0, p1));
    }

    function log(bool p0, uint256 p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256)", p0, p1));
    }

    function log(bool p0, string memory p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string)", p0, p1));
    }

    function log(bool p0, bool p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool)", p0, p1));
    }

    function log(bool p0, address p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address)", p0, p1));
    }

    function log(address p0, uint256 p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256)", p0, p1));
    }

    function log(address p0, string memory p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string)", p0, p1));
    }

    function log(address p0, bool p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool)", p0, p1));
    }

    function log(address p0, address p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address)", p0, p1));
    }

    function log(uint256 p0, uint256 p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,uint256)", p0, p1, p2));
    }

    function log(uint256 p0, uint256 p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,string)", p0, p1, p2));
    }

    function log(uint256 p0, uint256 p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,bool)", p0, p1, p2));
    }

    function log(uint256 p0, uint256 p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,address)", p0, p1, p2));
    }

    function log(uint256 p0, string memory p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,uint256)", p0, p1, p2));
    }

    function log(uint256 p0, string memory p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,string)", p0, p1, p2));
    }

    function log(uint256 p0, string memory p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,bool)", p0, p1, p2));
    }

    function log(uint256 p0, string memory p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,address)", p0, p1, p2));
    }

    function log(uint256 p0, bool p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,uint256)", p0, p1, p2));
    }

    function log(uint256 p0, bool p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,string)", p0, p1, p2));
    }

    function log(uint256 p0, bool p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,bool)", p0, p1, p2));
    }

    function log(uint256 p0, bool p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,address)", p0, p1, p2));
    }

    function log(uint256 p0, address p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,uint256)", p0, p1, p2));
    }

    function log(uint256 p0, address p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,string)", p0, p1, p2));
    }

    function log(uint256 p0, address p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,bool)", p0, p1, p2));
    }

    function log(uint256 p0, address p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,address)", p0, p1, p2));
    }

    function log(string memory p0, uint256 p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,uint256)", p0, p1, p2));
    }

    function log(string memory p0, uint256 p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,string)", p0, p1, p2));
    }

    function log(string memory p0, uint256 p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,bool)", p0, p1, p2));
    }

    function log(string memory p0, uint256 p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,address)", p0, p1, p2));
    }

    function log(string memory p0, string memory p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,uint256)", p0, p1, p2));
    }

    function log(string memory p0, string memory p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,string)", p0, p1, p2));
    }

    function log(string memory p0, string memory p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,bool)", p0, p1, p2));
    }

    function log(string memory p0, string memory p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,address)", p0, p1, p2));
    }

    function log(string memory p0, bool p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,uint256)", p0, p1, p2));
    }

    function log(string memory p0, bool p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,string)", p0, p1, p2));
    }

    function log(string memory p0, bool p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,bool)", p0, p1, p2));
    }

    function log(string memory p0, bool p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,address)", p0, p1, p2));
    }

    function log(string memory p0, address p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,uint256)", p0, p1, p2));
    }

    function log(string memory p0, address p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,string)", p0, p1, p2));
    }

    function log(string memory p0, address p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,bool)", p0, p1, p2));
    }

    function log(string memory p0, address p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,address)", p0, p1, p2));
    }

    function log(bool p0, uint256 p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,uint256)", p0, p1, p2));
    }

    function log(bool p0, uint256 p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,string)", p0, p1, p2));
    }

    function log(bool p0, uint256 p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,bool)", p0, p1, p2));
    }

    function log(bool p0, uint256 p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,address)", p0, p1, p2));
    }

    function log(bool p0, string memory p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,uint256)", p0, p1, p2));
    }

    function log(bool p0, string memory p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,string)", p0, p1, p2));
    }

    function log(bool p0, string memory p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,bool)", p0, p1, p2));
    }

    function log(bool p0, string memory p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,address)", p0, p1, p2));
    }

    function log(bool p0, bool p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,uint256)", p0, p1, p2));
    }

    function log(bool p0, bool p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,string)", p0, p1, p2));
    }

    function log(bool p0, bool p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,bool)", p0, p1, p2));
    }

    function log(bool p0, bool p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,address)", p0, p1, p2));
    }

    function log(bool p0, address p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,uint256)", p0, p1, p2));
    }

    function log(bool p0, address p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,string)", p0, p1, p2));
    }

    function log(bool p0, address p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,bool)", p0, p1, p2));
    }

    function log(bool p0, address p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,address)", p0, p1, p2));
    }

    function log(address p0, uint256 p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,uint256)", p0, p1, p2));
    }

    function log(address p0, uint256 p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,string)", p0, p1, p2));
    }

    function log(address p0, uint256 p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,bool)", p0, p1, p2));
    }

    function log(address p0, uint256 p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,address)", p0, p1, p2));
    }

    function log(address p0, string memory p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,uint256)", p0, p1, p2));
    }

    function log(address p0, string memory p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,string)", p0, p1, p2));
    }

    function log(address p0, string memory p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,bool)", p0, p1, p2));
    }

    function log(address p0, string memory p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,address)", p0, p1, p2));
    }

    function log(address p0, bool p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,uint256)", p0, p1, p2));
    }

    function log(address p0, bool p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,string)", p0, p1, p2));
    }

    function log(address p0, bool p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,bool)", p0, p1, p2));
    }

    function log(address p0, bool p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,address)", p0, p1, p2));
    }

    function log(address p0, address p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,uint256)", p0, p1, p2));
    }

    function log(address p0, address p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,string)", p0, p1, p2));
    }

    function log(address p0, address p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,bool)", p0, p1, p2));
    }

    function log(address p0, address p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,address)", p0, p1, p2));
    }

    function log(uint256 p0, uint256 p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,uint256,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,uint256,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,uint256,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,string,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,string,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,string,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,string,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,bool,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,bool,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,bool,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,bool,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,address,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,address,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,address,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,address,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,uint256,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,uint256,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,uint256,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,string,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,string,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,string,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,string,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,bool,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,bool,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,bool,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,bool,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,address,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,address,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,address,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,address,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,uint256,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,uint256,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,uint256,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,string,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,string,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,string,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,string,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,bool,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,bool,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,bool,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,bool,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,address,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,address,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,address,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,address,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,uint256,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,uint256,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,uint256,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,string,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,string,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,string,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,string,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,bool,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,bool,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,bool,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,bool,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,address,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,address,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,address,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,address,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,uint256,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,uint256,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,uint256,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,string,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,string,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,string,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,string,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,bool,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,bool,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,bool,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,bool,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,address,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,address,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,address,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,address,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,uint256,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,uint256,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,uint256,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,string,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,string,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,string,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,string,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,bool,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,bool,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,bool,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,bool,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,address,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,address,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,address,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,address,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,uint256,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,uint256,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,uint256,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,string,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,string,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,string,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,string,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,bool,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,bool,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,bool,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,bool,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,address,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,address,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,address,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,address,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,uint256,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,uint256,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,uint256,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,string,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,string,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,string,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,string,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,bool,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,bool,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,bool,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,bool,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,address,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,address,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,address,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,address,address)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,uint256,string)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,uint256,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,uint256,address)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,string,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,string,string)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,string,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,string,address)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,bool,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,bool,string)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,bool,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,bool,address)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,address,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,address,string)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,address,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,address,address)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,uint256,string)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,uint256,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,uint256,address)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,string,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,string,string)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,string,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,string,address)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,bool,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,bool,string)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,bool,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,bool,address)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,address,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,address,string)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,address,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,address,address)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,uint256,string)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,uint256,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,uint256,address)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,string,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,string,string)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,string,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,string,address)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,bool,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,bool,string)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,bool,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,bool,address)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,address,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,address,string)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,address,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,address,address)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,uint256,string)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,uint256,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,uint256,address)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,string,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,string,string)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,string,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,string,address)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,bool,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,bool,string)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,bool,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,bool,address)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,address,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,address,string)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,address,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,address,address)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,uint256,string)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,uint256,bool)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,uint256,address)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,string,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,string,string)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,string,bool)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,string,address)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,bool,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,bool,string)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,bool,bool)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,bool,address)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,address,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,address,string)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,address,bool)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,address,address)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,uint256,string)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,uint256,bool)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,uint256,address)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,string,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,string,string)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,string,bool)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,string,address)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,bool,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,bool,string)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,bool,bool)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,bool,address)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,address,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,address,string)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,address,bool)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,address,address)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,uint256,string)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,uint256,bool)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,uint256,address)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,string,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,string,string)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,string,bool)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,string,address)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,bool,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,bool,string)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,bool,bool)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,bool,address)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,address,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,address,string)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,address,bool)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,address,address)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,uint256,string)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,uint256,bool)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,uint256,address)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,string,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,string,string)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,string,bool)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,string,address)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,bool,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,bool,string)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,bool,bool)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,bool,address)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,address,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,address,string)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,address,bool)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,address,address)", p0, p1, p2, p3));
    }
}

// node_modules/@openzeppelin/contracts/interfaces/draft-IERC1822.sol

// OpenZeppelin Contracts (last updated v4.5.0) (interfaces/draft-IERC1822.sol)

/**
 * @dev ERC1822: Universal Upgradeable Proxy Standard (UUPS) documents a method for upgradeability through a simplified
 * proxy whose upgrades are fully controlled by the current implementation.
 */
interface IERC1822Proxiable {
    /**
     * @dev Returns the storage slot that the proxiable contract assumes is being used to store the implementation
     * address.
     *
     * IMPORTANT: A proxy pointing at a proxiable contract should not be considered proxiable itself, because this risks
     * bricking a proxy that upgrades to it, by delegating to itself until out of gas. Thus it is critical that this
     * function revert if invoked through a proxy.
     */
    function proxiableUUID() external view returns (bytes32);
}

// lib/forge-std/src/safeconsole.sol

/// @author philogy <https://github.com/philogy>
/// @dev Code generated automatically by script.
library safeconsole {
    uint256 constant CONSOLE_ADDR = 0x000000000000000000000000000000000000000000636F6e736F6c652e6c6f67;

    // Credit to [0age](https://twitter.com/z0age/status/1654922202930888704) and [0xdapper](https://github.com/foundry-rs/forge-std/pull/374)
    // for the view-to-pure log trick.
    function _sendLogPayload(uint256 offset, uint256 size) private pure {
        function(uint256, uint256) internal view fnIn = _sendLogPayloadView;
        function(uint256, uint256) internal pure pureSendLogPayload;
        /// @solidity memory-safe-assembly
        assembly {
            pureSendLogPayload := fnIn
        }
        pureSendLogPayload(offset, size);
    }

    function _sendLogPayloadView(uint256 offset, uint256 size) private view {
        /// @solidity memory-safe-assembly
        assembly {
            pop(staticcall(gas(), CONSOLE_ADDR, offset, size, 0x0, 0x0))
        }
    }

    function _memcopy(uint256 fromOffset, uint256 toOffset, uint256 length) private pure {
        function(uint256, uint256, uint256) internal view fnIn = _memcopyView;
        function(uint256, uint256, uint256) internal pure pureMemcopy;
        /// @solidity memory-safe-assembly
        assembly {
            pureMemcopy := fnIn
        }
        pureMemcopy(fromOffset, toOffset, length);
    }

    function _memcopyView(uint256 fromOffset, uint256 toOffset, uint256 length) private view {
        /// @solidity memory-safe-assembly
        assembly {
            pop(staticcall(gas(), 0x4, fromOffset, length, toOffset, length))
        }
    }

    function logMemory(uint256 offset, uint256 length) internal pure {
        if (offset >= 0x60) {
            // Sufficient memory before slice to prepare call header.
            bytes32 m0;
            bytes32 m1;
            bytes32 m2;
            /// @solidity memory-safe-assembly
            assembly {
                m0 := mload(sub(offset, 0x60))
                m1 := mload(sub(offset, 0x40))
                m2 := mload(sub(offset, 0x20))
                // Selector of `log(bytes)`.
                mstore(sub(offset, 0x60), 0x0be77f56)
                mstore(sub(offset, 0x40), 0x20)
                mstore(sub(offset, 0x20), length)
            }
            _sendLogPayload(offset - 0x44, length + 0x44);
            /// @solidity memory-safe-assembly
            assembly {
                mstore(sub(offset, 0x60), m0)
                mstore(sub(offset, 0x40), m1)
                mstore(sub(offset, 0x20), m2)
            }
        } else {
            // Insufficient space, so copy slice forward, add header and reverse.
            bytes32 m0;
            bytes32 m1;
            bytes32 m2;
            uint256 endOffset = offset + length;
            /// @solidity memory-safe-assembly
            assembly {
                m0 := mload(add(endOffset, 0x00))
                m1 := mload(add(endOffset, 0x20))
                m2 := mload(add(endOffset, 0x40))
            }
            _memcopy(offset, offset + 0x60, length);
            /// @solidity memory-safe-assembly
            assembly {
                // Selector of `log(bytes)`.
                mstore(add(offset, 0x00), 0x0be77f56)
                mstore(add(offset, 0x20), 0x20)
                mstore(add(offset, 0x40), length)
            }
            _sendLogPayload(offset + 0x1c, length + 0x44);
            _memcopy(offset + 0x60, offset, length);
            /// @solidity memory-safe-assembly
            assembly {
                mstore(add(endOffset, 0x00), m0)
                mstore(add(endOffset, 0x20), m1)
                mstore(add(endOffset, 0x40), m2)
            }
        }
    }

    function log(address p0) internal pure {
        bytes32 m0;
        bytes32 m1;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            // Selector of `log(address)`.
            mstore(0x00, 0x2c2ecbc2)
            mstore(0x20, p0)
        }
        _sendLogPayload(0x1c, 0x24);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
        }
    }

    function log(bool p0) internal pure {
        bytes32 m0;
        bytes32 m1;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            // Selector of `log(bool)`.
            mstore(0x00, 0x32458eed)
            mstore(0x20, p0)
        }
        _sendLogPayload(0x1c, 0x24);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
        }
    }

    function log(uint256 p0) internal pure {
        bytes32 m0;
        bytes32 m1;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            // Selector of `log(uint256)`.
            mstore(0x00, 0xf82c50f1)
            mstore(0x20, p0)
        }
        _sendLogPayload(0x1c, 0x24);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
        }
    }

    function log(bytes32 p0) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(string)`.
            mstore(0x00, 0x41304fac)
            mstore(0x20, 0x20)
            writeString(0x40, p0)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(address p0, address p1) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            // Selector of `log(address,address)`.
            mstore(0x00, 0xdaf0d4aa)
            mstore(0x20, p0)
            mstore(0x40, p1)
        }
        _sendLogPayload(0x1c, 0x44);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
        }
    }

    function log(address p0, bool p1) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            // Selector of `log(address,bool)`.
            mstore(0x00, 0x75b605d3)
            mstore(0x20, p0)
            mstore(0x40, p1)
        }
        _sendLogPayload(0x1c, 0x44);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
        }
    }

    function log(address p0, uint256 p1) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            // Selector of `log(address,uint256)`.
            mstore(0x00, 0x8309e8a8)
            mstore(0x20, p0)
            mstore(0x40, p1)
        }
        _sendLogPayload(0x1c, 0x44);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
        }
    }

    function log(address p0, bytes32 p1) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,string)`.
            mstore(0x00, 0x759f86bb)
            mstore(0x20, p0)
            mstore(0x40, 0x40)
            writeString(0x60, p1)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, address p1) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            // Selector of `log(bool,address)`.
            mstore(0x00, 0x853c4849)
            mstore(0x20, p0)
            mstore(0x40, p1)
        }
        _sendLogPayload(0x1c, 0x44);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
        }
    }

    function log(bool p0, bool p1) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            // Selector of `log(bool,bool)`.
            mstore(0x00, 0x2a110e83)
            mstore(0x20, p0)
            mstore(0x40, p1)
        }
        _sendLogPayload(0x1c, 0x44);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
        }
    }

    function log(bool p0, uint256 p1) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            // Selector of `log(bool,uint256)`.
            mstore(0x00, 0x399174d3)
            mstore(0x20, p0)
            mstore(0x40, p1)
        }
        _sendLogPayload(0x1c, 0x44);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
        }
    }

    function log(bool p0, bytes32 p1) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,string)`.
            mstore(0x00, 0x8feac525)
            mstore(0x20, p0)
            mstore(0x40, 0x40)
            writeString(0x60, p1)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, address p1) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            // Selector of `log(uint256,address)`.
            mstore(0x00, 0x69276c86)
            mstore(0x20, p0)
            mstore(0x40, p1)
        }
        _sendLogPayload(0x1c, 0x44);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
        }
    }

    function log(uint256 p0, bool p1) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            // Selector of `log(uint256,bool)`.
            mstore(0x00, 0x1c9d7eb3)
            mstore(0x20, p0)
            mstore(0x40, p1)
        }
        _sendLogPayload(0x1c, 0x44);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
        }
    }

    function log(uint256 p0, uint256 p1) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            // Selector of `log(uint256,uint256)`.
            mstore(0x00, 0xf666715a)
            mstore(0x20, p0)
            mstore(0x40, p1)
        }
        _sendLogPayload(0x1c, 0x44);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
        }
    }

    function log(uint256 p0, bytes32 p1) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,string)`.
            mstore(0x00, 0x643fd0df)
            mstore(0x20, p0)
            mstore(0x40, 0x40)
            writeString(0x60, p1)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bytes32 p0, address p1) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(string,address)`.
            mstore(0x00, 0x319af333)
            mstore(0x20, 0x40)
            mstore(0x40, p1)
            writeString(0x60, p0)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bytes32 p0, bool p1) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(string,bool)`.
            mstore(0x00, 0xc3b55635)
            mstore(0x20, 0x40)
            mstore(0x40, p1)
            writeString(0x60, p0)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bytes32 p0, uint256 p1) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(string,uint256)`.
            mstore(0x00, 0xb60e72cc)
            mstore(0x20, 0x40)
            mstore(0x40, p1)
            writeString(0x60, p0)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bytes32 p0, bytes32 p1) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,string)`.
            mstore(0x00, 0x4b5c4277)
            mstore(0x20, 0x40)
            mstore(0x40, 0x80)
            writeString(0x60, p0)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, address p1, address p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(address,address,address)`.
            mstore(0x00, 0x018c84c2)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(address p0, address p1, bool p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(address,address,bool)`.
            mstore(0x00, 0xf2a66286)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(address p0, address p1, uint256 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(address,address,uint256)`.
            mstore(0x00, 0x17fe6185)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(address p0, address p1, bytes32 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(address,address,string)`.
            mstore(0x00, 0x007150be)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x60)
            writeString(0x80, p2)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(address p0, bool p1, address p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(address,bool,address)`.
            mstore(0x00, 0xf11699ed)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(address p0, bool p1, bool p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(address,bool,bool)`.
            mstore(0x00, 0xeb830c92)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(address p0, bool p1, uint256 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(address,bool,uint256)`.
            mstore(0x00, 0x9c4f99fb)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(address p0, bool p1, bytes32 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(address,bool,string)`.
            mstore(0x00, 0x212255cc)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x60)
            writeString(0x80, p2)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(address p0, uint256 p1, address p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(address,uint256,address)`.
            mstore(0x00, 0x7bc0d848)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(address p0, uint256 p1, bool p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(address,uint256,bool)`.
            mstore(0x00, 0x678209a8)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(address p0, uint256 p1, uint256 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(address,uint256,uint256)`.
            mstore(0x00, 0xb69bcaf6)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(address p0, uint256 p1, bytes32 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(address,uint256,string)`.
            mstore(0x00, 0xa1f2e8aa)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x60)
            writeString(0x80, p2)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(address p0, bytes32 p1, address p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(address,string,address)`.
            mstore(0x00, 0xf08744e8)
            mstore(0x20, p0)
            mstore(0x40, 0x60)
            mstore(0x60, p2)
            writeString(0x80, p1)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(address p0, bytes32 p1, bool p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(address,string,bool)`.
            mstore(0x00, 0xcf020fb1)
            mstore(0x20, p0)
            mstore(0x40, 0x60)
            mstore(0x60, p2)
            writeString(0x80, p1)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(address p0, bytes32 p1, uint256 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(address,string,uint256)`.
            mstore(0x00, 0x67dd6ff1)
            mstore(0x20, p0)
            mstore(0x40, 0x60)
            mstore(0x60, p2)
            writeString(0x80, p1)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(address p0, bytes32 p1, bytes32 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            // Selector of `log(address,string,string)`.
            mstore(0x00, 0xfb772265)
            mstore(0x20, p0)
            mstore(0x40, 0x60)
            mstore(0x60, 0xa0)
            writeString(0x80, p1)
            writeString(0xc0, p2)
        }
        _sendLogPayload(0x1c, 0xe4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
        }
    }

    function log(bool p0, address p1, address p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(bool,address,address)`.
            mstore(0x00, 0xd2763667)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(bool p0, address p1, bool p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(bool,address,bool)`.
            mstore(0x00, 0x18c9c746)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(bool p0, address p1, uint256 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(bool,address,uint256)`.
            mstore(0x00, 0x5f7b9afb)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(bool p0, address p1, bytes32 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(bool,address,string)`.
            mstore(0x00, 0xde9a9270)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x60)
            writeString(0x80, p2)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(bool p0, bool p1, address p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(bool,bool,address)`.
            mstore(0x00, 0x1078f68d)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(bool p0, bool p1, bool p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(bool,bool,bool)`.
            mstore(0x00, 0x50709698)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(bool p0, bool p1, uint256 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(bool,bool,uint256)`.
            mstore(0x00, 0x12f21602)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(bool p0, bool p1, bytes32 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(bool,bool,string)`.
            mstore(0x00, 0x2555fa46)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x60)
            writeString(0x80, p2)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(bool p0, uint256 p1, address p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(bool,uint256,address)`.
            mstore(0x00, 0x088ef9d2)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(bool p0, uint256 p1, bool p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(bool,uint256,bool)`.
            mstore(0x00, 0xe8defba9)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(bool p0, uint256 p1, uint256 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(bool,uint256,uint256)`.
            mstore(0x00, 0x37103367)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(bool p0, uint256 p1, bytes32 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(bool,uint256,string)`.
            mstore(0x00, 0xc3fc3970)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x60)
            writeString(0x80, p2)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(bool p0, bytes32 p1, address p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(bool,string,address)`.
            mstore(0x00, 0x9591b953)
            mstore(0x20, p0)
            mstore(0x40, 0x60)
            mstore(0x60, p2)
            writeString(0x80, p1)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(bool p0, bytes32 p1, bool p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(bool,string,bool)`.
            mstore(0x00, 0xdbb4c247)
            mstore(0x20, p0)
            mstore(0x40, 0x60)
            mstore(0x60, p2)
            writeString(0x80, p1)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(bool p0, bytes32 p1, uint256 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(bool,string,uint256)`.
            mstore(0x00, 0x1093ee11)
            mstore(0x20, p0)
            mstore(0x40, 0x60)
            mstore(0x60, p2)
            writeString(0x80, p1)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(bool p0, bytes32 p1, bytes32 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            // Selector of `log(bool,string,string)`.
            mstore(0x00, 0xb076847f)
            mstore(0x20, p0)
            mstore(0x40, 0x60)
            mstore(0x60, 0xa0)
            writeString(0x80, p1)
            writeString(0xc0, p2)
        }
        _sendLogPayload(0x1c, 0xe4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
        }
    }

    function log(uint256 p0, address p1, address p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(uint256,address,address)`.
            mstore(0x00, 0xbcfd9be0)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(uint256 p0, address p1, bool p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(uint256,address,bool)`.
            mstore(0x00, 0x9b6ec042)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(uint256 p0, address p1, uint256 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(uint256,address,uint256)`.
            mstore(0x00, 0x5a9b5ed5)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(uint256 p0, address p1, bytes32 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(uint256,address,string)`.
            mstore(0x00, 0x63cb41f9)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x60)
            writeString(0x80, p2)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(uint256 p0, bool p1, address p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(uint256,bool,address)`.
            mstore(0x00, 0x35085f7b)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(uint256 p0, bool p1, bool p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(uint256,bool,bool)`.
            mstore(0x00, 0x20718650)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(uint256 p0, bool p1, uint256 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(uint256,bool,uint256)`.
            mstore(0x00, 0x20098014)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(uint256 p0, bool p1, bytes32 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(uint256,bool,string)`.
            mstore(0x00, 0x85775021)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x60)
            writeString(0x80, p2)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(uint256 p0, uint256 p1, address p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(uint256,uint256,address)`.
            mstore(0x00, 0x5c96b331)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(uint256 p0, uint256 p1, bool p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(uint256,uint256,bool)`.
            mstore(0x00, 0x4766da72)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(uint256 p0, uint256 p1, uint256 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            // Selector of `log(uint256,uint256,uint256)`.
            mstore(0x00, 0xd1ed7a3c)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
        }
        _sendLogPayload(0x1c, 0x64);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
        }
    }

    function log(uint256 p0, uint256 p1, bytes32 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(uint256,uint256,string)`.
            mstore(0x00, 0x71d04af2)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x60)
            writeString(0x80, p2)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(uint256 p0, bytes32 p1, address p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(uint256,string,address)`.
            mstore(0x00, 0x7afac959)
            mstore(0x20, p0)
            mstore(0x40, 0x60)
            mstore(0x60, p2)
            writeString(0x80, p1)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(uint256 p0, bytes32 p1, bool p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(uint256,string,bool)`.
            mstore(0x00, 0x4ceda75a)
            mstore(0x20, p0)
            mstore(0x40, 0x60)
            mstore(0x60, p2)
            writeString(0x80, p1)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(uint256 p0, bytes32 p1, uint256 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(uint256,string,uint256)`.
            mstore(0x00, 0x37aa7d4c)
            mstore(0x20, p0)
            mstore(0x40, 0x60)
            mstore(0x60, p2)
            writeString(0x80, p1)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(uint256 p0, bytes32 p1, bytes32 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            // Selector of `log(uint256,string,string)`.
            mstore(0x00, 0xb115611f)
            mstore(0x20, p0)
            mstore(0x40, 0x60)
            mstore(0x60, 0xa0)
            writeString(0x80, p1)
            writeString(0xc0, p2)
        }
        _sendLogPayload(0x1c, 0xe4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
        }
    }

    function log(bytes32 p0, address p1, address p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(string,address,address)`.
            mstore(0x00, 0xfcec75e0)
            mstore(0x20, 0x60)
            mstore(0x40, p1)
            mstore(0x60, p2)
            writeString(0x80, p0)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(bytes32 p0, address p1, bool p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(string,address,bool)`.
            mstore(0x00, 0xc91d5ed4)
            mstore(0x20, 0x60)
            mstore(0x40, p1)
            mstore(0x60, p2)
            writeString(0x80, p0)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(bytes32 p0, address p1, uint256 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(string,address,uint256)`.
            mstore(0x00, 0x0d26b925)
            mstore(0x20, 0x60)
            mstore(0x40, p1)
            mstore(0x60, p2)
            writeString(0x80, p0)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(bytes32 p0, address p1, bytes32 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            // Selector of `log(string,address,string)`.
            mstore(0x00, 0xe0e9ad4f)
            mstore(0x20, 0x60)
            mstore(0x40, p1)
            mstore(0x60, 0xa0)
            writeString(0x80, p0)
            writeString(0xc0, p2)
        }
        _sendLogPayload(0x1c, 0xe4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
        }
    }

    function log(bytes32 p0, bool p1, address p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(string,bool,address)`.
            mstore(0x00, 0x932bbb38)
            mstore(0x20, 0x60)
            mstore(0x40, p1)
            mstore(0x60, p2)
            writeString(0x80, p0)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(bytes32 p0, bool p1, bool p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(string,bool,bool)`.
            mstore(0x00, 0x850b7ad6)
            mstore(0x20, 0x60)
            mstore(0x40, p1)
            mstore(0x60, p2)
            writeString(0x80, p0)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(bytes32 p0, bool p1, uint256 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(string,bool,uint256)`.
            mstore(0x00, 0xc95958d6)
            mstore(0x20, 0x60)
            mstore(0x40, p1)
            mstore(0x60, p2)
            writeString(0x80, p0)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(bytes32 p0, bool p1, bytes32 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            // Selector of `log(string,bool,string)`.
            mstore(0x00, 0xe298f47d)
            mstore(0x20, 0x60)
            mstore(0x40, p1)
            mstore(0x60, 0xa0)
            writeString(0x80, p0)
            writeString(0xc0, p2)
        }
        _sendLogPayload(0x1c, 0xe4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
        }
    }

    function log(bytes32 p0, uint256 p1, address p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(string,uint256,address)`.
            mstore(0x00, 0x1c7ec448)
            mstore(0x20, 0x60)
            mstore(0x40, p1)
            mstore(0x60, p2)
            writeString(0x80, p0)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(bytes32 p0, uint256 p1, bool p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(string,uint256,bool)`.
            mstore(0x00, 0xca7733b1)
            mstore(0x20, 0x60)
            mstore(0x40, p1)
            mstore(0x60, p2)
            writeString(0x80, p0)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(bytes32 p0, uint256 p1, uint256 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            // Selector of `log(string,uint256,uint256)`.
            mstore(0x00, 0xca47c4eb)
            mstore(0x20, 0x60)
            mstore(0x40, p1)
            mstore(0x60, p2)
            writeString(0x80, p0)
        }
        _sendLogPayload(0x1c, 0xa4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
        }
    }

    function log(bytes32 p0, uint256 p1, bytes32 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            // Selector of `log(string,uint256,string)`.
            mstore(0x00, 0x5970e089)
            mstore(0x20, 0x60)
            mstore(0x40, p1)
            mstore(0x60, 0xa0)
            writeString(0x80, p0)
            writeString(0xc0, p2)
        }
        _sendLogPayload(0x1c, 0xe4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
        }
    }

    function log(bytes32 p0, bytes32 p1, address p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            // Selector of `log(string,string,address)`.
            mstore(0x00, 0x95ed0195)
            mstore(0x20, 0x60)
            mstore(0x40, 0xa0)
            mstore(0x60, p2)
            writeString(0x80, p0)
            writeString(0xc0, p1)
        }
        _sendLogPayload(0x1c, 0xe4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
        }
    }

    function log(bytes32 p0, bytes32 p1, bool p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            // Selector of `log(string,string,bool)`.
            mstore(0x00, 0xb0e0f9b5)
            mstore(0x20, 0x60)
            mstore(0x40, 0xa0)
            mstore(0x60, p2)
            writeString(0x80, p0)
            writeString(0xc0, p1)
        }
        _sendLogPayload(0x1c, 0xe4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
        }
    }

    function log(bytes32 p0, bytes32 p1, uint256 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            // Selector of `log(string,string,uint256)`.
            mstore(0x00, 0x5821efa1)
            mstore(0x20, 0x60)
            mstore(0x40, 0xa0)
            mstore(0x60, p2)
            writeString(0x80, p0)
            writeString(0xc0, p1)
        }
        _sendLogPayload(0x1c, 0xe4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
        }
    }

    function log(bytes32 p0, bytes32 p1, bytes32 p2) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        bytes32 m9;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            m9 := mload(0x120)
            // Selector of `log(string,string,string)`.
            mstore(0x00, 0x2ced7cef)
            mstore(0x20, 0x60)
            mstore(0x40, 0xa0)
            mstore(0x60, 0xe0)
            writeString(0x80, p0)
            writeString(0xc0, p1)
            writeString(0x100, p2)
        }
        _sendLogPayload(0x1c, 0x124);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
            mstore(0x120, m9)
        }
    }

    function log(address p0, address p1, address p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,address,address,address)`.
            mstore(0x00, 0x665bf134)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, address p1, address p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,address,address,bool)`.
            mstore(0x00, 0x0e378994)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, address p1, address p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,address,address,uint256)`.
            mstore(0x00, 0x94250d77)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, address p1, address p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,address,address,string)`.
            mstore(0x00, 0xf808da20)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, address p1, bool p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,address,bool,address)`.
            mstore(0x00, 0x9f1bc36e)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, address p1, bool p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,address,bool,bool)`.
            mstore(0x00, 0x2cd4134a)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, address p1, bool p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,address,bool,uint256)`.
            mstore(0x00, 0x3971e78c)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, address p1, bool p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,address,bool,string)`.
            mstore(0x00, 0xaa6540c8)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, address p1, uint256 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,address,uint256,address)`.
            mstore(0x00, 0x8da6def5)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, address p1, uint256 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,address,uint256,bool)`.
            mstore(0x00, 0x9b4254e2)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, address p1, uint256 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,address,uint256,uint256)`.
            mstore(0x00, 0xbe553481)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, address p1, uint256 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,address,uint256,string)`.
            mstore(0x00, 0xfdb4f990)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, address p1, bytes32 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,address,string,address)`.
            mstore(0x00, 0x8f736d16)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, address p1, bytes32 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,address,string,bool)`.
            mstore(0x00, 0x6f1a594e)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, address p1, bytes32 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,address,string,uint256)`.
            mstore(0x00, 0xef1cefe7)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, address p1, bytes32 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(address,address,string,string)`.
            mstore(0x00, 0x21bdaf25)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, 0xc0)
            writeString(0xa0, p2)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(address p0, bool p1, address p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,bool,address,address)`.
            mstore(0x00, 0x660375dd)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, bool p1, address p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,bool,address,bool)`.
            mstore(0x00, 0xa6f50b0f)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, bool p1, address p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,bool,address,uint256)`.
            mstore(0x00, 0xa75c59de)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, bool p1, address p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,bool,address,string)`.
            mstore(0x00, 0x2dd778e6)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, bool p1, bool p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,bool,bool,address)`.
            mstore(0x00, 0xcf394485)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, bool p1, bool p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,bool,bool,bool)`.
            mstore(0x00, 0xcac43479)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, bool p1, bool p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,bool,bool,uint256)`.
            mstore(0x00, 0x8c4e5de6)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, bool p1, bool p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,bool,bool,string)`.
            mstore(0x00, 0xdfc4a2e8)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, bool p1, uint256 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,bool,uint256,address)`.
            mstore(0x00, 0xccf790a1)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, bool p1, uint256 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,bool,uint256,bool)`.
            mstore(0x00, 0xc4643e20)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, bool p1, uint256 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,bool,uint256,uint256)`.
            mstore(0x00, 0x386ff5f4)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, bool p1, uint256 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,bool,uint256,string)`.
            mstore(0x00, 0x0aa6cfad)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, bool p1, bytes32 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,bool,string,address)`.
            mstore(0x00, 0x19fd4956)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, bool p1, bytes32 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,bool,string,bool)`.
            mstore(0x00, 0x50ad461d)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, bool p1, bytes32 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,bool,string,uint256)`.
            mstore(0x00, 0x80e6a20b)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, bool p1, bytes32 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(address,bool,string,string)`.
            mstore(0x00, 0x475c5c33)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, 0xc0)
            writeString(0xa0, p2)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(address p0, uint256 p1, address p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,uint256,address,address)`.
            mstore(0x00, 0x478d1c62)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, uint256 p1, address p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,uint256,address,bool)`.
            mstore(0x00, 0xa1bcc9b3)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, uint256 p1, address p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,uint256,address,uint256)`.
            mstore(0x00, 0x100f650e)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, uint256 p1, address p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,uint256,address,string)`.
            mstore(0x00, 0x1da986ea)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, uint256 p1, bool p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,uint256,bool,address)`.
            mstore(0x00, 0xa31bfdcc)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, uint256 p1, bool p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,uint256,bool,bool)`.
            mstore(0x00, 0x3bf5e537)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, uint256 p1, bool p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,uint256,bool,uint256)`.
            mstore(0x00, 0x22f6b999)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, uint256 p1, bool p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,uint256,bool,string)`.
            mstore(0x00, 0xc5ad85f9)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, uint256 p1, uint256 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,uint256,uint256,address)`.
            mstore(0x00, 0x20e3984d)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, uint256 p1, uint256 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,uint256,uint256,bool)`.
            mstore(0x00, 0x66f1bc67)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, uint256 p1, uint256 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(address,uint256,uint256,uint256)`.
            mstore(0x00, 0x34f0e636)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(address p0, uint256 p1, uint256 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,uint256,uint256,string)`.
            mstore(0x00, 0x4a28c017)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, uint256 p1, bytes32 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,uint256,string,address)`.
            mstore(0x00, 0x5c430d47)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, uint256 p1, bytes32 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,uint256,string,bool)`.
            mstore(0x00, 0xcf18105c)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, uint256 p1, bytes32 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,uint256,string,uint256)`.
            mstore(0x00, 0xbf01f891)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, uint256 p1, bytes32 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(address,uint256,string,string)`.
            mstore(0x00, 0x88a8c406)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, 0xc0)
            writeString(0xa0, p2)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(address p0, bytes32 p1, address p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,string,address,address)`.
            mstore(0x00, 0x0d36fa20)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, bytes32 p1, address p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,string,address,bool)`.
            mstore(0x00, 0x0df12b76)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, bytes32 p1, address p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,string,address,uint256)`.
            mstore(0x00, 0x457fe3cf)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, bytes32 p1, address p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(address,string,address,string)`.
            mstore(0x00, 0xf7e36245)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, 0xc0)
            writeString(0xa0, p1)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(address p0, bytes32 p1, bool p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,string,bool,address)`.
            mstore(0x00, 0x205871c2)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, bytes32 p1, bool p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,string,bool,bool)`.
            mstore(0x00, 0x5f1d5c9f)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, bytes32 p1, bool p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,string,bool,uint256)`.
            mstore(0x00, 0x515e38b6)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, bytes32 p1, bool p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(address,string,bool,string)`.
            mstore(0x00, 0xbc0b61fe)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, 0xc0)
            writeString(0xa0, p1)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(address p0, bytes32 p1, uint256 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,string,uint256,address)`.
            mstore(0x00, 0x63183678)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, bytes32 p1, uint256 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,string,uint256,bool)`.
            mstore(0x00, 0x0ef7e050)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, bytes32 p1, uint256 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(address,string,uint256,uint256)`.
            mstore(0x00, 0x1dc8e1b8)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(address p0, bytes32 p1, uint256 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(address,string,uint256,string)`.
            mstore(0x00, 0x448830a8)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, 0xc0)
            writeString(0xa0, p1)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(address p0, bytes32 p1, bytes32 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(address,string,string,address)`.
            mstore(0x00, 0xa04e2f87)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, 0xc0)
            mstore(0x80, p3)
            writeString(0xa0, p1)
            writeString(0xe0, p2)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(address p0, bytes32 p1, bytes32 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(address,string,string,bool)`.
            mstore(0x00, 0x35a5071f)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, 0xc0)
            mstore(0x80, p3)
            writeString(0xa0, p1)
            writeString(0xe0, p2)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(address p0, bytes32 p1, bytes32 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(address,string,string,uint256)`.
            mstore(0x00, 0x159f8927)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, 0xc0)
            mstore(0x80, p3)
            writeString(0xa0, p1)
            writeString(0xe0, p2)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(address p0, bytes32 p1, bytes32 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        bytes32 m9;
        bytes32 m10;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            m9 := mload(0x120)
            m10 := mload(0x140)
            // Selector of `log(address,string,string,string)`.
            mstore(0x00, 0x5d02c50b)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, 0xc0)
            mstore(0x80, 0x100)
            writeString(0xa0, p1)
            writeString(0xe0, p2)
            writeString(0x120, p3)
        }
        _sendLogPayload(0x1c, 0x144);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
            mstore(0x120, m9)
            mstore(0x140, m10)
        }
    }

    function log(bool p0, address p1, address p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,address,address,address)`.
            mstore(0x00, 0x1d14d001)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, address p1, address p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,address,address,bool)`.
            mstore(0x00, 0x46600be0)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, address p1, address p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,address,address,uint256)`.
            mstore(0x00, 0x0c66d1be)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, address p1, address p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,address,address,string)`.
            mstore(0x00, 0xd812a167)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, address p1, bool p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,address,bool,address)`.
            mstore(0x00, 0x1c41a336)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, address p1, bool p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,address,bool,bool)`.
            mstore(0x00, 0x6a9c478b)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, address p1, bool p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,address,bool,uint256)`.
            mstore(0x00, 0x07831502)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, address p1, bool p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,address,bool,string)`.
            mstore(0x00, 0x4a66cb34)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, address p1, uint256 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,address,uint256,address)`.
            mstore(0x00, 0x136b05dd)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, address p1, uint256 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,address,uint256,bool)`.
            mstore(0x00, 0xd6019f1c)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, address p1, uint256 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,address,uint256,uint256)`.
            mstore(0x00, 0x7bf181a1)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, address p1, uint256 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,address,uint256,string)`.
            mstore(0x00, 0x51f09ff8)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, address p1, bytes32 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,address,string,address)`.
            mstore(0x00, 0x6f7c603e)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, address p1, bytes32 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,address,string,bool)`.
            mstore(0x00, 0xe2bfd60b)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, address p1, bytes32 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,address,string,uint256)`.
            mstore(0x00, 0xc21f64c7)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, address p1, bytes32 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(bool,address,string,string)`.
            mstore(0x00, 0xa73c1db6)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, 0xc0)
            writeString(0xa0, p2)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bool p0, bool p1, address p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,bool,address,address)`.
            mstore(0x00, 0xf4880ea4)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, bool p1, address p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,bool,address,bool)`.
            mstore(0x00, 0xc0a302d8)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, bool p1, address p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,bool,address,uint256)`.
            mstore(0x00, 0x4c123d57)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, bool p1, address p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,bool,address,string)`.
            mstore(0x00, 0xa0a47963)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, bool p1, bool p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,bool,bool,address)`.
            mstore(0x00, 0x8c329b1a)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, bool p1, bool p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,bool,bool,bool)`.
            mstore(0x00, 0x3b2a5ce0)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, bool p1, bool p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,bool,bool,uint256)`.
            mstore(0x00, 0x6d7045c1)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, bool p1, bool p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,bool,bool,string)`.
            mstore(0x00, 0x2ae408d4)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, bool p1, uint256 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,bool,uint256,address)`.
            mstore(0x00, 0x54a7a9a0)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, bool p1, uint256 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,bool,uint256,bool)`.
            mstore(0x00, 0x619e4d0e)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, bool p1, uint256 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,bool,uint256,uint256)`.
            mstore(0x00, 0x0bb00eab)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, bool p1, uint256 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,bool,uint256,string)`.
            mstore(0x00, 0x7dd4d0e0)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, bool p1, bytes32 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,bool,string,address)`.
            mstore(0x00, 0xf9ad2b89)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, bool p1, bytes32 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,bool,string,bool)`.
            mstore(0x00, 0xb857163a)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, bool p1, bytes32 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,bool,string,uint256)`.
            mstore(0x00, 0xe3a9ca2f)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, bool p1, bytes32 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(bool,bool,string,string)`.
            mstore(0x00, 0x6d1e8751)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, 0xc0)
            writeString(0xa0, p2)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bool p0, uint256 p1, address p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,uint256,address,address)`.
            mstore(0x00, 0x26f560a8)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, uint256 p1, address p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,uint256,address,bool)`.
            mstore(0x00, 0xb4c314ff)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, uint256 p1, address p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,uint256,address,uint256)`.
            mstore(0x00, 0x1537dc87)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, uint256 p1, address p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,uint256,address,string)`.
            mstore(0x00, 0x1bb3b09a)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, uint256 p1, bool p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,uint256,bool,address)`.
            mstore(0x00, 0x9acd3616)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, uint256 p1, bool p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,uint256,bool,bool)`.
            mstore(0x00, 0xceb5f4d7)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, uint256 p1, bool p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,uint256,bool,uint256)`.
            mstore(0x00, 0x7f9bbca2)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, uint256 p1, bool p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,uint256,bool,string)`.
            mstore(0x00, 0x9143dbb1)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, uint256 p1, uint256 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,uint256,uint256,address)`.
            mstore(0x00, 0x00dd87b9)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, uint256 p1, uint256 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,uint256,uint256,bool)`.
            mstore(0x00, 0xbe984353)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, uint256 p1, uint256 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(bool,uint256,uint256,uint256)`.
            mstore(0x00, 0x374bb4b2)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(bool p0, uint256 p1, uint256 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,uint256,uint256,string)`.
            mstore(0x00, 0x8e69fb5d)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, uint256 p1, bytes32 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,uint256,string,address)`.
            mstore(0x00, 0xfedd1fff)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, uint256 p1, bytes32 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,uint256,string,bool)`.
            mstore(0x00, 0xe5e70b2b)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, uint256 p1, bytes32 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,uint256,string,uint256)`.
            mstore(0x00, 0x6a1199e2)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, uint256 p1, bytes32 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(bool,uint256,string,string)`.
            mstore(0x00, 0xf5bc2249)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, 0xc0)
            writeString(0xa0, p2)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bool p0, bytes32 p1, address p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,string,address,address)`.
            mstore(0x00, 0x2b2b18dc)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, bytes32 p1, address p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,string,address,bool)`.
            mstore(0x00, 0x6dd434ca)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, bytes32 p1, address p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,string,address,uint256)`.
            mstore(0x00, 0xa5cada94)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, bytes32 p1, address p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(bool,string,address,string)`.
            mstore(0x00, 0x12d6c788)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, 0xc0)
            writeString(0xa0, p1)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bool p0, bytes32 p1, bool p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,string,bool,address)`.
            mstore(0x00, 0x538e06ab)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, bytes32 p1, bool p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,string,bool,bool)`.
            mstore(0x00, 0xdc5e935b)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, bytes32 p1, bool p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,string,bool,uint256)`.
            mstore(0x00, 0x1606a393)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, bytes32 p1, bool p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(bool,string,bool,string)`.
            mstore(0x00, 0x483d0416)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, 0xc0)
            writeString(0xa0, p1)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bool p0, bytes32 p1, uint256 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,string,uint256,address)`.
            mstore(0x00, 0x1596a1ce)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, bytes32 p1, uint256 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,string,uint256,bool)`.
            mstore(0x00, 0x6b0e5d53)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, bytes32 p1, uint256 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(bool,string,uint256,uint256)`.
            mstore(0x00, 0x28863fcb)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bool p0, bytes32 p1, uint256 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(bool,string,uint256,string)`.
            mstore(0x00, 0x1ad96de6)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, 0xc0)
            writeString(0xa0, p1)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bool p0, bytes32 p1, bytes32 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(bool,string,string,address)`.
            mstore(0x00, 0x97d394d8)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, 0xc0)
            mstore(0x80, p3)
            writeString(0xa0, p1)
            writeString(0xe0, p2)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bool p0, bytes32 p1, bytes32 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(bool,string,string,bool)`.
            mstore(0x00, 0x1e4b87e5)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, 0xc0)
            mstore(0x80, p3)
            writeString(0xa0, p1)
            writeString(0xe0, p2)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bool p0, bytes32 p1, bytes32 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(bool,string,string,uint256)`.
            mstore(0x00, 0x7be0c3eb)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, 0xc0)
            mstore(0x80, p3)
            writeString(0xa0, p1)
            writeString(0xe0, p2)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bool p0, bytes32 p1, bytes32 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        bytes32 m9;
        bytes32 m10;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            m9 := mload(0x120)
            m10 := mload(0x140)
            // Selector of `log(bool,string,string,string)`.
            mstore(0x00, 0x1762e32a)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, 0xc0)
            mstore(0x80, 0x100)
            writeString(0xa0, p1)
            writeString(0xe0, p2)
            writeString(0x120, p3)
        }
        _sendLogPayload(0x1c, 0x144);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
            mstore(0x120, m9)
            mstore(0x140, m10)
        }
    }

    function log(uint256 p0, address p1, address p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,address,address,address)`.
            mstore(0x00, 0x2488b414)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, address p1, address p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,address,address,bool)`.
            mstore(0x00, 0x091ffaf5)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, address p1, address p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,address,address,uint256)`.
            mstore(0x00, 0x736efbb6)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, address p1, address p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,address,address,string)`.
            mstore(0x00, 0x031c6f73)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, address p1, bool p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,address,bool,address)`.
            mstore(0x00, 0xef72c513)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, address p1, bool p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,address,bool,bool)`.
            mstore(0x00, 0xe351140f)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, address p1, bool p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,address,bool,uint256)`.
            mstore(0x00, 0x5abd992a)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, address p1, bool p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,address,bool,string)`.
            mstore(0x00, 0x90fb06aa)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, address p1, uint256 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,address,uint256,address)`.
            mstore(0x00, 0x15c127b5)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, address p1, uint256 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,address,uint256,bool)`.
            mstore(0x00, 0x5f743a7c)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, address p1, uint256 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,address,uint256,uint256)`.
            mstore(0x00, 0x0c9cd9c1)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, address p1, uint256 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,address,uint256,string)`.
            mstore(0x00, 0xddb06521)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, address p1, bytes32 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,address,string,address)`.
            mstore(0x00, 0x9cba8fff)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, address p1, bytes32 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,address,string,bool)`.
            mstore(0x00, 0xcc32ab07)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, address p1, bytes32 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,address,string,uint256)`.
            mstore(0x00, 0x46826b5d)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, address p1, bytes32 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(uint256,address,string,string)`.
            mstore(0x00, 0x3e128ca3)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, 0xc0)
            writeString(0xa0, p2)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(uint256 p0, bool p1, address p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,bool,address,address)`.
            mstore(0x00, 0xa1ef4cbb)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, bool p1, address p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,bool,address,bool)`.
            mstore(0x00, 0x454d54a5)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, bool p1, address p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,bool,address,uint256)`.
            mstore(0x00, 0x078287f5)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, bool p1, address p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,bool,address,string)`.
            mstore(0x00, 0xade052c7)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, bool p1, bool p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,bool,bool,address)`.
            mstore(0x00, 0x69640b59)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, bool p1, bool p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,bool,bool,bool)`.
            mstore(0x00, 0xb6f577a1)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, bool p1, bool p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,bool,bool,uint256)`.
            mstore(0x00, 0x7464ce23)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, bool p1, bool p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,bool,bool,string)`.
            mstore(0x00, 0xdddb9561)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, bool p1, uint256 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,bool,uint256,address)`.
            mstore(0x00, 0x88cb6041)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, bool p1, uint256 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,bool,uint256,bool)`.
            mstore(0x00, 0x91a02e2a)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, bool p1, uint256 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,bool,uint256,uint256)`.
            mstore(0x00, 0xc6acc7a8)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, bool p1, uint256 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,bool,uint256,string)`.
            mstore(0x00, 0xde03e774)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, bool p1, bytes32 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,bool,string,address)`.
            mstore(0x00, 0xef529018)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, bool p1, bytes32 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,bool,string,bool)`.
            mstore(0x00, 0xeb928d7f)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, bool p1, bytes32 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,bool,string,uint256)`.
            mstore(0x00, 0x2c1d0746)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, bool p1, bytes32 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(uint256,bool,string,string)`.
            mstore(0x00, 0x68c8b8bd)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, 0xc0)
            writeString(0xa0, p2)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(uint256 p0, uint256 p1, address p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,uint256,address,address)`.
            mstore(0x00, 0x56a5d1b1)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, uint256 p1, address p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,uint256,address,bool)`.
            mstore(0x00, 0x15cac476)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, uint256 p1, address p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,uint256,address,uint256)`.
            mstore(0x00, 0x88f6e4b2)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, uint256 p1, address p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,uint256,address,string)`.
            mstore(0x00, 0x6cde40b8)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, uint256 p1, bool p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,uint256,bool,address)`.
            mstore(0x00, 0x9a816a83)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, uint256 p1, bool p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,uint256,bool,bool)`.
            mstore(0x00, 0xab085ae6)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, uint256 p1, bool p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,uint256,bool,uint256)`.
            mstore(0x00, 0xeb7f6fd2)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, uint256 p1, bool p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,uint256,bool,string)`.
            mstore(0x00, 0xa5b4fc99)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, uint256 p1, uint256 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,uint256,uint256,address)`.
            mstore(0x00, 0xfa8185af)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, uint256 p1, uint256 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,uint256,uint256,bool)`.
            mstore(0x00, 0xc598d185)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, uint256 p1, uint256 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        /// @solidity memory-safe-assembly
        assembly {
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            // Selector of `log(uint256,uint256,uint256,uint256)`.
            mstore(0x00, 0x193fb800)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
        }
        _sendLogPayload(0x1c, 0x84);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
        }
    }

    function log(uint256 p0, uint256 p1, uint256 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,uint256,uint256,string)`.
            mstore(0x00, 0x59cfcbe3)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0x80)
            writeString(0xa0, p3)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, uint256 p1, bytes32 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,uint256,string,address)`.
            mstore(0x00, 0x42d21db7)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, uint256 p1, bytes32 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,uint256,string,bool)`.
            mstore(0x00, 0x7af6ab25)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, uint256 p1, bytes32 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,uint256,string,uint256)`.
            mstore(0x00, 0x5da297eb)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, p3)
            writeString(0xa0, p2)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, uint256 p1, bytes32 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(uint256,uint256,string,string)`.
            mstore(0x00, 0x27d8afd2)
            mstore(0x20, p0)
            mstore(0x40, p1)
            mstore(0x60, 0x80)
            mstore(0x80, 0xc0)
            writeString(0xa0, p2)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(uint256 p0, bytes32 p1, address p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,string,address,address)`.
            mstore(0x00, 0x6168ed61)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, bytes32 p1, address p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,string,address,bool)`.
            mstore(0x00, 0x90c30a56)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, bytes32 p1, address p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,string,address,uint256)`.
            mstore(0x00, 0xe8d3018d)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, bytes32 p1, address p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(uint256,string,address,string)`.
            mstore(0x00, 0x9c3adfa1)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, 0xc0)
            writeString(0xa0, p1)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(uint256 p0, bytes32 p1, bool p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,string,bool,address)`.
            mstore(0x00, 0xae2ec581)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, bytes32 p1, bool p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,string,bool,bool)`.
            mstore(0x00, 0xba535d9c)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, bytes32 p1, bool p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,string,bool,uint256)`.
            mstore(0x00, 0xcf009880)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, bytes32 p1, bool p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(uint256,string,bool,string)`.
            mstore(0x00, 0xd2d423cd)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, 0xc0)
            writeString(0xa0, p1)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(uint256 p0, bytes32 p1, uint256 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,string,uint256,address)`.
            mstore(0x00, 0x3b2279b4)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, bytes32 p1, uint256 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,string,uint256,bool)`.
            mstore(0x00, 0x691a8f74)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, bytes32 p1, uint256 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(uint256,string,uint256,uint256)`.
            mstore(0x00, 0x82c25b74)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p1)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(uint256 p0, bytes32 p1, uint256 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(uint256,string,uint256,string)`.
            mstore(0x00, 0xb7b914ca)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, p2)
            mstore(0x80, 0xc0)
            writeString(0xa0, p1)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(uint256 p0, bytes32 p1, bytes32 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(uint256,string,string,address)`.
            mstore(0x00, 0xd583c602)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, 0xc0)
            mstore(0x80, p3)
            writeString(0xa0, p1)
            writeString(0xe0, p2)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(uint256 p0, bytes32 p1, bytes32 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(uint256,string,string,bool)`.
            mstore(0x00, 0xb3a6b6bd)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, 0xc0)
            mstore(0x80, p3)
            writeString(0xa0, p1)
            writeString(0xe0, p2)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(uint256 p0, bytes32 p1, bytes32 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(uint256,string,string,uint256)`.
            mstore(0x00, 0xb028c9bd)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, 0xc0)
            mstore(0x80, p3)
            writeString(0xa0, p1)
            writeString(0xe0, p2)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(uint256 p0, bytes32 p1, bytes32 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        bytes32 m9;
        bytes32 m10;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            m9 := mload(0x120)
            m10 := mload(0x140)
            // Selector of `log(uint256,string,string,string)`.
            mstore(0x00, 0x21ad0683)
            mstore(0x20, p0)
            mstore(0x40, 0x80)
            mstore(0x60, 0xc0)
            mstore(0x80, 0x100)
            writeString(0xa0, p1)
            writeString(0xe0, p2)
            writeString(0x120, p3)
        }
        _sendLogPayload(0x1c, 0x144);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
            mstore(0x120, m9)
            mstore(0x140, m10)
        }
    }

    function log(bytes32 p0, address p1, address p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,address,address,address)`.
            mstore(0x00, 0xed8f28f6)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, address p1, address p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,address,address,bool)`.
            mstore(0x00, 0xb59dbd60)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, address p1, address p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,address,address,uint256)`.
            mstore(0x00, 0x8ef3f399)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, address p1, address p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,address,address,string)`.
            mstore(0x00, 0x800a1c67)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0xc0)
            writeString(0xa0, p0)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, address p1, bool p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,address,bool,address)`.
            mstore(0x00, 0x223603bd)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, address p1, bool p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,address,bool,bool)`.
            mstore(0x00, 0x79884c2b)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, address p1, bool p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,address,bool,uint256)`.
            mstore(0x00, 0x3e9f866a)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, address p1, bool p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,address,bool,string)`.
            mstore(0x00, 0x0454c079)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0xc0)
            writeString(0xa0, p0)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, address p1, uint256 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,address,uint256,address)`.
            mstore(0x00, 0x63fb8bc5)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, address p1, uint256 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,address,uint256,bool)`.
            mstore(0x00, 0xfc4845f0)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, address p1, uint256 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,address,uint256,uint256)`.
            mstore(0x00, 0xf8f51b1e)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, address p1, uint256 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,address,uint256,string)`.
            mstore(0x00, 0x5a477632)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0xc0)
            writeString(0xa0, p0)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, address p1, bytes32 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,address,string,address)`.
            mstore(0x00, 0xaabc9a31)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, 0xc0)
            mstore(0x80, p3)
            writeString(0xa0, p0)
            writeString(0xe0, p2)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, address p1, bytes32 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,address,string,bool)`.
            mstore(0x00, 0x5f15d28c)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, 0xc0)
            mstore(0x80, p3)
            writeString(0xa0, p0)
            writeString(0xe0, p2)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, address p1, bytes32 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,address,string,uint256)`.
            mstore(0x00, 0x91d1112e)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, 0xc0)
            mstore(0x80, p3)
            writeString(0xa0, p0)
            writeString(0xe0, p2)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, address p1, bytes32 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        bytes32 m9;
        bytes32 m10;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            m9 := mload(0x120)
            m10 := mload(0x140)
            // Selector of `log(string,address,string,string)`.
            mstore(0x00, 0x245986f2)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, 0xc0)
            mstore(0x80, 0x100)
            writeString(0xa0, p0)
            writeString(0xe0, p2)
            writeString(0x120, p3)
        }
        _sendLogPayload(0x1c, 0x144);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
            mstore(0x120, m9)
            mstore(0x140, m10)
        }
    }

    function log(bytes32 p0, bool p1, address p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,bool,address,address)`.
            mstore(0x00, 0x33e9dd1d)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, bool p1, address p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,bool,address,bool)`.
            mstore(0x00, 0x958c28c6)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, bool p1, address p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,bool,address,uint256)`.
            mstore(0x00, 0x5d08bb05)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, bool p1, address p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,bool,address,string)`.
            mstore(0x00, 0x2d8e33a4)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0xc0)
            writeString(0xa0, p0)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, bool p1, bool p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,bool,bool,address)`.
            mstore(0x00, 0x7190a529)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, bool p1, bool p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,bool,bool,bool)`.
            mstore(0x00, 0x895af8c5)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, bool p1, bool p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,bool,bool,uint256)`.
            mstore(0x00, 0x8e3f78a9)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, bool p1, bool p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,bool,bool,string)`.
            mstore(0x00, 0x9d22d5dd)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0xc0)
            writeString(0xa0, p0)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, bool p1, uint256 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,bool,uint256,address)`.
            mstore(0x00, 0x935e09bf)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, bool p1, uint256 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,bool,uint256,bool)`.
            mstore(0x00, 0x8af7cf8a)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, bool p1, uint256 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,bool,uint256,uint256)`.
            mstore(0x00, 0x64b5bb67)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, bool p1, uint256 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,bool,uint256,string)`.
            mstore(0x00, 0x742d6ee7)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0xc0)
            writeString(0xa0, p0)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, bool p1, bytes32 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,bool,string,address)`.
            mstore(0x00, 0xe0625b29)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, 0xc0)
            mstore(0x80, p3)
            writeString(0xa0, p0)
            writeString(0xe0, p2)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, bool p1, bytes32 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,bool,string,bool)`.
            mstore(0x00, 0x3f8a701d)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, 0xc0)
            mstore(0x80, p3)
            writeString(0xa0, p0)
            writeString(0xe0, p2)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, bool p1, bytes32 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,bool,string,uint256)`.
            mstore(0x00, 0x24f91465)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, 0xc0)
            mstore(0x80, p3)
            writeString(0xa0, p0)
            writeString(0xe0, p2)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, bool p1, bytes32 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        bytes32 m9;
        bytes32 m10;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            m9 := mload(0x120)
            m10 := mload(0x140)
            // Selector of `log(string,bool,string,string)`.
            mstore(0x00, 0xa826caeb)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, 0xc0)
            mstore(0x80, 0x100)
            writeString(0xa0, p0)
            writeString(0xe0, p2)
            writeString(0x120, p3)
        }
        _sendLogPayload(0x1c, 0x144);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
            mstore(0x120, m9)
            mstore(0x140, m10)
        }
    }

    function log(bytes32 p0, uint256 p1, address p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,uint256,address,address)`.
            mstore(0x00, 0x5ea2b7ae)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, uint256 p1, address p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,uint256,address,bool)`.
            mstore(0x00, 0x82112a42)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, uint256 p1, address p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,uint256,address,uint256)`.
            mstore(0x00, 0x4f04fdc6)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, uint256 p1, address p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,uint256,address,string)`.
            mstore(0x00, 0x9ffb2f93)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0xc0)
            writeString(0xa0, p0)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, uint256 p1, bool p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,uint256,bool,address)`.
            mstore(0x00, 0xe0e95b98)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, uint256 p1, bool p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,uint256,bool,bool)`.
            mstore(0x00, 0x354c36d6)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, uint256 p1, bool p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,uint256,bool,uint256)`.
            mstore(0x00, 0xe41b6f6f)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, uint256 p1, bool p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,uint256,bool,string)`.
            mstore(0x00, 0xabf73a98)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0xc0)
            writeString(0xa0, p0)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, uint256 p1, uint256 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,uint256,uint256,address)`.
            mstore(0x00, 0xe21de278)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, uint256 p1, uint256 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,uint256,uint256,bool)`.
            mstore(0x00, 0x7626db92)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, uint256 p1, uint256 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            // Selector of `log(string,uint256,uint256,uint256)`.
            mstore(0x00, 0xa7a87853)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
        }
        _sendLogPayload(0x1c, 0xc4);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
        }
    }

    function log(bytes32 p0, uint256 p1, uint256 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,uint256,uint256,string)`.
            mstore(0x00, 0x854b3496)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, p2)
            mstore(0x80, 0xc0)
            writeString(0xa0, p0)
            writeString(0xe0, p3)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, uint256 p1, bytes32 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,uint256,string,address)`.
            mstore(0x00, 0x7c4632a4)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, 0xc0)
            mstore(0x80, p3)
            writeString(0xa0, p0)
            writeString(0xe0, p2)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, uint256 p1, bytes32 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,uint256,string,bool)`.
            mstore(0x00, 0x7d24491d)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, 0xc0)
            mstore(0x80, p3)
            writeString(0xa0, p0)
            writeString(0xe0, p2)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, uint256 p1, bytes32 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,uint256,string,uint256)`.
            mstore(0x00, 0xc67ea9d1)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, 0xc0)
            mstore(0x80, p3)
            writeString(0xa0, p0)
            writeString(0xe0, p2)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, uint256 p1, bytes32 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        bytes32 m9;
        bytes32 m10;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            m9 := mload(0x120)
            m10 := mload(0x140)
            // Selector of `log(string,uint256,string,string)`.
            mstore(0x00, 0x5ab84e1f)
            mstore(0x20, 0x80)
            mstore(0x40, p1)
            mstore(0x60, 0xc0)
            mstore(0x80, 0x100)
            writeString(0xa0, p0)
            writeString(0xe0, p2)
            writeString(0x120, p3)
        }
        _sendLogPayload(0x1c, 0x144);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
            mstore(0x120, m9)
            mstore(0x140, m10)
        }
    }

    function log(bytes32 p0, bytes32 p1, address p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,string,address,address)`.
            mstore(0x00, 0x439c7bef)
            mstore(0x20, 0x80)
            mstore(0x40, 0xc0)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
            writeString(0xe0, p1)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, bytes32 p1, address p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,string,address,bool)`.
            mstore(0x00, 0x5ccd4e37)
            mstore(0x20, 0x80)
            mstore(0x40, 0xc0)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
            writeString(0xe0, p1)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, bytes32 p1, address p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,string,address,uint256)`.
            mstore(0x00, 0x7cc3c607)
            mstore(0x20, 0x80)
            mstore(0x40, 0xc0)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
            writeString(0xe0, p1)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, bytes32 p1, address p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        bytes32 m9;
        bytes32 m10;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            m9 := mload(0x120)
            m10 := mload(0x140)
            // Selector of `log(string,string,address,string)`.
            mstore(0x00, 0xeb1bff80)
            mstore(0x20, 0x80)
            mstore(0x40, 0xc0)
            mstore(0x60, p2)
            mstore(0x80, 0x100)
            writeString(0xa0, p0)
            writeString(0xe0, p1)
            writeString(0x120, p3)
        }
        _sendLogPayload(0x1c, 0x144);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
            mstore(0x120, m9)
            mstore(0x140, m10)
        }
    }

    function log(bytes32 p0, bytes32 p1, bool p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,string,bool,address)`.
            mstore(0x00, 0xc371c7db)
            mstore(0x20, 0x80)
            mstore(0x40, 0xc0)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
            writeString(0xe0, p1)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, bytes32 p1, bool p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,string,bool,bool)`.
            mstore(0x00, 0x40785869)
            mstore(0x20, 0x80)
            mstore(0x40, 0xc0)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
            writeString(0xe0, p1)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, bytes32 p1, bool p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,string,bool,uint256)`.
            mstore(0x00, 0xd6aefad2)
            mstore(0x20, 0x80)
            mstore(0x40, 0xc0)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
            writeString(0xe0, p1)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, bytes32 p1, bool p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        bytes32 m9;
        bytes32 m10;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            m9 := mload(0x120)
            m10 := mload(0x140)
            // Selector of `log(string,string,bool,string)`.
            mstore(0x00, 0x5e84b0ea)
            mstore(0x20, 0x80)
            mstore(0x40, 0xc0)
            mstore(0x60, p2)
            mstore(0x80, 0x100)
            writeString(0xa0, p0)
            writeString(0xe0, p1)
            writeString(0x120, p3)
        }
        _sendLogPayload(0x1c, 0x144);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
            mstore(0x120, m9)
            mstore(0x140, m10)
        }
    }

    function log(bytes32 p0, bytes32 p1, uint256 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,string,uint256,address)`.
            mstore(0x00, 0x1023f7b2)
            mstore(0x20, 0x80)
            mstore(0x40, 0xc0)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
            writeString(0xe0, p1)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, bytes32 p1, uint256 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,string,uint256,bool)`.
            mstore(0x00, 0xc3a8a654)
            mstore(0x20, 0x80)
            mstore(0x40, 0xc0)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
            writeString(0xe0, p1)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, bytes32 p1, uint256 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            // Selector of `log(string,string,uint256,uint256)`.
            mstore(0x00, 0xf45d7d2c)
            mstore(0x20, 0x80)
            mstore(0x40, 0xc0)
            mstore(0x60, p2)
            mstore(0x80, p3)
            writeString(0xa0, p0)
            writeString(0xe0, p1)
        }
        _sendLogPayload(0x1c, 0x104);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
        }
    }

    function log(bytes32 p0, bytes32 p1, uint256 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        bytes32 m9;
        bytes32 m10;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            m9 := mload(0x120)
            m10 := mload(0x140)
            // Selector of `log(string,string,uint256,string)`.
            mstore(0x00, 0x5d1a971a)
            mstore(0x20, 0x80)
            mstore(0x40, 0xc0)
            mstore(0x60, p2)
            mstore(0x80, 0x100)
            writeString(0xa0, p0)
            writeString(0xe0, p1)
            writeString(0x120, p3)
        }
        _sendLogPayload(0x1c, 0x144);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
            mstore(0x120, m9)
            mstore(0x140, m10)
        }
    }

    function log(bytes32 p0, bytes32 p1, bytes32 p2, address p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        bytes32 m9;
        bytes32 m10;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            m9 := mload(0x120)
            m10 := mload(0x140)
            // Selector of `log(string,string,string,address)`.
            mstore(0x00, 0x6d572f44)
            mstore(0x20, 0x80)
            mstore(0x40, 0xc0)
            mstore(0x60, 0x100)
            mstore(0x80, p3)
            writeString(0xa0, p0)
            writeString(0xe0, p1)
            writeString(0x120, p2)
        }
        _sendLogPayload(0x1c, 0x144);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
            mstore(0x120, m9)
            mstore(0x140, m10)
        }
    }

    function log(bytes32 p0, bytes32 p1, bytes32 p2, bool p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        bytes32 m9;
        bytes32 m10;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            m9 := mload(0x120)
            m10 := mload(0x140)
            // Selector of `log(string,string,string,bool)`.
            mstore(0x00, 0x2c1754ed)
            mstore(0x20, 0x80)
            mstore(0x40, 0xc0)
            mstore(0x60, 0x100)
            mstore(0x80, p3)
            writeString(0xa0, p0)
            writeString(0xe0, p1)
            writeString(0x120, p2)
        }
        _sendLogPayload(0x1c, 0x144);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
            mstore(0x120, m9)
            mstore(0x140, m10)
        }
    }

    function log(bytes32 p0, bytes32 p1, bytes32 p2, uint256 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        bytes32 m9;
        bytes32 m10;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            m9 := mload(0x120)
            m10 := mload(0x140)
            // Selector of `log(string,string,string,uint256)`.
            mstore(0x00, 0x8eafb02b)
            mstore(0x20, 0x80)
            mstore(0x40, 0xc0)
            mstore(0x60, 0x100)
            mstore(0x80, p3)
            writeString(0xa0, p0)
            writeString(0xe0, p1)
            writeString(0x120, p2)
        }
        _sendLogPayload(0x1c, 0x144);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
            mstore(0x120, m9)
            mstore(0x140, m10)
        }
    }

    function log(bytes32 p0, bytes32 p1, bytes32 p2, bytes32 p3) internal pure {
        bytes32 m0;
        bytes32 m1;
        bytes32 m2;
        bytes32 m3;
        bytes32 m4;
        bytes32 m5;
        bytes32 m6;
        bytes32 m7;
        bytes32 m8;
        bytes32 m9;
        bytes32 m10;
        bytes32 m11;
        bytes32 m12;
        /// @solidity memory-safe-assembly
        assembly {
            function writeString(pos, w) {
                let length := 0
                for {} lt(length, 0x20) {
                    length := add(length, 1)
                } {
                    if iszero(byte(length, w)) {
                        break
                    }
                }
                mstore(pos, length)
                let shift := sub(256, shl(3, length))
                mstore(add(pos, 0x20), shl(shift, shr(shift, w)))
            }
            m0 := mload(0x00)
            m1 := mload(0x20)
            m2 := mload(0x40)
            m3 := mload(0x60)
            m4 := mload(0x80)
            m5 := mload(0xa0)
            m6 := mload(0xc0)
            m7 := mload(0xe0)
            m8 := mload(0x100)
            m9 := mload(0x120)
            m10 := mload(0x140)
            m11 := mload(0x160)
            m12 := mload(0x180)
            // Selector of `log(string,string,string,string)`.
            mstore(0x00, 0xde68f20a)
            mstore(0x20, 0x80)
            mstore(0x40, 0xc0)
            mstore(0x60, 0x100)
            mstore(0x80, 0x140)
            writeString(0xa0, p0)
            writeString(0xe0, p1)
            writeString(0x120, p2)
            writeString(0x160, p3)
        }
        _sendLogPayload(0x1c, 0x184);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, m0)
            mstore(0x20, m1)
            mstore(0x40, m2)
            mstore(0x60, m3)
            mstore(0x80, m4)
            mstore(0xa0, m5)
            mstore(0xc0, m6)
            mstore(0xe0, m7)
            mstore(0x100, m8)
            mstore(0x120, m9)
            mstore(0x140, m10)
            mstore(0x160, m11)
            mstore(0x180, m12)
        }
    }
}

// node_modules/@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol

// OpenZeppelin Contracts v4.4.1 (token/ERC20/extensions/IERC20Metadata.sol)

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}

// node_modules/@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol

// OpenZeppelin Contracts (last updated v4.9.0) (proxy/utils/Initializable.sol)

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since proxied contracts do not make use of a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * The initialization functions use a version number. Once a version number is used, it is consumed and cannot be
 * reused. This mechanism prevents re-execution of each "step" but allows the creation of new initialization steps in
 * case an upgrade adds a module that needs to be initialized.
 *
 * For example:
 *
 * [.hljs-theme-light.nopadding]
 * ```solidity
 * contract MyToken is ERC20Upgradeable {
 *     function initialize() initializer public {
 *         __ERC20_init("MyToken", "MTK");
 *     }
 * }
 *
 * contract MyTokenV2 is MyToken, ERC20PermitUpgradeable {
 *     function initializeV2() reinitializer(2) public {
 *         __ERC20Permit_init("MyToken");
 *     }
 * }
 * ```
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 *
 * [CAUTION]
 * ====
 * Avoid leaving a contract uninitialized.
 *
 * An uninitialized contract can be taken over by an attacker. This applies to both a proxy and its implementation
 * contract, which may impact the proxy. To prevent the implementation contract from being used, you should invoke
 * the {_disableInitializers} function in the constructor to automatically lock it when it is deployed:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * /// @custom:oz-upgrades-unsafe-allow constructor
 * constructor() {
 *     _disableInitializers();
 * }
 * ```
 * ====
 */
abstract contract Initializable {
    /**
     * @dev Indicates that the contract has been initialized.
     * @custom:oz-retyped-from bool
     */
    uint8 private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Triggered when the contract has been initialized or reinitialized.
     */
    event Initialized(uint8 version);

    /**
     * @dev A modifier that defines a protected initializer function that can be invoked at most once. In its scope,
     * `onlyInitializing` functions can be used to initialize parent contracts.
     *
     * Similar to `reinitializer(1)`, except that functions marked with `initializer` can be nested in the context of a
     * constructor.
     *
     * Emits an {Initialized} event.
     */
    modifier initializer() {
        bool isTopLevelCall = !_initializing;
        require(
            (isTopLevelCall && _initialized < 1)
                || (!AddressUpgradeable.isContract(address(this)) && _initialized == 1),
            "Initializable: contract is already initialized"
        );
        _initialized = 1;
        if (isTopLevelCall) {
            _initializing = true;
        }
        _;
        if (isTopLevelCall) {
            _initializing = false;
            emit Initialized(1);
        }
    }

    /**
     * @dev A modifier that defines a protected reinitializer function that can be invoked at most once, and only if the
     * contract hasn't been initialized to a greater version before. In its scope, `onlyInitializing` functions can be
     * used to initialize parent contracts.
     *
     * A reinitializer may be used after the original initialization step. This is essential to configure modules that
     * are added through upgrades and that require initialization.
     *
     * When `version` is 1, this modifier is similar to `initializer`, except that functions marked with `reinitializer`
     * cannot be nested. If one is invoked in the context of another, execution will revert.
     *
     * Note that versions can jump in increments greater than 1; this implies that if multiple reinitializers coexist in
     * a contract, executing them in the right order is up to the developer or operator.
     *
     * WARNING: setting the version to 255 will prevent any future reinitialization.
     *
     * Emits an {Initialized} event.
     */
    modifier reinitializer(uint8 version) {
        require(!_initializing && _initialized < version, "Initializable: contract is already initialized");
        _initialized = version;
        _initializing = true;
        _;
        _initializing = false;
        emit Initialized(version);
    }

    /**
     * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
     * {initializer} and {reinitializer} modifiers, directly or indirectly.
     */
    modifier onlyInitializing() {
        require(_initializing, "Initializable: contract is not initializing");
        _;
    }

    /**
     * @dev Locks the contract, preventing any future reinitialization. This cannot be part of an initializer call.
     * Calling this in the constructor of a contract will prevent that contract from being initialized or reinitialized
     * to any version. It is recommended to use this to lock implementation contracts that are designed to be called
     * through proxies.
     *
     * Emits an {Initialized} event the first time it is successfully executed.
     */
    function _disableInitializers() internal virtual {
        require(!_initializing, "Initializable: contract is initializing");
        if (_initialized != type(uint8).max) {
            _initialized = type(uint8).max;
            emit Initialized(type(uint8).max);
        }
    }

    /**
     * @dev Returns the highest version that has been initialized. See {reinitializer}.
     */
    function _getInitializedVersion() internal view returns (uint8) {
        return _initialized;
    }

    /**
     * @dev Returns `true` if the contract is currently initializing. See {onlyInitializing}.
     */
    function _isInitializing() internal view returns (bool) {
        return _initializing;
    }
}

// lib/forge-std/src/StdAssertions.sol

abstract contract StdAssertions {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    event log(string);
    event logs(bytes);

    event log_address(address);
    event log_bytes32(bytes32);
    event log_int(int256);
    event log_uint(uint256);
    event log_bytes(bytes);
    event log_string(string);

    event log_named_address(string key, address val);
    event log_named_bytes32(string key, bytes32 val);
    event log_named_decimal_int(string key, int256 val, uint256 decimals);
    event log_named_decimal_uint(string key, uint256 val, uint256 decimals);
    event log_named_int(string key, int256 val);
    event log_named_uint(string key, uint256 val);
    event log_named_bytes(string key, bytes val);
    event log_named_string(string key, string val);

    event log_array(uint256[] val);
    event log_array(int256[] val);
    event log_array(address[] val);
    event log_named_array(string key, uint256[] val);
    event log_named_array(string key, int256[] val);
    event log_named_array(string key, address[] val);

    bytes32 private constant FAILED_SLOT = bytes32("failed");

    bool private _failed;

    function failed() public view returns (bool) {
        if (_failed) {
            return true;
        } else {
            return vm.load(address(vm), FAILED_SLOT) != bytes32(0);
        }
    }

    function fail() internal virtual {
        vm.store(address(vm), FAILED_SLOT, bytes32(uint256(1)));
        _failed = true;
    }

    function fail(string memory message) internal virtual {
        fail();
        vm.assertTrue(false, message);
    }

    function assertTrue(bool data) internal pure virtual {
        if (!data) {
            vm.assertTrue(data);
        }
    }

    function assertTrue(bool data, string memory err) internal pure virtual {
        if (!data) {
            vm.assertTrue(data, err);
        }
    }

    function assertFalse(bool data) internal pure virtual {
        if (data) {
            vm.assertFalse(data);
        }
    }

    function assertFalse(bool data, string memory err) internal pure virtual {
        if (data) {
            vm.assertFalse(data, err);
        }
    }

    function assertEq(bool left, bool right) internal pure virtual {
        if (left != right) {
            vm.assertEq(left, right);
        }
    }

    function assertEq(bool left, bool right, string memory err) internal pure virtual {
        if (left != right) {
            vm.assertEq(left, right, err);
        }
    }

    function assertEq(uint256 left, uint256 right) internal pure virtual {
        if (left != right) {
            vm.assertEq(left, right);
        }
    }

    function assertEq(uint256 left, uint256 right, string memory err) internal pure virtual {
        if (left != right) {
            vm.assertEq(left, right, err);
        }
    }

    function assertEqDecimal(uint256 left, uint256 right, uint256 decimals) internal pure virtual {
        vm.assertEqDecimal(left, right, decimals);
    }

    function assertEqDecimal(uint256 left, uint256 right, uint256 decimals, string memory err) internal pure virtual {
        vm.assertEqDecimal(left, right, decimals, err);
    }

    function assertEq(int256 left, int256 right) internal pure virtual {
        if (left != right) {
            vm.assertEq(left, right);
        }
    }

    function assertEq(int256 left, int256 right, string memory err) internal pure virtual {
        if (left != right) {
            vm.assertEq(left, right, err);
        }
    }

    function assertEqDecimal(int256 left, int256 right, uint256 decimals) internal pure virtual {
        vm.assertEqDecimal(left, right, decimals);
    }

    function assertEqDecimal(int256 left, int256 right, uint256 decimals, string memory err) internal pure virtual {
        vm.assertEqDecimal(left, right, decimals, err);
    }

    function assertEq(address left, address right) internal pure virtual {
        if (left != right) {
            vm.assertEq(left, right);
        }
    }

    function assertEq(address left, address right, string memory err) internal pure virtual {
        if (left != right) {
            vm.assertEq(left, right, err);
        }
    }

    function assertEq(bytes32 left, bytes32 right) internal pure virtual {
        if (left != right) {
            vm.assertEq(left, right);
        }
    }

    function assertEq(bytes32 left, bytes32 right, string memory err) internal pure virtual {
        if (left != right) {
            vm.assertEq(left, right, err);
        }
    }

    function assertEq32(bytes32 left, bytes32 right) internal pure virtual {
        if (left != right) {
            vm.assertEq(left, right);
        }
    }

    function assertEq32(bytes32 left, bytes32 right, string memory err) internal pure virtual {
        if (left != right) {
            vm.assertEq(left, right, err);
        }
    }

    function assertEq(string memory left, string memory right) internal pure virtual {
        vm.assertEq(left, right);
    }

    function assertEq(string memory left, string memory right, string memory err) internal pure virtual {
        vm.assertEq(left, right, err);
    }

    function assertEq(bytes memory left, bytes memory right) internal pure virtual {
        vm.assertEq(left, right);
    }

    function assertEq(bytes memory left, bytes memory right, string memory err) internal pure virtual {
        vm.assertEq(left, right, err);
    }

    function assertEq(bool[] memory left, bool[] memory right) internal pure virtual {
        vm.assertEq(left, right);
    }

    function assertEq(bool[] memory left, bool[] memory right, string memory err) internal pure virtual {
        vm.assertEq(left, right, err);
    }

    function assertEq(uint256[] memory left, uint256[] memory right) internal pure virtual {
        vm.assertEq(left, right);
    }

    function assertEq(uint256[] memory left, uint256[] memory right, string memory err) internal pure virtual {
        vm.assertEq(left, right, err);
    }

    function assertEq(int256[] memory left, int256[] memory right) internal pure virtual {
        vm.assertEq(left, right);
    }

    function assertEq(int256[] memory left, int256[] memory right, string memory err) internal pure virtual {
        vm.assertEq(left, right, err);
    }

    function assertEq(address[] memory left, address[] memory right) internal pure virtual {
        vm.assertEq(left, right);
    }

    function assertEq(address[] memory left, address[] memory right, string memory err) internal pure virtual {
        vm.assertEq(left, right, err);
    }

    function assertEq(bytes32[] memory left, bytes32[] memory right) internal pure virtual {
        vm.assertEq(left, right);
    }

    function assertEq(bytes32[] memory left, bytes32[] memory right, string memory err) internal pure virtual {
        vm.assertEq(left, right, err);
    }

    function assertEq(string[] memory left, string[] memory right) internal pure virtual {
        vm.assertEq(left, right);
    }

    function assertEq(string[] memory left, string[] memory right, string memory err) internal pure virtual {
        vm.assertEq(left, right, err);
    }

    function assertEq(bytes[] memory left, bytes[] memory right) internal pure virtual {
        vm.assertEq(left, right);
    }

    function assertEq(bytes[] memory left, bytes[] memory right, string memory err) internal pure virtual {
        vm.assertEq(left, right, err);
    }

    // Legacy helper
    function assertEqUint(uint256 left, uint256 right) internal pure virtual {
        assertEq(left, right);
    }

    function assertNotEq(bool left, bool right) internal pure virtual {
        if (left == right) {
            vm.assertNotEq(left, right);
        }
    }

    function assertNotEq(bool left, bool right, string memory err) internal pure virtual {
        if (left == right) {
            vm.assertNotEq(left, right, err);
        }
    }

    function assertNotEq(uint256 left, uint256 right) internal pure virtual {
        if (left == right) {
            vm.assertNotEq(left, right);
        }
    }

    function assertNotEq(uint256 left, uint256 right, string memory err) internal pure virtual {
        if (left == right) {
            vm.assertNotEq(left, right, err);
        }
    }

    function assertNotEqDecimal(uint256 left, uint256 right, uint256 decimals) internal pure virtual {
        vm.assertNotEqDecimal(left, right, decimals);
    }

    function assertNotEqDecimal(uint256 left, uint256 right, uint256 decimals, string memory err)
        internal
        pure
        virtual
    {
        vm.assertNotEqDecimal(left, right, decimals, err);
    }

    function assertNotEq(int256 left, int256 right) internal pure virtual {
        if (left == right) {
            vm.assertNotEq(left, right);
        }
    }

    function assertNotEq(int256 left, int256 right, string memory err) internal pure virtual {
        if (left == right) {
            vm.assertNotEq(left, right, err);
        }
    }

    function assertNotEqDecimal(int256 left, int256 right, uint256 decimals) internal pure virtual {
        vm.assertNotEqDecimal(left, right, decimals);
    }

    function assertNotEqDecimal(int256 left, int256 right, uint256 decimals, string memory err) internal pure virtual {
        vm.assertNotEqDecimal(left, right, decimals, err);
    }

    function assertNotEq(address left, address right) internal pure virtual {
        if (left == right) {
            vm.assertNotEq(left, right);
        }
    }

    function assertNotEq(address left, address right, string memory err) internal pure virtual {
        if (left == right) {
            vm.assertNotEq(left, right, err);
        }
    }

    function assertNotEq(bytes32 left, bytes32 right) internal pure virtual {
        if (left == right) {
            vm.assertNotEq(left, right);
        }
    }

    function assertNotEq(bytes32 left, bytes32 right, string memory err) internal pure virtual {
        if (left == right) {
            vm.assertNotEq(left, right, err);
        }
    }

    function assertNotEq32(bytes32 left, bytes32 right) internal pure virtual {
        if (left == right) {
            vm.assertNotEq(left, right);
        }
    }

    function assertNotEq32(bytes32 left, bytes32 right, string memory err) internal pure virtual {
        if (left == right) {
            vm.assertNotEq(left, right, err);
        }
    }

    function assertNotEq(string memory left, string memory right) internal pure virtual {
        vm.assertNotEq(left, right);
    }

    function assertNotEq(string memory left, string memory right, string memory err) internal pure virtual {
        vm.assertNotEq(left, right, err);
    }

    function assertNotEq(bytes memory left, bytes memory right) internal pure virtual {
        vm.assertNotEq(left, right);
    }

    function assertNotEq(bytes memory left, bytes memory right, string memory err) internal pure virtual {
        vm.assertNotEq(left, right, err);
    }

    function assertNotEq(bool[] memory left, bool[] memory right) internal pure virtual {
        vm.assertNotEq(left, right);
    }

    function assertNotEq(bool[] memory left, bool[] memory right, string memory err) internal pure virtual {
        vm.assertNotEq(left, right, err);
    }

    function assertNotEq(uint256[] memory left, uint256[] memory right) internal pure virtual {
        vm.assertNotEq(left, right);
    }

    function assertNotEq(uint256[] memory left, uint256[] memory right, string memory err) internal pure virtual {
        vm.assertNotEq(left, right, err);
    }

    function assertNotEq(int256[] memory left, int256[] memory right) internal pure virtual {
        vm.assertNotEq(left, right);
    }

    function assertNotEq(int256[] memory left, int256[] memory right, string memory err) internal pure virtual {
        vm.assertNotEq(left, right, err);
    }

    function assertNotEq(address[] memory left, address[] memory right) internal pure virtual {
        vm.assertNotEq(left, right);
    }

    function assertNotEq(address[] memory left, address[] memory right, string memory err) internal pure virtual {
        vm.assertNotEq(left, right, err);
    }

    function assertNotEq(bytes32[] memory left, bytes32[] memory right) internal pure virtual {
        vm.assertNotEq(left, right);
    }

    function assertNotEq(bytes32[] memory left, bytes32[] memory right, string memory err) internal pure virtual {
        vm.assertNotEq(left, right, err);
    }

    function assertNotEq(string[] memory left, string[] memory right) internal pure virtual {
        vm.assertNotEq(left, right);
    }

    function assertNotEq(string[] memory left, string[] memory right, string memory err) internal pure virtual {
        vm.assertNotEq(left, right, err);
    }

    function assertNotEq(bytes[] memory left, bytes[] memory right) internal pure virtual {
        vm.assertNotEq(left, right);
    }

    function assertNotEq(bytes[] memory left, bytes[] memory right, string memory err) internal pure virtual {
        vm.assertNotEq(left, right, err);
    }

    function assertLt(uint256 left, uint256 right) internal pure virtual {
        if (left >= right) {
            vm.assertLt(left, right);
        }
    }

    function assertLt(uint256 left, uint256 right, string memory err) internal pure virtual {
        if (left >= right) {
            vm.assertLt(left, right, err);
        }
    }

    function assertLtDecimal(uint256 left, uint256 right, uint256 decimals) internal pure virtual {
        vm.assertLtDecimal(left, right, decimals);
    }

    function assertLtDecimal(uint256 left, uint256 right, uint256 decimals, string memory err) internal pure virtual {
        vm.assertLtDecimal(left, right, decimals, err);
    }

    function assertLt(int256 left, int256 right) internal pure virtual {
        if (left >= right) {
            vm.assertLt(left, right);
        }
    }

    function assertLt(int256 left, int256 right, string memory err) internal pure virtual {
        if (left >= right) {
            vm.assertLt(left, right, err);
        }
    }

    function assertLtDecimal(int256 left, int256 right, uint256 decimals) internal pure virtual {
        vm.assertLtDecimal(left, right, decimals);
    }

    function assertLtDecimal(int256 left, int256 right, uint256 decimals, string memory err) internal pure virtual {
        vm.assertLtDecimal(left, right, decimals, err);
    }

    function assertGt(uint256 left, uint256 right) internal pure virtual {
        if (left <= right) {
            vm.assertGt(left, right);
        }
    }

    function assertGt(uint256 left, uint256 right, string memory err) internal pure virtual {
        if (left <= right) {
            vm.assertGt(left, right, err);
        }
    }

    function assertGtDecimal(uint256 left, uint256 right, uint256 decimals) internal pure virtual {
        vm.assertGtDecimal(left, right, decimals);
    }

    function assertGtDecimal(uint256 left, uint256 right, uint256 decimals, string memory err) internal pure virtual {
        vm.assertGtDecimal(left, right, decimals, err);
    }

    function assertGt(int256 left, int256 right) internal pure virtual {
        if (left <= right) {
            vm.assertGt(left, right);
        }
    }

    function assertGt(int256 left, int256 right, string memory err) internal pure virtual {
        if (left <= right) {
            vm.assertGt(left, right, err);
        }
    }

    function assertGtDecimal(int256 left, int256 right, uint256 decimals) internal pure virtual {
        vm.assertGtDecimal(left, right, decimals);
    }

    function assertGtDecimal(int256 left, int256 right, uint256 decimals, string memory err) internal pure virtual {
        vm.assertGtDecimal(left, right, decimals, err);
    }

    function assertLe(uint256 left, uint256 right) internal pure virtual {
        if (left > right) {
            vm.assertLe(left, right);
        }
    }

    function assertLe(uint256 left, uint256 right, string memory err) internal pure virtual {
        if (left > right) {
            vm.assertLe(left, right, err);
        }
    }

    function assertLeDecimal(uint256 left, uint256 right, uint256 decimals) internal pure virtual {
        vm.assertLeDecimal(left, right, decimals);
    }

    function assertLeDecimal(uint256 left, uint256 right, uint256 decimals, string memory err) internal pure virtual {
        vm.assertLeDecimal(left, right, decimals, err);
    }

    function assertLe(int256 left, int256 right) internal pure virtual {
        if (left > right) {
            vm.assertLe(left, right);
        }
    }

    function assertLe(int256 left, int256 right, string memory err) internal pure virtual {
        if (left > right) {
            vm.assertLe(left, right, err);
        }
    }

    function assertLeDecimal(int256 left, int256 right, uint256 decimals) internal pure virtual {
        vm.assertLeDecimal(left, right, decimals);
    }

    function assertLeDecimal(int256 left, int256 right, uint256 decimals, string memory err) internal pure virtual {
        vm.assertLeDecimal(left, right, decimals, err);
    }

    function assertGe(uint256 left, uint256 right) internal pure virtual {
        if (left < right) {
            vm.assertGe(left, right);
        }
    }

    function assertGe(uint256 left, uint256 right, string memory err) internal pure virtual {
        if (left < right) {
            vm.assertGe(left, right, err);
        }
    }

    function assertGeDecimal(uint256 left, uint256 right, uint256 decimals) internal pure virtual {
        vm.assertGeDecimal(left, right, decimals);
    }

    function assertGeDecimal(uint256 left, uint256 right, uint256 decimals, string memory err) internal pure virtual {
        vm.assertGeDecimal(left, right, decimals, err);
    }

    function assertGe(int256 left, int256 right) internal pure virtual {
        if (left < right) {
            vm.assertGe(left, right);
        }
    }

    function assertGe(int256 left, int256 right, string memory err) internal pure virtual {
        if (left < right) {
            vm.assertGe(left, right, err);
        }
    }

    function assertGeDecimal(int256 left, int256 right, uint256 decimals) internal pure virtual {
        vm.assertGeDecimal(left, right, decimals);
    }

    function assertGeDecimal(int256 left, int256 right, uint256 decimals, string memory err) internal pure virtual {
        vm.assertGeDecimal(left, right, decimals, err);
    }

    function assertApproxEqAbs(uint256 left, uint256 right, uint256 maxDelta) internal pure virtual {
        vm.assertApproxEqAbs(left, right, maxDelta);
    }

    function assertApproxEqAbs(uint256 left, uint256 right, uint256 maxDelta, string memory err) internal pure virtual {
        vm.assertApproxEqAbs(left, right, maxDelta, err);
    }

    function assertApproxEqAbsDecimal(uint256 left, uint256 right, uint256 maxDelta, uint256 decimals)
        internal
        pure
        virtual
    {
        vm.assertApproxEqAbsDecimal(left, right, maxDelta, decimals);
    }

    function assertApproxEqAbsDecimal(
        uint256 left,
        uint256 right,
        uint256 maxDelta,
        uint256 decimals,
        string memory err
    ) internal pure virtual {
        vm.assertApproxEqAbsDecimal(left, right, maxDelta, decimals, err);
    }

    function assertApproxEqAbs(int256 left, int256 right, uint256 maxDelta) internal pure virtual {
        vm.assertApproxEqAbs(left, right, maxDelta);
    }

    function assertApproxEqAbs(int256 left, int256 right, uint256 maxDelta, string memory err) internal pure virtual {
        vm.assertApproxEqAbs(left, right, maxDelta, err);
    }

    function assertApproxEqAbsDecimal(int256 left, int256 right, uint256 maxDelta, uint256 decimals)
        internal
        pure
        virtual
    {
        vm.assertApproxEqAbsDecimal(left, right, maxDelta, decimals);
    }

    function assertApproxEqAbsDecimal(int256 left, int256 right, uint256 maxDelta, uint256 decimals, string memory err)
        internal
        pure
        virtual
    {
        vm.assertApproxEqAbsDecimal(left, right, maxDelta, decimals, err);
    }

    function assertApproxEqRel(
        uint256 left,
        uint256 right,
        uint256 maxPercentDelta // An 18 decimal fixed point number, where 1e18 == 100%
    )
        internal
        pure
        virtual
    {
        vm.assertApproxEqRel(left, right, maxPercentDelta);
    }

    function assertApproxEqRel(
        uint256 left,
        uint256 right,
        uint256 maxPercentDelta, // An 18 decimal fixed point number, where 1e18 == 100%
        string memory err
    )
        internal
        pure
        virtual
    {
        vm.assertApproxEqRel(left, right, maxPercentDelta, err);
    }

    function assertApproxEqRelDecimal(
        uint256 left,
        uint256 right,
        uint256 maxPercentDelta, // An 18 decimal fixed point number, where 1e18 == 100%
        uint256 decimals
    )
        internal
        pure
        virtual
    {
        vm.assertApproxEqRelDecimal(left, right, maxPercentDelta, decimals);
    }

    function assertApproxEqRelDecimal(
        uint256 left,
        uint256 right,
        uint256 maxPercentDelta, // An 18 decimal fixed point number, where 1e18 == 100%
        uint256 decimals,
        string memory err
    ) internal pure virtual {
        vm.assertApproxEqRelDecimal(left, right, maxPercentDelta, decimals, err);
    }

    function assertApproxEqRel(int256 left, int256 right, uint256 maxPercentDelta) internal pure virtual {
        vm.assertApproxEqRel(left, right, maxPercentDelta);
    }

    function assertApproxEqRel(
        int256 left,
        int256 right,
        uint256 maxPercentDelta, // An 18 decimal fixed point number, where 1e18 == 100%
        string memory err
    )
        internal
        pure
        virtual
    {
        vm.assertApproxEqRel(left, right, maxPercentDelta, err);
    }

    function assertApproxEqRelDecimal(
        int256 left,
        int256 right,
        uint256 maxPercentDelta, // An 18 decimal fixed point number, where 1e18 == 100%
        uint256 decimals
    )
        internal
        pure
        virtual
    {
        vm.assertApproxEqRelDecimal(left, right, maxPercentDelta, decimals);
    }

    function assertApproxEqRelDecimal(
        int256 left,
        int256 right,
        uint256 maxPercentDelta, // An 18 decimal fixed point number, where 1e18 == 100%
        uint256 decimals,
        string memory err
    ) internal pure virtual {
        vm.assertApproxEqRelDecimal(left, right, maxPercentDelta, decimals, err);
    }

    // Inherited from DSTest, not used but kept for backwards-compatibility
    function checkEq0(bytes memory left, bytes memory right) internal pure returns (bool) {
        return keccak256(left) == keccak256(right);
    }

    function assertEq0(bytes memory left, bytes memory right) internal pure virtual {
        assertEq(left, right);
    }

    function assertEq0(bytes memory left, bytes memory right, string memory err) internal pure virtual {
        assertEq(left, right, err);
    }

    function assertNotEq0(bytes memory left, bytes memory right) internal pure virtual {
        assertNotEq(left, right);
    }

    function assertNotEq0(bytes memory left, bytes memory right, string memory err) internal pure virtual {
        assertNotEq(left, right, err);
    }

    function assertEqCall(address target, bytes memory callDataA, bytes memory callDataB) internal virtual {
        assertEqCall(target, callDataA, target, callDataB, true);
    }

    function assertEqCall(address targetA, bytes memory callDataA, address targetB, bytes memory callDataB)
        internal
        virtual
    {
        assertEqCall(targetA, callDataA, targetB, callDataB, true);
    }

    function assertEqCall(address target, bytes memory callDataA, bytes memory callDataB, bool strictRevertData)
        internal
        virtual
    {
        assertEqCall(target, callDataA, target, callDataB, strictRevertData);
    }

    function assertEqCall(
        address targetA,
        bytes memory callDataA,
        address targetB,
        bytes memory callDataB,
        bool strictRevertData
    ) internal virtual {
        (bool successA, bytes memory returnDataA) = address(targetA).call(callDataA);
        (bool successB, bytes memory returnDataB) = address(targetB).call(callDataB);

        if (successA && successB) {
            assertEq(returnDataA, returnDataB, "Call return data does not match");
        }

        if (!successA && !successB && strictRevertData) {
            assertEq(returnDataA, returnDataB, "Call revert data does not match");
        }

        if (!successA && successB) {
            emit log("Error: Calls were not equal");
            emit log_named_bytes("  Left call revert data", returnDataA);
            emit log_named_bytes(" Right call return data", returnDataB);
            revert("assertion failed");
        }

        if (successA && !successB) {
            emit log("Error: Calls were not equal");
            emit log_named_bytes("  Left call return data", returnDataA);
            emit log_named_bytes(" Right call revert data", returnDataB);
            revert("assertion failed");
        }
    }
}

// lib/forge-std/src/StdChains.sol

/**
 * StdChains provides information about EVM compatible chains that can be used in scripts/tests.
 * For each chain, the chain's name, chain ID, and a default RPC URL are provided. Chains are
 * identified by their alias, which is the same as the alias in the `[rpc_endpoints]` section of
 * the `foundry.toml` file. For best UX, ensure the alias in the `foundry.toml` file match the
 * alias used in this contract, which can be found as the first argument to the
 * `setChainWithDefaultRpcUrl` call in the `initializeStdChains` function.
 *
 * There are two main ways to use this contract:
 *   1. Set a chain with `setChain(string memory chainAlias, ChainData memory chain)` or
 *      `setChain(string memory chainAlias, Chain memory chain)`
 *   2. Get a chain with `getChain(string memory chainAlias)` or `getChain(uint256 chainId)`.
 *
 * The first time either of those are used, chains are initialized with the default set of RPC URLs.
 * This is done in `initializeStdChains`, which uses `setChainWithDefaultRpcUrl`. Defaults are recorded in
 * `defaultRpcUrls`.
 *
 * The `setChain` function is straightforward, and it simply saves off the given chain data.
 *
 * The `getChain` methods use `getChainWithUpdatedRpcUrl` to return a chain. For example, let's say
 * we want to retrieve the RPC URL for `mainnet`:
 *   - If you have specified data with `setChain`, it will return that.
 *   - If you have configured a mainnet RPC URL in `foundry.toml`, it will return the URL, provided it
 *     is valid (e.g. a URL is specified, or an environment variable is given and exists).
 *   - If neither of the above conditions is met, the default data is returned.
 *
 * Summarizing the above, the prioritization hierarchy is `setChain` -> `foundry.toml` -> environment variable -> defaults.
 */
abstract contract StdChains {
    VmSafe private constant vm = VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));

    bool private stdChainsInitialized;

    struct ChainData {
        string name;
        uint256 chainId;
        string rpcUrl;
    }

    struct Chain {
        // The chain name.
        string name;
        // The chain's Chain ID.
        uint256 chainId;
        // The chain's alias. (i.e. what gets specified in `foundry.toml`).
        string chainAlias;
        // A default RPC endpoint for this chain.
        // NOTE: This default RPC URL is included for convenience to facilitate quick tests and
        // experimentation. Do not use this RPC URL for production test suites, CI, or other heavy
        // usage as you will be throttled and this is a disservice to others who need this endpoint.
        string rpcUrl;
    }

    // Maps from the chain's alias (matching the alias in the `foundry.toml` file) to chain data.
    mapping(string => Chain) private chains;
    // Maps from the chain's alias to it's default RPC URL.
    mapping(string => string) private defaultRpcUrls;
    // Maps from a chain ID to it's alias.
    mapping(uint256 => string) private idToAlias;

    bool private fallbackToDefaultRpcUrls = true;

    // The RPC URL will be fetched from config or defaultRpcUrls if possible.
    function getChain(string memory chainAlias) internal virtual returns (Chain memory chain) {
        require(bytes(chainAlias).length != 0, "StdChains getChain(string): Chain alias cannot be the empty string.");

        initializeStdChains();
        chain = chains[chainAlias];
        require(
            chain.chainId != 0,
            string(abi.encodePacked('StdChains getChain(string): Chain with alias "', chainAlias, '" not found.'))
        );

        chain = getChainWithUpdatedRpcUrl(chainAlias, chain);
    }

    function getChain(uint256 chainId) internal virtual returns (Chain memory chain) {
        require(chainId != 0, "StdChains getChain(uint256): Chain ID cannot be 0.");
        initializeStdChains();
        string memory chainAlias = idToAlias[chainId];

        chain = chains[chainAlias];

        require(
            chain.chainId != 0,
            string(abi.encodePacked("StdChains getChain(uint256): Chain with ID ", vm.toString(chainId), " not found."))
        );

        chain = getChainWithUpdatedRpcUrl(chainAlias, chain);
    }

    // set chain info, with priority to argument's rpcUrl field.
    function setChain(string memory chainAlias, ChainData memory chain) internal virtual {
        require(
            bytes(chainAlias).length != 0,
            "StdChains setChain(string,ChainData): Chain alias cannot be the empty string."
        );

        require(chain.chainId != 0, "StdChains setChain(string,ChainData): Chain ID cannot be 0.");

        initializeStdChains();
        string memory foundAlias = idToAlias[chain.chainId];

        require(
            bytes(foundAlias).length == 0 || keccak256(bytes(foundAlias)) == keccak256(bytes(chainAlias)),
            string(
                abi.encodePacked(
                    "StdChains setChain(string,ChainData): Chain ID ",
                    vm.toString(chain.chainId),
                    ' already used by "',
                    foundAlias,
                    '".'
                )
            )
        );

        uint256 oldChainId = chains[chainAlias].chainId;
        delete idToAlias[oldChainId];

        chains[chainAlias] =
            Chain({name: chain.name, chainId: chain.chainId, chainAlias: chainAlias, rpcUrl: chain.rpcUrl});
        idToAlias[chain.chainId] = chainAlias;
    }

    // set chain info, with priority to argument's rpcUrl field.
    function setChain(string memory chainAlias, Chain memory chain) internal virtual {
        setChain(chainAlias, ChainData({name: chain.name, chainId: chain.chainId, rpcUrl: chain.rpcUrl}));
    }

    function _toUpper(string memory str) private pure returns (string memory) {
        bytes memory strb = bytes(str);
        bytes memory copy = new bytes(strb.length);
        for (uint256 i = 0; i < strb.length; i++) {
            bytes1 b = strb[i];
            if (b >= 0x61 && b <= 0x7A) {
                copy[i] = bytes1(uint8(b) - 32);
            } else {
                copy[i] = b;
            }
        }
        return string(copy);
    }

    // lookup rpcUrl, in descending order of priority:
    // current -> config (foundry.toml) -> environment variable -> default
    function getChainWithUpdatedRpcUrl(string memory chainAlias, Chain memory chain)
        private
        view
        returns (Chain memory)
    {
        if (bytes(chain.rpcUrl).length == 0) {
            try vm.rpcUrl(chainAlias) returns (string memory configRpcUrl) {
                chain.rpcUrl = configRpcUrl;
            } catch (bytes memory err) {
                string memory envName = string(abi.encodePacked(_toUpper(chainAlias), "_RPC_URL"));
                if (fallbackToDefaultRpcUrls) {
                    chain.rpcUrl = vm.envOr(envName, defaultRpcUrls[chainAlias]);
                } else {
                    chain.rpcUrl = vm.envString(envName);
                }
                // Distinguish 'not found' from 'cannot read'
                // The upstream error thrown by forge for failing cheats changed so we check both the old and new versions
                bytes memory oldNotFoundError =
                    abi.encodeWithSignature("CheatCodeError", string(abi.encodePacked("invalid rpc url ", chainAlias)));
                bytes memory newNotFoundError = abi.encodeWithSignature(
                    "CheatcodeError(string)", string(abi.encodePacked("invalid rpc url: ", chainAlias))
                );
                bytes32 errHash = keccak256(err);
                if (
                    (errHash != keccak256(oldNotFoundError) && errHash != keccak256(newNotFoundError))
                        || bytes(chain.rpcUrl).length == 0
                ) {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, err), mload(err))
                    }
                }
            }
        }
        return chain;
    }

    function setFallbackToDefaultRpcUrls(bool useDefault) internal {
        fallbackToDefaultRpcUrls = useDefault;
    }

    function initializeStdChains() private {
        if (stdChainsInitialized) return;

        stdChainsInitialized = true;

        // If adding an RPC here, make sure to test the default RPC URL in `test_Rpcs` in `StdChains.t.sol`
        setChainWithDefaultRpcUrl("anvil", ChainData("Anvil", 31337, "http://127.0.0.1:8545"));
        setChainWithDefaultRpcUrl("mainnet", ChainData("Mainnet", 1, "https://eth.llamarpc.com"));
        setChainWithDefaultRpcUrl(
            "sepolia", ChainData("Sepolia", 11155111, "https://sepolia.infura.io/v3/b9794ad1ddf84dfb8c34d6bb5dca2001")
        );
        setChainWithDefaultRpcUrl("holesky", ChainData("Holesky", 17000, "https://rpc.holesky.ethpandaops.io"));
        setChainWithDefaultRpcUrl("hoodi", ChainData("Hoodi", 560048, "https://rpc.hoodi.ethpandaops.io"));
        setChainWithDefaultRpcUrl("optimism", ChainData("Optimism", 10, "https://mainnet.optimism.io"));
        setChainWithDefaultRpcUrl(
            "optimism_sepolia", ChainData("Optimism Sepolia", 11155420, "https://sepolia.optimism.io")
        );
        setChainWithDefaultRpcUrl("arbitrum_one", ChainData("Arbitrum One", 42161, "https://arb1.arbitrum.io/rpc"));
        setChainWithDefaultRpcUrl(
            "arbitrum_one_sepolia", ChainData("Arbitrum One Sepolia", 421614, "https://sepolia-rollup.arbitrum.io/rpc")
        );
        setChainWithDefaultRpcUrl("arbitrum_nova", ChainData("Arbitrum Nova", 42170, "https://nova.arbitrum.io/rpc"));
        setChainWithDefaultRpcUrl("polygon", ChainData("Polygon", 137, "https://polygon-rpc.com"));
        setChainWithDefaultRpcUrl(
            "polygon_amoy", ChainData("Polygon Amoy", 80002, "https://rpc-amoy.polygon.technology")
        );
        setChainWithDefaultRpcUrl("avalanche", ChainData("Avalanche", 43114, "https://api.avax.network/ext/bc/C/rpc"));
        setChainWithDefaultRpcUrl(
            "avalanche_fuji", ChainData("Avalanche Fuji", 43113, "https://api.avax-test.network/ext/bc/C/rpc")
        );
        setChainWithDefaultRpcUrl(
            "bnb_smart_chain", ChainData("BNB Smart Chain", 56, "https://bsc-dataseed1.binance.org")
        );
        setChainWithDefaultRpcUrl(
            "bnb_smart_chain_testnet",
            ChainData("BNB Smart Chain Testnet", 97, "https://rpc.ankr.com/bsc_testnet_chapel")
        );
        setChainWithDefaultRpcUrl("gnosis_chain", ChainData("Gnosis Chain", 100, "https://rpc.gnosischain.com"));
        setChainWithDefaultRpcUrl("moonbeam", ChainData("Moonbeam", 1284, "https://rpc.api.moonbeam.network"));
        setChainWithDefaultRpcUrl(
            "moonriver", ChainData("Moonriver", 1285, "https://rpc.api.moonriver.moonbeam.network")
        );
        setChainWithDefaultRpcUrl("moonbase", ChainData("Moonbase", 1287, "https://rpc.testnet.moonbeam.network"));
        setChainWithDefaultRpcUrl("base_sepolia", ChainData("Base Sepolia", 84532, "https://sepolia.base.org"));
        setChainWithDefaultRpcUrl("base", ChainData("Base", 8453, "https://mainnet.base.org"));
        setChainWithDefaultRpcUrl("blast_sepolia", ChainData("Blast Sepolia", 168587773, "https://sepolia.blast.io"));
        setChainWithDefaultRpcUrl("blast", ChainData("Blast", 81457, "https://rpc.blast.io"));
        setChainWithDefaultRpcUrl("fantom_opera", ChainData("Fantom Opera", 250, "https://rpc.ankr.com/fantom/"));
        setChainWithDefaultRpcUrl(
            "fantom_opera_testnet", ChainData("Fantom Opera Testnet", 4002, "https://rpc.ankr.com/fantom_testnet/")
        );
        setChainWithDefaultRpcUrl("fraxtal", ChainData("Fraxtal", 252, "https://rpc.frax.com"));
        setChainWithDefaultRpcUrl("fraxtal_testnet", ChainData("Fraxtal Testnet", 2522, "https://rpc.testnet.frax.com"));
        setChainWithDefaultRpcUrl(
            "berachain_bartio_testnet", ChainData("Berachain bArtio Testnet", 80084, "https://bartio.rpc.berachain.com")
        );
        setChainWithDefaultRpcUrl("flare", ChainData("Flare", 14, "https://flare-api.flare.network/ext/C/rpc"));
        setChainWithDefaultRpcUrl(
            "flare_coston2", ChainData("Flare Coston2", 114, "https://coston2-api.flare.network/ext/C/rpc")
        );

        setChainWithDefaultRpcUrl("mode", ChainData("Mode", 34443, "https://mode.drpc.org"));
        setChainWithDefaultRpcUrl("mode_sepolia", ChainData("Mode Sepolia", 919, "https://sepolia.mode.network"));

        setChainWithDefaultRpcUrl("zora", ChainData("Zora", 7777777, "https://zora.drpc.org"));
        setChainWithDefaultRpcUrl(
            "zora_sepolia", ChainData("Zora Sepolia", 999999999, "https://sepolia.rpc.zora.energy")
        );

        setChainWithDefaultRpcUrl("race", ChainData("Race", 6805, "https://racemainnet.io"));
        setChainWithDefaultRpcUrl("race_sepolia", ChainData("Race Sepolia", 6806, "https://racemainnet.io"));

        setChainWithDefaultRpcUrl("metal", ChainData("Metal", 1750, "https://metall2.drpc.org"));
        setChainWithDefaultRpcUrl("metal_sepolia", ChainData("Metal Sepolia", 1740, "https://testnet.rpc.metall2.com"));

        setChainWithDefaultRpcUrl("binary", ChainData("Binary", 624, "https://rpc.zero.thebinaryholdings.com"));
        setChainWithDefaultRpcUrl(
            "binary_sepolia", ChainData("Binary Sepolia", 625, "https://rpc.zero.thebinaryholdings.com")
        );

        setChainWithDefaultRpcUrl("orderly", ChainData("Orderly", 291, "https://rpc.orderly.network"));
        setChainWithDefaultRpcUrl(
            "orderly_sepolia", ChainData("Orderly Sepolia", 4460, "https://testnet-rpc.orderly.org")
        );
    }

    // set chain info, with priority to chainAlias' rpc url in foundry.toml
    function setChainWithDefaultRpcUrl(string memory chainAlias, ChainData memory chain) private {
        string memory rpcUrl = chain.rpcUrl;
        defaultRpcUrls[chainAlias] = rpcUrl;
        chain.rpcUrl = "";
        setChain(chainAlias, chain);
        chain.rpcUrl = rpcUrl; // restore argument
    }
}

// lib/forge-std/src/StdJson.sol

// Helpers for parsing and writing JSON files
// To parse:
// ```
// using stdJson for string;
// string memory json = vm.readFile("<some_path>");
// json.readUint("<json_path>");
// ```
// To write:
// ```
// using stdJson for string;
// string memory json = "json";
// json.serialize("a", uint256(123));
// string memory semiFinal = json.serialize("b", string("test"));
// string memory finalJson = json.serialize("c", semiFinal);
// finalJson.write("<some_path>");
// ```

library stdJson {
    VmSafe private constant vm = VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));

    function keyExists(string memory json, string memory key) internal view returns (bool) {
        return vm.keyExistsJson(json, key);
    }

    function parseRaw(string memory json, string memory key) internal pure returns (bytes memory) {
        return vm.parseJson(json, key);
    }

    function readUint(string memory json, string memory key) internal pure returns (uint256) {
        return vm.parseJsonUint(json, key);
    }

    function readUintArray(string memory json, string memory key) internal pure returns (uint256[] memory) {
        return vm.parseJsonUintArray(json, key);
    }

    function readInt(string memory json, string memory key) internal pure returns (int256) {
        return vm.parseJsonInt(json, key);
    }

    function readIntArray(string memory json, string memory key) internal pure returns (int256[] memory) {
        return vm.parseJsonIntArray(json, key);
    }

    function readBytes32(string memory json, string memory key) internal pure returns (bytes32) {
        return vm.parseJsonBytes32(json, key);
    }

    function readBytes32Array(string memory json, string memory key) internal pure returns (bytes32[] memory) {
        return vm.parseJsonBytes32Array(json, key);
    }

    function readString(string memory json, string memory key) internal pure returns (string memory) {
        return vm.parseJsonString(json, key);
    }

    function readStringArray(string memory json, string memory key) internal pure returns (string[] memory) {
        return vm.parseJsonStringArray(json, key);
    }

    function readAddress(string memory json, string memory key) internal pure returns (address) {
        return vm.parseJsonAddress(json, key);
    }

    function readAddressArray(string memory json, string memory key) internal pure returns (address[] memory) {
        return vm.parseJsonAddressArray(json, key);
    }

    function readBool(string memory json, string memory key) internal pure returns (bool) {
        return vm.parseJsonBool(json, key);
    }

    function readBoolArray(string memory json, string memory key) internal pure returns (bool[] memory) {
        return vm.parseJsonBoolArray(json, key);
    }

    function readBytes(string memory json, string memory key) internal pure returns (bytes memory) {
        return vm.parseJsonBytes(json, key);
    }

    function readBytesArray(string memory json, string memory key) internal pure returns (bytes[] memory) {
        return vm.parseJsonBytesArray(json, key);
    }

    function readUintOr(string memory json, string memory key, uint256 defaultValue) internal view returns (uint256) {
        return keyExists(json, key) ? readUint(json, key) : defaultValue;
    }

    function readUintArrayOr(string memory json, string memory key, uint256[] memory defaultValue)
        internal
        view
        returns (uint256[] memory)
    {
        return keyExists(json, key) ? readUintArray(json, key) : defaultValue;
    }

    function readIntOr(string memory json, string memory key, int256 defaultValue) internal view returns (int256) {
        return keyExists(json, key) ? readInt(json, key) : defaultValue;
    }

    function readIntArrayOr(string memory json, string memory key, int256[] memory defaultValue)
        internal
        view
        returns (int256[] memory)
    {
        return keyExists(json, key) ? readIntArray(json, key) : defaultValue;
    }

    function readBytes32Or(string memory json, string memory key, bytes32 defaultValue)
        internal
        view
        returns (bytes32)
    {
        return keyExists(json, key) ? readBytes32(json, key) : defaultValue;
    }

    function readBytes32ArrayOr(string memory json, string memory key, bytes32[] memory defaultValue)
        internal
        view
        returns (bytes32[] memory)
    {
        return keyExists(json, key) ? readBytes32Array(json, key) : defaultValue;
    }

    function readStringOr(string memory json, string memory key, string memory defaultValue)
        internal
        view
        returns (string memory)
    {
        return keyExists(json, key) ? readString(json, key) : defaultValue;
    }

    function readStringArrayOr(string memory json, string memory key, string[] memory defaultValue)
        internal
        view
        returns (string[] memory)
    {
        return keyExists(json, key) ? readStringArray(json, key) : defaultValue;
    }

    function readAddressOr(string memory json, string memory key, address defaultValue)
        internal
        view
        returns (address)
    {
        return keyExists(json, key) ? readAddress(json, key) : defaultValue;
    }

    function readAddressArrayOr(string memory json, string memory key, address[] memory defaultValue)
        internal
        view
        returns (address[] memory)
    {
        return keyExists(json, key) ? readAddressArray(json, key) : defaultValue;
    }

    function readBoolOr(string memory json, string memory key, bool defaultValue) internal view returns (bool) {
        return keyExists(json, key) ? readBool(json, key) : defaultValue;
    }

    function readBoolArrayOr(string memory json, string memory key, bool[] memory defaultValue)
        internal
        view
        returns (bool[] memory)
    {
        return keyExists(json, key) ? readBoolArray(json, key) : defaultValue;
    }

    function readBytesOr(string memory json, string memory key, bytes memory defaultValue)
        internal
        view
        returns (bytes memory)
    {
        return keyExists(json, key) ? readBytes(json, key) : defaultValue;
    }

    function readBytesArrayOr(string memory json, string memory key, bytes[] memory defaultValue)
        internal
        view
        returns (bytes[] memory)
    {
        return keyExists(json, key) ? readBytesArray(json, key) : defaultValue;
    }

    function serialize(string memory jsonKey, string memory rootObject) internal returns (string memory) {
        return vm.serializeJson(jsonKey, rootObject);
    }

    function serialize(string memory jsonKey, string memory key, bool value) internal returns (string memory) {
        return vm.serializeBool(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, bool[] memory value) internal returns (string memory) {
        return vm.serializeBool(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, uint256 value) internal returns (string memory) {
        return vm.serializeUint(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, uint256[] memory value)
        internal
        returns (string memory)
    {
        return vm.serializeUint(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, int256 value) internal returns (string memory) {
        return vm.serializeInt(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, int256[] memory value)
        internal
        returns (string memory)
    {
        return vm.serializeInt(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, address value) internal returns (string memory) {
        return vm.serializeAddress(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, address[] memory value)
        internal
        returns (string memory)
    {
        return vm.serializeAddress(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, bytes32 value) internal returns (string memory) {
        return vm.serializeBytes32(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, bytes32[] memory value)
        internal
        returns (string memory)
    {
        return vm.serializeBytes32(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, bytes memory value) internal returns (string memory) {
        return vm.serializeBytes(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, bytes[] memory value)
        internal
        returns (string memory)
    {
        return vm.serializeBytes(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, string memory value) internal returns (string memory) {
        return vm.serializeString(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, string[] memory value)
        internal
        returns (string memory)
    {
        return vm.serializeString(jsonKey, key, value);
    }

    function write(string memory jsonKey, string memory path) internal {
        vm.writeJson(jsonKey, path);
    }

    function write(string memory jsonKey, string memory path, string memory valueKey) internal {
        vm.writeJson(jsonKey, path, valueKey);
    }
}

// lib/forge-std/src/StdStorage.sol

struct FindData {
    uint256 slot;
    uint256 offsetLeft;
    uint256 offsetRight;
    bool found;
}

struct StdStorage {
    mapping(address => mapping(bytes4 => mapping(bytes32 => FindData))) finds;
    bytes32[] _keys;
    bytes4 _sig;
    uint256 _depth;
    address _target;
    bytes32 _set;
    bool _enable_packed_slots;
    bytes _calldata;
}

library stdStorageSafe {
    event SlotFound(address who, bytes4 fsig, bytes32 keysHash, uint256 slot);
    event WARNING_UninitedSlot(address who, uint256 slot);

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 constant UINT256_MAX = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

    function sigs(string memory sigStr) internal pure returns (bytes4) {
        return bytes4(keccak256(bytes(sigStr)));
    }

    function getCallParams(StdStorage storage self) internal view returns (bytes memory) {
        if (self._calldata.length == 0) {
            return flatten(self._keys);
        } else {
            return self._calldata;
        }
    }

    // Calls target contract with configured parameters
    function callTarget(StdStorage storage self) internal view returns (bool, bytes32) {
        bytes memory cd = abi.encodePacked(self._sig, getCallParams(self));
        (bool success, bytes memory rdat) = self._target.staticcall(cd);
        bytes32 result = bytesToBytes32(rdat, 32 * self._depth);

        return (success, result);
    }

    // Tries mutating slot value to determine if the targeted value is stored in it.
    // If current value is 0, then we are setting slot value to type(uint256).max
    // Otherwise, we set it to 0. That way, return value should always be affected.
    function checkSlotMutatesCall(StdStorage storage self, bytes32 slot) internal returns (bool) {
        bytes32 prevSlotValue = vm.load(self._target, slot);
        (bool success, bytes32 prevReturnValue) = callTarget(self);

        bytes32 testVal = prevReturnValue == bytes32(0) ? bytes32(UINT256_MAX) : bytes32(0);
        vm.store(self._target, slot, testVal);

        (, bytes32 newReturnValue) = callTarget(self);

        vm.store(self._target, slot, prevSlotValue);

        return (success && (prevReturnValue != newReturnValue));
    }

    // Tries setting one of the bits in slot to 1 until return value changes.
    // Index of resulted bit is an offset packed slot has from left/right side
    function findOffset(StdStorage storage self, bytes32 slot, bool left) internal returns (bool, uint256) {
        for (uint256 offset = 0; offset < 256; offset++) {
            uint256 valueToPut = left ? (1 << (255 - offset)) : (1 << offset);
            vm.store(self._target, slot, bytes32(valueToPut));

            (bool success, bytes32 data) = callTarget(self);

            if (success && (uint256(data) > 0)) {
                return (true, offset);
            }
        }
        return (false, 0);
    }

    function findOffsets(StdStorage storage self, bytes32 slot) internal returns (bool, uint256, uint256) {
        bytes32 prevSlotValue = vm.load(self._target, slot);

        (bool foundLeft, uint256 offsetLeft) = findOffset(self, slot, true);
        (bool foundRight, uint256 offsetRight) = findOffset(self, slot, false);

        // `findOffset` may mutate slot value, so we are setting it to initial value
        vm.store(self._target, slot, prevSlotValue);
        return (foundLeft && foundRight, offsetLeft, offsetRight);
    }

    function find(StdStorage storage self) internal returns (FindData storage) {
        return find(self, true);
    }

    /// @notice find an arbitrary storage slot given a function sig, input data, address of the contract and a value to check against
    // slot complexity:
    //  if flat, will be bytes32(uint256(uint));
    //  if map, will be keccak256(abi.encode(key, uint(slot)));
    //  if deep map, will be keccak256(abi.encode(key1, keccak256(abi.encode(key0, uint(slot)))));
    //  if map struct, will be bytes32(uint256(keccak256(abi.encode(key1, keccak256(abi.encode(key0, uint(slot)))))) + structFieldDepth);
    function find(StdStorage storage self, bool _clear) internal returns (FindData storage) {
        address who = self._target;
        bytes4 fsig = self._sig;
        uint256 field_depth = self._depth;
        bytes memory params = getCallParams(self);

        // calldata to test against
        if (self.finds[who][fsig][keccak256(abi.encodePacked(params, field_depth))].found) {
            if (_clear) {
                clear(self);
            }
            return self.finds[who][fsig][keccak256(abi.encodePacked(params, field_depth))];
        }
        vm.record();
        (, bytes32 callResult) = callTarget(self);
        (bytes32[] memory reads,) = vm.accesses(address(who));

        if (reads.length == 0) {
            revert("stdStorage find(StdStorage): No storage use detected for target.");
        } else {
            for (uint256 i = reads.length; --i >= 0;) {
                bytes32 prev = vm.load(who, reads[i]);
                if (prev == bytes32(0)) {
                    emit WARNING_UninitedSlot(who, uint256(reads[i]));
                }

                if (!checkSlotMutatesCall(self, reads[i])) {
                    continue;
                }

                (uint256 offsetLeft, uint256 offsetRight) = (0, 0);

                if (self._enable_packed_slots) {
                    bool found;
                    (found, offsetLeft, offsetRight) = findOffsets(self, reads[i]);
                    if (!found) {
                        continue;
                    }
                }

                // Check that value between found offsets is equal to the current call result
                uint256 curVal = (uint256(prev) & getMaskByOffsets(offsetLeft, offsetRight)) >> offsetRight;

                if (uint256(callResult) != curVal) {
                    continue;
                }

                emit SlotFound(who, fsig, keccak256(abi.encodePacked(params, field_depth)), uint256(reads[i]));
                self.finds[who][fsig][keccak256(abi.encodePacked(params, field_depth))] =
                    FindData(uint256(reads[i]), offsetLeft, offsetRight, true);
                break;
            }
        }

        require(
            self.finds[who][fsig][keccak256(abi.encodePacked(params, field_depth))].found,
            "stdStorage find(StdStorage): Slot(s) not found."
        );

        if (_clear) {
            clear(self);
        }
        return self.finds[who][fsig][keccak256(abi.encodePacked(params, field_depth))];
    }

    function target(StdStorage storage self, address _target) internal returns (StdStorage storage) {
        self._target = _target;
        return self;
    }

    function sig(StdStorage storage self, bytes4 _sig) internal returns (StdStorage storage) {
        self._sig = _sig;
        return self;
    }

    function sig(StdStorage storage self, string memory _sig) internal returns (StdStorage storage) {
        self._sig = sigs(_sig);
        return self;
    }

    function with_calldata(StdStorage storage self, bytes memory _calldata) internal returns (StdStorage storage) {
        self._calldata = _calldata;
        return self;
    }

    function with_key(StdStorage storage self, address who) internal returns (StdStorage storage) {
        self._keys.push(bytes32(uint256(uint160(who))));
        return self;
    }

    function with_key(StdStorage storage self, uint256 amt) internal returns (StdStorage storage) {
        self._keys.push(bytes32(amt));
        return self;
    }

    function with_key(StdStorage storage self, bytes32 key) internal returns (StdStorage storage) {
        self._keys.push(key);
        return self;
    }

    function enable_packed_slots(StdStorage storage self) internal returns (StdStorage storage) {
        self._enable_packed_slots = true;
        return self;
    }

    function depth(StdStorage storage self, uint256 _depth) internal returns (StdStorage storage) {
        self._depth = _depth;
        return self;
    }

    function read(StdStorage storage self) private returns (bytes memory) {
        FindData storage data = find(self, false);
        uint256 mask = getMaskByOffsets(data.offsetLeft, data.offsetRight);
        uint256 value = (uint256(vm.load(self._target, bytes32(data.slot))) & mask) >> data.offsetRight;
        clear(self);
        return abi.encode(value);
    }

    function read_bytes32(StdStorage storage self) internal returns (bytes32) {
        return abi.decode(read(self), (bytes32));
    }

    function read_bool(StdStorage storage self) internal returns (bool) {
        int256 v = read_int(self);
        if (v == 0) return false;
        if (v == 1) return true;
        revert("stdStorage read_bool(StdStorage): Cannot decode. Make sure you are reading a bool.");
    }

    function read_address(StdStorage storage self) internal returns (address) {
        return abi.decode(read(self), (address));
    }

    function read_uint(StdStorage storage self) internal returns (uint256) {
        return abi.decode(read(self), (uint256));
    }

    function read_int(StdStorage storage self) internal returns (int256) {
        return abi.decode(read(self), (int256));
    }

    function parent(StdStorage storage self) internal returns (uint256, bytes32) {
        address who = self._target;
        uint256 field_depth = self._depth;
        vm.startMappingRecording();
        uint256 child = find(self, true).slot - field_depth;
        (bool found, bytes32 key, bytes32 parent_slot) = vm.getMappingKeyAndParentOf(who, bytes32(child));
        if (!found) {
            revert(
                "stdStorage read_bool(StdStorage): Cannot find parent. Make sure you give a slot and startMappingRecording() has been called."
            );
        }
        return (uint256(parent_slot), key);
    }

    function root(StdStorage storage self) internal returns (uint256) {
        address who = self._target;
        uint256 field_depth = self._depth;
        vm.startMappingRecording();
        uint256 child = find(self, true).slot - field_depth;
        bool found;
        bytes32 root_slot;
        bytes32 parent_slot;
        (found,, parent_slot) = vm.getMappingKeyAndParentOf(who, bytes32(child));
        if (!found) {
            revert(
                "stdStorage read_bool(StdStorage): Cannot find parent. Make sure you give a slot and startMappingRecording() has been called."
            );
        }
        while (found) {
            root_slot = parent_slot;
            (found,, parent_slot) = vm.getMappingKeyAndParentOf(who, bytes32(root_slot));
        }
        return uint256(root_slot);
    }

    function bytesToBytes32(bytes memory b, uint256 offset) private pure returns (bytes32) {
        bytes32 out;

        uint256 max = b.length > 32 ? 32 : b.length;
        for (uint256 i = 0; i < max; i++) {
            out |= bytes32(b[offset + i] & 0xFF) >> (i * 8);
        }
        return out;
    }

    function flatten(bytes32[] memory b) private pure returns (bytes memory) {
        bytes memory result = new bytes(b.length * 32);
        for (uint256 i = 0; i < b.length; i++) {
            bytes32 k = b[i];
            /// @solidity memory-safe-assembly
            assembly {
                mstore(add(result, add(32, mul(32, i))), k)
            }
        }

        return result;
    }

    function clear(StdStorage storage self) internal {
        delete self._target;
        delete self._sig;
        delete self._keys;
        delete self._depth;
        delete self._enable_packed_slots;
        delete self._calldata;
    }

    // Returns mask which contains non-zero bits for values between `offsetLeft` and `offsetRight`
    // (slotValue & mask) >> offsetRight will be the value of the given packed variable
    function getMaskByOffsets(uint256 offsetLeft, uint256 offsetRight) internal pure returns (uint256 mask) {
        // mask = ((1 << (256 - (offsetRight + offsetLeft))) - 1) << offsetRight;
        // using assembly because (1 << 256) causes overflow
        assembly {
            mask := shl(offsetRight, sub(shl(sub(256, add(offsetRight, offsetLeft)), 1), 1))
        }
    }

    // Returns slot value with updated packed variable.
    function getUpdatedSlotValue(bytes32 curValue, uint256 varValue, uint256 offsetLeft, uint256 offsetRight)
        internal
        pure
        returns (bytes32 newValue)
    {
        return bytes32((uint256(curValue) & ~getMaskByOffsets(offsetLeft, offsetRight)) | (varValue << offsetRight));
    }
}

library stdStorage {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function sigs(string memory sigStr) internal pure returns (bytes4) {
        return stdStorageSafe.sigs(sigStr);
    }

    function find(StdStorage storage self) internal returns (uint256) {
        return find(self, true);
    }

    function find(StdStorage storage self, bool _clear) internal returns (uint256) {
        return stdStorageSafe.find(self, _clear).slot;
    }

    function target(StdStorage storage self, address _target) internal returns (StdStorage storage) {
        return stdStorageSafe.target(self, _target);
    }

    function sig(StdStorage storage self, bytes4 _sig) internal returns (StdStorage storage) {
        return stdStorageSafe.sig(self, _sig);
    }

    function sig(StdStorage storage self, string memory _sig) internal returns (StdStorage storage) {
        return stdStorageSafe.sig(self, _sig);
    }

    function with_key(StdStorage storage self, address who) internal returns (StdStorage storage) {
        return stdStorageSafe.with_key(self, who);
    }

    function with_key(StdStorage storage self, uint256 amt) internal returns (StdStorage storage) {
        return stdStorageSafe.with_key(self, amt);
    }

    function with_key(StdStorage storage self, bytes32 key) internal returns (StdStorage storage) {
        return stdStorageSafe.with_key(self, key);
    }

    function with_calldata(StdStorage storage self, bytes memory _calldata) internal returns (StdStorage storage) {
        return stdStorageSafe.with_calldata(self, _calldata);
    }

    function enable_packed_slots(StdStorage storage self) internal returns (StdStorage storage) {
        return stdStorageSafe.enable_packed_slots(self);
    }

    function depth(StdStorage storage self, uint256 _depth) internal returns (StdStorage storage) {
        return stdStorageSafe.depth(self, _depth);
    }

    function clear(StdStorage storage self) internal {
        stdStorageSafe.clear(self);
    }

    function checked_write(StdStorage storage self, address who) internal {
        checked_write(self, bytes32(uint256(uint160(who))));
    }

    function checked_write(StdStorage storage self, uint256 amt) internal {
        checked_write(self, bytes32(amt));
    }

    function checked_write_int(StdStorage storage self, int256 val) internal {
        checked_write(self, bytes32(uint256(val)));
    }

    function checked_write(StdStorage storage self, bool write) internal {
        bytes32 t;
        /// @solidity memory-safe-assembly
        assembly {
            t := write
        }
        checked_write(self, t);
    }

    function checked_write(StdStorage storage self, bytes32 set) internal {
        address who = self._target;
        bytes4 fsig = self._sig;
        uint256 field_depth = self._depth;
        bytes memory params = stdStorageSafe.getCallParams(self);

        if (!self.finds[who][fsig][keccak256(abi.encodePacked(params, field_depth))].found) {
            find(self, false);
        }
        FindData storage data = self.finds[who][fsig][keccak256(abi.encodePacked(params, field_depth))];
        if ((data.offsetLeft + data.offsetRight) > 0) {
            uint256 maxVal = 2 ** (256 - (data.offsetLeft + data.offsetRight));
            require(
                uint256(set) < maxVal,
                string(
                    abi.encodePacked(
                        "stdStorage find(StdStorage): Packed slot. We can't fit value greater than ",
                        vm.toString(maxVal)
                    )
                )
            );
        }
        bytes32 curVal = vm.load(who, bytes32(data.slot));
        bytes32 valToSet = stdStorageSafe.getUpdatedSlotValue(curVal, uint256(set), data.offsetLeft, data.offsetRight);

        vm.store(who, bytes32(data.slot), valToSet);

        (bool success, bytes32 callResult) = stdStorageSafe.callTarget(self);

        if (!success || callResult != set) {
            vm.store(who, bytes32(data.slot), curVal);
            revert("stdStorage find(StdStorage): Failed to write value.");
        }
        clear(self);
    }

    function read_bytes32(StdStorage storage self) internal returns (bytes32) {
        return stdStorageSafe.read_bytes32(self);
    }

    function read_bool(StdStorage storage self) internal returns (bool) {
        return stdStorageSafe.read_bool(self);
    }

    function read_address(StdStorage storage self) internal returns (address) {
        return stdStorageSafe.read_address(self);
    }

    function read_uint(StdStorage storage self) internal returns (uint256) {
        return stdStorageSafe.read_uint(self);
    }

    function read_int(StdStorage storage self) internal returns (int256) {
        return stdStorageSafe.read_int(self);
    }

    function parent(StdStorage storage self) internal returns (uint256, bytes32) {
        return stdStorageSafe.parent(self);
    }

    function root(StdStorage storage self) internal returns (uint256) {
        return stdStorageSafe.root(self);
    }
}

// lib/forge-std/src/StdStyle.sol

library StdStyle {
    VmSafe private constant vm = VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));

    string constant RED = "\u001b[91m";
    string constant GREEN = "\u001b[92m";
    string constant YELLOW = "\u001b[93m";
    string constant BLUE = "\u001b[94m";
    string constant MAGENTA = "\u001b[95m";
    string constant CYAN = "\u001b[96m";
    string constant BOLD = "\u001b[1m";
    string constant DIM = "\u001b[2m";
    string constant ITALIC = "\u001b[3m";
    string constant UNDERLINE = "\u001b[4m";
    string constant INVERSE = "\u001b[7m";
    string constant RESET = "\u001b[0m";

    function styleConcat(string memory style, string memory self) private pure returns (string memory) {
        return string(abi.encodePacked(style, self, RESET));
    }

    function red(string memory self) internal pure returns (string memory) {
        return styleConcat(RED, self);
    }

    function red(uint256 self) internal pure returns (string memory) {
        return red(vm.toString(self));
    }

    function red(int256 self) internal pure returns (string memory) {
        return red(vm.toString(self));
    }

    function red(address self) internal pure returns (string memory) {
        return red(vm.toString(self));
    }

    function red(bool self) internal pure returns (string memory) {
        return red(vm.toString(self));
    }

    function redBytes(bytes memory self) internal pure returns (string memory) {
        return red(vm.toString(self));
    }

    function redBytes32(bytes32 self) internal pure returns (string memory) {
        return red(vm.toString(self));
    }

    function green(string memory self) internal pure returns (string memory) {
        return styleConcat(GREEN, self);
    }

    function green(uint256 self) internal pure returns (string memory) {
        return green(vm.toString(self));
    }

    function green(int256 self) internal pure returns (string memory) {
        return green(vm.toString(self));
    }

    function green(address self) internal pure returns (string memory) {
        return green(vm.toString(self));
    }

    function green(bool self) internal pure returns (string memory) {
        return green(vm.toString(self));
    }

    function greenBytes(bytes memory self) internal pure returns (string memory) {
        return green(vm.toString(self));
    }

    function greenBytes32(bytes32 self) internal pure returns (string memory) {
        return green(vm.toString(self));
    }

    function yellow(string memory self) internal pure returns (string memory) {
        return styleConcat(YELLOW, self);
    }

    function yellow(uint256 self) internal pure returns (string memory) {
        return yellow(vm.toString(self));
    }

    function yellow(int256 self) internal pure returns (string memory) {
        return yellow(vm.toString(self));
    }

    function yellow(address self) internal pure returns (string memory) {
        return yellow(vm.toString(self));
    }

    function yellow(bool self) internal pure returns (string memory) {
        return yellow(vm.toString(self));
    }

    function yellowBytes(bytes memory self) internal pure returns (string memory) {
        return yellow(vm.toString(self));
    }

    function yellowBytes32(bytes32 self) internal pure returns (string memory) {
        return yellow(vm.toString(self));
    }

    function blue(string memory self) internal pure returns (string memory) {
        return styleConcat(BLUE, self);
    }

    function blue(uint256 self) internal pure returns (string memory) {
        return blue(vm.toString(self));
    }

    function blue(int256 self) internal pure returns (string memory) {
        return blue(vm.toString(self));
    }

    function blue(address self) internal pure returns (string memory) {
        return blue(vm.toString(self));
    }

    function blue(bool self) internal pure returns (string memory) {
        return blue(vm.toString(self));
    }

    function blueBytes(bytes memory self) internal pure returns (string memory) {
        return blue(vm.toString(self));
    }

    function blueBytes32(bytes32 self) internal pure returns (string memory) {
        return blue(vm.toString(self));
    }

    function magenta(string memory self) internal pure returns (string memory) {
        return styleConcat(MAGENTA, self);
    }

    function magenta(uint256 self) internal pure returns (string memory) {
        return magenta(vm.toString(self));
    }

    function magenta(int256 self) internal pure returns (string memory) {
        return magenta(vm.toString(self));
    }

    function magenta(address self) internal pure returns (string memory) {
        return magenta(vm.toString(self));
    }

    function magenta(bool self) internal pure returns (string memory) {
        return magenta(vm.toString(self));
    }

    function magentaBytes(bytes memory self) internal pure returns (string memory) {
        return magenta(vm.toString(self));
    }

    function magentaBytes32(bytes32 self) internal pure returns (string memory) {
        return magenta(vm.toString(self));
    }

    function cyan(string memory self) internal pure returns (string memory) {
        return styleConcat(CYAN, self);
    }

    function cyan(uint256 self) internal pure returns (string memory) {
        return cyan(vm.toString(self));
    }

    function cyan(int256 self) internal pure returns (string memory) {
        return cyan(vm.toString(self));
    }

    function cyan(address self) internal pure returns (string memory) {
        return cyan(vm.toString(self));
    }

    function cyan(bool self) internal pure returns (string memory) {
        return cyan(vm.toString(self));
    }

    function cyanBytes(bytes memory self) internal pure returns (string memory) {
        return cyan(vm.toString(self));
    }

    function cyanBytes32(bytes32 self) internal pure returns (string memory) {
        return cyan(vm.toString(self));
    }

    function bold(string memory self) internal pure returns (string memory) {
        return styleConcat(BOLD, self);
    }

    function bold(uint256 self) internal pure returns (string memory) {
        return bold(vm.toString(self));
    }

    function bold(int256 self) internal pure returns (string memory) {
        return bold(vm.toString(self));
    }

    function bold(address self) internal pure returns (string memory) {
        return bold(vm.toString(self));
    }

    function bold(bool self) internal pure returns (string memory) {
        return bold(vm.toString(self));
    }

    function boldBytes(bytes memory self) internal pure returns (string memory) {
        return bold(vm.toString(self));
    }

    function boldBytes32(bytes32 self) internal pure returns (string memory) {
        return bold(vm.toString(self));
    }

    function dim(string memory self) internal pure returns (string memory) {
        return styleConcat(DIM, self);
    }

    function dim(uint256 self) internal pure returns (string memory) {
        return dim(vm.toString(self));
    }

    function dim(int256 self) internal pure returns (string memory) {
        return dim(vm.toString(self));
    }

    function dim(address self) internal pure returns (string memory) {
        return dim(vm.toString(self));
    }

    function dim(bool self) internal pure returns (string memory) {
        return dim(vm.toString(self));
    }

    function dimBytes(bytes memory self) internal pure returns (string memory) {
        return dim(vm.toString(self));
    }

    function dimBytes32(bytes32 self) internal pure returns (string memory) {
        return dim(vm.toString(self));
    }

    function italic(string memory self) internal pure returns (string memory) {
        return styleConcat(ITALIC, self);
    }

    function italic(uint256 self) internal pure returns (string memory) {
        return italic(vm.toString(self));
    }

    function italic(int256 self) internal pure returns (string memory) {
        return italic(vm.toString(self));
    }

    function italic(address self) internal pure returns (string memory) {
        return italic(vm.toString(self));
    }

    function italic(bool self) internal pure returns (string memory) {
        return italic(vm.toString(self));
    }

    function italicBytes(bytes memory self) internal pure returns (string memory) {
        return italic(vm.toString(self));
    }

    function italicBytes32(bytes32 self) internal pure returns (string memory) {
        return italic(vm.toString(self));
    }

    function underline(string memory self) internal pure returns (string memory) {
        return styleConcat(UNDERLINE, self);
    }

    function underline(uint256 self) internal pure returns (string memory) {
        return underline(vm.toString(self));
    }

    function underline(int256 self) internal pure returns (string memory) {
        return underline(vm.toString(self));
    }

    function underline(address self) internal pure returns (string memory) {
        return underline(vm.toString(self));
    }

    function underline(bool self) internal pure returns (string memory) {
        return underline(vm.toString(self));
    }

    function underlineBytes(bytes memory self) internal pure returns (string memory) {
        return underline(vm.toString(self));
    }

    function underlineBytes32(bytes32 self) internal pure returns (string memory) {
        return underline(vm.toString(self));
    }

    function inverse(string memory self) internal pure returns (string memory) {
        return styleConcat(INVERSE, self);
    }

    function inverse(uint256 self) internal pure returns (string memory) {
        return inverse(vm.toString(self));
    }

    function inverse(int256 self) internal pure returns (string memory) {
        return inverse(vm.toString(self));
    }

    function inverse(address self) internal pure returns (string memory) {
        return inverse(vm.toString(self));
    }

    function inverse(bool self) internal pure returns (string memory) {
        return inverse(vm.toString(self));
    }

    function inverseBytes(bytes memory self) internal pure returns (string memory) {
        return inverse(vm.toString(self));
    }

    function inverseBytes32(bytes32 self) internal pure returns (string memory) {
        return inverse(vm.toString(self));
    }
}

// lib/forge-std/src/StdToml.sol

// Helpers for parsing and writing TOML files
// To parse:
// ```
// using stdToml for string;
// string memory toml = vm.readFile("<some_path>");
// toml.readUint("<json_path>");
// ```
// To write:
// ```
// using stdToml for string;
// string memory json = "json";
// json.serialize("a", uint256(123));
// string memory semiFinal = json.serialize("b", string("test"));
// string memory finalJson = json.serialize("c", semiFinal);
// finalJson.write("<some_path>");
// ```

library stdToml {
    VmSafe private constant vm = VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));

    function keyExists(string memory toml, string memory key) internal view returns (bool) {
        return vm.keyExistsToml(toml, key);
    }

    function parseRaw(string memory toml, string memory key) internal pure returns (bytes memory) {
        return vm.parseToml(toml, key);
    }

    function readUint(string memory toml, string memory key) internal pure returns (uint256) {
        return vm.parseTomlUint(toml, key);
    }

    function readUintArray(string memory toml, string memory key) internal pure returns (uint256[] memory) {
        return vm.parseTomlUintArray(toml, key);
    }

    function readInt(string memory toml, string memory key) internal pure returns (int256) {
        return vm.parseTomlInt(toml, key);
    }

    function readIntArray(string memory toml, string memory key) internal pure returns (int256[] memory) {
        return vm.parseTomlIntArray(toml, key);
    }

    function readBytes32(string memory toml, string memory key) internal pure returns (bytes32) {
        return vm.parseTomlBytes32(toml, key);
    }

    function readBytes32Array(string memory toml, string memory key) internal pure returns (bytes32[] memory) {
        return vm.parseTomlBytes32Array(toml, key);
    }

    function readString(string memory toml, string memory key) internal pure returns (string memory) {
        return vm.parseTomlString(toml, key);
    }

    function readStringArray(string memory toml, string memory key) internal pure returns (string[] memory) {
        return vm.parseTomlStringArray(toml, key);
    }

    function readAddress(string memory toml, string memory key) internal pure returns (address) {
        return vm.parseTomlAddress(toml, key);
    }

    function readAddressArray(string memory toml, string memory key) internal pure returns (address[] memory) {
        return vm.parseTomlAddressArray(toml, key);
    }

    function readBool(string memory toml, string memory key) internal pure returns (bool) {
        return vm.parseTomlBool(toml, key);
    }

    function readBoolArray(string memory toml, string memory key) internal pure returns (bool[] memory) {
        return vm.parseTomlBoolArray(toml, key);
    }

    function readBytes(string memory toml, string memory key) internal pure returns (bytes memory) {
        return vm.parseTomlBytes(toml, key);
    }

    function readBytesArray(string memory toml, string memory key) internal pure returns (bytes[] memory) {
        return vm.parseTomlBytesArray(toml, key);
    }

    function readUintOr(string memory toml, string memory key, uint256 defaultValue) internal view returns (uint256) {
        return keyExists(toml, key) ? readUint(toml, key) : defaultValue;
    }

    function readUintArrayOr(string memory toml, string memory key, uint256[] memory defaultValue)
        internal
        view
        returns (uint256[] memory)
    {
        return keyExists(toml, key) ? readUintArray(toml, key) : defaultValue;
    }

    function readIntOr(string memory toml, string memory key, int256 defaultValue) internal view returns (int256) {
        return keyExists(toml, key) ? readInt(toml, key) : defaultValue;
    }

    function readIntArrayOr(string memory toml, string memory key, int256[] memory defaultValue)
        internal
        view
        returns (int256[] memory)
    {
        return keyExists(toml, key) ? readIntArray(toml, key) : defaultValue;
    }

    function readBytes32Or(string memory toml, string memory key, bytes32 defaultValue)
        internal
        view
        returns (bytes32)
    {
        return keyExists(toml, key) ? readBytes32(toml, key) : defaultValue;
    }

    function readBytes32ArrayOr(string memory toml, string memory key, bytes32[] memory defaultValue)
        internal
        view
        returns (bytes32[] memory)
    {
        return keyExists(toml, key) ? readBytes32Array(toml, key) : defaultValue;
    }

    function readStringOr(string memory toml, string memory key, string memory defaultValue)
        internal
        view
        returns (string memory)
    {
        return keyExists(toml, key) ? readString(toml, key) : defaultValue;
    }

    function readStringArrayOr(string memory toml, string memory key, string[] memory defaultValue)
        internal
        view
        returns (string[] memory)
    {
        return keyExists(toml, key) ? readStringArray(toml, key) : defaultValue;
    }

    function readAddressOr(string memory toml, string memory key, address defaultValue)
        internal
        view
        returns (address)
    {
        return keyExists(toml, key) ? readAddress(toml, key) : defaultValue;
    }

    function readAddressArrayOr(string memory toml, string memory key, address[] memory defaultValue)
        internal
        view
        returns (address[] memory)
    {
        return keyExists(toml, key) ? readAddressArray(toml, key) : defaultValue;
    }

    function readBoolOr(string memory toml, string memory key, bool defaultValue) internal view returns (bool) {
        return keyExists(toml, key) ? readBool(toml, key) : defaultValue;
    }

    function readBoolArrayOr(string memory toml, string memory key, bool[] memory defaultValue)
        internal
        view
        returns (bool[] memory)
    {
        return keyExists(toml, key) ? readBoolArray(toml, key) : defaultValue;
    }

    function readBytesOr(string memory toml, string memory key, bytes memory defaultValue)
        internal
        view
        returns (bytes memory)
    {
        return keyExists(toml, key) ? readBytes(toml, key) : defaultValue;
    }

    function readBytesArrayOr(string memory toml, string memory key, bytes[] memory defaultValue)
        internal
        view
        returns (bytes[] memory)
    {
        return keyExists(toml, key) ? readBytesArray(toml, key) : defaultValue;
    }

    function serialize(string memory jsonKey, string memory rootObject) internal returns (string memory) {
        return vm.serializeJson(jsonKey, rootObject);
    }

    function serialize(string memory jsonKey, string memory key, bool value) internal returns (string memory) {
        return vm.serializeBool(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, bool[] memory value) internal returns (string memory) {
        return vm.serializeBool(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, uint256 value) internal returns (string memory) {
        return vm.serializeUint(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, uint256[] memory value)
        internal
        returns (string memory)
    {
        return vm.serializeUint(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, int256 value) internal returns (string memory) {
        return vm.serializeInt(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, int256[] memory value)
        internal
        returns (string memory)
    {
        return vm.serializeInt(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, address value) internal returns (string memory) {
        return vm.serializeAddress(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, address[] memory value)
        internal
        returns (string memory)
    {
        return vm.serializeAddress(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, bytes32 value) internal returns (string memory) {
        return vm.serializeBytes32(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, bytes32[] memory value)
        internal
        returns (string memory)
    {
        return vm.serializeBytes32(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, bytes memory value) internal returns (string memory) {
        return vm.serializeBytes(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, bytes[] memory value)
        internal
        returns (string memory)
    {
        return vm.serializeBytes(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, string memory value) internal returns (string memory) {
        return vm.serializeString(jsonKey, key, value);
    }

    function serialize(string memory jsonKey, string memory key, string[] memory value)
        internal
        returns (string memory)
    {
        return vm.serializeString(jsonKey, key, value);
    }

    function write(string memory jsonKey, string memory path) internal {
        vm.writeToml(jsonKey, path);
    }

    function write(string memory jsonKey, string memory path, string memory valueKey) internal {
        vm.writeToml(jsonKey, path, valueKey);
    }
}

// lib/forge-std/src/console2.sol

// lib/forge-std/src/Base.sol

abstract contract CommonBase {
    /// @dev Cheat code address.
    /// Calculated as `address(uint160(uint256(keccak256("hevm cheat code"))))`.
    address internal constant VM_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

    /// @dev console.sol and console2.sol work by executing a staticcall to this address.
    /// Calculated as `address(uint160(uint88(bytes11("console.log"))))`.
    address internal constant CONSOLE = 0x000000000000000000636F6e736F6c652e6c6f67;

    /// @dev Used when deploying with create2.
    /// Taken from https://github.com/Arachnid/deterministic-deployment-proxy.
    address internal constant CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @dev The default address for tx.origin and msg.sender.
    /// Calculated as `address(uint160(uint256(keccak256("foundry default caller"))))`.
    address internal constant DEFAULT_SENDER = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;

    /// @dev The address of the first contract `CREATE`d by a running test contract.
    /// When running tests, each test contract is `CREATE`d by `DEFAULT_SENDER` with nonce 1.
    /// Calculated as `VM.computeCreateAddress(VM.computeCreateAddress(DEFAULT_SENDER, 1), 1)`.
    address internal constant DEFAULT_TEST_CONTRACT = 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f;

    /// @dev Deterministic deployment address of the Multicall3 contract.
    /// Taken from https://www.multicall3.com.
    address internal constant MULTICALL3_ADDRESS = 0xcA11bde05977b3631167028862bE2a173976CA11;

    /// @dev The order of the secp256k1 curve.
    uint256 internal constant SECP256K1_ORDER =
        115792089237316195423570985008687907852837564279074904382605163141518161494337;

    uint256 internal constant UINT256_MAX =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;

    Vm internal constant vm = Vm(VM_ADDRESS);
    StdStorage internal stdstore;
}

abstract contract TestBase is CommonBase {}

abstract contract ScriptBase is CommonBase {
    VmSafe internal constant vmSafe = VmSafe(VM_ADDRESS);
}

// lib/pendle-sy/contracts/core/libraries/BoringOwnableUpgradeableV2.sol

contract BoringOwnableUpgradeableData {
    address public owner;
    address public pendingOwner;
}

abstract contract BoringOwnableUpgradeableV2 is BoringOwnableUpgradeableData, Initializable {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function __BoringOwnableV2_init(address _owner) internal onlyInitializing {
        owner = _owner;
    }

    /// @notice Transfers ownership to `newOwner`. Either directly or claimable by the new pending owner.
    /// Can only be invoked by the current `owner`.
    /// @param newOwner Address of the new owner.
    /// @param direct True if `newOwner` should be set immediately. False if `newOwner` needs to use `claimOwnership`.
    /// @param renounce Allows the `newOwner` to be `address(0)` if `direct` and `renounce` is True. Has no effect otherwise.
    function transferOwnership(address newOwner, bool direct, bool renounce) public onlyOwner {
        if (direct) {
            // Checks
            require(newOwner != address(0) || renounce, "Ownable: zero address");

            // Effects
            emit OwnershipTransferred(owner, newOwner);
            owner = newOwner;
            pendingOwner = address(0);
        } else {
            // Effects
            pendingOwner = newOwner;
        }
    }

    /// @notice Needs to be called by `pendingOwner` to claim ownership.
    function claimOwnership() public {
        address _pendingOwner = pendingOwner;

        // Checks
        require(msg.sender == _pendingOwner, "Ownable: caller != pending owner");

        // Effects
        emit OwnershipTransferred(owner, _pendingOwner);
        owner = _pendingOwner;
        pendingOwner = address(0);
    }

    /// @notice Only allows the `owner` to execute the function.
    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: caller is not the owner");
        _;
    }

    uint256[48] private __gap;
}

// lib/pendle-sy/contracts/interfaces/IStandardizedYield.sol

/*
 * MIT License
 * ===========
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 */

interface IStandardizedYield is IERC20Metadata {
    /// @dev Emitted when any base tokens is deposited to mint shares
    event Deposit(
        address indexed caller,
        address indexed receiver,
        address indexed tokenIn,
        uint256 amountDeposited,
        uint256 amountSyOut
    );

    /// @dev Emitted when any shares are redeemed for base tokens
    event Redeem(
        address indexed caller,
        address indexed receiver,
        address indexed tokenOut,
        uint256 amountSyToRedeem,
        uint256 amountTokenOut
    );

    /// @dev check `assetInfo()` for more information
    enum AssetType {
        TOKEN,
        LIQUIDITY
    }

    /// @dev Emitted when (`user`) claims their rewards
    event ClaimRewards(address indexed user, address[] rewardTokens, uint256[] rewardAmounts);

    /**
     * @notice mints an amount of shares by depositing a base token.
     * @param receiver shares recipient address
     * @param tokenIn address of the base tokens to mint shares
     * @param amountTokenToDeposit amount of base tokens to be transferred from (`msg.sender`)
     * @param minSharesOut reverts if amount of shares minted is lower than this
     * @return amountSharesOut amount of shares minted
     * @dev Emits a {Deposit} event
     *
     * Requirements:
     * - (`tokenIn`) must be a valid base token.
     */
    function deposit(address receiver, address tokenIn, uint256 amountTokenToDeposit, uint256 minSharesOut)
        external
        payable
        returns (uint256 amountSharesOut);

    /**
     * @notice redeems an amount of base tokens by burning some shares
     * @param receiver recipient address
     * @param amountSharesToRedeem amount of shares to be burned
     * @param tokenOut address of the base token to be redeemed
     * @param minTokenOut reverts if amount of base token redeemed is lower than this
     * @param burnFromInternalBalance if true, burns from balance of `address(this)`, otherwise burns from `msg.sender`
     * @return amountTokenOut amount of base tokens redeemed
     * @dev Emits a {Redeem} event
     *
     * Requirements:
     * - (`tokenOut`) must be a valid base token.
     */
    function redeem(
        address receiver,
        uint256 amountSharesToRedeem,
        address tokenOut,
        uint256 minTokenOut,
        bool burnFromInternalBalance
    ) external returns (uint256 amountTokenOut);

    /**
     * @notice exchangeRate * syBalance / 1e18 must return the asset balance of the account
     * @notice vice-versa, if a user uses some amount of tokens equivalent to X asset, the amount of sy
     * exchangeRate / 1e18
     * @dev SYUtils's assetToSy & syToAsset should be used instead of raw multiplication
     *  & division
     */
    function exchangeRate() external view returns (uint256 res);

    /**
     * @notice claims reward for (`user`)
     * @param user the user receiving their rewards
     * @return rewardAmounts an array of reward amounts in the same order as `getRewardTokens`
     * @dev
     * Emits a `ClaimRewards` event
     * See {getRewardTokens} for list of reward tokens
     */
    function claimRewards(address user) external returns (uint256[] memory rewardAmounts);

    /**
     * @notice get the amount of unclaimed rewards for (`user`)
     * @param user the user to check for
     * @return rewardAmounts an array of reward amounts in the same order as `getRewardTokens`
     */
    function accruedRewards(address user) external view returns (uint256[] memory rewardAmounts);

    function rewardIndexesCurrent() external returns (uint256[] memory indexes);

    function rewardIndexesStored() external view returns (uint256[] memory indexes);

    /**
     * @notice returns the list of reward token addresses
     */
    function getRewardTokens() external view returns (address[] memory);

    /**
     * @notice returns the address of the underlying yield token
     */
    function yieldToken() external view returns (address);

    /**
     * @notice returns all tokens that can mint this SY
     */
    function getTokensIn() external view returns (address[] memory res);

    /**
     * @notice returns all tokens that can be redeemed by this SY
     */
    function getTokensOut() external view returns (address[] memory res);

    function isValidTokenIn(address token) external view returns (bool);

    function isValidTokenOut(address token) external view returns (bool);

    function previewDeposit(address tokenIn, uint256 amountTokenToDeposit)
        external
        view
        returns (uint256 amountSharesOut);

    function previewRedeem(address tokenOut, uint256 amountSharesToRedeem)
        external
        view
        returns (uint256 amountTokenOut);

    /**
     * @notice This function contains information to interpret what the asset is
     * @return assetType the type of the asset (0 for ERC20 tokens, 1 for AMM liquidity tokens,
     *     2 for bridged yield bearing tokens like wstETH, rETH on Arbi whose the underlying asset doesn't exist on the chain)
     * @return assetAddress the address of the asset
     * @return assetDecimals the decimals of the asset
     */
    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals);
}

// lib/forge-std/src/StdConstants.sol

library StdConstants {
    /// @dev Cheat code address.
    /// Calculated as `address(uint160(uint256(keccak256("hevm cheat code"))))`.
    Vm internal constant VM = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    /// @dev console.sol and console2.sol work by executing a staticcall to this address.
    /// Calculated as `address(uint160(uint88(bytes11("console.log"))))`.
    address internal constant CONSOLE = 0x000000000000000000636F6e736F6c652e6c6f67;
    /// @dev Used when deploying with create2.
    /// Taken from https://github.com/Arachnid/deterministic-deployment-proxy.
    address internal constant CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    /// @dev The default address for tx.origin and msg.sender.
    /// Calculated as `address(uint160(uint256(keccak256("foundry default caller"))))`.
    address internal constant DEFAULT_SENDER = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    /// @dev The address of the first contract `CREATE`d by a running test contract.
    /// When running tests, each test contract is `CREATE`d by `DEFAULT_SENDER` with nonce 1.
    /// Calculated as `VM.computeCreateAddress(VM.computeCreateAddress(DEFAULT_SENDER, 1), 1)`.
    address internal constant DEFAULT_TEST_CONTRACT = 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f;
    /// @dev Deterministic deployment address of the Multicall3 contract.
    /// Taken from https://www.multicall3.com.
    IMulticall3 internal constant MULTICALL3_ADDRESS = IMulticall3(0xcA11bde05977b3631167028862bE2a173976CA11);
    /// @dev The order of the secp256k1 curve.
    uint256 internal constant SECP256K1_ORDER =
        115792089237316195423570985008687907852837564279074904382605163141518161494337;
}

// lib/forge-std/src/StdUtils.sol

abstract contract StdUtils {
    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    IMulticall3 private constant multicall = IMulticall3(0xcA11bde05977b3631167028862bE2a173976CA11);
    VmSafe private constant vm = VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant CONSOLE2_ADDRESS = 0x000000000000000000636F6e736F6c652e6c6f67;
    uint256 private constant INT256_MIN_ABS =
        57896044618658097711785492504343953926634992332820282019728792003956564819968;
    uint256 private constant SECP256K1_ORDER =
        115792089237316195423570985008687907852837564279074904382605163141518161494337;
    uint256 private constant UINT256_MAX =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;

    // Used by default when deploying with create2, https://github.com/Arachnid/deterministic-deployment-proxy.
    address private constant CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /*//////////////////////////////////////////////////////////////////////////
                                 INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    function _bound(uint256 x, uint256 min, uint256 max) internal pure virtual returns (uint256 result) {
        require(min <= max, "StdUtils bound(uint256,uint256,uint256): Max is less than min.");
        // If x is between min and max, return x directly. This is to ensure that dictionary values
        // do not get shifted if the min is nonzero. More info: https://github.com/foundry-rs/forge-std/issues/188
        if (x >= min && x <= max) return x;

        uint256 size = max - min + 1;

        // If the value is 0, 1, 2, 3, wrap that to min, min+1, min+2, min+3. Similarly for the UINT256_MAX side.
        // This helps ensure coverage of the min/max values.
        if (x <= 3 && size > x) return min + x;
        if (x >= UINT256_MAX - 3 && size > UINT256_MAX - x) {
            return max - (UINT256_MAX - x);
        }

        // Otherwise, wrap x into the range [min, max], i.e. the range is inclusive.
        if (x > max) {
            uint256 diff = x - max;
            uint256 rem = diff % size;
            if (rem == 0) return max;
            result = min + rem - 1;
        } else if (x < min) {
            uint256 diff = min - x;
            uint256 rem = diff % size;
            if (rem == 0) return min;
            result = max - rem + 1;
        }
    }

    function bound(uint256 x, uint256 min, uint256 max) internal pure virtual returns (uint256 result) {
        result = _bound(x, min, max);
        console2_log_StdUtils("Bound result", result);
    }

    function _bound(int256 x, int256 min, int256 max) internal pure virtual returns (int256 result) {
        require(min <= max, "StdUtils bound(int256,int256,int256): Max is less than min.");

        // Shifting all int256 values to uint256 to use _bound function. The range of two types are:
        // int256 : -(2**255) ~ (2**255 - 1)
        // uint256:     0     ~ (2**256 - 1)
        // So, add 2**255, INT256_MIN_ABS to the integer values.
        //
        // If the given integer value is -2**255, we cannot use `-uint256(-x)` because of the overflow.
        // So, use `~uint256(x) + 1` instead.
        uint256 _x = x < 0 ? (INT256_MIN_ABS - ~uint256(x) - 1) : (uint256(x) + INT256_MIN_ABS);
        uint256 _min = min < 0 ? (INT256_MIN_ABS - ~uint256(min) - 1) : (uint256(min) + INT256_MIN_ABS);
        uint256 _max = max < 0 ? (INT256_MIN_ABS - ~uint256(max) - 1) : (uint256(max) + INT256_MIN_ABS);

        uint256 y = _bound(_x, _min, _max);

        // To move it back to int256 value, subtract INT256_MIN_ABS at here.
        result = y < INT256_MIN_ABS ? int256(~(INT256_MIN_ABS - y) + 1) : int256(y - INT256_MIN_ABS);
    }

    function bound(int256 x, int256 min, int256 max) internal pure virtual returns (int256 result) {
        result = _bound(x, min, max);
        console2_log_StdUtils("Bound result", vm.toString(result));
    }

    function boundPrivateKey(uint256 privateKey) internal pure virtual returns (uint256 result) {
        result = _bound(privateKey, 1, SECP256K1_ORDER - 1);
    }

    function bytesToUint(bytes memory b) internal pure virtual returns (uint256) {
        require(b.length <= 32, "StdUtils bytesToUint(bytes): Bytes length exceeds 32.");
        return abi.decode(abi.encodePacked(new bytes(32 - b.length), b), (uint256));
    }

    /// @dev Compute the address a contract will be deployed at for a given deployer address and nonce
    function computeCreateAddress(address deployer, uint256 nonce) internal pure virtual returns (address) {
        console2_log_StdUtils("computeCreateAddress is deprecated. Please use vm.computeCreateAddress instead.");
        return vm.computeCreateAddress(deployer, nonce);
    }

    function computeCreate2Address(bytes32 salt, bytes32 initcodeHash, address deployer)
        internal
        pure
        virtual
        returns (address)
    {
        console2_log_StdUtils("computeCreate2Address is deprecated. Please use vm.computeCreate2Address instead.");
        return vm.computeCreate2Address(salt, initcodeHash, deployer);
    }

    /// @dev returns the address of a contract created with CREATE2 using the default CREATE2 deployer
    function computeCreate2Address(bytes32 salt, bytes32 initCodeHash) internal pure returns (address) {
        console2_log_StdUtils("computeCreate2Address is deprecated. Please use vm.computeCreate2Address instead.");
        return vm.computeCreate2Address(salt, initCodeHash);
    }

    /// @dev returns the hash of the init code (creation code + no args) used in CREATE2 with no constructor arguments
    /// @param creationCode the creation code of a contract C, as returned by type(C).creationCode
    function hashInitCode(bytes memory creationCode) internal pure returns (bytes32) {
        return hashInitCode(creationCode, "");
    }

    /// @dev returns the hash of the init code (creation code + ABI-encoded args) used in CREATE2
    /// @param creationCode the creation code of a contract C, as returned by type(C).creationCode
    /// @param args the ABI-encoded arguments to the constructor of C
    function hashInitCode(bytes memory creationCode, bytes memory args) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(creationCode, args));
    }

    // Performs a single call with Multicall3 to query the ERC-20 token balances of the given addresses.
    function getTokenBalances(address token, address[] memory addresses)
        internal
        virtual
        returns (uint256[] memory balances)
    {
        uint256 tokenCodeSize;
        assembly {
            tokenCodeSize := extcodesize(token)
        }
        require(tokenCodeSize > 0, "StdUtils getTokenBalances(address,address[]): Token address is not a contract.");

        // ABI encode the aggregate call to Multicall3.
        uint256 length = addresses.length;
        IMulticall3.Call[] memory calls = new IMulticall3.Call[](length);
        for (uint256 i = 0; i < length; ++i) {
            // 0x70a08231 = bytes4("balanceOf(address)"))
            calls[i] = IMulticall3.Call({target: token, callData: abi.encodeWithSelector(0x70a08231, (addresses[i]))});
        }

        // Make the aggregate call.
        (, bytes[] memory returnData) = multicall.aggregate(calls);

        // ABI decode the return data and return the balances.
        balances = new uint256[](length);
        for (uint256 i = 0; i < length; ++i) {
            balances[i] = abi.decode(returnData[i], (uint256));
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                 PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    function addressFromLast20Bytes(bytes32 bytesValue) private pure returns (address) {
        return address(uint160(uint256(bytesValue)));
    }

    // This section is used to prevent the compilation of console, which shortens the compilation time when console is
    // not used elsewhere. We also trick the compiler into letting us make the console log methods as `pure` to avoid
    // any breaking changes to function signatures.
    function _castLogPayloadViewToPure(function(bytes memory) internal view fnIn)
        internal
        pure
        returns (function(bytes memory) internal pure fnOut)
    {
        assembly {
            fnOut := fnIn
        }
    }

    function _sendLogPayload(bytes memory payload) internal pure {
        _castLogPayloadViewToPure(_sendLogPayloadView)(payload);
    }

    function _sendLogPayloadView(bytes memory payload) private view {
        uint256 payloadLength = payload.length;
        address consoleAddress = CONSOLE2_ADDRESS;
        /// @solidity memory-safe-assembly
        assembly {
            let payloadStart := add(payload, 32)
            let r := staticcall(gas(), consoleAddress, payloadStart, payloadLength, 0, 0)
        }
    }

    function console2_log_StdUtils(string memory p0) private pure {
        _sendLogPayload(abi.encodeWithSignature("log(string)", p0));
    }

    function console2_log_StdUtils(string memory p0, uint256 p1) private pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256)", p0, p1));
    }

    function console2_log_StdUtils(string memory p0, string memory p1) private pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string)", p0, p1));
    }
}

// node_modules/@openzeppelin/contracts/utils/Strings.sol

// OpenZeppelin Contracts (last updated v4.9.0) (utils/Strings.sol)

/**
 * @dev String operations.
 */
library Strings {
    bytes16 private constant _SYMBOLS = "0123456789abcdef";
    uint8 private constant _ADDRESS_LENGTH = 20;

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        unchecked {
            uint256 length = Math.log10(value) + 1;
            string memory buffer = new string(length);
            uint256 ptr;
            /// @solidity memory-safe-assembly
            assembly {
                ptr := add(buffer, add(32, length))
            }
            while (true) {
                ptr--;
                /// @solidity memory-safe-assembly
                assembly {
                    mstore8(ptr, byte(mod(value, 10), _SYMBOLS))
                }
                value /= 10;
                if (value == 0) break;
            }
            return buffer;
        }
    }

    /**
     * @dev Converts a `int256` to its ASCII `string` decimal representation.
     */
    function toString(int256 value) internal pure returns (string memory) {
        return string(abi.encodePacked(value < 0 ? "-" : "", toString(SignedMath.abs(value))));
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        unchecked {
            return toHexString(value, Math.log256(value) + 1);
        }
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
     */
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }

    /**
     * @dev Converts an `address` with fixed length of 20 bytes to its not checksummed ASCII `string` hexadecimal representation.
     */
    function toHexString(address addr) internal pure returns (string memory) {
        return toHexString(uint256(uint160(addr)), _ADDRESS_LENGTH);
    }

    /**
     * @dev Returns true if the two strings are equal.
     */
    function equal(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}

// node_modules/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol

// OpenZeppelin Contracts (last updated v4.9.3) (token/ERC20/utils/SafeERC20.sol)

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    /**
     * @dev Transfer `value` amount of `token` from the calling contract to `to`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    /**
     * @dev Transfer `value` amount of `token` from `from` to `to`, spending the approval given by `from` to the
     * calling contract. If `token` returns no value, non-reverting calls are assumed to be successful.
     */
    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    /**
     * @dev Increase the calling contract's allowance toward `spender` by `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 oldAllowance = token.allowance(address(this), spender);
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, oldAllowance + value));
    }

    /**
     * @dev Decrease the calling contract's allowance toward `spender` by `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, oldAllowance - value));
        }
    }

    /**
     * @dev Set the calling contract's allowance toward `spender` to `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful. Meant to be used with tokens that require the approval
     * to be set to zero before setting it to a non-zero value, such as USDT.
     */
    function forceApprove(IERC20 token, address spender, uint256 value) internal {
        bytes memory approvalCall = abi.encodeWithSelector(token.approve.selector, spender, value);

        if (!_callOptionalReturnBool(token, approvalCall)) {
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, 0));
            _callOptionalReturn(token, approvalCall);
        }
    }

    /**
     * @dev Use a ERC-2612 signature to set the `owner` approval toward `spender` on `token`.
     * Revert on invalid signature.
     */
    function safePermit(
        IERC20Permit token,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        uint256 nonceBefore = token.nonces(owner);
        token.permit(owner, spender, value, deadline, v, r, s);
        uint256 nonceAfter = token.nonces(owner);
        require(nonceAfter == nonceBefore + 1, "SafeERC20: permit did not succeed");
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address-functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        require(returndata.length == 0 || abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     *
     * This is a variant of {_callOptionalReturn} that silents catches all reverts and returns a bool instead.
     */
    function _callOptionalReturnBool(IERC20 token, bytes memory data) private returns (bool) {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We cannot use {Address-functionCall} here since this should return false
        // and not revert is the subcall reverts.

        (bool success, bytes memory returndata) = address(token).call(data);
        return
            success && (returndata.length == 0 || abi.decode(returndata, (bool))) && Address.isContract(address(token));
    }
}

// lib/forge-std/src/StdCheats.sol

abstract contract StdCheatsSafe {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant UINT256_MAX =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;

    bool private gasMeteringOff;

    // Data structures to parse Transaction objects from the broadcast artifact
    // that conform to EIP1559. The Raw structs is what is parsed from the JSON
    // and then converted to the one that is used by the user for better UX.

    struct RawTx1559 {
        string[] arguments;
        address contractAddress;
        string contractName;
        // json value name = function
        string functionSig;
        bytes32 hash;
        // json value name = tx
        RawTx1559Detail txDetail;
        // json value name = type
        string opcode;
    }

    struct RawTx1559Detail {
        AccessList[] accessList;
        bytes data;
        address from;
        bytes gas;
        bytes nonce;
        address to;
        bytes txType;
        bytes value;
    }

    struct Tx1559 {
        string[] arguments;
        address contractAddress;
        string contractName;
        string functionSig;
        bytes32 hash;
        Tx1559Detail txDetail;
        string opcode;
    }

    struct Tx1559Detail {
        AccessList[] accessList;
        bytes data;
        address from;
        uint256 gas;
        uint256 nonce;
        address to;
        uint256 txType;
        uint256 value;
    }

    // Data structures to parse Transaction objects from the broadcast artifact
    // that DO NOT conform to EIP1559. The Raw structs is what is parsed from the JSON
    // and then converted to the one that is used by the user for better UX.

    struct TxLegacy {
        string[] arguments;
        address contractAddress;
        string contractName;
        string functionSig;
        string hash;
        string opcode;
        TxDetailLegacy transaction;
    }

    struct TxDetailLegacy {
        AccessList[] accessList;
        uint256 chainId;
        bytes data;
        address from;
        uint256 gas;
        uint256 gasPrice;
        bytes32 hash;
        uint256 nonce;
        bytes1 opcode;
        bytes32 r;
        bytes32 s;
        uint256 txType;
        address to;
        uint8 v;
        uint256 value;
    }

    struct AccessList {
        address accessAddress;
        bytes32[] storageKeys;
    }

    // Data structures to parse Receipt objects from the broadcast artifact.
    // The Raw structs is what is parsed from the JSON
    // and then converted to the one that is used by the user for better UX.

    struct RawReceipt {
        bytes32 blockHash;
        bytes blockNumber;
        address contractAddress;
        bytes cumulativeGasUsed;
        bytes effectiveGasPrice;
        address from;
        bytes gasUsed;
        RawReceiptLog[] logs;
        bytes logsBloom;
        bytes status;
        address to;
        bytes32 transactionHash;
        bytes transactionIndex;
    }

    struct Receipt {
        bytes32 blockHash;
        uint256 blockNumber;
        address contractAddress;
        uint256 cumulativeGasUsed;
        uint256 effectiveGasPrice;
        address from;
        uint256 gasUsed;
        ReceiptLog[] logs;
        bytes logsBloom;
        uint256 status;
        address to;
        bytes32 transactionHash;
        uint256 transactionIndex;
    }

    // Data structures to parse the entire broadcast artifact, assuming the
    // transactions conform to EIP1559.

    struct EIP1559ScriptArtifact {
        string[] libraries;
        string path;
        string[] pending;
        Receipt[] receipts;
        uint256 timestamp;
        Tx1559[] transactions;
        TxReturn[] txReturns;
    }

    struct RawEIP1559ScriptArtifact {
        string[] libraries;
        string path;
        string[] pending;
        RawReceipt[] receipts;
        TxReturn[] txReturns;
        uint256 timestamp;
        RawTx1559[] transactions;
    }

    struct RawReceiptLog {
        // json value = address
        address logAddress;
        bytes32 blockHash;
        bytes blockNumber;
        bytes data;
        bytes logIndex;
        bool removed;
        bytes32[] topics;
        bytes32 transactionHash;
        bytes transactionIndex;
        bytes transactionLogIndex;
    }

    struct ReceiptLog {
        // json value = address
        address logAddress;
        bytes32 blockHash;
        uint256 blockNumber;
        bytes data;
        uint256 logIndex;
        bytes32[] topics;
        uint256 transactionIndex;
        uint256 transactionLogIndex;
        bool removed;
    }

    struct TxReturn {
        string internalType;
        string value;
    }

    struct Account {
        address addr;
        uint256 key;
    }

    enum AddressType {
        Payable,
        NonPayable,
        ZeroAddress,
        Precompile,
        ForgeAddress
    }

    // Checks that `addr` is not blacklisted by token contracts that have a blacklist.
    function assumeNotBlacklisted(address token, address addr) internal view virtual {
        // Nothing to check if `token` is not a contract.
        uint256 tokenCodeSize;
        assembly {
            tokenCodeSize := extcodesize(token)
        }
        require(tokenCodeSize > 0, "StdCheats assumeNotBlacklisted(address,address): Token address is not a contract.");

        bool success;
        bytes memory returnData;

        // 4-byte selector for `isBlacklisted(address)`, used by USDC.
        (success, returnData) = token.staticcall(abi.encodeWithSelector(0xfe575a87, addr));
        vm.assume(!success || abi.decode(returnData, (bool)) == false);

        // 4-byte selector for `isBlackListed(address)`, used by USDT.
        (success, returnData) = token.staticcall(abi.encodeWithSelector(0xe47d6060, addr));
        vm.assume(!success || abi.decode(returnData, (bool)) == false);
    }

    // Checks that `addr` is not blacklisted by token contracts that have a blacklist.
    // This is identical to `assumeNotBlacklisted(address,address)` but with a different name, for
    // backwards compatibility, since this name was used in the original PR which already has
    // a release. This function can be removed in a future release once we want a breaking change.
    function assumeNoBlacklisted(address token, address addr) internal view virtual {
        assumeNotBlacklisted(token, addr);
    }

    function assumeAddressIsNot(address addr, AddressType addressType) internal virtual {
        if (addressType == AddressType.Payable) {
            assumeNotPayable(addr);
        } else if (addressType == AddressType.NonPayable) {
            assumePayable(addr);
        } else if (addressType == AddressType.ZeroAddress) {
            assumeNotZeroAddress(addr);
        } else if (addressType == AddressType.Precompile) {
            assumeNotPrecompile(addr);
        } else if (addressType == AddressType.ForgeAddress) {
            assumeNotForgeAddress(addr);
        }
    }

    function assumeAddressIsNot(address addr, AddressType addressType1, AddressType addressType2) internal virtual {
        assumeAddressIsNot(addr, addressType1);
        assumeAddressIsNot(addr, addressType2);
    }

    function assumeAddressIsNot(
        address addr,
        AddressType addressType1,
        AddressType addressType2,
        AddressType addressType3
    ) internal virtual {
        assumeAddressIsNot(addr, addressType1);
        assumeAddressIsNot(addr, addressType2);
        assumeAddressIsNot(addr, addressType3);
    }

    function assumeAddressIsNot(
        address addr,
        AddressType addressType1,
        AddressType addressType2,
        AddressType addressType3,
        AddressType addressType4
    ) internal virtual {
        assumeAddressIsNot(addr, addressType1);
        assumeAddressIsNot(addr, addressType2);
        assumeAddressIsNot(addr, addressType3);
        assumeAddressIsNot(addr, addressType4);
    }

    // This function checks whether an address, `addr`, is payable. It works by sending 1 wei to
    // `addr` and checking the `success` return value.
    // NOTE: This function may result in state changes depending on the fallback/receive logic
    // implemented by `addr`, which should be taken into account when this function is used.
    function _isPayable(address addr) private returns (bool) {
        require(
            addr.balance < UINT256_MAX,
            "StdCheats _isPayable(address): Balance equals max uint256, so it cannot receive any more funds"
        );
        uint256 origBalanceTest = address(this).balance;
        uint256 origBalanceAddr = address(addr).balance;

        vm.deal(address(this), 1);
        (bool success,) = payable(addr).call{value: 1}("");

        // reset balances
        vm.deal(address(this), origBalanceTest);
        vm.deal(addr, origBalanceAddr);

        return success;
    }

    // NOTE: This function may result in state changes depending on the fallback/receive logic
    // implemented by `addr`, which should be taken into account when this function is used. See the
    // `_isPayable` method for more information.
    function assumePayable(address addr) internal virtual {
        vm.assume(_isPayable(addr));
    }

    function assumeNotPayable(address addr) internal virtual {
        vm.assume(!_isPayable(addr));
    }

    function assumeNotZeroAddress(address addr) internal pure virtual {
        vm.assume(addr != address(0));
    }

    function assumeNotPrecompile(address addr) internal pure virtual {
        assumeNotPrecompile(addr, _pureChainId());
    }

    function assumeNotPrecompile(address addr, uint256 chainId) internal pure virtual {
        // Note: For some chains like Optimism these are technically predeploys (i.e. bytecode placed at a specific
        // address), but the same rationale for excluding them applies so we include those too.

        // These are reserved by Ethereum and may be on all EVM-compatible chains.
        vm.assume(addr < address(0x1) || addr > address(0xff));

        // forgefmt: disable-start
        if (chainId == 10 || chainId == 420) {
            // https://github.com/ethereum-optimism/optimism/blob/eaa371a0184b56b7ca6d9eb9cb0a2b78b2ccd864/op-bindings/predeploys/addresses.go#L6-L21
            vm.assume(
                addr < address(0x4200000000000000000000000000000000000000) ||
                    addr > address(0x4200000000000000000000000000000000000800)
            );
        } else if (chainId == 42161 || chainId == 421613) {
            // https://developer.arbitrum.io/useful-addresses#arbitrum-precompiles-l2-same-on-all-arb-chains
            vm.assume(
                addr < address(0x0000000000000000000000000000000000000064) ||
                    addr > address(0x0000000000000000000000000000000000000068)
            );
        } else if (chainId == 43114 || chainId == 43113) {
            // https://github.com/ava-labs/subnet-evm/blob/47c03fd007ecaa6de2c52ea081596e0a88401f58/precompile/params.go#L18-L59
            vm.assume(
                addr < address(0x0100000000000000000000000000000000000000) ||
                    addr > address(0x01000000000000000000000000000000000000ff)
            );
            vm.assume(
                addr < address(0x0200000000000000000000000000000000000000) ||
                    addr > address(0x02000000000000000000000000000000000000FF)
            );
            vm.assume(
                addr < address(0x0300000000000000000000000000000000000000) ||
                    addr > address(0x03000000000000000000000000000000000000Ff)
            );
        }
        // forgefmt: disable-end
    }

    function assumeNotForgeAddress(address addr) internal pure virtual {
        // vm, console, and Create2Deployer addresses
        vm.assume(
            addr != address(vm) && addr != 0x000000000000000000636F6e736F6c652e6c6f67
                && addr != 0x4e59b44847b379578588920cA78FbF26c0B4956C
        );
    }

    function assumeUnusedAddress(address addr) internal view virtual {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        vm.assume(size == 0);

        assumeNotPrecompile(addr);
        assumeNotZeroAddress(addr);
        assumeNotForgeAddress(addr);
    }

    function readEIP1559ScriptArtifact(string memory path)
        internal
        view
        virtual
        returns (EIP1559ScriptArtifact memory)
    {
        string memory data = vm.readFile(path);
        bytes memory parsedData = vm.parseJson(data);
        RawEIP1559ScriptArtifact memory rawArtifact = abi.decode(parsedData, (RawEIP1559ScriptArtifact));
        EIP1559ScriptArtifact memory artifact;
        artifact.libraries = rawArtifact.libraries;
        artifact.path = rawArtifact.path;
        artifact.timestamp = rawArtifact.timestamp;
        artifact.pending = rawArtifact.pending;
        artifact.txReturns = rawArtifact.txReturns;
        artifact.receipts = rawToConvertedReceipts(rawArtifact.receipts);
        artifact.transactions = rawToConvertedEIPTx1559s(rawArtifact.transactions);
        return artifact;
    }

    function rawToConvertedEIPTx1559s(RawTx1559[] memory rawTxs) internal pure virtual returns (Tx1559[] memory) {
        Tx1559[] memory txs = new Tx1559[](rawTxs.length);
        for (uint256 i; i < rawTxs.length; i++) {
            txs[i] = rawToConvertedEIPTx1559(rawTxs[i]);
        }
        return txs;
    }

    function rawToConvertedEIPTx1559(RawTx1559 memory rawTx) internal pure virtual returns (Tx1559 memory) {
        Tx1559 memory transaction;
        transaction.arguments = rawTx.arguments;
        transaction.contractName = rawTx.contractName;
        transaction.functionSig = rawTx.functionSig;
        transaction.hash = rawTx.hash;
        transaction.txDetail = rawToConvertedEIP1559Detail(rawTx.txDetail);
        transaction.opcode = rawTx.opcode;
        return transaction;
    }

    function rawToConvertedEIP1559Detail(RawTx1559Detail memory rawDetail)
        internal
        pure
        virtual
        returns (Tx1559Detail memory)
    {
        Tx1559Detail memory txDetail;
        txDetail.data = rawDetail.data;
        txDetail.from = rawDetail.from;
        txDetail.to = rawDetail.to;
        txDetail.nonce = _bytesToUint(rawDetail.nonce);
        txDetail.txType = _bytesToUint(rawDetail.txType);
        txDetail.value = _bytesToUint(rawDetail.value);
        txDetail.gas = _bytesToUint(rawDetail.gas);
        txDetail.accessList = rawDetail.accessList;
        return txDetail;
    }

    function readTx1559s(string memory path) internal view virtual returns (Tx1559[] memory) {
        string memory deployData = vm.readFile(path);
        bytes memory parsedDeployData = vm.parseJson(deployData, ".transactions");
        RawTx1559[] memory rawTxs = abi.decode(parsedDeployData, (RawTx1559[]));
        return rawToConvertedEIPTx1559s(rawTxs);
    }

    function readTx1559(string memory path, uint256 index) internal view virtual returns (Tx1559 memory) {
        string memory deployData = vm.readFile(path);
        string memory key = string(abi.encodePacked(".transactions[", vm.toString(index), "]"));
        bytes memory parsedDeployData = vm.parseJson(deployData, key);
        RawTx1559 memory rawTx = abi.decode(parsedDeployData, (RawTx1559));
        return rawToConvertedEIPTx1559(rawTx);
    }

    // Analogous to readTransactions, but for receipts.
    function readReceipts(string memory path) internal view virtual returns (Receipt[] memory) {
        string memory deployData = vm.readFile(path);
        bytes memory parsedDeployData = vm.parseJson(deployData, ".receipts");
        RawReceipt[] memory rawReceipts = abi.decode(parsedDeployData, (RawReceipt[]));
        return rawToConvertedReceipts(rawReceipts);
    }

    function readReceipt(string memory path, uint256 index) internal view virtual returns (Receipt memory) {
        string memory deployData = vm.readFile(path);
        string memory key = string(abi.encodePacked(".receipts[", vm.toString(index), "]"));
        bytes memory parsedDeployData = vm.parseJson(deployData, key);
        RawReceipt memory rawReceipt = abi.decode(parsedDeployData, (RawReceipt));
        return rawToConvertedReceipt(rawReceipt);
    }

    function rawToConvertedReceipts(RawReceipt[] memory rawReceipts) internal pure virtual returns (Receipt[] memory) {
        Receipt[] memory receipts = new Receipt[](rawReceipts.length);
        for (uint256 i; i < rawReceipts.length; i++) {
            receipts[i] = rawToConvertedReceipt(rawReceipts[i]);
        }
        return receipts;
    }

    function rawToConvertedReceipt(RawReceipt memory rawReceipt) internal pure virtual returns (Receipt memory) {
        Receipt memory receipt;
        receipt.blockHash = rawReceipt.blockHash;
        receipt.to = rawReceipt.to;
        receipt.from = rawReceipt.from;
        receipt.contractAddress = rawReceipt.contractAddress;
        receipt.effectiveGasPrice = _bytesToUint(rawReceipt.effectiveGasPrice);
        receipt.cumulativeGasUsed = _bytesToUint(rawReceipt.cumulativeGasUsed);
        receipt.gasUsed = _bytesToUint(rawReceipt.gasUsed);
        receipt.status = _bytesToUint(rawReceipt.status);
        receipt.transactionIndex = _bytesToUint(rawReceipt.transactionIndex);
        receipt.blockNumber = _bytesToUint(rawReceipt.blockNumber);
        receipt.logs = rawToConvertedReceiptLogs(rawReceipt.logs);
        receipt.logsBloom = rawReceipt.logsBloom;
        receipt.transactionHash = rawReceipt.transactionHash;
        return receipt;
    }

    function rawToConvertedReceiptLogs(RawReceiptLog[] memory rawLogs)
        internal
        pure
        virtual
        returns (ReceiptLog[] memory)
    {
        ReceiptLog[] memory logs = new ReceiptLog[](rawLogs.length);
        for (uint256 i; i < rawLogs.length; i++) {
            logs[i].logAddress = rawLogs[i].logAddress;
            logs[i].blockHash = rawLogs[i].blockHash;
            logs[i].blockNumber = _bytesToUint(rawLogs[i].blockNumber);
            logs[i].data = rawLogs[i].data;
            logs[i].logIndex = _bytesToUint(rawLogs[i].logIndex);
            logs[i].topics = rawLogs[i].topics;
            logs[i].transactionIndex = _bytesToUint(rawLogs[i].transactionIndex);
            logs[i].transactionLogIndex = _bytesToUint(rawLogs[i].transactionLogIndex);
            logs[i].removed = rawLogs[i].removed;
        }
        return logs;
    }

    // Deploy a contract by fetching the contract bytecode from
    // the artifacts directory
    // e.g. `deployCode(code, abi.encode(arg1,arg2,arg3))`
    function deployCode(string memory what, bytes memory args) internal virtual returns (address addr) {
        bytes memory bytecode = abi.encodePacked(vm.getCode(what), args);
        /// @solidity memory-safe-assembly
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        require(addr != address(0), "StdCheats deployCode(string,bytes): Deployment failed.");
    }

    function deployCode(string memory what) internal virtual returns (address addr) {
        bytes memory bytecode = vm.getCode(what);
        /// @solidity memory-safe-assembly
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        require(addr != address(0), "StdCheats deployCode(string): Deployment failed.");
    }

    /// @dev deploy contract with value on construction
    function deployCode(string memory what, bytes memory args, uint256 val) internal virtual returns (address addr) {
        bytes memory bytecode = abi.encodePacked(vm.getCode(what), args);
        /// @solidity memory-safe-assembly
        assembly {
            addr := create(val, add(bytecode, 0x20), mload(bytecode))
        }

        require(addr != address(0), "StdCheats deployCode(string,bytes,uint256): Deployment failed.");
    }

    function deployCode(string memory what, uint256 val) internal virtual returns (address addr) {
        bytes memory bytecode = vm.getCode(what);
        /// @solidity memory-safe-assembly
        assembly {
            addr := create(val, add(bytecode, 0x20), mload(bytecode))
        }

        require(addr != address(0), "StdCheats deployCode(string,uint256): Deployment failed.");
    }

    // creates a labeled address and the corresponding private key
    function makeAddrAndKey(string memory name) internal virtual returns (address addr, uint256 privateKey) {
        privateKey = uint256(keccak256(abi.encodePacked(name)));
        addr = vm.addr(privateKey);
        vm.label(addr, name);
    }

    // creates a labeled address
    function makeAddr(string memory name) internal virtual returns (address addr) {
        (addr,) = makeAddrAndKey(name);
    }

    // Destroys an account immediately, sending the balance to beneficiary.
    // Destroying means: balance will be zero, code will be empty, and nonce will be 0
    // This is similar to selfdestruct but not identical: selfdestruct destroys code and nonce
    // only after tx ends, this will run immediately.
    function destroyAccount(address who, address beneficiary) internal virtual {
        uint256 currBalance = who.balance;
        vm.etch(who, abi.encode());
        vm.deal(who, 0);
        vm.resetNonce(who);

        uint256 beneficiaryBalance = beneficiary.balance;
        vm.deal(beneficiary, currBalance + beneficiaryBalance);
    }

    // creates a struct containing both a labeled address and the corresponding private key
    function makeAccount(string memory name) internal virtual returns (Account memory account) {
        (account.addr, account.key) = makeAddrAndKey(name);
    }

    function deriveRememberKey(string memory mnemonic, uint32 index)
        internal
        virtual
        returns (address who, uint256 privateKey)
    {
        privateKey = vm.deriveKey(mnemonic, index);
        who = vm.rememberKey(privateKey);
    }

    function _bytesToUint(bytes memory b) private pure returns (uint256) {
        require(b.length <= 32, "StdCheats _bytesToUint(bytes): Bytes length exceeds 32.");
        return abi.decode(abi.encodePacked(new bytes(32 - b.length), b), (uint256));
    }

    function isFork() internal view virtual returns (bool status) {
        try vm.activeFork() {
            status = true;
        } catch (bytes memory) {}
    }

    modifier skipWhenForking() {
        if (!isFork()) {
            _;
        }
    }

    modifier skipWhenNotForking() {
        if (isFork()) {
            _;
        }
    }

    modifier noGasMetering() {
        vm.pauseGasMetering();
        // To prevent turning gas monitoring back on with nested functions that use this modifier,
        // we check if gasMetering started in the off position. If it did, we don't want to turn
        // it back on until we exit the top level function that used the modifier
        //
        // i.e. funcA() noGasMetering { funcB() }, where funcB has noGasMetering as well.
        // funcA will have `gasStartedOff` as false, funcB will have it as true,
        // so we only turn metering back on at the end of the funcA
        bool gasStartedOff = gasMeteringOff;
        gasMeteringOff = true;

        _;

        // if gas metering was on when this modifier was called, turn it back on at the end
        if (!gasStartedOff) {
            gasMeteringOff = false;
            vm.resumeGasMetering();
        }
    }

    // We use this complex approach of `_viewChainId` and `_pureChainId` to ensure there are no
    // compiler warnings when accessing chain ID in any solidity version supported by forge-std. We
    // can't simply access the chain ID in a normal view or pure function because the solc View Pure
    // Checker changed `chainid` from pure to view in 0.8.0.
    function _viewChainId() private view returns (uint256 chainId) {
        // Assembly required since `block.chainid` was introduced in 0.8.0.
        assembly {
            chainId := chainid()
        }

        address(this); // Silence warnings in older Solc versions.
    }

    function _pureChainId() private pure returns (uint256 chainId) {
        function() internal view returns (uint256) fnIn = _viewChainId;
        function() internal pure returns (uint256) pureChainId;
        assembly {
            pureChainId := fnIn
        }
        chainId = pureChainId();
    }
}

// Wrappers around cheatcodes to avoid footguns
abstract contract StdCheats is StdCheatsSafe {
    using stdStorage for StdStorage;

    StdStorage private stdstore;
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant CONSOLE2_ADDRESS = 0x000000000000000000636F6e736F6c652e6c6f67;

    // Skip forward or rewind time by the specified number of seconds
    function skip(uint256 time) internal virtual {
        vm.warp(vm.getBlockTimestamp() + time);
    }

    function rewind(uint256 time) internal virtual {
        vm.warp(vm.getBlockTimestamp() - time);
    }

    // Setup a prank from an address that has some ether
    function hoax(address msgSender) internal virtual {
        vm.deal(msgSender, 1 << 128);
        vm.prank(msgSender);
    }

    function hoax(address msgSender, uint256 give) internal virtual {
        vm.deal(msgSender, give);
        vm.prank(msgSender);
    }

    function hoax(address msgSender, address origin) internal virtual {
        vm.deal(msgSender, 1 << 128);
        vm.prank(msgSender, origin);
    }

    function hoax(address msgSender, address origin, uint256 give) internal virtual {
        vm.deal(msgSender, give);
        vm.prank(msgSender, origin);
    }

    // Start perpetual prank from an address that has some ether
    function startHoax(address msgSender) internal virtual {
        vm.deal(msgSender, 1 << 128);
        vm.startPrank(msgSender);
    }

    function startHoax(address msgSender, uint256 give) internal virtual {
        vm.deal(msgSender, give);
        vm.startPrank(msgSender);
    }

    // Start perpetual prank from an address that has some ether
    // tx.origin is set to the origin parameter
    function startHoax(address msgSender, address origin) internal virtual {
        vm.deal(msgSender, 1 << 128);
        vm.startPrank(msgSender, origin);
    }

    function startHoax(address msgSender, address origin, uint256 give) internal virtual {
        vm.deal(msgSender, give);
        vm.startPrank(msgSender, origin);
    }

    function changePrank(address msgSender) internal virtual {
        console2_log_StdCheats("changePrank is deprecated. Please use vm.startPrank instead.");
        vm.stopPrank();
        vm.startPrank(msgSender);
    }

    function changePrank(address msgSender, address txOrigin) internal virtual {
        vm.stopPrank();
        vm.startPrank(msgSender, txOrigin);
    }

    // The same as Vm's `deal`
    // Use the alternative signature for ERC20 tokens
    function deal(address to, uint256 give) internal virtual {
        vm.deal(to, give);
    }

    // Set the balance of an account for any ERC20 token
    // Use the alternative signature to update `totalSupply`
    function deal(address token, address to, uint256 give) internal virtual {
        deal(token, to, give, false);
    }

    // Set the balance of an account for any ERC1155 token
    // Use the alternative signature to update `totalSupply`
    function dealERC1155(address token, address to, uint256 id, uint256 give) internal virtual {
        dealERC1155(token, to, id, give, false);
    }

    function deal(address token, address to, uint256 give, bool adjust) internal virtual {
        // get current balance
        (, bytes memory balData) = token.staticcall(abi.encodeWithSelector(0x70a08231, to));
        uint256 prevBal = abi.decode(balData, (uint256));

        // update balance
        stdstore.target(token).sig(0x70a08231).with_key(to).checked_write(give);

        // update total supply
        if (adjust) {
            (, bytes memory totSupData) = token.staticcall(abi.encodeWithSelector(0x18160ddd));
            uint256 totSup = abi.decode(totSupData, (uint256));
            if (give < prevBal) {
                totSup -= (prevBal - give);
            } else {
                totSup += (give - prevBal);
            }
            stdstore.target(token).sig(0x18160ddd).checked_write(totSup);
        }
    }

    function dealERC1155(address token, address to, uint256 id, uint256 give, bool adjust) internal virtual {
        // get current balance
        (, bytes memory balData) = token.staticcall(abi.encodeWithSelector(0x00fdd58e, to, id));
        uint256 prevBal = abi.decode(balData, (uint256));

        // update balance
        stdstore.target(token).sig(0x00fdd58e).with_key(to).with_key(id).checked_write(give);

        // update total supply
        if (adjust) {
            (, bytes memory totSupData) = token.staticcall(abi.encodeWithSelector(0xbd85b039, id));
            require(
                totSupData.length != 0,
                "StdCheats deal(address,address,uint,uint,bool): target contract is not ERC1155Supply."
            );
            uint256 totSup = abi.decode(totSupData, (uint256));
            if (give < prevBal) {
                totSup -= (prevBal - give);
            } else {
                totSup += (give - prevBal);
            }
            stdstore.target(token).sig(0xbd85b039).with_key(id).checked_write(totSup);
        }
    }

    function dealERC721(address token, address to, uint256 id) internal virtual {
        // check if token id is already minted and the actual owner.
        (bool successMinted, bytes memory ownerData) = token.staticcall(abi.encodeWithSelector(0x6352211e, id));
        require(successMinted, "StdCheats deal(address,address,uint,bool): id not minted.");

        // get owner current balance
        (, bytes memory fromBalData) =
            token.staticcall(abi.encodeWithSelector(0x70a08231, abi.decode(ownerData, (address))));
        uint256 fromPrevBal = abi.decode(fromBalData, (uint256));

        // get new user current balance
        (, bytes memory toBalData) = token.staticcall(abi.encodeWithSelector(0x70a08231, to));
        uint256 toPrevBal = abi.decode(toBalData, (uint256));

        // update balances
        stdstore.target(token).sig(0x70a08231).with_key(abi.decode(ownerData, (address))).checked_write(--fromPrevBal);
        stdstore.target(token).sig(0x70a08231).with_key(to).checked_write(++toPrevBal);

        // update owner
        stdstore.target(token).sig(0x6352211e).with_key(id).checked_write(to);
    }

    function deployCodeTo(string memory what, address where) internal virtual {
        deployCodeTo(what, "", 0, where);
    }

    function deployCodeTo(string memory what, bytes memory args, address where) internal virtual {
        deployCodeTo(what, args, 0, where);
    }

    function deployCodeTo(string memory what, bytes memory args, uint256 value, address where) internal virtual {
        bytes memory creationCode = vm.getCode(what);
        vm.etch(where, abi.encodePacked(creationCode, args));
        (bool success, bytes memory runtimeBytecode) = where.call{value: value}("");
        require(success, "StdCheats deployCodeTo(string,bytes,uint256,address): Failed to create runtime bytecode.");
        vm.etch(where, runtimeBytecode);
    }

    // Used to prevent the compilation of console, which shortens the compilation time when console is not used elsewhere.
    function console2_log_StdCheats(string memory p0) private view {
        (bool status,) = address(CONSOLE2_ADDRESS).staticcall(abi.encodeWithSignature("log(string)", p0));
        status;
    }
}

// lib/pendle-sy/contracts/core/misc/TokenWithSupplyCapUpg.sol

abstract contract TokenWithSupplyCapUpg is BoringOwnableUpgradeableV2, IPTokenWithSupplyCap {
    uint256 private _supplyCap;

    uint256[100] private __gap; // reserved for future use

    event SupplyCapUpdated(uint256 newSupplyCap);

    error SupplyCapExceeded(uint256 totalSupply, uint256 supplyCap);

    function __tokenWithSupplyCap_init(uint256 initialSupplyCap) internal onlyInitializing {
        _updateSupplyCap(initialSupplyCap);
    }

    function updateSupplyCap(uint256 newSupplyCap) external onlyOwner {
        _updateSupplyCap(newSupplyCap);
    }

    function getAbsoluteSupplyCap() external view returns (uint256) {
        return _supplyCap;
    }

    function _updateSupplyCap(uint256 newSupplyCap) internal {
        _supplyCap = newSupplyCap;
        emit SupplyCapUpdated(newSupplyCap);
    }

    function _checkSupplyCap(uint256 _supply) internal view {
        uint256 _cap = _supplyCap;
        if (_supply > _cap) {
            revert SupplyCapExceeded(_supply, _cap);
        }
    }
}

// node_modules/@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol

// OpenZeppelin Contracts (last updated v4.9.0) (proxy/ERC1967/ERC1967Upgrade.sol)

/**
 * @dev This abstract contract provides getters and event emitting update functions for
 * https://eips.ethereum.org/EIPS/eip-1967[EIP1967] slots.
 *
 * _Available since v4.1._
 */
abstract contract ERC1967Upgrade is IERC1967 {
    // This is the keccak-256 hash of "eip1967.proxy.rollback" subtracted by 1
    bytes32 private constant _ROLLBACK_SLOT = 0x4910fdfa16fed3260ed0e7147f7cc6da11a60208b5b9406d12a635614ffd9143;

    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev Returns the current implementation address.
     */
    function _getImplementation() internal view returns (address) {
        return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
    }

    /**
     * @dev Stores a new address in the EIP1967 implementation slot.
     */
    function _setImplementation(address newImplementation) private {
        require(Address.isContract(newImplementation), "ERC1967: new implementation is not a contract");
        StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
    }

    /**
     * @dev Perform implementation upgrade
     *
     * Emits an {Upgraded} event.
     */
    function _upgradeTo(address newImplementation) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    /**
     * @dev Perform implementation upgrade with additional setup call.
     *
     * Emits an {Upgraded} event.
     */
    function _upgradeToAndCall(address newImplementation, bytes memory data, bool forceCall) internal {
        _upgradeTo(newImplementation);
        if (data.length > 0 || forceCall) {
            Address.functionDelegateCall(newImplementation, data);
        }
    }

    /**
     * @dev Perform implementation upgrade with security checks for UUPS proxies, and additional setup call.
     *
     * Emits an {Upgraded} event.
     */
    function _upgradeToAndCallUUPS(address newImplementation, bytes memory data, bool forceCall) internal {
        // Upgrades from old implementations will perform a rollback test. This test requires the new
        // implementation to upgrade back to the old, non-ERC1822 compliant, implementation. Removing
        // this special case will break upgrade paths from old UUPS implementation to new ones.
        if (StorageSlot.getBooleanSlot(_ROLLBACK_SLOT).value) {
            _setImplementation(newImplementation);
        } else {
            try IERC1822Proxiable(newImplementation).proxiableUUID() returns (bytes32 slot) {
                require(slot == _IMPLEMENTATION_SLOT, "ERC1967Upgrade: unsupported proxiableUUID");
            } catch {
                revert("ERC1967Upgrade: new implementation is not UUPS");
            }
            _upgradeToAndCall(newImplementation, data, forceCall);
        }
    }

    /**
     * @dev Storage slot with the admin of the contract.
     * This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 internal constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @dev Returns the current admin.
     */
    function _getAdmin() internal view returns (address) {
        return StorageSlot.getAddressSlot(_ADMIN_SLOT).value;
    }

    /**
     * @dev Stores a new address in the EIP1967 admin slot.
     */
    function _setAdmin(address newAdmin) private {
        require(newAdmin != address(0), "ERC1967: new admin is the zero address");
        StorageSlot.getAddressSlot(_ADMIN_SLOT).value = newAdmin;
    }

    /**
     * @dev Changes the admin of the proxy.
     *
     * Emits an {AdminChanged} event.
     */
    function _changeAdmin(address newAdmin) internal {
        emit AdminChanged(_getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    /**
     * @dev The storage slot of the UpgradeableBeacon contract which defines the implementation for this proxy.
     * This is bytes32(uint256(keccak256('eip1967.proxy.beacon')) - 1)) and is validated in the constructor.
     */
    bytes32 internal constant _BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /**
     * @dev Returns the current beacon.
     */
    function _getBeacon() internal view returns (address) {
        return StorageSlot.getAddressSlot(_BEACON_SLOT).value;
    }

    /**
     * @dev Stores a new beacon in the EIP1967 beacon slot.
     */
    function _setBeacon(address newBeacon) private {
        require(Address.isContract(newBeacon), "ERC1967: new beacon is not a contract");
        require(
            Address.isContract(IBeacon(newBeacon).implementation()), "ERC1967: beacon implementation is not a contract"
        );
        StorageSlot.getAddressSlot(_BEACON_SLOT).value = newBeacon;
    }

    /**
     * @dev Perform beacon upgrade with additional setup call. Note: This upgrades the address of the beacon, it does
     * not upgrade the implementation contained in the beacon (see {UpgradeableBeacon-_setImplementation} for that).
     *
     * Emits a {BeaconUpgraded} event.
     */
    function _upgradeBeaconToAndCall(address newBeacon, bytes memory data, bool forceCall) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);
        if (data.length > 0 || forceCall) {
            Address.functionDelegateCall(IBeacon(newBeacon).implementation(), data);
        }
    }
}

// node_modules/@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol

// OpenZeppelin Contracts (last updated v4.7.0) (proxy/ERC1967/ERC1967Proxy.sol)

/**
 * @dev This contract implements an upgradeable proxy. It is upgradeable because calls are delegated to an
 * implementation address that can be changed. This address is stored in storage in the location specified by
 * https://eips.ethereum.org/EIPS/eip-1967[EIP1967], so that it doesn't conflict with the storage layout of the
 * implementation behind the proxy.
 */
contract ERC1967Proxy is Proxy, ERC1967Upgrade {
    /**
     * @dev Initializes the upgradeable proxy with an initial implementation specified by `_logic`.
     *
     * If `_data` is nonempty, it's used as data in a delegate call to `_logic`. This will typically be an encoded
     * function call, and allows initializing the storage of the proxy like a Solidity constructor.
     */
    constructor(address _logic, bytes memory _data) payable {
        _upgradeToAndCall(_logic, _data, false);
    }

    /**
     * @dev Returns the current implementation address.
     */
    function _implementation() internal view virtual override returns (address impl) {
        return ERC1967Upgrade._getImplementation();
    }
}

// node_modules/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol

// OpenZeppelin Contracts (last updated v4.9.0) (proxy/transparent/TransparentUpgradeableProxy.sol)

/**
 * @dev Interface for {TransparentUpgradeableProxy}. In order to implement transparency, {TransparentUpgradeableProxy}
 * does not implement this interface directly, and some of its functions are implemented by an internal dispatch
 * mechanism. The compiler is unaware that these functions are implemented by {TransparentUpgradeableProxy} and will not
 * include them in the ABI so this interface must be used to interact with it.
 */
interface ITransparentUpgradeableProxy is IERC1967 {
    function admin() external view returns (address);

    function implementation() external view returns (address);

    function changeAdmin(address) external;

    function upgradeTo(address) external;

    function upgradeToAndCall(address, bytes memory) external payable;
}

/**
 * @dev This contract implements a proxy that is upgradeable by an admin.
 *
 * To avoid https://medium.com/nomic-labs-blog/malicious-backdoors-in-ethereum-proxies-62629adf3357[proxy selector
 * clashing], which can potentially be used in an attack, this contract uses the
 * https://blog.openzeppelin.com/the-transparent-proxy-pattern/[transparent proxy pattern]. This pattern implies two
 * things that go hand in hand:
 *
 * 1. If any account other than the admin calls the proxy, the call will be forwarded to the implementation, even if
 * that call matches one of the admin functions exposed by the proxy itself.
 * 2. If the admin calls the proxy, it can access the admin functions, but its calls will never be forwarded to the
 * implementation. If the admin tries to call a function on the implementation it will fail with an error that says
 * "admin cannot fallback to proxy target".
 *
 * These properties mean that the admin account can only be used for admin actions like upgrading the proxy or changing
 * the admin, so it's best if it's a dedicated account that is not used for anything else. This will avoid headaches due
 * to sudden errors when trying to call a function from the proxy implementation.
 *
 * Our recommendation is for the dedicated account to be an instance of the {ProxyAdmin} contract. If set up this way,
 * you should think of the `ProxyAdmin` instance as the real administrative interface of your proxy.
 *
 * NOTE: The real interface of this proxy is that defined in `ITransparentUpgradeableProxy`. This contract does not
 * inherit from that interface, and instead the admin functions are implicitly implemented using a custom dispatch
 * mechanism in `_fallback`. Consequently, the compiler will not produce an ABI for this contract. This is necessary to
 * fully implement transparency without decoding reverts caused by selector clashes between the proxy and the
 * implementation.
 *
 * WARNING: It is not recommended to extend this contract to add additional external functions. If you do so, the compiler
 * will not check that there are no selector conflicts, due to the note above. A selector clash between any new function
 * and the functions declared in {ITransparentUpgradeableProxy} will be resolved in favor of the new one. This could
 * render the admin operations inaccessible, which could prevent upgradeability. Transparency may also be compromised.
 */
contract TransparentUpgradeableProxy is ERC1967Proxy {
    /**
     * @dev Initializes an upgradeable proxy managed by `_admin`, backed by the implementation at `_logic`, and
     * optionally initialized with `_data` as explained in {ERC1967Proxy-constructor}.
     */
    constructor(address _logic, address admin_, bytes memory _data) payable ERC1967Proxy(_logic, _data) {
        _changeAdmin(admin_);
    }

    /**
     * @dev Modifier used internally that will delegate the call to the implementation unless the sender is the admin.
     *
     * CAUTION: This modifier is deprecated, as it could cause issues if the modified function has arguments, and the
     * implementation provides a function with the same selector.
     */
    modifier ifAdmin() {
        if (msg.sender == _getAdmin()) {
            _;
        } else {
            _fallback();
        }
    }

    /**
     * @dev If caller is the admin process the call internally, otherwise transparently fallback to the proxy behavior
     */
    function _fallback() internal virtual override {
        if (msg.sender == _getAdmin()) {
            bytes memory ret;
            bytes4 selector = msg.sig;
            if (selector == ITransparentUpgradeableProxy.upgradeTo.selector) {
                ret = _dispatchUpgradeTo();
            } else if (selector == ITransparentUpgradeableProxy.upgradeToAndCall.selector) {
                ret = _dispatchUpgradeToAndCall();
            } else if (selector == ITransparentUpgradeableProxy.changeAdmin.selector) {
                ret = _dispatchChangeAdmin();
            } else if (selector == ITransparentUpgradeableProxy.admin.selector) {
                ret = _dispatchAdmin();
            } else if (selector == ITransparentUpgradeableProxy.implementation.selector) {
                ret = _dispatchImplementation();
            } else {
                revert("TransparentUpgradeableProxy: admin cannot fallback to proxy target");
            }
            assembly {
                return(add(ret, 0x20), mload(ret))
            }
        } else {
            super._fallback();
        }
    }

    /**
     * @dev Returns the current admin.
     *
     * TIP: To get this value clients can read directly from the storage slot shown below (specified by EIP1967) using the
     * https://eth.wiki/json-rpc/API#eth_getstorageat[`eth_getStorageAt`] RPC call.
     * `0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103`
     */
    function _dispatchAdmin() private returns (bytes memory) {
        _requireZeroValue();

        address admin = _getAdmin();
        return abi.encode(admin);
    }

    /**
     * @dev Returns the current implementation.
     *
     * TIP: To get this value clients can read directly from the storage slot shown below (specified by EIP1967) using the
     * https://eth.wiki/json-rpc/API#eth_getstorageat[`eth_getStorageAt`] RPC call.
     * `0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc`
     */
    function _dispatchImplementation() private returns (bytes memory) {
        _requireZeroValue();

        address implementation = _implementation();
        return abi.encode(implementation);
    }

    /**
     * @dev Changes the admin of the proxy.
     *
     * Emits an {AdminChanged} event.
     */
    function _dispatchChangeAdmin() private returns (bytes memory) {
        _requireZeroValue();

        address newAdmin = abi.decode(msg.data[4:], (address));
        _changeAdmin(newAdmin);

        return "";
    }

    /**
     * @dev Upgrade the implementation of the proxy.
     */
    function _dispatchUpgradeTo() private returns (bytes memory) {
        _requireZeroValue();

        address newImplementation = abi.decode(msg.data[4:], (address));
        _upgradeToAndCall(newImplementation, bytes(""), false);

        return "";
    }

    /**
     * @dev Upgrade the implementation of the proxy, and then call a function from the new implementation as specified
     * by `data`, which should be an encoded function call. This is useful to initialize new storage variables in the
     * proxied contract.
     */
    function _dispatchUpgradeToAndCall() private returns (bytes memory) {
        (address newImplementation, bytes memory data) = abi.decode(msg.data[4:], (address, bytes));
        _upgradeToAndCall(newImplementation, data, true);

        return "";
    }

    /**
     * @dev Returns the current admin.
     *
     * CAUTION: This function is deprecated. Use {ERC1967Upgrade-_getAdmin} instead.
     */
    function _admin() internal view virtual returns (address) {
        return _getAdmin();
    }

    /**
     * @dev To keep this contract fully transparent, all `ifAdmin` functions must be payable. This helper is here to
     * emulate some proxy functions being non-payable while still allowing value to pass through.
     */
    function _requireZeroValue() private {
        require(msg.value == 0);
    }
}

// lib/forge-std/src/Test.sol

// 💬 ABOUT
// Forge Std's default Test.

// 🧩 MODULES

// 📦 BOILERPLATE

// ⭐️ TEST
abstract contract Test is TestBase, StdAssertions, StdChains, StdCheats, StdInvariant, StdUtils {
    // Note: IS_TEST() must return true.
    bool public IS_TEST = true;
}

// test/helpers/TokenHelpers.sol

abstract contract TokenHelpers is StdCheats {
    address internal constant NATIVE = address(0);

    function getSymbol(address token) internal view virtual returns (string memory) {
        if (token == NATIVE) {
            return "NATIVE";
        } else {
            return IERC20Metadata(token).symbol();
        }
    }

    function getDecimals(address token) internal view virtual returns (uint8) {
        if (token == NATIVE) {
            return 18;
        } else {
            return IERC20Metadata(token).decimals();
        }
    }

    function printTokenSymbols(address[] memory tokens) internal view virtual {
        for (uint256 i = 0; i < tokens.length; i++) {
            console.log(tokens[i], getSymbol(tokens[i]));
        }
    }

    function getBalance(address wallet, address token) internal view virtual returns (uint256) {
        if (token == NATIVE) {
            return wallet.balance;
        } else {
            return IERC20(token).balanceOf(wallet);
        }
    }

    function getBalances(address wallet, address[] memory tokens)
        internal
        view
        virtual
        returns (uint256[] memory balances)
    {
        balances = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = getBalance(wallet, tokens[i]);
        }
    }

    function fundToken(address wallet, address token, uint256 amount) internal virtual {
        if (token == NATIVE) {
            deal(wallet, amount);
        } else {
            deal(token, wallet, amount, false);
        }
    }

    /// @notice Approves the stipulated contract to spend the given allowance in the given token
    /// @dev PLS PAY ATTENTION to tokens that requires the approval to be set to 0 before changing it
    function safeApprove(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.approve.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Safe Approve");
    }
}

// test/helpers/DeployHelpers.sol

abstract contract DeployHelpers {
    function deployTransparentProxy(address _logic, address admin_, bytes memory _data) internal returns (address) {
        return address(new TransparentUpgradeableProxy(_logic, admin_, _data));
    }
}

// test/common/TestFoundation.sol

abstract contract TestFoundation is ArrayHelpers, DeployHelpers, TokenHelpers, Test {
    using StdStyle for string;

    address deployer;
    address[] wallets;

    IStandardizedYield sy;
    address startToken;

    function setUp() public virtual {
        deployer = makeAddr("deployer");

        wallets.push(makeAddr("alice"));
        wallets.push(makeAddr("bob"));
        wallets.push(makeAddr("charlie"));
        wallets.push(makeAddr("david"));
        wallets.push(makeAddr("eve"));

        setUpFork();
        deploySY();
        initializeSY();
    }

    function setUpFork() internal virtual;

    function deploySY() internal virtual;

    function initializeSY() internal virtual {}

    function test_exchangeRateSanity() public view {
        uint256 exchangeRate = sy.exchangeRate();

        uint256 decimalsSY = IERC20Metadata(address(sy)).decimals();
        (,, uint8 decimalsAsset) = sy.assetInfo();

        uint256 amtAsset = ((10 ** decimalsSY) * sy.exchangeRate()) / (10 ** 18);
        uint256 amtAsset18 = amtAsset;
        if (decimalsAsset < 18) {
            amtAsset18 = amtAsset * (10 ** (18 - decimalsAsset));
        } else if (decimalsAsset > 18) {
            amtAsset18 = amtAsset / (10 ** (decimalsAsset - 18));
        }

        checkRequired(string.concat("Exchange rate: ", vm.toString(exchangeRate)));
        console.log("                 1 SY = %18e asset", amtAsset18);

        assertGt(exchangeRate, 0, "Exchange rate should be greater than 0");
    }

    function refAmountFor(address token) internal view virtual returns (uint256) {
        if (token == NATIVE) {
            return 1 ether;
        } else {
            return 10 ** IERC20Metadata(token).decimals();
        }
    }

    function upgradeExistingProxy(address proxy, address newImplementation, bytes memory data) internal virtual {
        vm.startPrank(0xA28c08f165116587D4F3E708743B4dEe155c5E64);
        ITransparentUpgradeableProxy(proxy).upgradeToAndCall(newImplementation, data);
        vm.stopPrank();
    }

    function deposit(address wallet, address tokenIn, uint256 amountTokenIn)
        internal
        virtual
        returns (uint256 amountSharesOut)
    {
        if (tokenIn == NATIVE) {
            vm.prank(wallet);
            amountSharesOut = sy.deposit{value: amountTokenIn}(wallet, tokenIn, amountTokenIn, 0);
        } else {
            vm.startPrank(wallet);
            safeApprove(tokenIn, address(sy), 0);
            safeApprove(tokenIn, address(sy), amountTokenIn);
            amountSharesOut = sy.deposit(wallet, tokenIn, amountTokenIn, 0);
            vm.stopPrank();
        }
    }

    function redeem(address wallet, address tokenOut, uint256 amountSharesIn)
        internal
        virtual
        returns (uint256 amountTokenOut)
    {
        vm.prank(wallet);
        amountTokenOut = sy.redeem(wallet, amountSharesIn, tokenOut, 0, false);
    }

    function checkRequired(string memory message) internal pure {
        console.log(string.concat(string("[CHECK REQUIRED]").red().bold(), " ", message));
    }
}

// test/common/tests/Metadata.t.sol

abstract contract MetadataTest is TestFoundation {
    function test_metadata_assetInfo() public view {
        (IStandardizedYield.AssetType assetType, address assetAddress, uint8 assetDecimals) = sy.assetInfo();

        if (assetType == IStandardizedYield.AssetType.TOKEN) {
            console.log("Asset type: TOKEN");
        } else if (assetType == IStandardizedYield.AssetType.LIQUIDITY) {
            console.log("Asset type: LIQUIDITY");
        } else {
            assert(false);
        }
        console.log("Asset address:", assetAddress);

        if (assetAddress == address(0)) {
            console.log("Asset symbol: ETH");
        } else if (assetAddress == address(1)) {
            console.log("Asset symbol: Wrapped");
        } else {
            console.log("Asset symbol:", getSymbol(assetAddress));
        }
        console.log("Asset decimals:", assetDecimals);

        address yieldToken = sy.yieldToken();
        console.log("Yield token:", yieldToken);
        console.log("Yield token symbol:", getSymbol(yieldToken));
        console.log("Yield token decimals:", getDecimals(yieldToken));
    }

    function test_metadata_getTokensIn() public view {
        address[] memory tokens = sy.getTokensIn();
        console.log("Tokens in:", tokens.length);
        printTokenSymbols(tokens);
    }

    function test_metadata_getTokensOut() public view {
        address[] memory tokens = sy.getTokensOut();
        console.log("Tokens out:", tokens.length);
        printTokenSymbols(tokens);
    }

    function test_metadata_getRewardTokens() public view {
        address[] memory tokens = sy.getRewardTokens();
        console.log("Reward tokens:", tokens.length);
        printTokenSymbols(tokens);
    }

    function test_metadata_isValidTokenIn() public view {
        address[] memory tokens = sy.getTokensIn();
        for (uint256 i = 0; i < tokens.length; ++i) {
            assertTrue(sy.isValidTokenIn(tokens[i]));
        }
        assertFalse(sy.isValidTokenIn(vm.addr(123456)));
    }

    function test_metadata_isValidTokenOut() public view {
        address[] memory tokens = sy.getTokensOut();
        for (uint256 i = 0; i < tokens.length; ++i) {
            assertTrue(sy.isValidTokenOut(tokens[i]));
        }
        assertFalse(sy.isValidTokenOut(vm.addr(123456)));
    }
}

// test/common/tests/Rewards.t.sol

abstract contract RewardsTest is TestFoundation {
    function test_rewards_claim() public {
        vm.skip(!hasReward());

        console.log("[-----test_rewards_claim-----]");

        address alice = wallets[0];

        uint256 refAmount = refAmountFor(startToken);
        fundToken(alice, startToken, refAmount);
        deposit(alice, startToken, refAmount);

        bool[] memory hasRewards = addFakeRewards();
        assertEq(hasRewards.length, sy.getRewardTokens().length, "hasRewards.length mismatch");

        address[] memory rewardTokens = sy.getRewardTokens();
        uint256[] memory rewardBalancesBefore = getBalances(alice, rewardTokens);

        uint256[] memory rewardAmounts = sy.claimRewards(alice);
        uint256[] memory rewardBalancesAfter = getBalances(alice, rewardTokens);

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (!hasRewards[i]) continue;

            uint256 expected = rewardAmounts[i];
            uint256 actual = rewardBalancesAfter[i] - rewardBalancesBefore[i];
            checkRequired(string.concat("Claimed ", vm.toString(actual), " ", getSymbol(rewardTokens[i])));
            assertGt(actual, 0, "Claimed amount should be greater than 0");
            assertEq(
                actual, expected, string.concat("claimRewards ", getSymbol(rewardTokens[i]), " actual != expected")
            );
        }
        console.log("");
    }

    function addFakeRewards() internal virtual returns (bool[] memory) {}

    function hasReward() internal pure virtual returns (bool) {
        return false;
    }
}

// test/common/tests/DepositRedeem.t.sol

abstract contract DepositRedeemTest is TestFoundation {
    using PMath_1 for uint256;

    // function test_depositRedeem_exchangeRate() public {
    //     uint256 snapshot = vm.snapshotState();

    //     address[] memory tokensIn = getTokensInForDepositRedeemTest();
    //     for (uint256 k = 0; k < tokensIn.length; ++k) {
    //         vm.revertToState(snapshot);

    //         address tokenIn = tokensIn[k];

    //         uint256 n = wallets.length;
    //         uint256 refAmount = refAmountFor(tokenIn);
    //         for (uint256 i = 0; i < n; ++i) {
    //             uint256 expectedSyBalance = getExpectedSyOut(tokenIn, refAmount);

    //             fundToken(wallets[i], tokenIn, refAmount);
    //             deposit(wallets[i], tokenIn, refAmount);
    //             assertApproxEqRel(sy.balanceOf(wallets[i]), expectedSyBalance, 1e8);
    //         }
    //     }
    // }

    // function getTokensInForDepositRedeemTest() internal view virtual returns (address[] memory);

    // function getExpectedSyOut(address tokenIn, uint256 amountIn) internal view virtual returns (uint256);
}

// test/common/tests/Preview.t.sol

abstract contract PreviewTest is TestFoundation {
    struct PreviewDepositThenRedeemTestParam {
        address tokenIn;
        uint256 netTokenIn;
        address tokenOut;
        bool shouldCheck;
    }

    uint256 constant N_SPLIT = 2;

    function test_preview_depositThenRedeem() public {
        vm.skip(skipPreviewTest(), "Skipped preview test. Be sure its not a new one.");

        PreviewDepositThenRedeemTestParam[] memory testParams = _genPreviewDepositThenRedeemTestParams();
        console.log("[-----test_preview_depositThenRedeem-----]");

        address alice = wallets[0];
        uint256 maxRoundTripDeltaAbs = 0;
        uint256 maxRoundTripDeltaRel = 0;
        uint256 totalRoundTripDeltaRel = 0;

        uint256 cntRoundTripTest = 0;

        for (uint256 i = 0; i < testParams.length; ++i) {
            address tokenIn = testParams[i].tokenIn;
            address tokenOut = testParams[i].tokenOut;
            uint256 amountIn = testParams[i].netTokenIn;

            if (testParams[i].shouldCheck) {
                checkRequired(string.concat("Test ", vm.toString(i + 1)));
                console.log("Testing ", getSymbol(tokenIn), "=>", getSymbol(tokenOut));
                console.log("Amount in :", amountIn);
            }

            fundToken(alice, tokenIn, amountIn);

            (uint256 amountOut, bool doRoundTrip, uint256 amountRoundTrip, uint256 roundTripDeltaAbs) =
                _executePreviewTest(alice, tokenIn, amountIn, tokenOut);

            if (doRoundTrip) {
                cntRoundTripTest++;
            }

            uint256 roundTripDeltaRel = PMath_0.divDown(roundTripDeltaAbs, amountIn);
            maxRoundTripDeltaAbs = PMath_0.max(maxRoundTripDeltaAbs, roundTripDeltaAbs);
            maxRoundTripDeltaRel = PMath_0.max(maxRoundTripDeltaRel, roundTripDeltaRel);
            totalRoundTripDeltaRel += roundTripDeltaRel;

            if (testParams[i].shouldCheck) {
                console.log("Amount out:", amountOut);
                if (doRoundTrip) {
                    console.log("Amount round trip:", amountRoundTrip);
                    console.log("Round trip delta abs:", roundTripDeltaAbs);
                    console.log("Round trip delta rel: %18e", roundTripDeltaRel);
                } else {
                    console.log("No round trip possible for this pair");
                }
                console.log("");
            }
        }

        checkRequired("Summary");
        console.log("Total tests                    :", testParams.length);
        console.log("Total round trip tests         :", cntRoundTripTest);
        // console.log("Max round trip delta abs:", maxRoundTripDeltaAbs);
        console.log("Max round trip delta rel       : %18e", maxRoundTripDeltaRel);
        console.log("Average round trip delta rel   : %18e", totalRoundTripDeltaRel / cntRoundTripTest);

        console.log("");
    }

    PreviewDepositThenRedeemTestParam[] params;

    // override this if you want a different set of test parameters
    function _genPreviewDepositThenRedeemTestParams()
        internal
        virtual
        returns (PreviewDepositThenRedeemTestParam[] memory)
    {
        uint256 DENOM = 17;
        uint256 NUMER = 3;
        uint256 NUM_TESTS_PER_PAIR = 5;

        address[] memory allTokensIn = getTokensInForPreviewTest();
        address[] memory allTokensOut = getTokensOutForPreviewTest();
        delete params;

        uint256 divBy = 1;
        for (uint256 i = 0; i < allTokensIn.length; ++i) {
            for (uint256 j = 0; j < allTokensOut.length; ++j) {
                uint256 refAmount = refAmountFor(allTokensIn[i]);
                for (uint256 numTest = 0; numTest < NUM_TESTS_PER_PAIR; ++numTest) {
                    uint256 amountIn = refAmount / divBy;
                    divBy = (divBy * NUMER) % DENOM;

                    params.push() = PreviewDepositThenRedeemTestParam({
                        tokenIn: allTokensIn[i],
                        netTokenIn: amountIn,
                        tokenOut: allTokensOut[j],
                        shouldCheck: numTest == 0
                    });
                }
            }
        }

        return params;
    }

    function _executePreviewTest(address wallet, address tokenIn, uint256 netTokenIn, address tokenOut)
        private
        returns (uint256 totalAmountOut, bool doRoundTrip, uint256 amountRoundTrip, uint256 roundTripDeltaAbs)
    {
        totalAmountOut = _executePreviewTestOnce(wallet, tokenIn, netTokenIn, tokenOut);

        doRoundTrip = sy.isValidTokenIn(tokenOut) && sy.isValidTokenOut(tokenIn);
        if (doRoundTrip) {
            amountRoundTrip = _executePreviewTestOnce(wallet, tokenOut, totalAmountOut, tokenIn);
            roundTripDeltaAbs = stdMath.delta(amountRoundTrip, netTokenIn);

            if (!hasFee()) {
                assertApprox(
                    amountRoundTrip,
                    netTokenIn,
                    getDecimals(tokenIn),
                    "amountRoundTrip should be close to netTokenIn | 50"
                );
            }
        }
    }

    function _executePreviewTestOnce(address wallet, address tokenIn, uint256 netTokenIn, address tokenOut)
        internal
        returns (uint256)
    {
        uint256 depositIn = netTokenIn / N_SPLIT;
        for (uint256 i = 0; i < N_SPLIT; ++i) {
            uint256 balanceBefore = sy.balanceOf(wallet);

            uint256 amountIn = (i != N_SPLIT - 1) ? depositIn : depositIn + (netTokenIn % N_SPLIT); // Adjust to use up all amounts
            uint256 preview = sy.previewDeposit(tokenIn, amountIn);
            uint256 actual = deposit(wallet, tokenIn, amountIn);
            uint256 earning = sy.balanceOf(wallet) - balanceBefore;
            uint8 decimals = sy.decimals();

            assertApprox(earning, actual, decimals, "previewDeposit: actual != earning | 59");
            assertApprox(preview, actual, decimals, "previewDeposit: preview != actual | 60");
        }

        uint256 redeemIn = sy.balanceOf(wallet) / N_SPLIT;
        uint256 totalAmountOut = 0;
        for (uint256 i = 0; i < N_SPLIT; ++i) {
            uint256 balanceBefore = getBalance(wallet, tokenOut);

            uint256 amountOut = (i != N_SPLIT - 1) ? redeemIn : sy.balanceOf(wallet); // Adjust to use up all amounts
            uint256 preview = sy.previewRedeem(tokenOut, amountOut);
            uint256 actual = redeem(wallet, tokenOut, amountOut);
            uint256 earning = getBalance(wallet, tokenOut) - balanceBefore;
            uint8 decimals = getDecimals(tokenOut);

            assertApprox(earning, actual, decimals, "previewRedeem: actual != earning | 72");
            assertApprox(preview, actual, decimals, "previewRedeem: preview != actual | 73");

            totalAmountOut += actual;
        }
        return totalAmountOut;
    }

    function getTokensInForPreviewTest() internal view virtual returns (address[] memory) {
        return sy.getTokensIn();
    }

    function getTokensOutForPreviewTest() internal view virtual returns (address[] memory) {
        return sy.getTokensOut();
    }

    function getPreviewTestAllowedEps() internal pure virtual returns (uint256) {
        return 0;
    }

    function assertApprox(uint256 actual, uint256 expected, uint8 decimal, string memory message) internal pure {
        uint256 allowedEps = getPreviewTestAllowedEps();
        if (allowedEps == 0) {
            assertEqDecimal(actual, expected, decimal, message);
        } else {
            uint256 allowDiffAbs = PMath_0.max(1, PMath_0.mulDown(expected, allowedEps));
            assertApproxEqAbsDecimal(actual, expected, allowDiffAbs, decimal, message);
        }
    }

    function hasFee() internal pure virtual returns (bool) {
        return false;
    }

    function skipPreviewTest() internal pure virtual returns (bool) {
        return false;
    }
}

// test/common/tests/SupplyCap.t.sol

abstract contract SupplyCapTest is TestFoundation {
    using SafeERC20 for IERC20;

    enum SupplyCapType {
        None,
        Underlying,
        BuiltIn
    }

    function test_supply_cap() public {
        if (getSupplyCapType() == SupplyCapType.None) {
            vm.skip(true);
        }

        uint256 supplyCap = TokenWithSupplyCapUpg(address(sy)).getAbsoluteSupplyCap();
        uint256 supply = TokenWithSupplyCapUpg(address(sy)).getAbsoluteTotalSupply();

        checkRequired(string.concat("Init cap: [", vm.toString(supply), " / ", vm.toString(supplyCap), "]"));

        if (getSupplyCapType() != SupplyCapType.BuiltIn) {
            return;
        }

        console.log("[-----test_supply_cap-----]");

        // Set supply cap to 1
        vm.prank(TokenWithSupplyCapUpg(address(sy)).owner());
        TokenWithSupplyCapUpg(address(sy)).updateSupplyCap(1);

        // try minting
        address alice = wallets[0];
        uint256 refAmount = refAmountFor(startToken);
        fundToken(alice, startToken, refAmount);

        vm.startPrank(alice);

        if (startToken == address(0)) {
            vm.expectPartialRevert(TokenWithSupplyCapUpg.SupplyCapExceeded.selector);
            sy.deposit{value: refAmount}(alice, startToken, refAmount, 0);
        } else {
            safeApprove(startToken, address(sy), 0);
            safeApprove(startToken, address(sy), refAmount);

            vm.expectPartialRevert(TokenWithSupplyCapUpg.SupplyCapExceeded.selector);
            sy.deposit(alice, startToken, refAmount, 0);
        }
        vm.stopPrank();
    }

    function getSupplyCapType() internal pure virtual returns (SupplyCapType) {
        // return false;
        return SupplyCapType.None;
    }
}

// test/common/SYTest.t.sol

abstract contract SYTest is DepositRedeemTest, MetadataTest, PreviewTest, RewardsTest, SupplyCapTest {}
