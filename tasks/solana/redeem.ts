import { task, types } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { BigNumberish, utils } from 'ethers'
import { createAssociatedToken, fetchMint, findAssociatedTokenPda, safeFetchToken } from '@metaplex-foundation/mpl-toolbox'
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
import { oft } from '@layerzerolabs/oft-v2-solana-sdk'
import { parseDecimalToUnits } from './utils'
import { publicKey } from '@metaplex-foundation/umi'
import { createGetHreByEid } from '@layerzerolabs/devtools-evm-hardhat'
import { createLogger } from '@layerzerolabs/io-devtools'
import { parseUnits } from 'ethers/lib/utils'
import { Options } from '@layerzerolabs/lz-v2-utilities'
import { makeBytes32 } from '@layerzerolabs/devtools'


const USDC_MINT = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v'

const logger = createLogger()


/**
 * RedeemType enum values matching Solidity NestVaultCoreTypes.RedeemType
 * INSTANT_REDEEM = 0, REQUEST_REDEEM = 1, UPDATE_REDEEM_REQUEST = 2, FINISH_REDEEM = 3
 */
const RedeemTypeEnum = {
    INSTANT_REDEEM: 0,
    REQUEST_REDEEM: 1,
    UPDATE_REDEEM_REQUEST: 2,
    FINISH_REDEEM: 3,
} as const

type RedeemMode = 'instant-redeem' | 'request-redeem' | 'finish-redeem' | 'update-redeem-request'

/**
 * Builds compose message for instant redeem
 * @param recipient - bytes32 recipient address
 * @param dstEid - destination endpoint ID
 * @param minAmountReceived - minimum amount of assets expected
 * @param minMsgValue - minimum msg.value for lzCompose
 */
const buildInstantRedeemComposeMsg = (
    recipient: Uint8Array,
    dstEid: number,
    minAmountReceived: bigint,
    minMsgValue: bigint
) =>
    utils.arrayify(
        utils.defaultAbiCoder.encode(
            [
                'tuple(uint32 dstEid, bytes32 to, uint256 amountLD, uint256 minAmountLD, bytes extraOptions, bytes composeMsg, bytes oftCmd)',
                'uint256',
            ],
            [
                {
                    dstEid,
                    to: recipient,
                    amountLD: 0, // overridden by NestVaultComposer (actual amount of assets received)
                    minAmountLD: minAmountReceived,
                    extraOptions: '0x',
                    composeMsg: '0x',
                    oftCmd: utils.defaultAbiCoder.encode(['uint8'], [RedeemTypeEnum.INSTANT_REDEEM]),
                },
                minMsgValue,
            ]
        )
    )

/**
 * Builds compose message for request redeem (async redemption)
 * @param recipient - bytes32 recipient address
 * @param dstEid - destination endpoint ID
 * @param sharesAmount - amount of shares to request redeem
 * @param minMsgValue - minimum msg.value for lzCompose
 */
const buildRequestRedeemComposeMsg = (
    recipient: Uint8Array,
    dstEid: number,
    sharesAmount: bigint,
    minMsgValue: bigint
) =>
    utils.arrayify(
        utils.defaultAbiCoder.encode(
            [
                'tuple(uint32 dstEid, bytes32 to, uint256 amountLD, uint256 minAmountLD, bytes extraOptions, bytes composeMsg, bytes oftCmd)',
                'uint256',
            ],
            [
                {
                    dstEid,
                    to: recipient,
                    amountLD: sharesAmount,
                    minAmountLD: 0,
                    extraOptions: '0x',
                    composeMsg: '0x',
                    oftCmd: utils.defaultAbiCoder.encode(['uint8'], [RedeemTypeEnum.REQUEST_REDEEM]),
                },
                minMsgValue,
            ]
        )
    )

const buildUpdateRedeemComposeMsg = (
    srcEid: number,
    recipient: Uint8Array,
    sharesAmount: bigint,
    minMsgValue: bigint
) =>
    utils.arrayify(
        utils.defaultAbiCoder.encode(
            [
                'tuple(uint32 dstEid, bytes32 to, uint256 amountLD, uint256 minAmountLD, bytes extraOptions, bytes composeMsg, bytes oftCmd)',
                'uint256',
            ],
            [
                {
                    dstEid: srcEid,
                    to: recipient,
                    amountLD: sharesAmount,
                    minAmountLD: 0,
                    extraOptions: '0x',
                    composeMsg: '0x',
                    oftCmd: utils.defaultAbiCoder.encode(['uint8'], [RedeemTypeEnum.UPDATE_REDEEM_REQUEST]),
                },
                minMsgValue,
            ]
        )
    )

