import { task, types } from "hardhat/config";
import { BigNumber, Contract, providers, Signer, utils } from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { resolvePredicateV2Deployment } from "./predicateV2Config";
import { encodePayload, toBytes32Identity } from "./predicateV2Payloads";
import type { Flow } from "./predicateV2Payloads";

export { encodePayload, toBytes32Identity } from "./predicateV2Payloads";
export type { Flow } from "./predicateV2Payloads";

/**
 * Predicate V2 tooling for the ComplianceProxy + PredicateV2Hook stack.
 *
 *  - `nest:predicate-v2:attest`  requests an attestation and simulates
 *    `PredicateV2Hook.checkCompliance` with `from = ComplianceProxy` (eth_call
 *    does not spend the UUID). Use it to validate dashboard registration and
 *    the policy before any governance batch is executed.
 *  - `nest:predicate-v2:deposit` requests an attestation and deposits through
 *    `ComplianceProxy.deposit` or, with `--on-behalf`, `depositOnBehalf`.
 *  - `nest:predicate-v2:access-check` tests direct and relayed access checks.
 *  - `nest:predicate-v2:request-redeem` and `instant-redeem` exercise the two
 *    compliance-gated redemption entrypoints.
 *
 * Attestations are one-time and short-lived: request them right before the
 * transaction and never reuse one.
 */

const DEFAULT_PREDICATE_API_URL = "https://api.predicate.io/v2/attestation";
/** Request field carrying the represented user; Predicate is finalizing the name. */
const ON_BEHALF_FIELD = process.env.PREDICATE_V2_ON_BEHALF_FIELD ?? "on_behalf";

type PredicateAttestation = {
  uuid: string;
  expiration: string | number;
  attester: string;
  signature: string;
};

export type PredicateV2Response = {
  is_compliant?: boolean;
  attestation?: PredicateAttestation;
  policy_id?: string;
  policy_name?: string;
  reason?: { code?: string; message?: string };
  error?: string;
};

export class PredicateRejectedError extends Error {
  constructor(
    message: string,
    readonly response: PredicateV2Response,
  ) {
    super(message);
    this.name = "PredicateRejectedError";
  }
}

const ERC20_ABI = [
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function balanceOf(address owner) view returns (uint256)",
  "function decimals() view returns (uint8)",
];
const VAULT_ABI = [
  "function asset() view returns (address)",
  "function share() view returns (address)",
];
const COMPLIANCE_PROXY_ABI = [
  "function deposit(address asset,uint256 amount,address recipient,address vault,bytes complianceData) external returns (uint256)",
  "function depositOnBehalf(address vault,address asset,uint256 amount,address receiver,bytes32 depositor,bytes complianceData) external returns (uint256)",
  "function requestRedeem(uint256 shares,address controller,address vault,bytes complianceData) external returns (uint256)",
  "function instantRedeem(uint256 shares,address receiver,address vault,bytes complianceData) external returns (uint256,uint256)",
  "function complianceHook() view returns (address)",
  "event Deposit(address indexed receiver,address indexed depositAsset,uint256 depositAmount,uint256 shareAmount,uint256 depositTimestamp,address vault)",
  "event RedeemRequest(address indexed owner,address indexed controller,uint256 shareAmount,uint256 requestId,uint256 requestTimestamp,address vault)",
  "event InstantRedeem(address indexed owner,address indexed receiver,uint256 shareAmount,uint256 postFeeAmount,uint256 feeAmount,uint256 redeemTimestamp,address vault)",
];
const HOOK_ABI = [
  "function checkCompliance(address sender,bytes payload,bytes complianceData) external returns (bool)",
  "function getPolicyID() view returns (string)",
  "function getRegistry() view returns (address)",
];

export function encodeComplianceData(
  attestation: PredicateAttestation,
): string {
  return utils.defaultAbiCoder.encode(
    ["tuple(string uuid,uint256 expiration,address attester,bytes signature)"],
    [
      [
        attestation.uuid,
        attestation.expiration,
        attestation.attester,
        attestation.signature,
      ],
    ],
  );
}

