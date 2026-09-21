import { existsSync, readFileSync } from 'node:fs'
import path from 'node:path'

import { PublicKey } from '@solana/web3.js'
import bs58 from 'bs58'
import { Contract, providers, utils as ethersUtils } from 'ethers'
import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

import { types as devtoolsTypes } from '@layerzerolabs/devtools-evm-hardhat'
import { createSolanaConnectionFactory, getSolanaKeypair } from '@layerzerolabs/devtools-solana'
import { EndpointId, endpointIdToNetwork } from '@layerzerolabs/lz-definitions'
import { UlnProgram } from '@layerzerolabs/lz-solana-sdk-v2'
import { OFT } from '@layerzerolabs/ua-devtools-solana'

import { getSolanaDeployment } from './index'

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

const CHAIN_TO_NETWORK: Record<number, string> = {
    1: 'ethereummainnet',
    56: 'bnbmainnet',
    480: 'worldchain',
    8453: 'base',
    9745: 'plasma-mainnet',
    98866: 'plumephoenix',
    43114: "avalanche",
}

const OAPP_ABI = [
    'function peers(uint32 _eid) view returns (bytes32)',
    'function enforcedOptions(uint32 _eid, uint16 _msgType) view returns (bytes)',
    'function owner() view returns (address)',
    'function endpoint() view returns (address)',
]

const ENDPOINT_ABI = [
    'function getSendLibrary(address _sender, uint32 _dstEid) view returns (address)',
    'function getReceiveLibrary(address _receiver, uint32 _srcEid) view returns (address, bool)',
    'function isDefaultSendLibrary(address _sender, uint32 _dstEid) view returns (bool)',
    'function getConfig(address _oapp, address _lib, uint32 _eid, uint32 _configType) view returns (bytes)',
    'function delegates(address _oapp) view returns (address)',
]

const CONFIG_TYPE_EXECUTOR = 1
const CONFIG_TYPE_ULN = 2

type EvmOutput = {
    baseAssetSymbol: string
    vaultType: string
    contracts: { share: string; vaults: Array<{ address: string; assetSymbol: string }> }
}

const evmOappAddress = (vaultSymbol: string, chainId: number): string => {
    const p = path.resolve(`script/output/${vaultSymbol}/${chainId}-${vaultSymbol}.json`)
    if (!existsSync(p)) throw new Error(`EVM output file missing: ${p}`)
    const out = JSON.parse(readFileSync(p, 'utf-8')) as EvmOutput
    const isOFT = out.vaultType === 'NestVaultOFT'
    const addr = isOFT
        ? out.contracts.vaults.find((v) => v.assetSymbol === out.baseAssetSymbol)?.address
        : out.contracts.share
    if (!addr || /^0x0+$/i.test(addr)) {
        throw new Error(`no canonical OApp address for chainId=${chainId}`)
    }
    return addr
}

const evmEndpointAddress = (eid: EndpointId): string => {
    const network = endpointIdToNetwork(eid)
    if (!network) throw new Error(`no network mapping for eid ${eid}`)
    const deployment = require(`@layerzerolabs/lz-evm-sdk-v2/deployments/${network}/EndpointV2.json`)
    return deployment.address
}

const decodeUlnConfig = (
    data: string
): {
    confirmations: string
    requiredDVNCount: number
    optionalDVNCount: number
    optionalDVNThreshold: number
    requiredDVNs: string[]
    optionalDVNs: string[]
} | null => {
    if (!data || data === '0x') return null
    const [decoded] = ethersUtils.defaultAbiCoder.decode(
        ['tuple(uint64 confirmations, uint8 requiredDVNCount, uint8 optionalDVNCount, uint8 optionalDVNThreshold, address[] requiredDVNs, address[] optionalDVNs)'],
        data
    )
    return {
        confirmations: decoded.confirmations.toString(),
        requiredDVNCount: decoded.requiredDVNCount,
        optionalDVNCount: decoded.optionalDVNCount,
        optionalDVNThreshold: decoded.optionalDVNThreshold,
        requiredDVNs: decoded.requiredDVNs,
        optionalDVNs: decoded.optionalDVNs,
    }
}

