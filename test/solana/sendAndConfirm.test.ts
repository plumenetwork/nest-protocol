import { TransactionBuilder, Umi } from "@metaplex-foundation/umi";
import {
  SendTransactionError,
  TransactionExpiredTimeoutError,
} from "@solana/web3.js";

import {
  isEmptySignaturePreflightFailure,
  sendAndConfirmInitOft,
} from "../../tasks/solana/sendAndConfirm";

const asTransactionBuilder = (sendAndConfirm: jest.Mock): TransactionBuilder =>
  ({
    sendAndConfirm,
  }) as unknown as TransactionBuilder;

const umi = {} as Umi;
const success = {
  signature: new Uint8Array([1]),
  result: {
    context: { slot: 101 },
    value: { err: null },
  },
};

describe("sendAndConfirmInitOft", () => {
  it("passes the create-token confirmation slot as minContextSlot", async () => {
    const sendAndConfirm = jest.fn().mockResolvedValue(success);

    await expect(
      sendAndConfirmInitOft(asTransactionBuilder(sendAndConfirm), umi, 100),
    ).resolves.toBe(success);

    expect(sendAndConfirm).toHaveBeenCalledTimes(1);
    expect(sendAndConfirm).toHaveBeenCalledWith(umi, {
      send: {
        minContextSlot: 100,
      },
    });
  });

  it("retries an empty-signature preflight failure", async () => {
    jest.spyOn(console, "warn").mockImplementation();
    const preflightFailure = new SendTransactionError({
      action: "simulate",
      signature: "",
      transactionMessage: "Minimum context slot has not been reached",
    });
    const sendAndConfirm = jest
      .fn()
      .mockRejectedValueOnce(preflightFailure)
      .mockResolvedValueOnce(success);

    await expect(
      sendAndConfirmInitOft(asTransactionBuilder(sendAndConfirm), umi, 100),
    ).resolves.toBe(success);

    expect(sendAndConfirm).toHaveBeenCalledTimes(2);
    expect(isEmptySignaturePreflightFailure(preflightFailure)).toBe(true);
  });

  it("does not retry a confirmation timeout", async () => {
    const timeout = new TransactionExpiredTimeoutError(
      "broadcast-signature",
      30,
    );
    const sendAndConfirm = jest.fn().mockRejectedValue(timeout);

    await expect(
      sendAndConfirmInitOft(asTransactionBuilder(sendAndConfirm), umi, 100),
    ).rejects.toBe(timeout);

    expect(sendAndConfirm).toHaveBeenCalledTimes(1);
    expect(isEmptySignaturePreflightFailure(timeout)).toBe(false);
  });

  it("does not retry a send failure that has a signature", async () => {
    const broadcastFailure = new SendTransactionError({
      action: "send",
      signature: "broadcast-signature",
      transactionMessage: 'Status: ({"err":"failed"})',
    });
    const sendAndConfirm = jest.fn().mockRejectedValue(broadcastFailure);

    await expect(
      sendAndConfirmInitOft(asTransactionBuilder(sendAndConfirm), umi, 100),
    ).rejects.toBe(broadcastFailure);

    expect(sendAndConfirm).toHaveBeenCalledTimes(1);
    expect(isEmptySignaturePreflightFailure(broadcastFailure)).toBe(false);
  });

  it("keeps MABA compatible when there is no create-token slot", async () => {
    const sendAndConfirm = jest.fn().mockResolvedValue(success);

    await sendAndConfirmInitOft(asTransactionBuilder(sendAndConfirm), umi);

    expect(sendAndConfirm).toHaveBeenCalledWith(umi, {
      send: {
        minContextSlot: undefined,
      },
    });
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });
});
