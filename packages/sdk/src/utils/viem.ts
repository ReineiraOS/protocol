import { BrowserProvider } from "ethers";
import type { ethers } from "ethers";

/**
 * Convert a viem WalletClient to an ethers.js Signer.
 *
 * ```ts
 * import { walletClientToSigner } from "@reineira-os/sdk";
 * const signer = await walletClientToSigner(walletClient);
 * const sdk = ReineiraSDK.create({ network: "testnet", signer });
 * ```
 */
export async function walletClientToSigner(walletClient: {
  transport: { url?: string };
  chain?: { id: number };
  account: { address: string };
  request: (...args: unknown[]) => Promise<unknown>;
}): Promise<ethers.Signer> {
  const provider = new BrowserProvider(walletClient as any, walletClient.chain?.id);
  return provider.getSigner(walletClient.account.address);
}

/**
 * Convert a viem PublicClient to an ethers.js Provider.
 *
 * ```ts
 * import { publicClientToProvider } from "@reineira-os/sdk";
 * const provider = publicClientToProvider(publicClient);
 * ```
 */
export function publicClientToProvider(publicClient: {
  transport: { url?: string };
  chain?: { id: number };
}): ethers.Provider {
  return new BrowserProvider(publicClient as any, publicClient.chain?.id);
}