const decodeExecutorConfig = (data: string): { maxMessageSize: number; executor: string } | null => {
    if (!data || data === '0x') return null
    const [decoded] = ethersUtils.defaultAbiCoder.decode(
        ['tuple(uint32 maxMessageSize, address executor)'],
        data
    )
    return { maxMessageSize: decoded.maxMessageSize, executor: decoded.executor }
}

const printEvmSection = async (
    hre: HardhatRuntimeEnvironment,
    vaultSymbol: string,
    chainId: number,
    solanaEid: EndpointId
) => {
    const eid = CHAIN_TO_EID[chainId]
    if (!eid) throw new Error(`unknown chainId in peers: ${chainId}`)
    const networkName = CHAIN_TO_NETWORK[chainId]
    if (!networkName) throw new Error(`no hardhat network for chainId ${chainId}`)
    const netCfg = hre.config.networks[networkName] as { url?: string }
    if (!netCfg?.url) throw new Error(`network ${networkName} has no RPC URL configured`)

    const oappAddr = evmOappAddress(vaultSymbol, chainId)
    const endpointAddr = evmEndpointAddress(eid)

    printSection(`EVM source ${chainId}/${eid} (${networkName}) → Solana ${solanaEid}`)
    printKV('OApp', oappAddr)
    printKV('EndpointV2', endpointAddr)

    const provider = new providers.JsonRpcProvider(netCfg.url)
    const oapp = new Contract(oappAddr, OAPP_ABI, provider)
    const endpoint = new Contract(endpointAddr, ENDPOINT_ABI, provider)

    try {
        const peerBytes32: string = await oapp.peers(solanaEid)
        printKV('Peer (Solana bytes32)', peerBytes32)
        if (peerBytes32 && peerBytes32 !== '0x' + '0'.repeat(64)) {
            const peerSolana = bs58.encode(Uint8Array.from(Buffer.from(peerBytes32.slice(2), 'hex')))
            printKV('Peer (Solana base58)', peerSolana)
        }
    } catch (e) {
        printKV('Peer', `<error: ${(e as Error).message}>`)
    }

    try {
        const owner: string = await oapp.owner()
        printKV('OApp Owner', owner)
    } catch (e) {
        printKV('OApp Owner', `<error: ${(e as Error).message}>`)
    }
    try {
        const delegate: string = await endpoint.delegates(oappAddr)
        printKV('Delegate', delegate)
    } catch (e) {
        printKV('Delegate', `<error: ${(e as Error).message}>`)
    }

    let sendLib = ''
    let receiveLib = ''
    try {
        sendLib = await endpoint.getSendLibrary(oappAddr, solanaEid)
        const isDefaultSend: boolean = await endpoint.isDefaultSendLibrary(oappAddr, solanaEid)
        printKV('Send Library', `${sendLib}${isDefaultSend ? ' (default)' : ' (custom)'}`)
    } catch (e) {
        printKV('Send Library', `<error: ${(e as Error).message}>`)
    }
    try {
        const [lib, isDefault]: [string, boolean] = await endpoint.getReceiveLibrary(oappAddr, solanaEid)
        receiveLib = lib
        printKV('Receive Library', `${lib}${isDefault ? ' (default)' : ' (custom)'}`)
    } catch (e) {
        printKV('Receive Library', `<error: ${(e as Error).message}>`)
    }

    if (sendLib) {
        try {
            const execRaw: string = await endpoint.getConfig(oappAddr, sendLib, solanaEid, CONFIG_TYPE_EXECUTOR)
            const exec = decodeExecutorConfig(execRaw)
            if (!exec) printKV('Send Executor (app override)', 'NOT SET (empty bytes — uses lib default)')
            else {
                printKV('Send Executor (app override)', '')
                printKV('  maxMessageSize', exec.maxMessageSize)
                printKV('  executor', exec.executor)
            }
        } catch (e) {
            printKV('Send Executor', `<error: ${(e as Error).message}>`)
        }
        try {
            const ulnRaw: string = await endpoint.getConfig(oappAddr, sendLib, solanaEid, CONFIG_TYPE_ULN)
            const uln = decodeUlnConfig(ulnRaw)
            if (!uln) printKV('Send ULN (app override)', 'NOT SET (empty bytes — uses lib default)')
            else {
                printKV('Send ULN (app override)', '')
                printKV('  confirmations', uln.confirmations)
                printKV('  requiredDVNCount', uln.requiredDVNCount)
                printKV('  optionalDVNCount', uln.optionalDVNCount)
                printKV('  optionalDVNThreshold', uln.optionalDVNThreshold)
                printKV('  requiredDVNs', JSON.stringify(uln.requiredDVNs))
                printKV('  optionalDVNs', JSON.stringify(uln.optionalDVNs))
            }
        } catch (e) {
            printKV('Send ULN', `<error: ${(e as Error).message}>`)
        }
    }

    if (receiveLib) {
        try {
            const ulnRaw: string = await endpoint.getConfig(oappAddr, receiveLib, solanaEid, CONFIG_TYPE_ULN)
            const uln = decodeUlnConfig(ulnRaw)
            if (!uln) printKV('Receive ULN (app override)', 'NOT SET (empty bytes — uses lib default)')
            else {
                printKV('Receive ULN (app override)', '')
                printKV('  confirmations', uln.confirmations)
                printKV('  requiredDVNCount', uln.requiredDVNCount)
                printKV('  optionalDVNCount', uln.optionalDVNCount)
                printKV('  optionalDVNThreshold', uln.optionalDVNThreshold)
                printKV('  requiredDVNs', JSON.stringify(uln.requiredDVNs))
                printKV('  optionalDVNs', JSON.stringify(uln.optionalDVNs))
            }
        } catch (e) {
            printKV('Receive ULN', `<error: ${(e as Error).message}>`)
        }
    }

    for (const msgType of [1, 2] as const) {
        try {
            const opts: string = await oapp.enforcedOptions(solanaEid, msgType)
            const label = msgType === 1 ? 'msgType 1 (send)' : 'msgType 2 (sendAndCall)'
            printKV(`Enforced Options ${label}`, opts || '(empty)')
        } catch (e) {
            printKV(`Enforced Options msgType ${msgType}`, `<error: ${(e as Error).message}>`)
        }
    }
}

