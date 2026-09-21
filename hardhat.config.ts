// Force ts-node to use CommonJS mode
// This must be set before any imports
process.env.TS_NODE_COMPILER_OPTIONS = JSON.stringify({
    module: 'commonjs',
    esModuleInterop: true,
})

// Get the environment configuration from .env file
//
// To make use of automatic environment setup:
// - Duplicate .env.example file and name it .env
// - Fill in the environment variables
import 'dotenv/config'

import 'hardhat-deploy'
import '@nomicfoundation/hardhat-ethers'
import '@nomiclabs/hardhat-waffle'
import 'hardhat-deploy-ethers'
import 'hardhat-contract-sizer'
import '@nomiclabs/hardhat-ethers'
import '@layerzerolabs/toolbox-hardhat'

import { HardhatUserConfig, HttpNetworkAccountsUserConfig } from 'hardhat/types'

import { EndpointId } from '@layerzerolabs/lz-definitions'

import './tasks/index'

// Set your preferred authentication method
//
// If you prefer using a mnemonic, set a MNEMONIC environment variable
// to a valid mnemonic
const MNEMONIC = process.env.MNEMONIC

// If you prefer to be authenticated using a private key, set a PRIVATE_KEY environment variable
const PRIVATE_KEY = process.env.PRIVATE_KEY

const accounts: HttpNetworkAccountsUserConfig | undefined = MNEMONIC
    ? { mnemonic: MNEMONIC }
    : PRIVATE_KEY
      ? [PRIVATE_KEY]
      : undefined

if (accounts == null) {
    console.warn(
        'Could not find MNEMONIC or PRIVATE_KEY environment variables. It will not be possible to execute transactions in your example.'
    )
}

const config: HardhatUserConfig = {
    paths: {
        cache: 'cache/hardhat',
        tests: 'test/hardhat',
    },
    solidity: {
        compilers: [
            {
                version: '0.8.22',
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
        ],
    },
    networks: {
        localhost: {
            url: process.env.LOCAL_RPC_URL || 'http://127.0.0.1:8546',
            accounts,
        },
        'bnbmainnet': {
            eid: EndpointId.BSC_V2_MAINNET,
            url: process.env.BNB_RPC_URL || 'https://bsc-dataseed.binance.org/',
            accounts,
        },
        'ethereummainnet': {
            eid: EndpointId.ETHEREUM_V2_MAINNET,
            url: process.env.ETHEREUM_RPC_URL || 'https://ethereum-rpc.publicnode.com',
            accounts,
        },
        avalanche: {
            eid: EndpointId.AVALANCHE_V2_MAINNET,
            url: process.env.AVALANCHE_RPC_URL || 'https://api.avax.network/ext/bc/C/rpc',
            accounts,
        },
        'plumephoenix': {
            eid: EndpointId.PLUMEPHOENIX_V2_MAINNET,
            url: process.env.PLUME_RPC_URL || 'https://rpc.plume.org',
            accounts,
        },
        'plasma-mainnet': {
            eid: EndpointId.PLASMA_V2_MAINNET,
            url: process.env.PLASMA_RPC_URL || 'https://rpc.plasma.to',
            accounts,
        },
        'worldchain': {
            eid: EndpointId.WORLDCHAIN_V2_MAINNET,
            url: process.env.WORLDCHAIN_RPC_URL || 'https://rpc.worldchain.org',
            accounts,
        },
        base: {
            eid: EndpointId.BASE_V2_MAINNET,
            url: process.env.BASE_RPC_URL || 'https://mainnet.base.org',
            accounts,
        },
        hardhat: {
            // Need this for testing because TestHelperOz5.sol is exceeding the compiled contract size limit
            allowUnlimitedContractSize: true,
        },
    },
    namedAccounts: {
        deployer: {
            default: 0, // wallet address of index[0], of the mnemonic in .env
        },
    },
}

export default config
