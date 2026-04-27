import { publicKey } from '@metaplex-foundation/umi'
import { fromWeb3JsPublicKey } from '@metaplex-foundation/umi-web3js-adapters'
import { TOKEN_PROGRAM_ID } from '@solana/spl-token'
import { task } from 'hardhat/config'

import { types as devtoolsTypes } from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'
import { oft } from '@layerzerolabs/oft-v2-solana-sdk'
import {
    deriveConnection,
    getSolanaDeployment,
} from './index'

interface Args {
    fromEid: EndpointId
    toEid: EndpointId
    tokenProgram: string
}

// Define a Hardhat task for getting enforced options
task('lz:oft:solana:getenforceoptions', 'get enforced options')
    .addParam('fromEid', 'The source endpoint ID', undefined, devtoolsTypes.eid)
    .addParam('toEid', 'The destination endpoint ID', undefined, devtoolsTypes.eid)
    .addParam('tokenProgram', 'The Token Program public key', TOKEN_PROGRAM_ID.toBase58(), devtoolsTypes.string, true)
    .setAction(async (args: Args) => {
        const { fromEid, toEid, tokenProgram: tokenProgramStr } = args

        const { umi } = await deriveConnection(fromEid)

        const solanaDeployment = getSolanaDeployment(fromEid)

        const oftProgramId = publicKey(solanaDeployment.programId)

        const res = await oft.getEnforcedOptions(
            umi.rpc,
            publicKey(getSolanaDeployment(fromEid).oftStore),
            toEid,
            publicKey(oftProgramId)
        )
        console.log(Buffer.from(res.send).toString('hex'))
        console.log(Buffer.from(res.sendAndCall).toString('hex'))

    })