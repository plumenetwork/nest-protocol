import { existsSync, readFileSync } from 'node:fs'
import path from 'node:path'

import { createNoopSigner, publicKey as umiPublicKey } from '@metaplex-foundation/umi'
import { toWeb3JsInstruction } from '@metaplex-foundation/umi-web3js-adapters'
import { Keypair, PublicKey, Transaction } from '@solana/web3.js'
import { task } from 'hardhat/config'

import { types as devtoolsTypes } from '@layerzerolabs/devtools-evm-hardhat'
import {
    OmniSignerSolanaSquads,
    createSolanaConnectionFactory,
    getSolanaKeypair,
} from '@layerzerolabs/devtools-solana'
import { EndpointId } from '@layerzerolabs/lz-definitions'
import { oft } from '@layerzerolabs/oft-v2-solana-sdk'
import { OFT } from '@layerzerolabs/ua-devtools-solana'

import { getSolanaDeployment } from './index'

// Severs the Solana OFT's own peers to BNB(56) / World(480) / Plasma(9745) — the
// reverse leg of script/setup/DisablePeers.s.sol (which only zeroes the EVM side). Leaves
// the Plume<->Ethereum<->Solana triangle live.
//
// On Solana a peer is removed by setting its PeerConfig PeerAddress to 32 zero
// bytes (the same semantics as EVM setPeer(eid, 0)). We build one surgical
// set_peer_config(PeerAddress=0) instruction per still-set lane and propose them
// as a single Squads vault transaction.
//
// Idempotent: reads getPeer(eid) first and skips any lane already unset, so
// re-running never queues a no-op Squads tx.

const SOLANA_CHAIN_ID = 101

/** Chains whose bridging is being torn down. Mirrors script/setup/DisablePeers.s.sol. */
const DISABLED_CHAIN_IDS = [56, 480, 9745]

const CHAIN_TO_EID: Record<number, EndpointId> = {
    56: EndpointId.BSC_V2_MAINNET,
    480: EndpointId.WORLDCHAIN_V2_MAINNET,
    9745: EndpointId.PLASMA_V2_MAINNET,
}

const CHAIN_NAME: Record<number, string> = {
    56: 'BNB',
    480: 'World',
    9745: 'Plasma',
}

interface Args {
    multisigKey: string
}

task('lz:oft:solana:unsetpeers', 'Zero the Solana OFT peers to BNB/World/Plasma in one Squads tx')
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

        // Idempotency: only zero lanes that are currently set. getPeer returns
        // undefined for an unset/zero peer (and we treat a missing PeerConfig PDA
        // the same way).
        const toUnset: { chainId: number; eid: EndpointId }[] = []
        for (const chainId of DISABLED_CHAIN_IDS) {
            const eid = CHAIN_TO_EID[chainId]
            let current: string | undefined
            try {
                current = await oftSdk.getPeer(eid)
            } catch {
                current = undefined // no PeerConfig PDA → already unset
            }
            if (current) {
                console.log(`  ${CHAIN_NAME[chainId]} (eid ${eid}): peer ${current} → unset`)
                toUnset.push({ chainId, eid })
            } else {
                console.log(`  ${CHAIN_NAME[chainId]} (eid ${eid}): already unset, skipping`)
            }
        }

        if (toUnset.length === 0) {
            console.log(`Nothing to unset for ${vaultSymbol} — all BNB/World/Plasma peers already zero.`)
            return
        }

        // Build one surgical set_peer_config(PeerAddress=0) instruction per lane.
        // admin is the OFT store's on-chain owner (the Squads vault PDA) as a noop
        // signer — Squads supplies the real signature on execution.
        const owner = await oftSdk.getOwner()
        const admin = createNoopSigner(umiPublicKey(owner))
        const oftStorePk = umiPublicKey(solanaDeployment.oftStore)
        const programIdPk = umiPublicKey(solanaDeployment.programId)

        const web3Tx = new Transaction()
        for (const { eid } of toUnset) {
            const ix = oft.setPeerConfig(
                { admin, oftStore: oftStorePk },
                { __kind: 'PeerAddress', peer: new Uint8Array(32), remote: eid },
                programIdPk
            )
            web3Tx.add(toWeb3JsInstruction(ix.instruction))
        }

        // createTransaction (feePayer + blockhash + serialize) is protected on the
        // base SDK; reuse it so the OmniTransaction matches what the Squads signer
        // expects — same path setEnforcedOptions takes.
        const omniTx = await (oftSdk as unknown as {
            createTransaction(tx: Transaction): Promise<{ point: unknown; data: string }>
        }).createTransaction(web3Tx)

        const multisigKey = new PublicKey(args.multisigKey)
        const signer = new OmniSignerSolanaSquads(solanaEid, connection, multisigKey, keypair)

        console.log(
            `\nProposing unset of ${toUnset.length} peer(s) [${toUnset
                .map((t) => CHAIN_NAME[t.chainId])
                .join(', ')}] to Squads vault ${args.multisigKey}...`
        )
        const { transactionHash } = await signer.signAndSend(omniTx)
        console.log(`Squads vaultTransactionCreate tx: ${transactionHash}`)
        console.log(`Approve & execute the proposal in the Squads UI.`)
    })