/**
 * Builds compose message for finish redeem (complete redemption by share amount)
 * @param recipient - bytes32 recipient address
 * @param dstEid - destination endpoint ID
 * @param shareAmount - shares to redeem from claimable
 * @param minAssetAmount - minimum assets expected
 * @param minMsgValue - minimum msg.value for lzCompose
 */
const buildFinishRedeemComposeMsg = (
    recipient: Uint8Array,
    dstEid: number,
    shareAmount: bigint,
    minAssetAmount: bigint,
    minMsgValue: bigint
) =>
    utils.arrayify(
        utils.defaultAbiCoder.encode(
            [
                'tuple(uint32 dstEid, bytes32 to, uint256 amountLD, uint256 minAmountLD, bytes extraOptions, bytes composeMsg, bytes oftCmd)',
                'uint256',
            ],
            [
                {
                    dstEid,
                    to: recipient,
                    amountLD: shareAmount,
                    minAmountLD: minAssetAmount,
                    extraOptions: '0x',
                    composeMsg: '0x',
                    oftCmd: utils.defaultAbiCoder.encode(['uint8'], [RedeemTypeEnum.FINISH_REDEEM]),
                },
                minMsgValue,
            ]
        )
    )

/**
 * Builds the appropriate compose message based on redeem mode
 * @param mode - redeem mode
 * @param recipient - bytes32 recipient address
 * @param dstEid - destination endpoint ID
 * @param amount - amount (shares or assets depending on mode)
 * @param minAmount - minimum amount expected
 * @param minMsgValue - minimum msg.value for lzCompose
 */
const buildComposeMsgForMode = (
    mode: RedeemMode,
    recipient: Uint8Array,
    srcEid: number,
    dstEid: number,
    amount: bigint,
    minAmount: bigint,
    minMsgValue: bigint
): Uint8Array => {
    switch (mode) {
        case 'instant-redeem':
            return buildInstantRedeemComposeMsg(recipient, dstEid, minAmount, minMsgValue)
        case 'request-redeem':
            return buildRequestRedeemComposeMsg(recipient, dstEid, amount, minMsgValue)
        case 'update-redeem-request':
            return buildUpdateRedeemComposeMsg(srcEid, recipient, amount, minMsgValue)
        case 'finish-redeem':
            return buildFinishRedeemComposeMsg(recipient, dstEid, amount, minAmount, minMsgValue)
        default:
            throw new Error(`Unknown redeem mode: ${mode}`)
    }
}

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
    /** Redeem mode: 'finish-redeem' | 'instant-redeem' | 'request-redeem' | 'update-redeem-request'  */
    redeemMode?: string
}

