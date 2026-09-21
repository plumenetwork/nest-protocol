// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

abstract contract Constants {
    uint8 constant OWNER_ROLE = 0;
    uint8 constant STRATEGIST_ROLE = 1;
    uint8 constant MANAGER_ROLE = 2;
    uint8 constant TELLER_ROLE = 3;
    uint8 constant UPDATE_EXCHANGE_RATE_ROLE = 4;
    uint8 constant SOLVER_ROLE = 5;
    uint8 constant PAUSER_ROLE = 6;
    uint8 constant PREDICATE_PROXY_ROLE = 7;
    uint8 constant DEPOSITOR_ROLE = 8;
    uint8 constant COMPLIANCE_HOOK_ROLE = 9;
    uint8 constant QUEUE_ROLE = 10;
    uint8 constant CAN_SOLVE_ROLE = 11;
    uint8 constant COMPOSER_ROLE = 12;
    uint8 constant RELAYER_ROLE = 13;
    uint8 constant KEEPER_ROLE = 14;
    uint8 constant SEIZER_ROLE = 15;
    uint8 constant COMPLIANCE_PROXY_ROLE = 16;
}
