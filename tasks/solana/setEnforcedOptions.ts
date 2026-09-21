import { existsSync, readFileSync } from 'node:fs'
import path from 'node:path'

import { Keypair, PublicKey } from '@solana/web3.js'
import { task } from 'hardhat/config'

import { types as devtoolsTypes } from '@layerzerolabs/devtools-evm-hardhat'
import {
    OmniSignerSolanaSquads,
    createSolanaConnectionFactory,
    getSolanaKeypair,
} from '@layerzerolabs/devtools-solana'
import { EndpointId } from '@layerzerolabs/lz-definitions'
import { Options } from '@layerzerolabs/lz-v2-utilities'
import { OFT } from '@layerzerolabs/ua-devtools-solana'

import { getSolanaDeployment } from './index'

// Workaround for LayerZero wire ping-pong bug on Solana OFT enforced options.
// configureEnforcedOptions in @layerzerolabs/ua-devtools pushes only the diff'd
// msgType per (eid). ua-devtools-solana's setEnforcedOptions then fills the
// other msgType with Options.newOptions() (empty), and Solana's set_peer_config
// overwrites both fields — wiping the other msgType on chain. Running wire
// again sees the wiped msgType differ and ping-pongs forever.
//
// This task bypasses wire and sends a single Squads vault transaction that
// sets BOTH msgType 1 and msgType 2 for every EVM peer at once, matching the
// values defined here (kept in sync with EVM_ENFORCED_OPTIONS in
// script/solana-layerzero.config.ts).

const SOLANA_CHAIN_ID = 101

const CHAIN_TO_EID: Record<number, EndpointId> = {
    98866: EndpointId.PLUMEPHOENIX_V2_MAINNET,
    1: EndpointId.ETHEREUM_V2_MAINNET,
    42161: EndpointId.ARBITRUM_V2_MAINNET,
    9745: EndpointId.PLASMA_V2_MAINNET,
    56: EndpointId.BSC_V2_MAINNET,
    480: EndpointId.WORLDCHAIN_V2_MAINNET,
    8453: EndpointId.BASE_V2_MAINNET,
    43114: EndpointId.AVALANCHE_V2_MAINNET,
}

const MSG_TYPE_SEND = 1
const MSG_TYPE_SEND_AND_CALL = 2

const MSG_TYPE_1_GAS = 100_000
const MSG_TYPE_2_LZ_RECEIVE_GAS = 350_000
const MSG_TYPE_2_COMPOSE_GAS = 350_000

interface Args {
    multisigKey: string
}

task(
    'lz:oft:solana:setenforcedoptions',
    'Set enforced options for all EVM peers in one Squads tx (bypass wire ping-pong bug)'
)
    .addParam('multisigKey', 'Squads vault multisig key (base58)', undefined, devtoolsTypes.string)
    .setAction(async (args: Args) => {
        const vaultSymbol = process.env.VAULT_SYMBOL
        if (!vaultSymbol) {
            throw new Error('VAULT_SYMBOL env var is required (e.g. VAULT_SYMBOL=nTBILL)')
        }

        const vaultPath = path.resolve(`script/deployment-config/vaults/${vaultSymbol}.json`)
        if (!existsSync(vaultPath)) {
            throw new Error(`vault config missing: ${vaultPath}`)
        }
        const vaultConfig = JSON.parse(readFileSync(vaultPath, 'utf-8'))
        const peers: number[] = vaultConfig.peers ?? []
        if (!peers.includes(SOLANA_CHAIN_ID)) {
            throw new Error(`vault ${vaultSymbol} has no Solana peer`)
        }

        const evmChainIds = peers.filter((c) => c !== SOLANA_CHAIN_ID)
        if (evmChainIds.length === 0) {
            throw new Error(`vault ${vaultSymbol} has no EVM peers to configure`)
        }

        const solanaEid = EndpointId.SOLANA_V2_MAINNET
        const solanaDeployment = getSolanaDeployment(solanaEid)

        const connectionFactory = createSolanaConnectionFactory()
        const connection = await connectionFactory(solanaEid)
        const keypair: Keypair = await getSolanaKeypair()

        const oftSdk = new OFT(
            connection,
            { eid: solanaEid, address: solanaDeployment.oftStore },
            keypair.publicKey,
            new PublicKey(solanaDeployment.programId)
        )

        const msg1Options = Options.newOptions().addExecutorLzReceiveOption(MSG_TYPE_1_GAS, 0).toHex()
        const msg2Options = Options.newOptions()
            .addExecutorLzReceiveOption(MSG_TYPE_2_LZ_RECEIVE_GAS, 0)
            .addExecutorComposeOption(0, MSG_TYPE_2_COMPOSE_GAS, 0)
            .toHex()

        const enforcedOptions = evmChainIds.flatMap((chainId) => {
            const eid = CHAIN_TO_EID[chainId]
            if (!eid) throw new Error(`unknown chainId in peers: ${chainId}`)
            return [
                { eid, option: { msgType: MSG_TYPE_SEND, options: msg1Options } },
                { eid, option: { msgType: MSG_TYPE_SEND_AND_CALL, options: msg2Options } },
            ]
        })

        console.log('Building enforced options tx for', vaultSymbol)
        console.log(JSON.stringify(enforcedOptions, null, 2))

        const omniTx = await oftSdk.setEnforcedOptions(enforcedOptions)

        const multisigKey = new PublicKey(args.multisigKey)
        const signer = new OmniSignerSolanaSquads(solanaEid, connection, multisigKey, keypair)

        console.log(`Proposing to Squads vault ${args.multisigKey}...`)
        const { transactionHash } = await signer.signAndSend(omniTx)
        console.log(`Squads vaultTransactionCreate tx: ${transactionHash}`)
        console.log(`Approve & execute the proposal in the Squads UI.`)
    })
