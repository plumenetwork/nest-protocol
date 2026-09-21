import { task, types } from "hardhat/config";
import { BigNumber, Contract, providers, utils, Wallet } from "ethers";
import {
  Connection,
  ComputeBudgetProgram,
  Keypair,
  PublicKey,
  TransactionMessage,
  VersionedTransaction,
} from "@solana/web3.js";
import {
  createAssociatedTokenAccountIdempotentInstruction,
  getAssociatedTokenAddressSync,
} from "@solana/spl-token";
import { getSolanaKeypair } from "@layerzerolabs/devtools-solana";
import { requestAttestation, encodeComplianceData } from "../evm/depositV2";
import { encodePayload } from "../evm/predicateV2Payloads";
import { buildBurnInstruction } from "./cctpBurnInstruction";
import {
  buildDepositHook,
  feeFromBps,
  pubkeyHex,
  resolveSolanaDeposit,
  SOLANA_DOMAIN,
  SOLANA_EID,
  SolanaDepositRoute,
  validateDepositMessage,
} from "./cctpDeposit";

const RELAY = "relay(bytes,bytes,bytes,bytes,bool)";
const RELAYER_ABI = [
  "function isComposer(address) view returns(bool)",
  "function USDC() view returns(address)",
  "function owner() view returns(address)",
  "function authority() view returns(address)",
  "function quoteRelay(bytes,bytes,bytes) view returns(tuple(uint256 nativeFee,uint256 lzTokenFee))",
  `function ${RELAY} payable returns(bool,bool)`,
  "event HookRelayed(bytes32 nonce)",
  "event Refunded(bytes32 nonce)",
];

async function canCall(
  provider: providers.Provider,
  sender: string,
  target: string,
  signature: string,
) {
  const auth = new Contract(
    target,
    [
      "function owner() view returns(address)",
      "function authority() view returns(address)",
    ],
    provider,
  );
  if ((await auth.owner()).toLowerCase() === sender.toLowerCase()) return true;
  const authority = await auth.authority();
  if (BigNumber.from(authority).isZero()) return false;
  return new Contract(
    authority,
    ["function canCall(address,address,bytes4) view returns(bool)"],
    provider,
  ).canCall(sender, target, utils.id(signature).slice(0, 10));
}

export async function preflightSolanaDeposit(
  route: SolanaDepositRoute,
  provider: providers.Provider,
) {
  const composer = new Contract(
    route.composer,
    [
      "function COMPLIANCE_PROXY() view returns(address)",
      "function ASSET_OFT() view returns(address)",
      "function VAULT() view returns(address)",
      "function SHARE_OFT() view returns(address)",
    ],
    provider,
  );
  const proxy = new Contract(
    route.complianceProxy,
    [
      "function complianceHook() view returns(address)",
      "function paused() view returns(bool)",
    ],
    provider,
  );
  const relayer = new Contract(route.relayer, RELAYER_ABI, provider);
  const [proxyAddress, assetOft, vault, shareOft, hook, paused, enabled, usdc] =
    await Promise.all([
      composer.COMPLIANCE_PROXY(),
      composer.ASSET_OFT(),
      composer.VAULT(),
      composer.SHARE_OFT(),
      proxy.complianceHook(),
      proxy.paused(),
      relayer.isComposer(route.composer),
      relayer.USDC(),
    ]);
  for (const [actual, expected] of [
    [proxyAddress, route.complianceProxy],
    [assetOft, route.relayer],
    [vault, route.vaultAddress],
    [hook, route.predicateHook],
  ]) {
    if (utils.getAddress(actual) !== utils.getAddress(expected))
      throw new Error(`Live route mismatch: ${actual} != ${expected}`);
  }
  if (paused || !enabled)
    throw new Error("ComplianceProxy is paused or Composer V2 is not enabled");
  const oft = new Contract(
    shareOft,
    ["function peers(uint32) view returns(bytes32)"],
    provider,
  );
  if ((await oft.peers(SOLANA_EID)) !== pubkeyHex(route.oftStore))
    throw new Error("Live OFT Solana peer differs from deployment config");
  const vaultAsset = await new Contract(
    route.vaultAddress,
    ["function asset() view returns(address)"],
    provider,
  ).asset();
  if (utils.getAddress(vaultAsset) !== utils.getAddress(usdc))
    throw new Error("Vault asset differs from CCTP USDC");
  const token = new Contract(
    usdc,
    ["function allowance(address,address) view returns(uint256)"],
    provider,
  );
  for (const [owner, spender] of [
    [route.relayer, route.composer],
    [route.composer, route.complianceProxy],
  ]) {
    if ((await token.allowance(owner, spender)).isZero())
      throw new Error(`Missing USDC approval: ${owner} -> ${spender}`);
  }
  const hops = [
    [
      route.relayer,
      route.composer,
      "depositAndSend(bytes32,uint256,(uint32,bytes32,uint256,uint256,bytes,bytes,bytes),address)",
    ],
    [
      route.composer,
      route.complianceProxy,
      "depositOnBehalf(address,address,uint256,address,bytes32,bytes)",
    ],
    [
      route.complianceProxy,
      route.predicateHook,
      "checkCompliance(address,bytes,bytes)",
    ],
    [route.complianceProxy, route.vaultAddress, "deposit(uint256,address)"],
    [
      route.composer,
      shareOft,
      "send((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),(uint256,uint256),address)",
    ],
  ];
  for (const [sender, target, signature] of hops) {
    if (!(await canCall(provider, sender, target, signature)))
      throw new Error(
        `Missing permission: ${sender} -> ${target} ${signature}`,
      );
  }
  return relayer;
}

