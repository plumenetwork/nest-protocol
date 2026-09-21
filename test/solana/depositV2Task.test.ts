import path from "node:path";
import { BigNumber, utils } from "ethers";
import { Keypair } from "@solana/web3.js";
import { getSolanaKeypair } from "@layerzerolabs/devtools-solana";
import {
  requestAttestation,
  encodeComplianceData,
} from "../../tasks/evm/depositV2";
import { encodePayload } from "../../tasks/evm/predicateV2Payloads";
import {
  buildDepositHook,
  pubkeyHex,
  resolveSolanaDeposit,
  SOLANA_USDC,
} from "../../tasks/solana/cctpDeposit";
import { TOKEN_MESSENGER } from "../../tasks/solana/cctpBurnInstruction";

const mockActions = new Map<string, (args: any, hre: any) => Promise<void>>();
const mockContracts = new Map<string, any>();
const relayOwner = "0x1111111111111111111111111111111111111111";
const mockGenesisHash = jest.fn();
const mockLookupTable = jest.fn();

jest.mock("@solana/web3.js", () => ({
  ...jest.requireActual("@solana/web3.js"),
  Connection: jest.fn(() => ({
    getGenesisHash: mockGenesisHash,
    getAddressLookupTable: mockLookupTable,
  })),
}));

jest.mock("hardhat/config", () => ({
  types: { string: "string" },
  task: (name: string) => {
    const builder = {
      addOptionalParam: () => builder,
      addFlag: () => builder,
      setAction: (action: any) => mockActions.set(name, action),
    };
    return builder;
  },
}));
jest.mock("../../tasks/evm/depositV2", () => ({
  requestAttestation: jest.fn(),
  encodeComplianceData: jest.fn(),
}));
jest.mock("@layerzerolabs/devtools-solana", () => ({
  getSolanaKeypair: jest.fn(),
}));
jest.mock("ethers", () => {
  const actual = jest.requireActual("ethers");
  return {
    ...actual,
    providers: {
      ...actual.providers,
      Web3Provider: jest.fn(() => ({
        getNetwork: async () => ({ chainId: 98866 }),
      })),
    },
    Contract: jest.fn((address: string) => {
      const contract = mockContracts.get(address.toLowerCase());
      if (!contract) throw new Error(`Unexpected contract: ${address}`);
      return contract;
    }),
    Wallet: jest.fn(() => ({ address: relayOwner })),
  };
});

// Register only this task, with all network and signing boundaries mocked.
require("../../tasks/solana/depositV2");
const route = resolveSolanaDeposit(
  path.resolve(__dirname, "../.."),
  "nTEST",
  98866,
);
const owner = Keypair.fromSeed(new Uint8Array(32).fill(7)).publicKey;
const nonce = utils.hexZeroPad("0x01", 32);
const hook = buildDepositHook(route.composer, owner, 1_000_000n, 200n);
const message = utils.solidityPack(
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
    22,
    nonce,
    pubkeyHex(TOKEN_MESSENGER),
    utils.hexZeroPad(route.tokenMessenger, 32),
    utils.hexZeroPad(route.relayer, 32),
    1000,
    1000,
    1,
    pubkeyHex(SOLANA_USDC),
    utils.hexZeroPad(route.relayer, 32),
    1_000_000,
    pubkeyHex(owner),
    200,
    100,
    0,
    hook,
  ],
);
const RELAY = "relay(bytes,bytes,bytes,bytes,bool)";
const relayInterface = new utils.Interface([
  "event HookRelayed(bytes32 nonce)",
]);
const simulate = jest.fn();
const submit = jest.fn();
const connect = jest.fn();
const fetchMock = jest.fn();
const originalFetch = global.fetch;
const originalKey = process.env.PRIVATE_KEY;
let logSpy: jest.SpyInstance;
const args = {
  vault: "nTEST",
  solanaTx: "existing-burn",
  circleApi: "https://circle.example",
  extraOptions: "0x",
  broadcast: false,
};
const run = (overrides = {}) =>
  mockActions.get("nest:predicate-v2:solana-deposit")!(
    { ...args, ...overrides },
    { config: { paths: { root: path.resolve(__dirname, "../..") } } },
  );

