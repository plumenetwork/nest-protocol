import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { BigNumber, utils } from "ethers";

const PREDICATE_API_URL = "https://api.predicate.io/v1/task";

const DEPOSIT_INTERFACE = new utils.Interface(["function deposit()"]);

const DEPOSIT_ENCODED_FUNCTION_DATA =
  DEPOSIT_INTERFACE.encodeFunctionData("deposit");

const normalizeAddress = (address: string) =>
  utils.getAddress(address).toLowerCase();

type PredicateApiResponse = {
  is_compliant: boolean;
  task_id?: string;
  expiry_block?: number;
  signers?: string[];
  signature?: string[];
  error?: string;
};

type PredicateMessage = {
  taskId: string | null;
  expireByTime: number | null;
  signerAddresses: string[];
  signatures: string[];
};

async function getPredicateCompliance(
  predicateProxyContractAddress: string,
  userAddress: string,
  chainId: number,
): Promise<{
  isCompliant: boolean;
  predicateMessage: PredicateMessage;
}> {
  const encodedArgs = DEPOSIT_ENCODED_FUNCTION_DATA;

  const apiContractAddress = normalizeAddress(predicateProxyContractAddress);
  const user = normalizeAddress(userAddress);

  const predicateApiKey = process.env.PREDICATE_API_KEY;
  if (!predicateApiKey) {
    throw new Error("Predicate API key is not set");
  }

  const payload = {
    from: user,
    chain_id: chainId,
    to: apiContractAddress,
    data: encodedArgs,
    msg_value: "0",
  };

  console.log("[Predicate] Call from hardhat task to predicate API", {
    chainId,
    payload,
  });

  const response = await fetch(PREDICATE_API_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": predicateApiKey,
    },
    body: JSON.stringify(payload),
  });

  const responseText = await response.text();
  let data: PredicateApiResponse | null = null;
  if (responseText) {
    try {
      data = JSON.parse(responseText) as PredicateApiResponse;
    } catch (_error) {
      throw new Error("Predicate API error: invalid JSON response");
    }
  }

  if (!response.ok) {
    const errorMessage =
      data?.error ??
      `Predicate API error (${response.status} ${response.statusText})`;
    throw new Error(errorMessage);
  }

  if (!data) {
    throw new Error("Predicate API error: empty response");
  }

  if (data.error && data.error.length > 0) {
    throw new Error(data.error);
  }
  if (!data.is_compliant) {
    console.warn(
      `Received not compliant response for user: ${user}, contract: ${apiContractAddress} chainId: ${chainId}`,
    );
  }

  return {
    isCompliant: data.is_compliant,
    predicateMessage: {
      taskId: data.task_id ?? null,
      expireByTime: data.expiry_block ?? null,
      signerAddresses: data.signers ?? [],
      signatures: data.signature ?? [],
    },
  };
}

const ERC20_ABI = [
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function decimals() view returns (uint8)",
];
const ERC4626_ABI = ["function asset() view returns (address)"];

const PREDICATE_PROXY_ABI = [
  "function deposit(address asset, uint256 amount, address recipient, address vault, tuple(string taskId, uint256 expireByTime, address[] signerAddresses, bytes[] signatures) predicateMessage) external returns (uint256)",
];

interface DepositArgs {
  predicateProxy: string;
  vault: string;
  amount: string;
  recipient?: string;
  decimals?: number;
  rawAmount?: boolean;
  gasPriceGwei?: string;
}

task(
  "nest:predicate:deposit",
  "Deposit into NestVaultPredicateProxy with predicate authorization",
)
  .addParam(
    "predicateProxy",
    "NestVaultPredicateProxy address",
    "0xfC0c4222B3A0c9B060C0B959DEc62442036b9035",
    types.string,
  )
  .addParam("vault", "NestVault address", undefined, types.string)
  .addParam(
    "amount",
    "Amount to deposit (human readable unless --rawAmount)",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "recipient",
    "Recipient of vault shares (defaults to signer)",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "decimals",
    "Token decimals override (required if decimals() is unavailable)",
    undefined,
    types.int,
  )
  .addOptionalParam(
    "rawAmount",
    "Treat amount as base units (no decimal conversion)",
    false,
    types.boolean,
  )
  .addOptionalParam(
    "gasPriceGwei",
    "Legacy transaction gas price in gwei",
    undefined,
    types.string,
  )
  .setAction(async (args: DepositArgs, hre: HardhatRuntimeEnvironment) => {
    const [signer] = await hre.ethers.getSigners();
    const predicateProxy = utils.getAddress(args.predicateProxy);
    const vault = utils.getAddress(args.vault);
    const recipient = args.recipient
      ? utils.getAddress(args.recipient)
      : signer.address;

    const vaultContract = new hre.ethers.Contract(vault, ERC4626_ABI, signer);
    const asset = utils.getAddress(await vaultContract.asset());
    const erc20 = new hre.ethers.Contract(asset, ERC20_ABI, signer);

    let amountUnits: BigNumber;
    if (args.rawAmount) {
      amountUnits = BigNumber.from(args.amount);
    } else {
      let decimals = args.decimals;
      if (decimals == null) {
        try {
          decimals = await erc20.decimals();
        } catch (error) {
          throw new Error(
            "Failed to read token decimals. Pass --decimals or use --rawAmount.",
          );
        }
      }
      amountUnits = utils.parseUnits(args.amount, decimals);
    }

    const network = await hre.ethers.provider.getNetwork();
    const { isCompliant, predicateMessage } = await getPredicateCompliance(
      predicateProxy,
      signer.address,
      network.chainId,
    );

    if (!isCompliant) {
      throw new Error(
        "Predicate API returned non-compliant response. Aborting deposit.",
      );
    }

    const predicateMessageForContract = {
      taskId: predicateMessage.taskId ?? "",
      expireByTime: predicateMessage.expireByTime ?? 0,
      signerAddresses: predicateMessage.signerAddresses,
      signatures: predicateMessage.signatures,
    };

    const transactionOverrides = args.gasPriceGwei
      ? { gasPrice: utils.parseUnits(args.gasPriceGwei, "gwei") }
      : {};

    const currentAllowance: BigNumber = await erc20.allowance(
      signer.address,
      predicateProxy,
    );
    if (currentAllowance.lt(amountUnits)) {
      const approveTx = await erc20.approve(
        predicateProxy,
        amountUnits,
        transactionOverrides,
      );
      await approveTx.wait();
      console.log(
        `Approved ${args.amount} tokens for deposit (tx: ${approveTx.hash})`,
      );
    } else {
      console.log("Existing allowance is sufficient; skipping approval");
    }

    const predicateProxyContract = new hre.ethers.Contract(
      predicateProxy,
      PREDICATE_PROXY_ABI,
      signer,
    );
    const depositTx = await predicateProxyContract.deposit(
      asset,
      amountUnits,
      recipient,
      vault,
      predicateMessageForContract,
      transactionOverrides,
    );
    const receipt = await depositTx.wait();

    const parsedLogs = receipt.logs
      .map((log) => {
        try {
          return predicateProxyContract.interface.parseLog(log);
        } catch {
          return null;
        }
      })
      .filter((log) => log?.name === "Deposit");

    if (parsedLogs.length > 0) {
      const depositLog = parsedLogs[0];
      console.log("Shares minted:", depositLog?.args?.shareAmount?.toString());
    }

    console.log("Deposit tx hash:", receipt.transactionHash);
  });
