// SPDX-License-Identifier: Apache-2.0
// Minimal instruction interface from Circle's TokenMessengerMinterV2 IDL,
// as used by plume-hub/packages/nest-sdk-node/src/solana-cctp/idl/.
// https://github.com/circlefin/solana-cctp-contracts/tree/master/programs/v2
import { BorshInstructionCoder, BN, Idl } from "@coral-xyz/anchor";
import {
  PublicKey,
  SystemProgram,
  TransactionInstruction,
} from "@solana/web3.js";
import {
  getAssociatedTokenAddressSync,
  TOKEN_PROGRAM_ID,
} from "@solana/spl-token";
import { utils } from "ethers";
import { SOLANA_USDC } from "./cctpDeposit";

export const TOKEN_MESSENGER = new PublicKey(
  "CCTPV2vPZJS2u2BBsUoscuikbYjnpFmbFsvVuJdgUMQe",
);
export const MESSAGE_TRANSMITTER = new PublicKey(
  "CCTPV2Sm4AdWt5296sk4P66VBZ7bEhcARwFaaS9YPbeC",
);

const idl: Idl = {
  address: TOKEN_MESSENGER.toBase58(),
  metadata: { name: "cctp_deposit", version: "2.0.0", spec: "0.1.0" },
  instructions: [
    {
      name: "deposit_for_burn_with_hook",
      discriminator: [111, 245, 62, 131, 204, 108, 223, 155],
      accounts: [], // Explicit ordered account metas below; no Anchor account resolution.
      args: [
        {
          name: "params",
          type: { defined: { name: "DepositForBurnWithHookParams" } },
        },
      ],
    },
  ],
  types: [
    {
      name: "DepositForBurnWithHookParams",
      type: {
        kind: "struct",
        fields: [
          { name: "amount", type: "u64" },
          { name: "destination_domain", type: "u32" },
          { name: "mint_recipient", type: "pubkey" },
          { name: "destination_caller", type: "pubkey" },
          { name: "max_fee", type: "u64" },
          { name: "min_finality_threshold", type: "u32" },
          { name: "hook_data", type: "bytes" },
        ],
      },
    },
  ],
};

export function buildBurnInstruction(args: {
  owner: PublicKey;
  eventAccount: PublicKey;
  relayer: string;
  destinationDomain: number;
  amount: bigint;
  maxFee: bigint;
  finalityThreshold: number;
  hookData: string;
}) {
  const pda = (program: PublicKey, seed: string, ...extra: Uint8Array[]) =>
    PublicKey.findProgramAddressSync(
      [Buffer.from(seed), ...extra.map((x) => Buffer.from(x))],
      program,
    )[0];
  const tokenPda = (seed: string, ...extra: Uint8Array[]) =>
    pda(TOKEN_MESSENGER, seed, ...extra);
  const relayer = new PublicKey(
    utils.arrayify(utils.hexZeroPad(args.relayer, 32)),
  );
  const meta = (pubkey: PublicKey, isWritable = false, isSigner = false) => ({
    pubkey,
    isWritable,
    isSigner,
  });
  return new TransactionInstruction({
    programId: TOKEN_MESSENGER,
    keys: [
      meta(args.owner, false, true),
      meta(args.owner, true, true), // CLI wallet pays event rent (no server keeper).
      meta(tokenPda("sender_authority")),
      meta(getAssociatedTokenAddressSync(SOLANA_USDC, args.owner), true),
      meta(tokenPda("denylist_account", args.owner.toBytes())),
      meta(pda(MESSAGE_TRANSMITTER, "message_transmitter"), true),
      meta(tokenPda("token_messenger")),
      meta(
        tokenPda(
          "remote_token_messenger",
          new TextEncoder().encode(String(args.destinationDomain)),
        ),
      ),
      meta(tokenPda("token_minter")),
      meta(tokenPda("local_token", SOLANA_USDC.toBytes()), true),
      meta(SOLANA_USDC, true),
      meta(args.eventAccount, true, true),
      meta(MESSAGE_TRANSMITTER),
      meta(TOKEN_MESSENGER),
      meta(TOKEN_PROGRAM_ID),
      meta(SystemProgram.programId),
      meta(tokenPda("__event_authority")),
      meta(TOKEN_MESSENGER),
    ],
    data: new BorshInstructionCoder(idl).encode("deposit_for_burn_with_hook", {
      params: {
        amount: new BN(args.amount.toString()),
        destination_domain: args.destinationDomain,
        mint_recipient: relayer,
        destination_caller: relayer,
        max_fee: new BN(args.maxFee.toString()),
        min_finality_threshold: args.finalityThreshold,
        hook_data: Buffer.from(utils.arrayify(args.hookData)),
      },
    }),
  });
}
