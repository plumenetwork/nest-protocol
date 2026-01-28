// require("dotenv").config("./.env")
const bs58 = require('bs58');
const { Keypair } = require('@solana/web3.js');

const privateKey:number[] = process.env.SOLANA_PRIVATE_KEY_PAIR as unknown as number[];

const secretKey = Keypair.fromSeed(Uint8Array.from(privateKey.slice(0,32))).secretKey;

const keypairData = Keypair.fromSeed(Uint8Array.from(bs58.default.decode(privateKey).slice(0, 32)));

console.log('Public Key:', keypairData.publicKey.toString());
console.log('Secret Key:', bs58.default.encode(secretKey));