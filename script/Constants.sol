// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

abstract contract Constants {
    // Nest Constants
    address payable public constant NALPHA = payable(0x593cCcA4c4bf58b7526a4C164cEEf4003C6388db);
    address public constant NALPHA_TELLER = 0xc9F6a492Fb1D623690Dc065BBcEd6DfB4a324A35;
    address public constant NALPHA_ACCOUNTANT = 0xe0CF451d6E373FF04e8eE3c50340F18AFa6421E1;
    address public constant NALPHA_MANAGER = 0xf71DE9Ba3Bc45Eab9014A89A11563e0f398C0c81;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address public constant NTBILL = 0xE72Fe64840F4EF80E3Ec73a1c749491b5c938CB9;
    address public constant NTBILL_TELLER = 0x1492062B3aE7996c71f87a2b390b6B82afea0c59;
    address public constant NTBILL_ACCOUNTANT = 0x0b738cd187872b265A689e8e4130C336e76892eC;
    address public constant NTBILL_MANAGAER = 0xf713a353F38d2E90245B94c1B004c10AB3a34857;

    address public constant NBASIS = 0x11113Ff3a60C2450F4b22515cB760417259eE94B;
    address public constant NBASIS_TELLER = 0xAD60d43a33cA26e40eAcc5BBc60f1C7136FFB89b;
    address public constant NBASIS_ACCOUNTANT = 0xa67d20A49e6Fe68Cf97E556DB6b2f5DE1dF4dC2f;
    address public constant NBASIS_MANAGER = 0x17767f384cead5182cAaf9056635bAc14aFC24a1;

    address public constant NCREDIT = 0xA5f78B2A0Ab85429d2DfbF8B60abc70F4CeC066c;
    address public constant NCREDIT_TELLER = 0x27200293AAC3D04d2B305244f78d013B3c759F9D;
    address public constant NCREDIT_ACCOUNTANT = 0x486e0362B0641c0fca21CAc2E317F6E21a8b19f3;
    address public constant NCREDIT_MANAGER = 0xca88561210221b9611a5Ed15389611Bac87Afc63;

    address public constant NYIELD = 0x892DFf5257B39f7afB7803dd7C81E8ECDB6af3E8;
    address public constant NYIELD_TELLER = 0x92A735f600175FE9bA350a915572a86F68EBBE66;
    address public constant NYIELD_ACCOUNTANT = 0x5da1A1d004Fe6b63b37228F08dB6CaEb418A6467;
    address public constant NYIELD_MANAGER = 0x912d14E0584B8E3273E5605c301033b77e34D940;

    // Predicate constants
    address public constant SERVICE_MANAGER = 0xf6f4A30EeF7cf51Ed4Ee1415fB3bFDAf3694B0d2;
    string public constant POLICY_ID = "x-nest-prod-003";

    uint8 constant OWNER_ROLE = 0;
    uint8 constant STRATEGIST_ROLE = 1;
    uint8 constant MANAGER_ROLE = 2;
    uint8 constant TELLER_ROLE = 3;
    uint8 constant UPDATE_EXCHANGE_RATE_ROLE = 4;
    uint8 constant SOLVER_ROLE = 5;
    uint8 constant PAUSER_ROLE = 6;
    uint8 constant PREDICATE_PROXY_ROLE = 7;
    uint8 constant QUEUE_ROLE = 10;
    uint8 constant CAN_SOLVE_ROLE = 11;
    uint8 constant COMPOSER_ROLE = 12;
    uint8 constant RELAYER_ROLE = 13;
    uint8 constant KEEPER_ROLE = 14;
}