export async function requestAttestation(args: {
  predicateHook: string;
  sender: string;
  chain: string;
  payload: string;
  onBehalf?: string;
  apiUrl?: string;
}): Promise<{
  attestation: PredicateAttestation;
  response: PredicateV2Response;
}> {
  const apiKey = process.env.PREDICATE_API_KEY;
  if (!apiKey) throw new Error("PREDICATE_API_KEY is not set");

  const body: Record<string, string> = {
    from: utils.getAddress(args.sender).toLowerCase(),
    to: utils.getAddress(args.predicateHook).toLowerCase(),
    chain: args.chain,
    data: args.payload,
    msg_value: "0",
    ...(args.onBehalf ? { [ON_BEHALF_FIELD]: args.onBehalf } : {}),
  };
  console.log("[PredicateV2] request", body);

  const response = await fetch(
    args.apiUrl ??
      process.env.PREDICATE_V2_API_URL ??
      DEFAULT_PREDICATE_API_URL,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-api-key": apiKey },
      body: JSON.stringify(body),
    },
  );

  const responseText = await response.text();
  let result: PredicateV2Response = {};
  if (responseText) {
    try {
      result = JSON.parse(responseText) as PredicateV2Response;
    } catch {
      throw new Error(
        `Predicate API returned invalid JSON (${response.status})`,
      );
    }
  }
  if (!response.ok) {
    throw new Error(
      result.error ??
        `Predicate API error (${response.status} ${response.statusText})`,
    );
  }
  console.log("[PredicateV2] response", {
    is_compliant: result.is_compliant,
    policy_id: result.policy_id,
    policy_name: result.policy_name,
    reason: result.reason,
    attestation: result.attestation,
  });
  if (!result.is_compliant) {
    const reason =
      result.reason?.message ??
      result.reason?.code ??
      "policy returned non-compliant";
    throw new PredicateRejectedError(
      `Predicate rejected the request: ${reason}`,
      result,
    );
  }
  if (!result.attestation)
    throw new Error("Predicate response did not include an attestation");
  return { attestation: result.attestation, response: result };
}

type PredicateV2ContextArgs = {
  vault?: string;
  complianceProxy?: string;
  predicateHook?: string;
  chain?: string;
};

type PredicateV2Context = {
  vault?: string;
  complianceProxy: string;
  predicateHook: string;
  chain: string;
};

async function resolvePredicateV2Context(
  hre: HardhatRuntimeEnvironment,
  args: PredicateV2ContextArgs,
): Promise<PredicateV2Context> {
  const network = await hre.ethers.provider.getNetwork();
  const deployment =
    args.vault && !utils.isAddress(args.vault)
      ? resolvePredicateV2Deployment(
          hre.config.paths.root,
          args.vault,
          network.chainId,
        )
      : undefined;
  const complianceProxy = utils.getAddress(
    args.complianceProxy ??
      deployment?.complianceProxy ??
      (() => {
        throw new Error(
          "--compliance-proxy is required unless --vault is a configured symbol",
        );
      })(),
  );
  const predicateHook = utils.getAddress(
    args.predicateHook ??
      deployment?.predicateHook ??
      (() => {
        throw new Error(
          "--predicate-hook is required unless --vault is a configured symbol",
        );
      })(),
  );
  const vault = args.vault
    ? utils.getAddress(deployment?.vaultAddress ?? args.vault)
    : undefined;
  const chain = args.chain ?? deployment?.apiChain ?? "plume";

  if (deployment) {
    console.log("[PredicateV2] resolved deployment", {
      symbol: deployment.symbol,
      chainId: deployment.chainId,
      assetSymbol: deployment.assetSymbol,
      vault,
      complianceProxy,
      predicateHook,
      apiChain: chain,
    });
  }

  return { vault, complianceProxy, predicateHook, chain };
}

function requireVault(context: PredicateV2Context): string {
  if (!context.vault) throw new Error("--vault is required");
  return context.vault;
}

