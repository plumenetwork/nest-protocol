import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";

import { EndpointId } from "@layerzerolabs/lz-definitions";
import { generateConnectionsConfig } from "@layerzerolabs/metadata-tools";

import buildSolanaLayerZeroConfig from "../../script/solana-layerzero.config";

jest.mock("node:fs", () => ({
  existsSync: jest.fn(),
  mkdirSync: jest.fn(),
  readFileSync: jest.fn(),
  writeFileSync: jest.fn(),
}));

jest.mock("@layerzerolabs/metadata-tools", () => ({
  generateConnectionsConfig: jest.fn(),
}));

const mockedExistsSync = jest.mocked(existsSync);
const mockedMkdirSync = jest.mocked(mkdirSync);
const mockedReadFileSync = jest.mocked(readFileSync);
const mockedWriteFileSync = jest.mocked(writeFileSync);
const mockedGenerateConnectionsConfig = jest.mocked(generateConnectionsConfig);

const BASE_OAPP = "0x1111111111111111111111111111111111111111";

describe("solana LayerZero config", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    process.env.VAULT_SYMBOL = "FACTOR";
    delete process.env.EVM_CHAIN_IDS;
    delete process.env.INCLUDE_ALL_ROUTES;

    mockedExistsSync.mockImplementation((filePath) => {
      const value = String(filePath);
      return (
        value.endsWith("script/deployment-config/vaults/FACTOR.json") ||
        value.endsWith("deployments/solana-mainnet/FACTOR-OFT.json") ||
        value.endsWith("script/output/FACTOR/8453-FACTOR.json") ||
        value.endsWith("script/solana-lz-abi/NestShareOFT.json")
      );
    });
    mockedReadFileSync.mockImplementation((filePath) => {
      const value = String(filePath);
      if (value.endsWith("script/deployment-config/vaults/FACTOR.json")) {
        return JSON.stringify({ peers: [101, 8453] });
      }
      if (value.endsWith("deployments/solana-mainnet/FACTOR-OFT.json")) {
        return JSON.stringify({
          oftStore: "11111111111111111111111111111111",
        });
      }
      if (value.endsWith("script/output/FACTOR/8453-FACTOR.json")) {
        return JSON.stringify({
          baseAssetSymbol: "FACTOR",
          vaultType: "NestShareOFT",
          contracts: { share: BASE_OAPP, vaults: [] },
        });
      }
      if (value.endsWith("script/solana-lz-abi/NestShareOFT.json")) {
        return "[]";
      }
      throw new Error(`unexpected read: ${value}`);
    });
    mockedGenerateConnectionsConfig.mockResolvedValue([]);
  });

  afterAll(() => {
    delete process.env.VAULT_SYMBOL;
    delete process.env.EVM_CHAIN_IDS;
    delete process.env.INCLUDE_ALL_ROUTES;
  });

  it("builds the Base peer and its hardhat-deploy stub", async () => {
    const config = await buildSolanaLayerZeroConfig();

    expect(mockedGenerateConnectionsConfig).toHaveBeenCalledTimes(1);
    const [tuples] = mockedGenerateConnectionsConfig.mock.calls[0];
    expect(tuples[0][0]).toMatchObject({
      eid: EndpointId.BASE_V2_MAINNET,
      address: BASE_OAPP,
    });
    expect(config.contracts[0].contract).toMatchObject({
      eid: EndpointId.BASE_V2_MAINNET,
      address: BASE_OAPP,
    });
    expect(mockedMkdirSync).toHaveBeenCalledWith(
      expect.stringMatching(/deployments\/base$/),
      { recursive: true },
    );
    expect(mockedWriteFileSync).toHaveBeenCalledWith(
      expect.stringMatching(/deployments\/base\/FACTOR\.json$/),
      expect.any(String),
    );
    expect(mockedWriteFileSync).toHaveBeenCalledWith(
      expect.stringMatching(/deployments\/base\/\.chainId$/),
      "8453",
    );
  });
});