async function circleJson(base: string, pathname: string) {
  const response = await fetch(`${base.replace(/\/$/, "")}/${pathname}`, {
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok)
    throw new Error(
      `Circle HTTP ${response.status}; retry with the same --solana-tx after attestation is ready`,
    );
  return response.json();
}

type Args = {
  vault: string;
  amount?: string;
  finality: string;
  maxFee?: string;
  minShares: string;
  solanaRpc?: string;
  lookupTable: string;
  solanaTx?: string;
  circleApi: string;
  extraOptions: string;
  relayFrom?: string;
  broadcast: boolean;
};

task(
  "nest:predicate-v2:solana-deposit",
  "Simulate or submit a Solana CCTP burn, then relay it through Composer V2 / depositOnBehalf",
)
  .addOptionalParam("vault", "Configured vault symbol", "nTEST", types.string)
  .addOptionalParam(
    "amount",
    "USDC to burn, human units (e.g. 1.25)",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "finality",
    "CCTP fast or standard",
    "standard",
    types.string,
  )
  .addOptionalParam(
    "maxFee",
    "USDC fee cap, human units; defaults to Circle quote",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "minShares",
    "Minimum raw share units after vault fees",
    "0",
    types.string,
  )
  .addOptionalParam(
    "solanaRpc",
    "Solana mainnet RPC; defaults to SOLANA_RPC_URL",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "lookupTable",
    "Solana CCTP lookup table (plume-hub default)",
    "2Hd1BW1xK5wPZB8zKm9Diu9zvadZJSpK47QyP6CbedM6",
    types.string,
  )
  .addOptionalParam(
    "solanaTx",
    "Existing Solana burn signature; selects Plume relay instead of another burn",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "circleApi",
    "Circle Iris API base",
    "https://iris-api.circle.com",
    types.string,
  )
  .addOptionalParam(
    "extraOptions",
    "LayerZero return-hop options",
    "0x",
    types.string,
  )
  .addOptionalParam(
    "relayFrom",
    "eth_call sender for relay simulation; defaults to relayer owner",
    undefined,
    types.string,
  )
  .addFlag("broadcast", "Submit the selected phase; default is simulation")
  .setAction(async (args: Args, hre) => {
    const provider = new providers.Web3Provider({
      request: ({ method, params }) =>
        hre.network.provider.send(method, params),
    });
    const route = resolveSolanaDeposit(
      hre.config.paths.root,
      args.vault,
      (await provider.getNetwork()).chainId,
    );
    const relayer = await preflightSolanaDeposit(route, provider);
    console.log("Solana Predicate V2 route", {
      composer: route.composer,
      relayer: route.relayer,
      complianceProxy: route.complianceProxy,
      hook: route.predicateHook,
    });
    if (args.solanaTx) {
      if (args.amount || args.maxFee)
        throw new Error(
          "--solana-tx resumes a burn; omit --amount and --max-fee",
        );
      const response = await circleJson(
        args.circleApi,
        `v2/messages/${SOLANA_DOMAIN}?transactionHash=${encodeURIComponent(args.solanaTx)}`,
      );
      const messages = response.messages ?? [];
      if (messages.length !== 1)
        throw new Error(
          "Expected exactly one CCTP message for the Solana transaction",
        );
      const { message, attestation: circleAttestation, status } = messages[0];
      if (
        status !== "complete" ||
        !utils.isHexString(circleAttestation) ||
        circleAttestation === "0x"
      )
        throw new Error(
          "Circle attestation is pending; rerun with the same --solana-tx",
        );
      const decoded = validateDepositMessage(message, route);
      const key = process.env.PRIVATE_KEY;
      if (args.broadcast && !key)
        throw new Error("PRIVATE_KEY is required for Plume relay broadcast");
      const signer = args.broadcast
        ? new Wallet(key!.startsWith("0x") ? key! : `0x${key}`, provider)
        : undefined;
      const relayFrom =
        signer?.address ??
        utils.getAddress(args.relayFrom ?? (await relayer.owner()));
      if (
        args.broadcast &&
        args.relayFrom &&
        utils.getAddress(args.relayFrom) !== signer!.address
      )
        throw new Error("--relay-from differs from PRIVATE_KEY signer");
      if (!(await canCall(provider, relayFrom, route.relayer, RELAY)))
        throw new Error(`Relay caller ${relayFrom} is not authorized`);
      // The statement sender is the composer, never the relay EOA or CCTP relayer.
      const { attestation } = await requestAttestation({
        predicateHook: route.predicateHook,
        sender: route.composer,
        chain: route.apiChain,
        payload: encodePayload("deposit", route.composer, decoded.depositor),
        onBehalf: decoded.depositor,
      });
      const proof = encodeComplianceData(attestation);
      const fee = await relayer.quoteRelay(message, proof, args.extraOptions);
      const callArgs = [
        message,
        circleAttestation,
        proof,
        args.extraOptions,
        false,
      ];
      const result = await relayer.callStatic[RELAY](...callArgs, {
        from: relayFrom,
        value: fee.nativeFee,
      });
      if (!result[0] || !result[1])
        throw new Error("Relay simulation would refund instead of depositing");
      console.log("Plume relay simulation passed", {
        depositor: decoded.depositor,
        relayFrom,
        nativeFee: fee.nativeFee.toString(),
      });
      if (!signer) return;
      const tx = await relayer
        .connect(signer)
        [RELAY](...callArgs, { value: fee.nativeFee });
      console.log("Plume relay submitted:", tx.hash);
      const receipt = await tx.wait();
      const success = receipt.logs.some(
        (log: providers.Log) =>
          log.address.toLowerCase() === route.relayer.toLowerCase() &&
          log.topics[0] === relayer.interface.getEventTopic("HookRelayed") &&
          relayer.interface.parseLog(log).args.nonce === decoded.nonce,
      );
      if (!success)
        throw new Error(
          `Relay ${tx.hash} did not emit HookRelayed; inspect receipt for refund`,
        );
      console.log(
        "Deposit relayed; track Solana share delivery:",
        `https://layerzeroscan.com/tx/${tx.hash}`,
      );
      return;
    }

    if (!args.amount)
      throw new Error(
        "Provide --amount for a new burn, or --solana-tx to relay an existing burn",
      );
    if (args.finality !== "fast" && args.finality !== "standard")
      throw new Error("--finality must be fast or standard");
    if (!/^\d+$/.test(args.minShares))
      throw new Error("--min-shares must be raw non-negative integer units");
    const amount = BigInt(utils.parseUnits(args.amount, 6).toString());
    const finalityThreshold = args.finality === "fast" ? 1000 : 2000;
    const rows = await circleJson(
      args.circleApi,
      `v2/burn/USDC/fees/${SOLANA_DOMAIN}/${route.destinationDomain}`,
    );
    const row = rows.find(
      (value: { finalityThreshold: number }) =>
        value.finalityThreshold === finalityThreshold,
    );
    if (!row)
      throw new Error("Circle has no fee quote for the requested finality");
    const minimumFee = feeFromBps(amount, row.minimumFee);
    const maxFee =
      args.maxFee === undefined
        ? minimumFee
        : BigInt(utils.parseUnits(args.maxFee, 6).toString());
    if (maxFee < minimumFee)
      throw new Error("--max-fee is below Circle's current minimum");
    const wallet = await getSolanaKeypair();
    const hookData = buildDepositHook(
      route.composer,
      wallet.publicKey,
      amount,
      maxFee,
      BigInt(args.minShares),
    );
    // Check this exact composer/owner policy before burning. Request another proof
    // during relay because this one may expire while Circle attests the burn.
    const { attestation: preBurnAttestation } = await requestAttestation({
      predicateHook: route.predicateHook,
      sender: route.composer,
      chain: route.apiChain,
      payload: encodePayload(
        "deposit",
        route.composer,
        pubkeyHex(wallet.publicKey),
      ),
      onBehalf: pubkeyHex(wallet.publicKey),
    });
    const hook = new Contract(
      route.predicateHook,
      ["function checkCompliance(address,bytes,bytes) returns(bool)"],
      provider,
    );
    const compliant = await hook.callStatic.checkCompliance(
      route.composer,
      encodePayload("deposit", route.composer, pubkeyHex(wallet.publicKey)),
      encodeComplianceData(preBurnAttestation),
      { from: route.complianceProxy },
    );
    if (!compliant)
      throw new Error("Predicate hook rejected the pre-burn attestation");
    const rpcUrl = args.solanaRpc ?? process.env.SOLANA_RPC_URL;
    if (!rpcUrl) throw new Error("--solana-rpc or SOLANA_RPC_URL is required");
    const connection = new Connection(rpcUrl, "confirmed");
    const genesisHash = await connection.getGenesisHash();
    if (genesisHash !== "5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d")
      throw new Error(
        `Solana RPC must be mainnet-beta; received genesis hash ${genesisHash}`,
      );
    const eventAccount = Keypair.generate();
    const shareAta = getAssociatedTokenAddressSync(
      route.shareMint,
      wallet.publicKey,
    );
    const instructions = [
      ComputeBudgetProgram.setComputeUnitLimit({ units: 150_000 }),
      createAssociatedTokenAccountIdempotentInstruction(
        wallet.publicKey,
        shareAta,
        wallet.publicKey,
        route.shareMint,
      ),
      buildBurnInstruction({
        owner: wallet.publicKey,
        eventAccount: eventAccount.publicKey,
        relayer: route.relayer,
        destinationDomain: route.destinationDomain,
        amount,
        maxFee,
        finalityThreshold,
        hookData,
      }),
    ];
    const lookup = (
      await connection.getAddressLookupTable(new PublicKey(args.lookupTable))
    ).value;
    if (!lookup) throw new Error("CCTP address lookup table not found");
    const latest = await connection.getLatestBlockhash();
    const tx = new VersionedTransaction(
      new TransactionMessage({
        payerKey: wallet.publicKey,
        recentBlockhash: latest.blockhash,
        instructions,
      }).compileToV0Message([lookup]),
    );
    tx.sign([wallet, eventAccount]);
    if (tx.serialize().length > 1232)
      throw new Error(
        "Solana transaction exceeds 1232 bytes; update the CCTP lookup table",
      );
    const simulation = await connection.simulateTransaction(tx, {
      sigVerify: true,
    });
    if (simulation.value.err)
      throw new Error(
        `Solana simulation failed: ${JSON.stringify(simulation.value.err)}\n${simulation.value.logs?.join("\n")}`,
      );
    console.log("Solana burn simulation passed", {
      owner: wallet.publicKey.toBase58(),
      amount: amount.toString(),
      maxFee: maxFee.toString(),
      hookData,
    });
    if (!args.broadcast) return;
    const signature = await connection.sendTransaction(tx, {
      skipPreflight: false,
    });
    console.log("Solana burn submitted:", signature);
    console.log(
      `Resume after Circle attests: pnpm hardhat nest:predicate-v2:solana-deposit --network plumephoenix --vault ${args.vault} --solana-tx ${signature} --broadcast`,
    );
    const confirmation = await connection.confirmTransaction(
      { ...latest, signature },
      "confirmed",
    );
    if (confirmation.value.err)
      throw new Error(
        `Solana burn failed: ${JSON.stringify(confirmation.value.err)}`,
      );
  });
