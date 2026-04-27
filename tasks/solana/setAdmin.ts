import { findAssociatedTokenPda } from '@metaplex-foundation/mpl-toolbox'
import { publicKey, transactionBuilder } from '@metaplex-foundation/umi'
import { fromWeb3JsPublicKey } from '@metaplex-foundation/umi-web3js-adapters'
import { TOKEN_PROGRAM_ID } from '@solana/spl-token'
import bs58 from 'bs58'
import { task } from 'hardhat/config'

import { types as devtoolsTypes } from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'
import { oft } from '@layerzerolabs/oft-v2-solana-sdk'
import {
    TransactionType,
    addComputeUnitInstructions,
    deriveConnection,
    getExplorerTxLink,
    getSolanaDeployment,
} from './index'

interface Args {
    eid: EndpointId
    tokenProgram: string
    newAdmin: string
}

// Define a Hardhat task for setting admin for solana oft
task('lz:oft:solana:setadmin', 'set admin for solana oft')
    .addParam('eid', 'The source endpoint ID', undefined, devtoolsTypes.eid)
    .addParam('tokenProgram', 'The Token Program public key', TOKEN_PROGRAM_ID.toBase58(), devtoolsTypes.string, true)
    .addParam('newAdmin', 'The new admin', undefined, devtoolsTypes.string)
    .setAction(async (args: Args) => {
        const { eid, tokenProgram: tokenProgramStr, newAdmin: newAdminStr } = args

        const { connection, umi, umiWalletSigner } = await deriveConnection(eid)

        const solanaDeployment = getSolanaDeployment(eid)

        const oftProgramId = publicKey(solanaDeployment.programId)
        const mint = publicKey(solanaDeployment.mint)
        const tokenProgramId = tokenProgramStr ? publicKey(tokenProgramStr) : fromWeb3JsPublicKey(TOKEN_PROGRAM_ID)

        const tokenAccount = findAssociatedTokenPda(umi, {
            mint,
            owner: publicKey(newAdminStr),
            tokenProgramId,
        })

        if (!tokenAccount) {
            throw new Error(
                `No token account found for mint ${mint.toString()} and owner ${newAdminStr} in program ${tokenProgramId}`
            )
        }

        const setAdminIX = await oft.setOFTConfig(
            {
                admin: umiWalletSigner,
                oftStore: publicKey(solanaDeployment.oftStore)
            },
            {
                __kind: 'Admin',
                admin: publicKey(newAdminStr)
            },
            {
                oft: oftProgramId
            }
        )
        let txBuilder = transactionBuilder().add([setAdminIX])
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
            `SetAdminTx: ${getExplorerTxLink(bs58.encode(signature), eid == EndpointId.SOLANA_V2_TESTNET)}`
        )

    })