function parseFlow(value: string): Flow {
  if (
    value === "deposit" ||
    value === "accessCheck" ||
    value === "requestRedeem" ||
    value === "instantRedeem"
  ) {
    return value;
  }
  throw new Error(
    `flow must be deposit, accessCheck, requestRedeem, or instantRedeem; received ${value}`,
  );
}

type RpcProvider = {
  send(method: string, params: unknown[]): Promise<unknown>;
};

/** eth_call of `hook.checkCompliance` with `from = ComplianceProxy`; does not spend the UUID. */
async function simulateCheckCompliance(
  hre: HardhatRuntimeEnvironment,
  args: {
    predicateHook: string;
    complianceProxy: string;
    sender: string;
    payload: string;
    complianceData: string;
  },
): Promise<boolean> {
  const hookInterface = new utils.Interface(HOOK_ABI);
  const data = hookInterface.encodeFunctionData("checkCompliance", [
    args.sender,
    args.payload,
    args.complianceData,
  ]);
  const provider = hre.ethers.provider as unknown as RpcProvider;
  try {
    const raw = (await provider.send("eth_call", [
      { from: args.complianceProxy, to: args.predicateHook, data },
      "latest",
    ])) as string;
    const [ok] = hookInterface.decodeFunctionResult(
      "checkCompliance",
      raw,
    ) as unknown as [boolean];
    console.log("[PredicateV2] checkCompliance simulation:", ok);
    return ok;
  } catch (error) {
    console.error(
      "[PredicateV2] checkCompliance simulation reverted:",
      (error as Error).message,
    );
    return false;
  }
}

interface AttestArgs {
  vault?: string;
  complianceProxy?: string;
  predicateHook?: string;
  flow: string;
  chain?: string;
  sender?: string;
  onBehalf?: string;
  apiUrl?: string;
  expectRejected: boolean;
}

task(
  "nest:predicate-v2:attest",
  "Request a Predicate V2 attestation and simulate PredicateV2Hook.checkCompliance from the ComplianceProxy",
)
  .addOptionalParam(
    "complianceProxy",
    "ComplianceProxy override (resolved when --vault is a symbol)",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "predicateHook",
    "PredicateV2Hook override (resolved when --vault is a symbol)",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "vault",
    "Vault symbol (for example nTEST); optional with both address overrides",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "flow",
    "deposit | accessCheck | requestRedeem | instantRedeem",
    "deposit",
    types.string,
  )
  .addOptionalParam(
    "chain",
    "Predicate API chain name override",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "sender",
    "API `from`: direct user, or relayer for on-behalf checks (defaults to signer)",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "onBehalf",
    "Original user/Predicate initiator (EVM, bytes32, or Solana); deposit and accessCheck only",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "apiUrl",
    "Predicate V2 API URL override",
    undefined,
    types.string,
  )
  .addFlag(
    "expectRejected",
    "Succeed only if Predicate returns is_compliant=false",
  )
  .setAction(async (args: AttestArgs, hre: HardhatRuntimeEnvironment) => {
    const [signer] = await hre.ethers.getSigners();
    const sender = utils.getAddress(args.sender ?? (await signer.getAddress()));
    const flow = parseFlow(args.flow);
    if (args.onBehalf && flow !== "deposit" && flow !== "accessCheck") {
      throw new Error(
        `--on-behalf is not supported by the ${flow} policy payload`,
      );
    }
    const { predicateHook, complianceProxy, chain } =
      await resolvePredicateV2Context(hre, args);
    const onBehalf = args.onBehalf
      ? toBytes32Identity(args.onBehalf)
      : undefined;
    const payload = encodePayload(flow, sender, onBehalf);

    const signerV5 = signer as unknown as Signer;
    const hook = new Contract(predicateHook, HOOK_ABI, signerV5);
    console.log("[PredicateV2] hook policyID:", await hook.getPolicyID());
    console.log("[PredicateV2] hook registry:", await hook.getRegistry());
    const proxy = new Contract(complianceProxy, COMPLIANCE_PROXY_ABI, signerV5);
    const activeHook: string = await proxy.complianceHook();
    console.log(
      "[PredicateV2] ComplianceProxy.complianceHook():",
      activeHook,
      activeHook.toLowerCase() === predicateHook.toLowerCase()
        ? "(active)"
        : "(NOT the active hook — attestation targets a staged hook)",
    );

    let attestation: PredicateAttestation;
    try {
      ({ attestation } = await requestAttestation({
        predicateHook,
        sender,
        chain,
        payload,
        onBehalf,
        apiUrl: args.apiUrl,
      }));
    } catch (error) {
      if (args.expectRejected && error instanceof PredicateRejectedError) {
        console.log("[PredicateV2] expected rejection confirmed", {
          code: error.response.reason?.code,
          message: error.response.reason?.message,
        });
        return;
      }
      throw error;
    }
    if (args.expectRejected) {
      throw new Error(
        "Expected Predicate to reject the request, but it returned is_compliant=true",
      );
    }
    const complianceData = encodeComplianceData(attestation);
    console.log("[PredicateV2] payload:", payload);
    console.log("[PredicateV2] complianceData:", complianceData);

    const ok = await simulateCheckCompliance(hre, {
      predicateHook,
      complianceProxy,
      sender,
      payload,
      complianceData,
    });
    if (!ok)
      throw new Error("checkCompliance simulation failed (see revert above)");
  });

