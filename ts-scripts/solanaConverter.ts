import { makeBytes32 } from '@layerzerolabs/devtools'
import bs58 from 'bs58'

function main() {
    // solana base58 to bytes32
    console.log("bytes32 ", makeBytes32(bs58.decode("RgP5qMfX58PBLm6EoEgCfgfWxLdVBmGTm6bYnD3kECq"))) // oftStore
}

main();