interface Args {
    remoteEid?: number
    skipEvm?: boolean
}

const formatBytes = (value: unknown): string => {
    if (value == null) return 'null'
    if (typeof value === 'string') return value
    if (value instanceof Uint8Array || Array.isArray(value)) {
        return bs58.encode(Uint8Array.from(value as ArrayLike<number>))
    }
    return String(value)
}

const formatDvns = (dvns: unknown[]): string[] => {
    return dvns.map((dvn) => {
        if (dvn instanceof PublicKey) return dvn.toBase58()
        if (typeof dvn === 'string') return dvn
        if (dvn instanceof Uint8Array) return bs58.encode(dvn)
        return String(dvn)
    })
}

const printSection = (title: string) => {
    console.log()
    console.log(`=== ${title} ===`)
}

const printKV = (k: string, v: unknown) => {
    console.log(`  ${k}: ${v}`)
}

type UlnConfigShape = {
    confirmations: bigint | number | string
    requiredDvnCount: number
    optionalDvnCount: number
    optionalDvnThreshold: number
    requiredDvns: Array<unknown>
    optionalDvns: Array<unknown>
}

type ExecutorConfigShape = {
    maxMessageSize: number
    executor: PublicKey
}

const fmtUln = (label: string, c: UlnConfigShape | null) => {
    if (!c) {
        printKV(label, '<no account>')
        return
    }
    printKV(label, '')
    printKV('  confirmations', c.confirmations.toString())
    printKV('  requiredDvnCount', c.requiredDvnCount)
    printKV('  optionalDvnCount', c.optionalDvnCount)
    printKV('  optionalDvnThreshold', c.optionalDvnThreshold)
    printKV('  requiredDVNs', JSON.stringify(formatDvns(c.requiredDvns ?? [])))
    printKV('  optionalDVNs', JSON.stringify(formatDvns(c.optionalDvns ?? [])))
}

