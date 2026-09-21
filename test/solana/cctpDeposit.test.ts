import path from "node:path";
import { BigNumber, utils } from "ethers";
import { Keypair, PublicKey } from "@solana/web3.js";
import { getAssociatedTokenAddressSync } from "@solana/spl-token";
import {
  buildBurnInstruction,
  TOKEN_MESSENGER,
  MESSAGE_TRANSMITTER,
} from "../../tasks/solana/cctpBurnInstruction";
import {
  buildDepositHook,
  DEPOSIT_SELECTOR,
  feeFromBps,
  pubkeyHex,
  resolveSolanaDeposit,
  SEND_PARAM,
  SOLANA_USDC,
  validateDepositMessage,
} from "../../tasks/solana/cctpDeposit";

const root = path.resolve(__dirname, "../..");
const owner = Keypair.fromSeed(new Uint8Array(32).fill(7)).publicKey;
const route = resolveSolanaDeposit(root, "nTEST", 98866);
const amount = 1_000_000n;
const maxFee = 200n;
const hook = buildDepositHook(route.composer, owner, amount, maxFee, 123n);

function message(
  overrides: {
    hook?: string;
    fee?: bigint;
    owner?: PublicKey;
    recipient?: string;
    domain?: number;
  } = {},
) {
  return utils.solidityPack(
    [
      "uint32",
      "uint32",
      "uint32",
      "bytes32",
      "bytes32",
      "bytes32",
      "bytes32",
      "uint32",
      "uint32",
      "uint32",
      "bytes32",
      "bytes32",
      "uint256",
      "bytes32",
      "uint256",
      "uint256",
      "uint256",
      "bytes",
    ],
    [
      1,
      5,
      overrides.domain ?? 22,
      utils.hexZeroPad("0x01", 32),
      pubkeyHex(TOKEN_MESSENGER),
      utils.hexZeroPad(route.tokenMessenger, 32),
      utils.hexZeroPad(route.relayer, 32),
      1000,
      1000,
      1,
      pubkeyHex(SOLANA_USDC),
      utils.hexZeroPad(overrides.recipient ?? route.relayer, 32),
      amount,
      pubkeyHex(overrides.owner ?? owner),
      maxFee,
      overrides.fee ?? 100n,
      0,
      overrides.hook ?? hook,
    ],
  );
}

describe("Solana CCTP Predicate V2 deposit", () => {
  it("resolves the parallel V2 composer and nTEST's relayer override", () => {
    expect(route.composer).toBe("0x4e6A52b0d22E333C01e71ed574DB6cE2b20CC0a1");
    expect(route.relayer).toBe("0x45bD35BEb70a3F0937f9701fE49AC1842dCc97b3");
    expect(() => resolveSolanaDeposit(root, "nTEST", 1)).toThrow("Plume");
  });

  it("matches plume-hub's burn hook: wallet receiver, USDC ATA refund, net amount", () => {
    expect(DEPOSIT_SELECTOR).toBe("0xfe030ec4");
    expect(utils.hexDataSlice(hook, 0, 20)).toBe(route.composer.toLowerCase());
    const [refund, net, send, refundAddress] = utils.defaultAbiCoder.decode(
      ["bytes32", "uint256", SEND_PARAM, "address"],
      utils.hexDataSlice(hook, 24),
    );
    expect(refund).toBe(
      pubkeyHex(getAssociatedTokenAddressSync(SOLANA_USDC, owner)),
    );
    expect(send.to).toBe(pubkeyHex(owner));
    expect(send.dstEid).toBe(30168);
    expect(net.toString()).toBe("999800");
    expect(send.minAmountLD.toString()).toBe("123");
    expect(send.oftCmd).toBe("0x");
    expect(refundAddress).toBe(route.composer);
  });

  it("encodes Circle's Borsh instruction and binds both EVM recipients to nTEST's relayer", () => {
    const eventAccount = Keypair.fromSeed(new Uint8Array(32).fill(8)).publicKey;
    const ix = buildBurnInstruction({
      owner,
      eventAccount,
      relayer: route.relayer,
      destinationDomain: 22,
      amount,
      maxFee,
      finalityThreshold: 1000,
      hookData: hook,
    });
    expect([...ix.data.subarray(0, 8)]).toEqual([
      111, 245, 62, 131, 204, 108, 223, 155,
    ]);
    expect(ix.data.readBigUInt64LE(8)).toBe(amount);
    expect(ix.data.readUInt32LE(16)).toBe(22);
    expect(utils.hexlify(new Uint8Array(ix.data.subarray(20, 52)))).toBe(
      utils.hexZeroPad(route.relayer, 32).toLowerCase(),
    );
    expect([...ix.data.subarray(20, 52)]).toEqual([
      ...ix.data.subarray(52, 84),
    ]);
    expect(ix.data.readBigUInt64LE(84)).toBe(maxFee);
    expect(ix.data.readUInt32LE(92)).toBe(1000);
    expect(ix.data.readUInt32LE(96)).toBe(utils.hexDataLength(hook));
    expect(utils.hexlify(new Uint8Array(ix.data.subarray(100)))).toBe(hook);
    expect(ix.keys).toHaveLength(18);
    expect(ix.keys[0].pubkey.equals(owner)).toBe(true);
    expect(ix.keys[1]).toMatchObject({ isSigner: true, isWritable: true });
    expect(ix.keys[11].pubkey.equals(eventAccount)).toBe(true);
    expect(ix.keys[12].pubkey.equals(MESSAGE_TRANSMITTER)).toBe(true);
    expect(ix.keys[17].pubkey.equals(TOKEN_MESSENGER)).toBe(true);
  });

  it("derives Predicate's original sender from signed message bytes and accounts for actual fees", () => {
    const result = validateDepositMessage(message(), route);
    expect(result.depositor).toBe(pubkeyHex(owner));
    expect(result.amountReceived.eq(BigNumber.from("999900"))).toBe(true);
  });

  it("refuses legacy composer hooks, incorrect relayers, domains, owners, and invalid fee bounds", () => {
    const v1 = buildDepositHook(
      "0x1daF84Ae51CcD1D9cdeDfF31e689cD2aA7579034",
      owner,
      amount,
      maxFee,
    );
    expect(() => validateDepositMessage(message({ hook: v1 }), route)).toThrow(
      "Composer V2",
    );
    expect(() =>
      validateDepositMessage(message({ recipient: route.composer }), route),
    ).toThrow("mintRecipient");
    expect(() => validateDepositMessage(message({ domain: 6 }), route)).toThrow(
      "domain",
    );
    expect(() =>
      validateDepositMessage(
        message({
          owner: Keypair.fromSeed(new Uint8Array(32).fill(9)).publicKey,
        }),
        route,
      ),
    ).toThrow("receiver/refund");
    expect(() => validateDepositMessage(message({ fee: 201n }), route)).toThrow(
      "after CCTP fees",
    );
    expect(() => validateDepositMessage("0x00", route)).toThrow("Truncated");
    expect(() =>
      buildDepositHook(route.composer, owner, amount, amount),
    ).toThrow("maxFee");
    expect(() =>
      buildDepositHook(route.composer, owner, 1n << 64n, 0n),
    ).toThrow("u64");
  });

  it("rounds fractional-bps Circle fees upward without converting USDC amounts to Number", () => {
    expect(feeFromBps(1_000_001n, "0.5")).toBe(51n);
    expect(feeFromBps((1n << 64n) - 1n, 2)).toBe(3_689_348_814_741_911n);
    expect(() => feeFromBps(amount, -1)).toThrow("minimumFee");
  });
});
