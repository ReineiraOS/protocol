import { TimeoutError } from "../errors/index.js";
import type { PollOptions } from "../types/index.js";

const DEFAULT_POLL_INTERVAL_MS = 5_000;
const DEFAULT_TIMEOUT_MS = 300_000;

export async function pollUntil(fn: () => Promise<boolean>, options?: PollOptions): Promise<void> {
  const interval = options?.pollIntervalMs ?? DEFAULT_POLL_INTERVAL_MS;
  const timeout = options?.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const deadline = Date.now() + timeout;

  while (Date.now() < deadline) {
    if (await fn()) return;
    await sleep(interval);
  }

  throw new TimeoutError(`Polling timed out after ${timeout}ms`);
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