interface DepositV2Args {
  complianceProxy?: string;
  predicateHook?: string;
  vault: string;
  amount: string;
  chain?: string;
  recipient?: string;
  onBehalf?: string;
  decimals?: number;
  rawAmount: boolean;
  simulate: boolean;
  apiUrl?: string;
}

task(
  "nest:predicate-v2:deposit",
  "Request a Predicate V2 attestation and deposit through ComplianceProxy (deposit or depositOnBehalf)",
)
  .addOptionalParam(
    "complianceProxy",
    "ComplianceProxy address override (resolved when --vault is a symbol)",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "predicateHook",
    "PredicateV2Hook address override (resolved when --vault is a symbol)",
    undefined,
    types.string,
  )
  .addParam(
    "vault",
    "Vault symbol (for example nTEST) or NestVault address",
    undefined,
    types.string,
  )
  .addParam(
    "amount",
    "Amount to deposit (human-readable unless --raw-amount)",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "chain",
    "Predicate API chain name override",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "recipient",
    "Share recipient (defaults to signer)",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "onBehalf",
    "Represented user (EVM address, bytes32, or 32-byte Base58/Solana public key). Routes through depositOnBehalf",
    undefined,
    types.string,
  )
  .addOptionalParam("decimals", "Asset decimals override", undefined, types.int)
  .addOptionalParam(
    "apiUrl",
    "Predicate V2 API URL override",
    undefined,
    types.string,
  )
  .addFlag("rawAmount", "Treat amount as base units")
  .addFlag(
    "simulate",
    "eth_call the deposit instead of broadcasting (does not spend the attestation)",
  )
  .setAction(async (args: DepositV2Args, hre: HardhatRuntimeEnvironment) => {
    const [signer] = await hre.ethers.getSigners();
    const signerV5 = signer as unknown as Signer;
    const signerAddress = await signer.getAddress();
    const context = await resolvePredicateV2Context(hre, args);
    const { complianceProxy, predicateHook, chain } = context;
    const vault = requireVault(context);
    const recipient = args.recipient
      ? utils.getAddress(args.recipient)
      : signerAddress;
    const onBehalf = args.onBehalf
      ? toBytes32Identity(args.onBehalf)
      : undefined;

    const vaultContract = new Contract(vault, VAULT_ABI, signerV5);
    const asset = utils.getAddress(await vaultContract.asset());
    const assetContract = new Contract(asset, ERC20_ABI, signerV5);

    let amount: BigNumber;
    if (args.rawAmount) {
      amount = BigNumber.from(args.amount);
    } else {
      const decimals = args.decimals ?? (await assetContract.decimals());
      amount = utils.parseUnits(args.amount, decimals);
    }

    const allowance: BigNumber = await assetContract.allowance(
      signerAddress,
      complianceProxy,
    );
    if (allowance.lt(amount) && !args.simulate) {
      const approval = await assetContract.approve(complianceProxy, amount);
      await approval.wait();
      console.log("Approval tx:", approval.hash);
    }

    // Request the short-lived, one-time attestation only after token approval is ready.
    const payload = encodePayload("deposit", signerAddress, onBehalf);
    const { attestation } = await requestAttestation({
      predicateHook,
      sender: signerAddress,
      chain,
      payload,
      onBehalf,
      apiUrl: args.apiUrl,
    });
    const complianceData = encodeComplianceData(attestation);

    const proxy = new Contract(complianceProxy, COMPLIANCE_PROXY_ABI, signerV5);
    const call = onBehalf
      ? {
          name: "depositOnBehalf",
          args: [vault, asset, amount, recipient, onBehalf, complianceData],
        }
      : {
          name: "deposit",
          args: [asset, amount, recipient, vault, complianceData],
        };
    console.log(
      `[PredicateV2] ComplianceProxy.${call.name}`,
      call.args.map(String),
    );

    if (args.simulate) {
      const shares: BigNumber = await proxy.callStatic[call.name](...call.args);
      console.log("Simulated shares:", shares.toString());
      return;
    }

    const tx = await proxy[call.name](...call.args);
    const receipt = await tx.wait();
    const deposit = receipt.logs
      .map((log: providers.Log) => {
        try {
          return proxy.interface.parseLog(log);
        } catch {
          return null;
        }
      })
      .find((log: utils.LogDescription | null) => log?.name === "Deposit");

    if (deposit)
      console.log("Shares minted:", deposit.args.shareAmount.toString());
    console.log("Deposit tx:", receipt.transactionHash);
  });