const fmtExecutor = (label: string, c: ExecutorConfigShape | null) => {
    if (!c) {
        printKV(label, '<no account>')
        return
    }
    printKV(label, '')
    printKV('  maxMessageSize', c.maxMessageSize)
    printKV('  executor', c.executor.toBase58())
}

const printUlnSection = async (
    direction: 'Send' | 'Receive',
    connection: import('@solana/web3.js').Connection,
    libPk: PublicKey,
    oappPk: PublicKey,
    remoteEid: EndpointId,
    type: 'send' | 'receive'
) => {
    const uln = new UlnProgram.Uln(libPk)
    try {
        const appState =
            type === 'send'
                ? await uln.getSendConfigState(connection, oappPk, remoteEid)
                : await uln.getReceiveConfigState(connection, oappPk, remoteEid)

        if (!appState) {
            printKV(`${direction} app override`, 'NOT SET (account missing — falls back to lib default)')
            return
        }

        if (type === 'send') {
            const appExec = (appState as unknown as { executor?: ExecutorConfigShape }).executor ?? null
            fmtExecutor(`${direction} Executor (app override)`, appExec)
        }

        const appUln = (appState.uln ?? null) as unknown as UlnConfigShape | null
        fmtUln(`${direction} ULN (app override)`, appUln)
    } catch (e) {
        printKV(`${direction} config`, `<error: ${(e as Error).message}>`)
    }
}

