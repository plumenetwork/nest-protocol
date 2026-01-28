import { task, types } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { utils } from 'ethers'
import { fetchMint, findAssociatedTokenPda } from '@metaplex-foundation/mpl-toolbox'
import { fromWeb3JsPublicKey } from '@metaplex-foundation/umi-web3js-adapters'
import { PublicKey } from '@solana/web3.js'
import { TOKEN_PROGRAM_ID } from '@solana/spl-token'
import bs58 from 'bs58'

import { ChainType, endpointIdToChainType, endpointIdToNetwork } from '@layerzerolabs/lz-definitions'

import { EvmArgs, sendEvm } from '../evm/sendEvm'
import { SolanaArgs, sendSolana } from '../solana/sendSolana'

import { SendResult } from '../common/types'
import { DebugLogger, KnownOutputs, KnownWarnings, getBlockExplorerLink } from '../common/utils'
import { deriveConnection, getSolanaDeployment } from './index'
import { parseDecimalToUnits } from './utils'
import { oft } from '@layerzerolabs/oft-v2-solana-sdk'
import { publicKey } from '@metaplex-foundation/umi'


const USDC_MINT = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v'

const buildComposeMsg = (recipient: Uint8Array, amount: bigint) =>
    utils.arrayify(
        utils.defaultAbiCoder.encode(
            [
                'tuple(uint32 dstEid, bytes32 to, uint256 amountLD, uint256 minAmountLD, bytes extraOptions, bytes composeMsg, bytes oftCmd)',
                'uint256',
            ],
            [
                {
                    dstEid: 30168,
                    to: recipient,
                    amountLD: 0,
                    minAmountLD: 0,
                    extraOptions: '0x',
                    composeMsg: '0x',
                    oftCmd: '0x',
                },
                0,
            ],
        ),
    )

interface MasterArgs {
    srcEid: number
    dstEid: number
    amount: string
    to: string
    /** Minimum amount to receive in case of custom slippage or fees (human readable units, e.g. "1.5") */
    minAmount?: string
    /** Extra options for sending additional gas units to lzReceive, lzCompose, or receiver address */
    extraOptions?: string
    /** EVM: 20-byte hex; Solana: base58 PDA of the store */
    oftAddress?: string
    /** Solana only: override the OFT program ID (base58) */
    oftProgramId?: string
    tokenProgram?: string
    computeUnitPriceScaleFactor?: number
    addressLookupTables?: string
}

task('lz:oft:nest:deposit', 'Redeem nest tokens cross‐chain from Solana to any supported chain')
    .addParam('srcEid', 'Source endpoint ID', undefined, types.int)
    .addParam('dstEid', 'Destination endpoint ID', undefined, types.int)
    .addParam('amount', 'Amount to send (human readable units, e.g. "1.5")', undefined, types.string)
    .addParam('to', 'NestVaultComposer address', undefined, types.string)
    .addOptionalParam(
        'minAmount',
        'Minimum amount to receive in case of custom slippage or fees (human readable units, e.g. "1.5")',
        undefined,
        types.string
    )
    .addOptionalParam(
        'extraOptions',
        'Extra options for sending additional gas units to lzReceive, lzCompose, or receiver address',
        undefined,
        types.string
    )
    .addOptionalParam(
        'oftAddress',
        'Override the source local deployment OFT address (20-byte hex for EVM, base58 PDA for Solana)',
        undefined,
        types.string
    )
    .addOptionalParam('oftProgramId', 'Solana only: override the OFT program ID (base58)', undefined, types.string)
    .addOptionalParam('tokenProgram', 'Solana Token Program pubkey', undefined, types.string)
    .addOptionalParam('computeUnitPriceScaleFactor', 'Solana compute unit price scale factor', 4, types.float)
    .addOptionalParam(
        'addressLookupTables',
        'Solana address lookup tables (comma separated base58 list)',
        undefined,
        types.string
    )
    .setAction(async (args: MasterArgs, hre: HardhatRuntimeEnvironment) => {
        const chainType = endpointIdToChainType(args.srcEid)
        let result: SendResult

        if (args.oftAddress || args.oftProgramId) {
            DebugLogger.printWarning(
                KnownWarnings.USING_OVERRIDE_OFT,
                `For network: ${endpointIdToNetwork(args.srcEid)}, OFT: ${args.oftAddress + (args.oftProgramId ? `, OFT program: ${args.oftProgramId}` : '')}`
            )
        }

        // route to the correct function based on the chain type
        if (chainType === ChainType.EVM) {
            result = await sendEvm(args as EvmArgs, hre)
        } else if (chainType === ChainType.SOLANA) {
            const { umi, umiWalletSigner } = await deriveConnection(args.srcEid)

            // Derive sender's associated token account for USDC
            const tokenAccountPda = findAssociatedTokenPda(umi, {
                mint: fromWeb3JsPublicKey(new PublicKey(USDC_MINT)),
                owner: umiWalletSigner.publicKey,
                tokenProgramId: fromWeb3JsPublicKey(TOKEN_PROGRAM_ID),
            })
            console.log('tokenAccountPda:', tokenAccountPda[0])

            // Convert the PDA public key (base58 string) to bytes32 format for encoding
            const pdaAddress = tokenAccountPda[0] as string
            const pdaBytes = bs58.decode(pdaAddress)
            const storePda = args.oftAddress ? publicKey(args.oftAddress) : publicKey(getSolanaDeployment(args.srcEid).oftStore)
            const oftStoreInfo = await oft.accounts.fetchOFTStore(umi, storePda)
            const mintPk = new PublicKey(oftStoreInfo.tokenMint)
            const decimals = (await fetchMint(umi, fromWeb3JsPublicKey(mintPk))).decimals
            const composeMsgBytes = buildComposeMsg(pdaBytes, parseDecimalToUnits(args.amount, decimals))
            const composeMsgHex = utils.hexlify(composeMsgBytes)
            console.log(composeMsgHex)
            result = await sendSolana({
                ...args,
                composeMsg: composeMsgHex,
                addressLookupTables: args.addressLookupTables ? args.addressLookupTables.split(',') : [],
            } as SolanaArgs)
        } else {
            throw new Error(`The chain type ${chainType} is not implemented in sendOFT for this example`)
        }

        DebugLogger.printLayerZeroOutput(
            KnownOutputs.SENT_VIA_OFT,
            `Successfully sent ${args.amount} tokens from ${endpointIdToNetwork(args.srcEid)} to ${endpointIdToNetwork(args.dstEid)}`
        )
        // print the explorer link for the srcEid from metadata
        const explorerLink = await getBlockExplorerLink(args.srcEid, result.txHash)
        // if explorer link is available, print the tx hash link
        if (explorerLink) {
            DebugLogger.printLayerZeroOutput(
                KnownOutputs.TX_HASH,
                `Explorer link for source chain ${endpointIdToNetwork(args.srcEid)}: ${explorerLink}`
            )
        }
        // print the LayerZero Scan link from metadata
        DebugLogger.printLayerZeroOutput(
            KnownOutputs.EXPLORER_LINK,
            `LayerZero Scan link for tracking all cross-chain transaction details: ${result.scanLink}`
        )
    })