interface AccessCheckV2Args {
  vault: string;
  complianceProxy?: string;
  predicateHook?: string;
  chain?: string;
  initiator?: string;
  relayer?: string;
  apiUrl?: string;
  expectRejected: boolean;
}

task(
  "nest:predicate-v2:access-check",
  "Test Predicate V2 accessCheck(address) or relayed accessCheck(bytes32) without spending the attestation",
)
  .addParam(
    "vault",
    "Vault symbol (for example nTEST)",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "complianceProxy",
    "ComplianceProxy address override",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "predicateHook",
    "PredicateV2Hook address override",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "chain",
    "Predicate API chain name override",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "initiator",
    "Original user (defaults to signer; EVM, bytes32, or Solana when --relayer is set)",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "relayer",
    "Executing EVM address/API `from`; setting it selects accessCheck(bytes32)",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "apiUrl",
    "Predicate V2 API URL override",
    undefined,
    types.string,
  )
  .addFlag(
    "expectRejected",
    "Succeed only if Predicate returns is_compliant=false",
  )
  .setAction(
    async (args: AccessCheckV2Args, hre: HardhatRuntimeEnvironment) => {
      const [signer] = await hre.ethers.getSigners();
      const signerAddress = await signer.getAddress();
      const initiator = args.initiator ?? signerAddress;
      const sender = args.relayer
        ? utils.getAddress(args.relayer)
        : utils.getAddress(initiator);
      const onBehalf = args.relayer ? initiator : undefined;

      console.log("[PredicateV2] access-check subjects", {
        initiator,
        relayer: args.relayer ? sender : undefined,
        mode: args.relayer ? "accessCheck(bytes32)" : "accessCheck(address)",
      });

      await hre.run("nest:predicate-v2:attest", {
        vault: args.vault,
        complianceProxy: args.complianceProxy,
        predicateHook: args.predicateHook,
        chain: args.chain,
        flow: "accessCheck",
        sender,
        onBehalf,
        apiUrl: args.apiUrl,
        expectRejected: args.expectRejected,
      });
    },
  );

interface RedeemV2Args {
  complianceProxy?: string;
  predicateHook?: string;
  vault: string;
  amount: string;
  chain?: string;
  controller?: string;
  receiver?: string;
  decimals?: number;
  rawAmount: boolean;
  simulate: boolean;
  apiUrl?: string;
}

