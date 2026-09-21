import { fetchMetadataFromSeeds, updateV1 } from '@metaplex-foundation/mpl-token-metadata'
import { publicKey, some, transactionBuilder } from '@metaplex-foundation/umi'
import bs58 from 'bs58'
import { task } from 'hardhat/config'

import { types as devtoolsTypes } from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'

import {
    TransactionType,
    addComputeUnitInstructions,
    deriveConnection,
    getExplorerTxLink,
    getSolanaDeployment,
} from './index'

interface Args {
    eid: EndpointId
    uri: string
    name?: string
    symbol?: string
}

// Update the SPL token's Metaplex metadata (uri / name / symbol).
// The metadata update authority is the deployer keypair (set by createV1 at create time;
// createOFT only reassigns mint+freeze authority to the SPL multisig, not the metadata
// update authority). Requires the token to have been created with --token-metadata-is-mutable true.
task('lz:oft:solana:update-metadata', 'Update SPL token Metaplex metadata (uri/name/symbol)')
    .addParam('eid', 'Solana mainnet (30168) or testnet (40168)', undefined, devtoolsTypes.eid)
    .addParam('uri', 'New metadata URI', undefined, devtoolsTypes.string)
    .addParam('name', 'New token name (optional, keeps current)', undefined, devtoolsTypes.string, true)
    .addParam('symbol', 'New token symbol (optional, keeps current)', undefined, devtoolsTypes.string, true)
    .setAction(async ({ eid, uri, name, symbol }: Args) => {
        const { connection, umi, umiWalletSigner } = await deriveConnection(eid)

        const { mint } = getSolanaDeployment(eid)
        const mintPk = publicKey(mint)

        const current = await fetchMetadataFromSeeds(umi, { mint: mintPk })
        console.log(`Current metadata: name="${current.name}" symbol="${current.symbol}" uri="${current.uri}"`)

        let txBuilder = transactionBuilder().add(
            updateV1(umi, {
                mint: mintPk,
                authority: umiWalletSigner,
                data: some({
                    name: name ?? current.name,
                    symbol: symbol ?? current.symbol,
                    uri,
                    sellerFeeBasisPoints: current.sellerFeeBasisPoints,
                    creators: current.creators,
                }),
            })
        )
        txBuilder = await addComputeUnitInstructions(
            connection,
            umi,
            eid,
            txBuilder,
            umiWalletSigner,
            4, // computeUnitPriceScaleFactor
            TransactionType.SendOFTConfig
        )
        const { signature } = await txBuilder.sendAndConfirm(umi)
        console.log(
            `updateMetadataTx: ${getExplorerTxLink(bs58.encode(signature), eid == EndpointId.SOLANA_V2_TESTNET)}`
        )
        console.log(`New uri: ${uri}`)
    })
