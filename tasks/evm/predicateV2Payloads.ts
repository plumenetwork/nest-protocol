import bs58 from "bs58";
import { utils } from "ethers";

const PAYLOADS = {
  deposit: () =>
    new utils.Interface(["function deposit()"]).encodeFunctionData("deposit"),
  depositOnBehalf: (user: string) =>
    new utils.Interface(["function deposit(bytes32)"]).encodeFunctionData(
      "deposit",
      [user],
    ),
  accessCheck: (user: string) =>
    new utils.Interface(["function accessCheck(address)"]).encodeFunctionData(
      "accessCheck",
      [user],
    ),
  accessCheckOnBehalf: (user: string) =>
    new utils.Interface(["function accessCheck(bytes32)"]).encodeFunctionData(
      "accessCheck",
      [user],
    ),
  requestRedeem: () =>
    new utils.Interface(["function requestRedeem()"]).encodeFunctionData(
      "requestRedeem",
    ),
  instantRedeem: () =>
    new utils.Interface(["function instantRedeem()"]).encodeFunctionData(
      "instantRedeem",
    ),
};

export type Flow =
  | "deposit"
  | "accessCheck"
  | "requestRedeem"
  | "instantRedeem";

/** Converts an EVM address or Solana public key to the bytes32 identity used by on-behalf payloads. */
export function toBytes32Identity(value: string): string {
  if (utils.isAddress(value))
    return utils.hexZeroPad(utils.getAddress(value).toLowerCase(), 32);
  if (utils.isHexString(value, 32)) return value.toLowerCase();

  try {
    const decoded = bs58.decode(value);
    if (decoded.length === 32) return utils.hexlify(decoded).toLowerCase();
  } catch {
    // Fall through to the actionable error below.
  }

  throw new Error(
    `onBehalf must be an EVM address, 32-byte hex identifier, or 32-byte Solana public key, received ${value}`,
  );
}

export function encodePayload(
  flow: Flow,
  sender: string,
  onBehalf?: string,
): string {
  switch (flow) {
    case "deposit":
      return onBehalf ? PAYLOADS.depositOnBehalf(onBehalf) : PAYLOADS.deposit();
    case "accessCheck":
      return onBehalf
        ? PAYLOADS.accessCheckOnBehalf(onBehalf)
        : PAYLOADS.accessCheck(sender);
    case "requestRedeem":
      return PAYLOADS.requestRedeem();
    case "instantRedeem":
      return PAYLOADS.instantRedeem();
  }
}