task(
    'lz:oft:nest:redeem',
    "Cross-chain redeem helper: supports 'instant-redeem', 'request-redeem', 'finish-redeem', and 'withdraw' from Solana or EVM"
)
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
    .addOptionalParam(
        'redeemMode',
        "Redeem mode: 'instant-redeem' | 'request-redeem' | 'update-redeem-request' |'finish-redeem'",
        'redeem',
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
            const usdcMint = fromWeb3JsPublicKey(new PublicKey(USDC_MINT))
            const tokenProgramId = fromWeb3JsPublicKey(TOKEN_PROGRAM_ID)
            const tokenAccountPda = findAssociatedTokenPda(umi, {
                mint: usdcMint,
                owner: umiWalletSigner.publicKey,
                tokenProgramId,
            })
            console.log('tokenAccountPda:', tokenAccountPda[0])

            // fund the associated token account if has not been funded yet
            const tokenAccount = await safeFetchToken(umi, tokenAccountPda)
            if (!tokenAccount) {
                console.log('Creating and funding associated token account for USDC...')
                await createAssociatedToken(umi, {
                    ata: tokenAccountPda,
                    owner: umiWalletSigner.publicKey,
                    mint: usdcMint,
                    tokenProgram: tokenProgramId,
                }).sendAndConfirm(umi)
                console.log('Token account funded:', tokenAccountPda[0])
            }

            // Convert the PDA public key (base58 string) to bytes32 format for encoding
            const pdaAddress = tokenAccountPda[0] as string
            const pdaBytes = bs58.decode(pdaAddress)
            const storePda = args.oftAddress ? publicKey(args.oftAddress) : publicKey(getSolanaDeployment(args.srcEid).oftStore)
            const oftStoreInfo = await oft.accounts.fetchOFTStore(umi, storePda)
            const mintPk = new PublicKey(oftStoreInfo.tokenMint)
            const decimals = (await fetchMint(umi, fromWeb3JsPublicKey(mintPk))).decimals

            // Parse amounts
            const amount = parseDecimalToUnits(args.amount, decimals)
            const minAmount = args.minAmount ? parseDecimalToUnits(args.minAmount, decimals) : BigInt(0)
            // Pass through the requested redeem mode
            const redeemMode = args.redeemMode as RedeemMode
            let minMsgValue = BigInt(0) // Can be made configurable if needed 

            if (redeemMode === "update-redeem-request") {
                // ============================================================
                // Quote the destination hop fee (Fraxtal -> Final Destination)
                // ============================================================
                const PLUME_EID = 30370

                logger.info('Quoting destination composer fee (Plume -> Final Destination)...')

                // Connect to Fraxtal to quote the second hop
                const getHreByEid = createGetHreByEid(hre)
                const plumeHre = await getHreByEid(PLUME_EID)
                const evmOftAddress = (await plumeHre.deployments.get('OFT')).address

                // Load the NestVaultComposer contract (it should have quoteSend or we use the underlying OFT)
                const plumeOft = await plumeHre.ethers.getContractAt((await plumeHre.deployments.get('OFT')).abi, evmOftAddress)

                // Get decimals directly from the underlying token using minimal ABI
                const plumeDecimals: number = await plumeOft.decimals()
                const plumeAmountUnits = parseUnits(args.amount, plumeDecimals)

                // Build sendParam for the Plume -> Final Destination quote
                const dstSendParam = {
                    dstEid: args.srcEid,
                    to: makeBytes32(bs58.decode(umiWalletSigner.publicKey)),
                    amountLD: plumeAmountUnits.toString(),
                    minAmountLD: plumeAmountUnits.toString(),
                    extraOptions: '0x',
                    composeMsg: utils.defaultAbiCoder.encode(['uint8'], [RedeemTypeEnum.UPDATE_REDEEM_REQUEST]),
                    oftCmd: '0x',
                }

                // Quote the fee for the destination hop
                let destinationMsgFee: { nativeFee: BigNumber; lzTokenFee: BigNumber }
                try {
                    destinationMsgFee = await plumeOft.quoteSend(dstSendParam, false)
                    logger.info(`Destination hop fee: ${utils.formatEther(destinationMsgFee.nativeFee)} PLUME`)
                } catch (error) {
                    logger.error('Failed to quote destination hop fee:', error)
                    throw error
                }

                // ============================================================
                // Now prepare the Solana -> Plume send with compose message
                // ============================================================


                // Add compose options with the destination native fee as nativeDrop
                // The nativeDrop is in wei (destination chain's native token)
                minMsgValue = BigInt(destinationMsgFee.nativeFee.toString())

                logger.info(`Compose options with nativeDrop: ${minMsgValue} wei`)
            }

            // Build mode-specific compose message
            const composeMsgBytes = buildComposeMsgForMode(
                redeemMode,
                redeemMode === "instant-redeem" || redeemMode === "finish-redeem" ? pdaBytes : bs58.decode(umiWalletSigner.publicKey),
                args.srcEid,
                args.dstEid,
                amount,
                minAmount,
                minMsgValue
            )
            const composeMsgHex = utils.hexlify(composeMsgBytes)

            if (redeemMode === "update-redeem-request") {
                logger.info(`Adding extra options for with nativeDrop: ${minMsgValue} wei`)
                args.extraOptions = Options.newOptions()
                    .addExecutorComposeOption(0, 350_000, minMsgValue)
                    .toHex()
            }
            result = await sendSolana({
                ...args,
                composeMsg: composeMsgHex,
                addressLookupTables: args.addressLookupTables ? args.addressLookupTables.split(',') : [],
                redeemType: redeemMode,
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
