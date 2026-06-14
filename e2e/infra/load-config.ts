import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

export interface E2EConfig {
  rpcUrl: string;
  chainId: number;
  privateKey: string;
  deployer: string;
  addresses: {
    usdc: string;
    plainEscrow: string;
    plainEscrowReceiver: string;
    plainPolicyRegistry: string;
    plainCoverageManager: string;
    plainPoolFactory: string;
    plainUnderwriterPolicy: string;
  };
}

export function loadConfig(): E2EConfig {
  const path = resolve(__dirname, "..", ".addresses.local.json");
  try {
    const raw = readFileSync(path, "utf-8");
    return JSON.parse(raw) as E2EConfig;
  } catch (err) {
    throw new Error(
      `Cannot read ${path}. Did you start anvil + deploy? Run e2e/run.sh.\n${(err as Error).message}`,
    );
  }
}
