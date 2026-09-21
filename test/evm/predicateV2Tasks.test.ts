import { utils } from "ethers";

import {
  encodePayload,
  toBytes32Identity,
} from "../../tasks/evm/predicateV2Payloads";

describe("Predicate V2 task payloads", () => {
  const sender = "0xc28e1cDfB582953fEf53f76C64426c2aC79C716e";

  it("encodes every direct policy flow", () => {
    expect(encodePayload("deposit", sender)).toBe(
      new utils.Interface(["function deposit()"]).encodeFunctionData("deposit"),
    );
    expect(encodePayload("accessCheck", sender)).toBe(
      new utils.Interface(["function accessCheck(address)"]).encodeFunctionData(
        "accessCheck",
        [sender],
      ),
    );
    expect(encodePayload("requestRedeem", sender)).toBe(
      new utils.Interface(["function requestRedeem()"]).encodeFunctionData(
        "requestRedeem",
      ),
    );
    expect(encodePayload("instantRedeem", sender)).toBe(
      new utils.Interface(["function instantRedeem()"]).encodeFunctionData(
        "instantRedeem",
      ),
    );
  });

  it("encodes EVM and Solana initiators for on-behalf flows", () => {
    const evm = "0xe05f529f5284d75624eba386cb716928c3b54a2a";
    const solana = "Fc1EwQUZyTEagaDvA1utHXCcZNyG1x2PLt2DfNu1cJdH";
    const evmIdentity = toBytes32Identity(evm);
    const solanaIdentity = toBytes32Identity(solana);

    expect(evmIdentity).toBe(
      "0x000000000000000000000000e05f529f5284d75624eba386cb716928c3b54a2a",
    );
    expect(solanaIdentity).toBe(
      "0xd8fb378dbe54d3d1794ee77fa65df31195bb30c9433e1d8000c9822d9a43dbd4",
    );
    expect(encodePayload("deposit", sender, solanaIdentity)).toBe(
      new utils.Interface(["function deposit(bytes32)"]).encodeFunctionData(
        "deposit",
        [solanaIdentity],
      ),
    );
    expect(encodePayload("accessCheck", sender, evmIdentity)).toBe(
      new utils.Interface(["function accessCheck(bytes32)"]).encodeFunctionData(
        "accessCheck",
        [evmIdentity],
      ),
    );
  });

  it("rejects non-32-byte base58 values instead of changing the identity", () => {
    expect(() =>
      toBytes32Identity("qWWra8ombzaw6VHrG5xpQ972jCYF6bbHiFCbWmr4U"),
    ).toThrow("32-byte Solana public key");
  });
});
