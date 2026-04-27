// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

contract BaseInherited {
    function pushSerializedTx(string memory _name, address _to, uint256 _value, bytes memory _data) public virtual {}
}
