import {
  TransactionBuilder,
  TransactionBuilderSendAndConfirmOptions,
  Umi,
} from "@metaplex-foundation/umi";
import { SendTransactionError } from "@solana/web3.js";
import { backOff } from "exponential-backoff";

const INIT_OFT_SEND_ATTEMPTS = 5;

/**
 * A sendTransaction RPC rejection with an empty signature happened before
 * broadcast. This includes stale minContextSlot and preflight simulation
 * failures. Once a signature exists, confirmation is ambiguous and retrying
 * could submit the instruction twice.
 */
export const isEmptySignaturePreflightFailure = (error: unknown): boolean => {
  if (!(error instanceof SendTransactionError)) {
    return false;
  }
  return (error as unknown as { signature?: unknown }).signature === "";
};

export const sendAndConfirmInitOft = async (
  txBuilder: TransactionBuilder,
  umi: Umi,
  minContextSlot?: number,
) =>
  backOff(
    () =>
      txBuilder.sendAndConfirm(umi, {
        send: {
          minContextSlot,
        },
      } satisfies TransactionBuilderSendAndConfirmOptions),
    {
      maxDelay: 4_000,
      numOfAttempts: INIT_OFT_SEND_ATTEMPTS,
      retry: (error, attemptNumber) => {
        const retry = isEmptySignaturePreflightFailure(error);
        if (retry) {
          console.warn(
            `InitOft was rejected before broadcast; retrying send (${attemptNumber}/${INIT_OFT_SEND_ATTEMPTS - 1})`,
          );
        }
        return retry;
      },
      startingDelay: 500,
    },
  );