async function prepareRedeem(
  args: RedeemV2Args,
  hre: HardhatRuntimeEnvironment,
): Promise<{
  signer: Signer;
  signerAddress: string;
  complianceProxy: string;
  predicateHook: string;
  vault: string;
  chain: string;
  amount: BigNumber;
}> {
  const [hreSigner] = await hre.ethers.getSigners();
  const signer = hreSigner as unknown as Signer;
  const signerAddress = await hreSigner.getAddress();
  const context = await resolvePredicateV2Context(hre, args);
  const { complianceProxy, predicateHook, chain } = context;
  const vault = requireVault(context);
  const vaultContract = new Contract(vault, VAULT_ABI, signer);
  const share = utils.getAddress(await vaultContract.share());
  const shareContract = new Contract(share, ERC20_ABI, signer);
  const amount = args.rawAmount
    ? BigNumber.from(args.amount)
    : utils.parseUnits(
        args.amount,
        args.decimals ?? (await shareContract.decimals()),
      );
  if (amount.isZero()) throw new Error("amount must be greater than zero");

  const balance: BigNumber = await shareContract.balanceOf(signerAddress);
  if (balance.lt(amount)) {
    throw new Error(
      `Insufficient share balance: have ${balance.toString()}, need ${amount.toString()}`,
    );
  }

  const allowance: BigNumber = await shareContract.allowance(
    signerAddress,
    complianceProxy,
  );
  if (allowance.lt(amount)) {
    if (args.simulate) {
      throw new Error(
        `Simulation requires an existing share allowance of at least ${amount.toString()} for ComplianceProxy`,
      );
    }
    const approval = await shareContract.approve(complianceProxy, amount);
    await approval.wait();
    console.log("Share approval tx:", approval.hash);
  }

  return {
    signer,
    signerAddress,
    complianceProxy,
    predicateHook,
    vault,
    chain,
    amount,
  };
}

task(
  "nest:predicate-v2:request-redeem",
  "Request a Predicate V2 attestation and call ComplianceProxy.requestRedeem",
)
  .addOptionalParam(
    "complianceProxy",
    "ComplianceProxy address override (resolved when --vault is a symbol)",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "predicateHook",
    "PredicateV2Hook address override (resolved when --vault is a symbol)",
    undefined,
    types.string,
  )
  .addParam(
    "vault",
    "Vault symbol (for example nTEST) or NestVault address",
    undefined,
    types.string,
  )
  .addParam(
    "amount",
    "Shares to request for redemption (human-readable unless --raw-amount)",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "chain",
    "Predicate API chain name override",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "controller",
    "Pending-redeem controller (defaults to signer)",
    undefined,
    types.string,
  )
  .addOptionalParam("decimals", "Share decimals override", undefined, types.int)
  .addOptionalParam(
    "apiUrl",
    "Predicate V2 API URL override",
    undefined,
    types.string,
  )
  .addFlag("rawAmount", "Treat amount as base units")
  .addFlag(
    "simulate",
    "eth_call requestRedeem instead of broadcasting (requires existing share allowance)",
  )
  .setAction(async (args: RedeemV2Args, hre: HardhatRuntimeEnvironment) => {
    const prepared = await prepareRedeem(args, hre);
    const controller = args.controller
      ? utils.getAddress(args.controller)
      : prepared.signerAddress;
    const payload = encodePayload("requestRedeem", prepared.signerAddress);
    const { attestation } = await requestAttestation({
      predicateHook: prepared.predicateHook,
      sender: prepared.signerAddress,
      chain: prepared.chain,
      payload,
      apiUrl: args.apiUrl,
    });
    const complianceData = encodeComplianceData(attestation);
    const proxy = new Contract(
      prepared.complianceProxy,
      COMPLIANCE_PROXY_ABI,
      prepared.signer,
    );
    const callArgs = [
      prepared.amount,
      controller,
      prepared.vault,
      complianceData,
    ];
    console.log("[PredicateV2] ComplianceProxy.requestRedeem", {
      shares: prepared.amount.toString(),
      controller,
      vault: prepared.vault,
    });

    if (args.simulate) {
      const requestId: BigNumber = await proxy.callStatic.requestRedeem(
        ...callArgs,
      );
      console.log("Simulated request ID:", requestId.toString());
      return;
    }

    const tx = await proxy.requestRedeem(...callArgs);
    const receipt = await tx.wait();
    const redeemRequest = receipt.logs
      .map((log: providers.Log) => {
        try {
          return proxy.interface.parseLog(log);
        } catch {
          return null;
        }
      })
      .find(
        (log: utils.LogDescription | null) => log?.name === "RedeemRequest",
      );
    if (redeemRequest)
      console.log("Request ID:", redeemRequest.args.requestId.toString());
    console.log("Request redeem tx:", receipt.transactionHash);
  });

