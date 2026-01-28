// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {DeployBoringVaultSYSingle} from "script/DeployBoringVaultSYSingle.sol";

// forge script ./script/DeployBoringVaultSY_nBASIS.s.sol --rpc-url https://ethereum-rpc.publicnode.com --broadcast --verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY
contract DeployBoringVaultSY_nBASIS is DeployBoringVaultSYSingle {
    constructor() {
        boringVaultSymbol = "nBASIS";
        asset = USDC;
        attempt = "1";
    }
}
