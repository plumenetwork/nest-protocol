import { readFileSync } from "node:fs";
import path from "node:path";
import { BigNumber, utils } from "ethers";
import { PublicKey } from "@solana/web3.js";
import { getAssociatedTokenAddressSync } from "@solana/spl-token";
import { resolvePredicateV2Deployment } from "../evm/predicateV2Config";

export const SOLANA_DOMAIN = 5;
export const SOLANA_EID = 30168;
export const SOLANA_USDC = new PublicKey(
  "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
);
export const SEND_PARAM =
  "tuple(uint32 dstEid,bytes32 to,uint256 amountLD,uint256 minAmountLD,bytes extraOptions,bytes composeMsg,bytes oftCmd)";
export const DEPOSIT_SELECTOR = utils
  .id(
    "depositAndSend(bytes32,uint256,(uint32,bytes32,uint256,uint256,bytes,bytes,bytes),address)",
  )
  .slice(0, 10);

export function resolveSolanaDeposit(
  root: string,
  symbol: string,
  chainId: number,
) {
  if (chainId !== 98866)
    throw new Error(
      "Solana Predicate V2 deposits currently support Plume (98866) only",
    );
  const deployment = resolvePredicateV2Deployment(root, symbol, chainId);
  const read = (file: string) =>
    JSON.parse(readFileSync(path.join(root, file), "utf8"));
  const vault = read(`script/deployment-config/vaults/${symbol}.json`);
  const compliance = read(
    `script/deployment-config/compliance/${chainId}-${symbol}.json`,
  );
  const common = read(`script/deployment-config/common/${chainId}.json`);
  const cctp = read(`config/cctp/${chainId}.json`);
  const solana = read(`deployments/solana-mainnet/${symbol}-OFT.json`);
  const overrides = vault.commonOverrides;
  const relayer =
    overrides?.[String(chainId)]?.cctpRelayer ??
    overrides?.cctpRelayer ??
    common.cctpRelayer;
  if (!vault.peers?.includes(101) || deployment.assetSymbol !== "USDC") {
    throw new Error("Vault must have a Solana peer and USDC base asset");
  }
  for (const [name, address] of Object.entries({
    composerV2: compliance.composerV2,
    relayer,
  })) {
    if (
      typeof address !== "string" ||
      !utils.isAddress(address) ||
      BigNumber.from(address).isZero()
    ) {
      throw new Error(
        `Missing or invalid ${name}; refusing to fall back to Composer V1`,
      );
    }
  }
  return {
    ...deployment,
    composer: utils.getAddress(compliance.composerV2),
    relayer: utils.getAddress(relayer),
    destinationDomain: cctp.domain as number,
    shareMint: new PublicKey(solana.mint),
    oftStore: new PublicKey(solana.oftStore),
    tokenMessenger: utils.getAddress(cctp.tokenMessenger),
  };
}

export type SolanaDepositRoute = ReturnType<typeof resolveSolanaDeposit>;

export const pubkeyHex = (key: PublicKey) => utils.hexlify(key.toBytes());

/** Matches plume-hub's mintNestToSolanaNode: USDC ATA refund, wallet OFT receiver,
 * net-of-maxFee lower bound, and a composer depositAndSend hook. The relayer
 * replaces the first argument with the CCTP burn owner and injects the proof.
 */
export function buildDepositHook(
  composer: string,
  owner: PublicKey,
  amount: bigint,
  maxFee: bigint,
  minShares = 0n,
) {
  if (amount <= 0n || amount > (1n << 64n) - 1n)
    throw new Error("USDC amount must fit a positive u64");
  if (maxFee < 0n || maxFee >= amount)
    throw new Error(
      "maxFee must be non-negative and less than the burn amount",
    );
  if (minShares < 0n) throw new Error("Minimum shares must be non-negative");
  const refundRecipient = pubkeyHex(
    getAssociatedTokenAddressSync(SOLANA_USDC, owner),
  );
  const sendParam = [
    SOLANA_EID,
    pubkeyHex(owner),
    0,
    minShares,
    "0x",
    "0x",
    "0x",
  ];
  return utils.solidityPack(
    ["address", "bytes4", "bytes"],
    [
      composer,
      DEPOSIT_SELECTOR,
      utils.defaultAbiCoder.encode(
        ["bytes32", "uint256", SEND_PARAM, "address"],
        [refundRecipient, amount - maxFee, sendParam, composer],
      ),
    ],
  );
}

/** Parse signed CCTP V2 bytes, never API-derived sender/target metadata. */
export function validateDepositMessage(
  message: string,
  route: SolanaDepositRoute,
) {
  if (
    !utils.isHexString(message) ||
    utils.hexDataLength(message) < 148 + 228 + 472
  )
    throw new Error("Truncated CCTP deposit message");
  const slice = (start: number, end: number) =>
    utils.hexDataSlice(message, start, end);
  const uint = (start: number, end: number) =>
    BigNumber.from(slice(start, end));
  if (!uint(0, 4).eq(1) || !uint(148, 152).eq(1))
    throw new Error("Expected CCTP V2 message/body version 1");
  if (!uint(4, 8).eq(SOLANA_DOMAIN) || !uint(8, 12).eq(route.destinationDomain))
    throw new Error("Wrong CCTP source/destination domain");
  const relayer32 = utils.hexZeroPad(route.relayer, 32).toLowerCase();
  if (
    slice(108, 140).toLowerCase() !== relayer32 ||
    slice(184, 216).toLowerCase() !== relayer32
  )
    throw new Error(
      "Burn must name the configured relayer as destinationCaller and mintRecipient",
    );
  if (
    slice(76, 108).toLowerCase() !==
    utils.hexZeroPad(route.tokenMessenger, 32).toLowerCase()
  )
    throw new Error("Wrong destination TokenMessenger");
  if (slice(152, 184) !== pubkeyHex(SOLANA_USDC))
    throw new Error("Burn token must be Solana USDC");
  const depositor = slice(248, 280);
  const hook = utils.hexDataSlice(message, 376);
  if (
    utils.getAddress(utils.hexDataSlice(hook, 0, 20)) !== route.composer ||
    utils.hexDataSlice(hook, 20, 24) !== DEPOSIT_SELECTOR
  )
    throw new Error(
      "Burn hook does not target configured Composer V2 depositAndSend",
    );
  const [refund, amount, sendParam] = utils.defaultAbiCoder.decode(
    ["bytes32", "uint256", SEND_PARAM, "address"],
    utils.hexDataSlice(hook, 24),
  );
  const owner = new PublicKey(utils.arrayify(depositor));
  if (
    refund !== pubkeyHex(getAssociatedTokenAddressSync(SOLANA_USDC, owner)) ||
    sendParam.dstEid !== SOLANA_EID ||
    sendParam.to !== depositor
  )
    throw new Error("Burn receiver/refund must match the Solana owner");
  const amountReceived = uint(216, 248).sub(uint(312, 344));
  if (amountReceived.lte(0) || amount.gt(amountReceived))
    throw new Error("Hook amount exceeds USDC received after CCTP fees");
  return { depositor, amountReceived, nonce: slice(12, 44), sendParam };
}

export function feeFromBps(amount: bigint, bps: string | number): bigint {
  const rate = String(bps);
  if (!/^\d+(\.\d+)?$/.test(rate)) throw new Error("Invalid Circle minimumFee");
  const decimals = rate.split(".")[1]?.length ?? 0;
  const numerator = BigInt(rate.replace(".", ""));
  const denominator = 10_000n * 10n ** BigInt(decimals);
  return (amount * numerator + denominator - 1n) / denominator;
}