task(
  "nest:predicate-v2:instant-redeem",
  "Request a Predicate V2 attestation and call ComplianceProxy.instantRedeem",
)
  .addOptionalParam(
    "complianceProxy",
    "ComplianceProxy address override (resolved when --vault is a symbol)",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "predicateHook",
    "PredicateV2Hook address override (resolved when --vault is a symbol)",
    undefined,
    types.string,
  )
  .addParam(
    "vault",
    "Vault symbol (for example nTEST) or NestVault address",
    undefined,
    types.string,
  )
  .addParam(
    "amount",
    "Shares to redeem instantly (human-readable unless --raw-amount)",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "chain",
    "Predicate API chain name override",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "receiver",
    "Redeemed-asset receiver (defaults to signer)",
    undefined,
    types.string,
  )
  .addOptionalParam("decimals", "Share decimals override", undefined, types.int)
  .addOptionalParam(
    "apiUrl",
    "Predicate V2 API URL override",
    undefined,
    types.string,
  )
  .addFlag("rawAmount", "Treat amount as base units")
  .addFlag(
    "simulate",
    "eth_call instantRedeem instead of broadcasting (requires existing share allowance)",
  )
  .setAction(async (args: RedeemV2Args, hre: HardhatRuntimeEnvironment) => {
    const prepared = await prepareRedeem(args, hre);
    const receiver = args.receiver
      ? utils.getAddress(args.receiver)
      : prepared.signerAddress;
    const payload = encodePayload("instantRedeem", prepared.signerAddress);
    const { attestation } = await requestAttestation({
      predicateHook: prepared.predicateHook,
      sender: prepared.signerAddress,
      chain: prepared.chain,
      payload,
      apiUrl: args.apiUrl,
    });
    const complianceData = encodeComplianceData(attestation);
    const proxy = new Contract(
      prepared.complianceProxy,
      COMPLIANCE_PROXY_ABI,
      prepared.signer,
    );
    const callArgs = [
      prepared.amount,
      receiver,
      prepared.vault,
      complianceData,
    ];
    console.log("[PredicateV2] ComplianceProxy.instantRedeem", {
      shares: prepared.amount.toString(),
      receiver,
      vault: prepared.vault,
    });

    if (args.simulate) {
      const [postFeeAmount, feeAmount] = (await proxy.callStatic.instantRedeem(
        ...callArgs,
      )) as [BigNumber, BigNumber];
      console.log("Simulated assets after fee:", postFeeAmount.toString());
      console.log("Simulated fee:", feeAmount.toString());
      return;
    }

    const tx = await proxy.instantRedeem(...callArgs);
    const receipt = await tx.wait();
    const instantRedeem = receipt.logs
      .map((log: providers.Log) => {
        try {
          return proxy.interface.parseLog(log);
        } catch {
          return null;
        }
      })
      .find(
        (log: utils.LogDescription | null) => log?.name === "InstantRedeem",
      );
    if (instantRedeem) {
      console.log(
        "Assets after fee:",
        instantRedeem.args.postFeeAmount.toString(),
      );
      console.log("Fee:", instantRedeem.args.feeAmount.toString());
    }
    console.log("Instant redeem tx:", receipt.transactionHash);
  });
