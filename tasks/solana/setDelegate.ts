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
    newDelegate: string
}

// Define a Hardhat task for setting delegate for solana oft
task('lz:oft:solana:setdelegate', 'set delegate for solana oft')
    .addParam('eid', 'The source endpoint ID', undefined, devtoolsTypes.eid)
    .addParam('tokenProgram', 'The Token Program public key', TOKEN_PROGRAM_ID.toBase58(), devtoolsTypes.string, true)
    .addParam('newDelegate', 'The new delegate', undefined, devtoolsTypes.string)
    .setAction(async (args: Args) => {
        const { eid, tokenProgram: tokenProgramStr, newDelegate: newDelegateStr } = args

        const { connection, umi, umiWalletKeyPair, umiWalletSigner } = await deriveConnection(eid)

        const solanaDeployment = getSolanaDeployment(eid)

        const oftProgramId = publicKey(solanaDeployment.programId)
        const mint = publicKey(solanaDeployment.mint)
        const tokenProgramId = tokenProgramStr ? publicKey(tokenProgramStr) : fromWeb3JsPublicKey(TOKEN_PROGRAM_ID)

        const tokenAccount = findAssociatedTokenPda(umi, {
            mint,
            owner: publicKey(newDelegateStr),
            tokenProgramId,
        })

        if (!tokenAccount) {
            throw new Error(
                `No token account found for mint ${mint.toString()} and owner ${newDelegateStr} in program ${tokenProgramId}`
            )
        }

        const setDelegateIX = await oft.setOFTConfig(
            {
                admin: umiWalletSigner,
                oftStore: publicKey(solanaDeployment.oftStore)
            },
            {
                __kind: 'Delegate',
                delegate: publicKey(newDelegateStr)
            },
            {
                oft: oftProgramId
            }
        )
        let txBuilder = transactionBuilder().add([setDelegateIX])
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
            `SetDelegateTx: ${getExplorerTxLink(bs58.encode(signature), eid == EndpointId.SOLANA_V2_TESTNET)}`
        )

    })