beforeEach(() => {
  jest.clearAllMocks();
  mockContracts.clear();
  global.fetch = fetchMock;
  process.env.PRIVATE_KEY = "test-key-never-signed";
  logSpy = jest.spyOn(console, "log").mockImplementation(() => {});
  const auth = {
    owner: async () => relayOwner,
    authority: async () => relayOwner,
  };
  const put = (address: string, contract: any) =>
    mockContracts.set(address.toLowerCase(), { ...auth, ...contract });
  put(relayOwner, { canCall: async () => true });
  put(route.composer, {
    COMPLIANCE_PROXY: async () => route.complianceProxy,
    ASSET_OFT: async () => route.relayer,
    VAULT: async () => route.vaultAddress,
    SHARE_OFT: async () => route.vaultAddress,
  });
  put(route.complianceProxy, {
    complianceHook: async () => route.predicateHook,
    paused: async () => false,
  });
  put(route.predicateHook, {});
  put(route.vaultAddress, {
    peers: async () => pubkeyHex(route.oftStore),
    asset: async () => route.tokenMessenger,
  });
  put(route.tokenMessenger, { allowance: async () => BigNumber.from(1) });
  simulate.mockResolvedValue([true, true]);
  submit.mockResolvedValue({
    hash: "0xrelay",
    wait: async () => ({
      logs: [
        {
          address: route.relayer,
          ...relayInterface.encodeEventLog(
            relayInterface.getEvent("HookRelayed"),
            [nonce],
          ),
        },
      ],
    }),
  });
  connect.mockReturnValue({ [RELAY]: submit });
  put(route.relayer, {
    isComposer: async () => true,
    USDC: async () => route.tokenMessenger,
    quoteRelay: async () => ({ nativeFee: BigNumber.from(123) }),
    callStatic: { [RELAY]: simulate },
    connect,
    interface: relayInterface,
  });
  fetchMock.mockResolvedValue({
    ok: true,
    json: async () => ({
      messages: [{ message, status: "complete", attestation: "0xcafe" }],
    }),
  });
  jest
    .mocked(requestAttestation)
    .mockResolvedValue({ attestation: { fresh: true } } as any);
  jest.mocked(encodeComplianceData).mockReturnValue("0xbeef");
});
afterEach(() => {
  global.fetch = originalFetch;
  if (originalKey === undefined) delete process.env.PRIVATE_KEY;
  else process.env.PRIVATE_KEY = originalKey;
  logSpy.mockRestore();
});

it("requests a fresh composer/on-behalf proof and simulates by default without submitting", async () => {
  await run();
  expect(requestAttestation).toHaveBeenCalledWith({
    predicateHook: route.predicateHook,
    sender: route.composer,
    chain: route.apiChain,
    payload: encodePayload("deposit", route.composer, pubkeyHex(owner)),
    onBehalf: pubkeyHex(owner),
  });
  expect(simulate).toHaveBeenCalledWith(
    message,
    "0xcafe",
    "0xbeef",
    "0x",
    false,
    { from: relayOwner, value: BigNumber.from(123) },
  );
  expect(connect).not.toHaveBeenCalled();
  expect(submit).not.toHaveBeenCalled();
});

it("stops pending Circle messages before requesting a proof", async () => {
  fetchMock.mockResolvedValue({
    ok: true,
    json: async () => ({
      messages: [{ status: "pending", attestation: "PENDING" }],
    }),
  });
  await expect(run()).rejects.toThrow("same --solana-tx");
  expect(requestAttestation).not.toHaveBeenCalled();
  expect(submit).not.toHaveBeenCalled();
});

it("refuses to broadcast a relay whose simulation refunds", async () => {
  simulate.mockResolvedValue([true, false]);
  await expect(run({ broadcast: true })).rejects.toThrow("refund instead");
  expect(submit).not.toHaveBeenCalled();
});

it("recognizes the real non-indexed HookRelayed event after an explicit broadcast", async () => {
  await run({ broadcast: true });
  expect(submit).toHaveBeenCalledTimes(1);
});

it("does not report deposit success for a receipt without HookRelayed", async () => {
  submit.mockResolvedValue({
    hash: "0xrefund",
    wait: async () => ({ logs: [] }),
  });
  await expect(run({ broadcast: true })).rejects.toThrow(
    "did not emit HookRelayed",
  );
});

it("rejects stale live hook configuration before contacting Circle or Predicate", async () => {
  mockContracts.get(route.complianceProxy.toLowerCase()).complianceHook =
    async () => relayOwner;
  await expect(run()).rejects.toThrow("Live route mismatch");
  expect(fetchMock).not.toHaveBeenCalled();
  expect(requestAttestation).not.toHaveBeenCalled();
});

describe("Solana burn cluster guard", () => {
  const burnArgs = {
    solanaTx: undefined,
    amount: "0.01",
    finality: "fast",
    minShares: "0",
    solanaRpc: "https://solana.example",
    lookupTable: "2Hd1BW1xK5wPZB8zKm9Diu9zvadZJSpK47QyP6CbedM6",
  };
  beforeEach(() => {
    jest
      .mocked(getSolanaKeypair)
      .mockResolvedValue(Keypair.fromSeed(new Uint8Array(32).fill(7)));
    fetchMock.mockResolvedValue({
      ok: true,
      json: async () => [{ finalityThreshold: 1000, minimumFee: 2 }],
    });
    mockContracts.get(route.predicateHook.toLowerCase()).callStatic = {
      checkCompliance: async () => true,
    };
    // Stop immediately after the guard; no transaction signing or submission.
    mockLookupTable.mockRejectedValue(
      new Error("Reached lookup-table loading"),
    );
  });

  it("accepts the full genesis hash returned by the mainnet RPC", async () => {
    mockGenesisHash.mockResolvedValue(
      "5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d",
    );
    await expect(run(burnArgs)).rejects.toThrow("Reached lookup-table loading");
    expect(mockLookupTable).toHaveBeenCalledTimes(1);
  });

  it.each([
    "EtWTRABZaYq6iMfeYKouRu166VU2xqa1",
    "5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp",
  ])("rejects a different or truncated genesis hash: %s", async (hash) => {
    mockGenesisHash.mockResolvedValue(hash);
    await expect(run(burnArgs)).rejects.toThrow(
      "Solana RPC must be mainnet-beta",
    );
    expect(mockLookupTable).not.toHaveBeenCalled();
  });
});
