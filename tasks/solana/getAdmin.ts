import { publicKey } from '@metaplex-foundation/umi'
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
    eid: EndpointId
    tokenProgram: string
}

// Define a Hardhat task for getting admin
task('lz:oft:solana:getadmin', 'get admin')
    .addParam('eid', 'The source endpoint ID', undefined, devtoolsTypes.eid)
    .addParam('tokenProgram', 'The Token Program public key', TOKEN_PROGRAM_ID.toBase58(), devtoolsTypes.string, true)
    .setAction(async (args: Args) => {
        const { eid } = args

        const { umi } = await deriveConnection(eid)

        const res = await oft.accounts.fetchOFTStore(
            umi,
            publicKey(getSolanaDeployment(eid).oftStore)
        )
        console.log(res)
    })