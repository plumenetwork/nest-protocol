import path from "node:path";
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";

import { resolvePredicateV2Deployment } from "../../tasks/evm/predicateV2Config";

describe("Predicate V2 deployment config", () => {
  const repoRoot = path.resolve(__dirname, "../..");
  let fixtureRoot: string;

  beforeEach(() => {
    fixtureRoot = mkdtempSync(path.join(tmpdir(), "nest-compliance-"));
    for (const file of [
      "script/deployment-config/vaults/nTEST.json",
      "script/deployment-config/compliance/98866-nTEST.json",
      "config/compliance/98866.json",
    ]) {
      mkdirSync(path.dirname(path.join(fixtureRoot, file)), {
        recursive: true,
      });
      writeFileSync(
        path.join(fixtureRoot, file),
        readFileSync(path.join(repoRoot, file)),
      );
    }
  });

  afterEach(() => rmSync(fixtureRoot, { recursive: true, force: true }));

  it("resolves nTEST addresses from the active chain", () => {
    expect(
      resolvePredicateV2Deployment(
        path.resolve(__dirname, "../.."),
        "nTEST",
        98866,
      ),
    ).toEqual({
      symbol: "nTEST",
      chainId: 98866,
      assetSymbol: "USDC",
      vaultAddress: "0x802E1f92A6890430bCF350Ad553C936fA425266c",
      complianceProxy: "0xF325E0f939963b42A22538B98b30E1CAeB2C37bA",
      predicateHook: "0xe1CD2F46B5aC47F5c65158a53116A0f413f4Ce4f",
      apiChain: "plume",
    });
  });

  it("reads the API chain from the shared compliance config", () => {
    writeFileSync(
      path.join(fixtureRoot, "config/compliance/98866.json"),
      JSON.stringify({ chainId: 98866, v2: { apiChain: "shared-chain" } }),
    );
    expect(
      resolvePredicateV2Deployment(fixtureRoot, "nTEST", 98866).apiChain,
    ).toBe("shared-chain");
  });

  it("rejects a shared compliance config for a different chain", () => {
    writeFileSync(
      path.join(fixtureRoot, "config/compliance/98866.json"),
      JSON.stringify({ chainId: 1, v2: { apiChain: "ethereum" } }),
    );
    expect(() =>
      resolvePredicateV2Deployment(fixtureRoot, "nTEST", 98866),
    ).toThrow(
      "Common compliance config chain mismatch: expected 98866, received 1",
    );
  });

  it("rejects an unconfigured V2 API chain", () => {
    writeFileSync(
      path.join(fixtureRoot, "config/compliance/98866.json"),
      JSON.stringify({ chainId: 98866, v2: { apiChain: "" } }),
    );
    expect(() =>
      resolvePredicateV2Deployment(fixtureRoot, "nTEST", 98866),
    ).toThrow("Common compliance config for chain 98866 has no v2.apiChain");
  });
});