task(
    'lz:oft:solana:getconfig',
    'Print Solana OFT config (peers, libraries, ULN DVNs, executor, enforced options) for a vault'
)
    .addOptionalParam(
        'remoteEid',
        'Limit output to a single remote EVM endpoint ID (otherwise prints all peers)',
        undefined,
        devtoolsTypes.int
    )
    .addFlag('skipEvm', 'Skip EVM-side config (only print Solana view)')
    .setAction(async (args: Args, hre: HardhatRuntimeEnvironment) => {
        const vaultSymbol = process.env.VAULT_SYMBOL
        if (!vaultSymbol) {
            throw new Error('VAULT_SYMBOL env var is required (e.g. VAULT_SYMBOL=nTBILL)')
        }

        const vaultPath = path.resolve(`script/deployment-config/vaults/${vaultSymbol}.json`)
        if (!existsSync(vaultPath)) throw new Error(`vault config missing: ${vaultPath}`)
        const vaultConfig = JSON.parse(readFileSync(vaultPath, 'utf-8'))
        const peers: number[] = vaultConfig.peers ?? []
        if (!peers.includes(SOLANA_CHAIN_ID)) {
            throw new Error(`vault ${vaultSymbol} has no Solana peer`)
        }

        const solanaEid = EndpointId.SOLANA_V2_MAINNET
        const solanaDeployment = getSolanaDeployment(solanaEid)

        const connectionFactory = createSolanaConnectionFactory()
        const connection = await connectionFactory(solanaEid)
        const keypair = await getSolanaKeypair(true)

        const oftStorePk = new PublicKey(solanaDeployment.oftStore)
        const programPk = new PublicKey(solanaDeployment.programId)

        const oftSdk = new OFT(
            connection,
            { eid: solanaEid, address: solanaDeployment.oftStore },
            keypair.publicKey,
            programPk
        )

        const owner = await oftSdk.getOwner()
        const delegate = await oftSdk.getDelegate()

        console.log(`Vault:           ${vaultSymbol}`)
        console.log(`Source EID:      ${solanaEid} (${endpointIdToNetwork(solanaEid)})`)
        console.log(`OFT Store:       ${oftStorePk.toBase58()}`)
        console.log(`OFT Program:     ${programPk.toBase58()}`)
        console.log(`Mint:            ${solanaDeployment.mint}`)
        console.log(`Escrow:          ${solanaDeployment.escrow}`)
        console.log(`Owner (admin):   ${owner}`)
        console.log(`Delegate:        ${delegate ?? 'null'}`)

        const endpointSdk = await oftSdk.getEndpointSDK()

        const allEvmPeers = peers.filter((c) => c !== SOLANA_CHAIN_ID)
        const eidsToShow = args.remoteEid
            ? [args.remoteEid as EndpointId]
            : allEvmPeers.map((chainId) => {
                  const eid = CHAIN_TO_EID[chainId]
                  if (!eid) throw new Error(`unknown chainId in peers: ${chainId}`)
                  return eid
              })

        for (const remoteEid of eidsToShow) {
            const remoteLabel = endpointIdToNetwork(remoteEid) ?? `eid ${remoteEid}`
            printSection(`Remote: ${remoteEid} (${remoteLabel})`)

            const peer = await oftSdk.getPeer(remoteEid)
            printKV('Peer Address', peer ? formatBytes(peer) : 'NOT SET')

            const sendLibrary = await endpointSdk.getSendLibrary(oftStorePk.toBase58(), remoteEid)
            const sendLibIsDefault = sendLibrary
                ? await endpointSdk.isDefaultSendLibrary(oftStorePk.toBase58(), remoteEid)
                : false
            const [receiveLibrary, receiveLibIsDefault] = await endpointSdk.getReceiveLibrary(
                oftStorePk.toBase58(),
                remoteEid
            )
            printKV(
                'Send Library',
                sendLibrary
                    ? `${sendLibrary}${sendLibIsDefault ? ' (default)' : ' (custom)'}`
                    : 'NOT SET'
            )
            printKV(
                'Receive Library',
                receiveLibrary
                    ? `${receiveLibrary}${receiveLibIsDefault ? ' (default)' : ' (custom)'}`
                    : 'NOT SET'
            )

            if (sendLibrary) {
                await printUlnSection(
                    'Send',
                    connection,
                    new PublicKey(sendLibrary),
                    oftStorePk,
                    remoteEid,
                    'send'
                )
            }

            if (receiveLibrary) {
                await printUlnSection(
                    'Receive',
                    connection,
                    new PublicKey(receiveLibrary),
                    oftStorePk,
                    remoteEid,
                    'receive'
                )
            }

            try {
                const enforcedSend = await oftSdk.getEnforcedOptions(remoteEid, 1)
                printKV('Enforced Options msgType 1 (send)', enforcedSend || '(empty)')
            } catch (e) {
                printKV('Enforced Options msgType 1', `<error: ${(e as Error).message}>`)
            }
            try {
                const enforcedSendAndCall = await oftSdk.getEnforcedOptions(remoteEid, 2)
                printKV('Enforced Options msgType 2 (sendAndCall)', enforcedSendAndCall || '(empty)')
            } catch (e) {
                printKV('Enforced Options msgType 2', `<error: ${(e as Error).message}>`)
            }
        }

        if (!args.skipEvm) {
            console.log()
            console.log('################################################################')
            console.log('# EVM-side config (each EVM peer → Solana lane)')
            console.log('################################################################')
            const chainIdFilter = args.remoteEid
                ? Object.entries(CHAIN_TO_EID).find(([, eid]) => eid === args.remoteEid)?.[0]
                : undefined
            const evmChainsToShow = chainIdFilter
                ? [Number(chainIdFilter)]
                : allEvmPeers
            for (const chainId of evmChainsToShow) {
                try {
                    await printEvmSection(hre, vaultSymbol, chainId, solanaEid)
                } catch (e) {
                    printSection(`EVM source ${chainId} (errored)`)
                    printKV('error', (e as Error).message)
                }
            }
        }

        console.log()
    })
