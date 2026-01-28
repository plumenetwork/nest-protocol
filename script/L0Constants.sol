// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

struct Asset {
    address assetAddress; // maps to "address" in JSON (1st alphabetically: a < s)
    string symbol; // maps to "symbol" in JSON (2nd alphabetically: s > a)
}

struct NestVaultConfig {
    address accountant; // 1st alphabetically
    address boringVault; // 2nd alphabetically
    address manager; // 3rd alphabetically
    address rolesAuthority; // 4th alphabetically
    string symbol; // 5th alphabetically
    address teller; // 6th alphabetically
}

struct NestShareConfig {
    string name;
    string symbol;
}

struct L0Config {
    string RPC; // 1st alphabetically (R)
    Asset[] assets; // 2nd alphabetically (a) - array of supported assets per chain
    uint256 chainid; // 3rd alphabetically (c)
    address delegate; // 4th alphabetically (d)
    uint256 eid; // 5th alphabetically (e)
    address endpoint; // 6th alphabetically (e)
    NestShareConfig[] nestShareConfigs; // 7th alphabetically (nestS) - array of supported nest shares per chain
    NestVaultConfig[] nestVaultConfigs; // 8rd alphabetically (nestV) - array of supported vaults per chain
    address receiveLib302; // 9th alphabetically (r)
    address sendLib302; // 10th alphabetically (se)
}

library L0ConfigConstant {
    /// @dev Library cannot have non-constant state variables
    uint32 internal constant CONFIG_TYPE_EXECUTOR = 1;
    uint32 internal constant CONFIG_TYPE_ULN = 2;
    uint32 internal constant CONFIG_TYPE_UNKNOWN = 11111;

    uint8 internal constant NIL_DVN_COUNT = type(uint8).max;
    uint64 internal constant NIL_CONFIRMATIONS = type(uint64).max;
}

contract L0Constants {
    address[] public expectedNestVaultOfts;
    address[] public expectedNestShareOfts;
    address[] public connectedOfts;

    // deterministic addresses
    address public nALPHAVaultOFT_USDC = 0x0342EE795e7864319fB8D48651b47feBf1163C34;
    address public nBASISVaultOFT_USDC = 0x5F35D1cef957467F4c7b35B36371355170A0DbB1;
    address public nOPALVaultOFT_USDC = 0xD258029cF5a177e3306E09Fbea63424543a505c0;
    address public nTBILLVaultOFT_USDC = 0x250c2D14Ed6376fB392FbA1edd2cfd11d2Bf7F12;
    address public nWISDOMVaultOFT_USDC = 0x6330a14FC1520CFdF0834CCf23B15FD47a89a651;

    constructor() {
        expectedNestVaultOfts.push(nALPHAVaultOFT_USDC);
        expectedNestVaultOfts.push(nBASISVaultOFT_USDC);
        expectedNestVaultOfts.push(nOPALVaultOFT_USDC);
        expectedNestVaultOfts.push(nTBILLVaultOFT_USDC);
        expectedNestVaultOfts.push(nWISDOMVaultOFT_USDC);
    }
}
