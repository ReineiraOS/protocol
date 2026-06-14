import type { ethers } from "ethers";
import { FHEInitError, EncryptionError } from "../errors/index.js";

export type FHEInitCallback = (status: "starting" | "done" | "error") => void;

let cachedClient: any = null;

export function injectCofhe(client: any) {
  cachedClient = client;
  _cofheInjected = true;
}

/** @internal */
export let _cofheInjected = false;

async function loadSdk(): Promise<{
  createCofheConfig: (cfg: unknown) => unknown;
  createCofheClient: (cfg: unknown) => any;
  Encryptable: {
    address: (v: string) => unknown;
    uint64: (v: bigint) => unknown;
  };
  arbSepolia: unknown;
  Ethers6Adapter: (
    provider: unknown,
    signer: unknown,
  ) => Promise<{ publicClient: unknown; walletClient: unknown }>;
}> {
  const sdk: any =
    typeof require !== "undefined" ? require("@cofhe/sdk/node") : await import("@cofhe/sdk/node");
  const core: any =
    typeof require !== "undefined" ? require("@cofhe/sdk") : await import("@cofhe/sdk");
  const chains: any =
    typeof require !== "undefined"
      ? require("@cofhe/sdk/chains")
      : await import("@cofhe/sdk/chains");
  const adapters: any =
    typeof require !== "undefined"
      ? require("@cofhe/sdk/adapters")
      : await import("@cofhe/sdk/adapters");

  return {
    createCofheConfig: sdk.createCofheConfig,
    createCofheClient: sdk.createCofheClient,
    Encryptable: core.Encryptable,
    arbSepolia: chains.arbSepolia,
    Ethers6Adapter: adapters.Ethers6Adapter,
  };
}

export class FHEClient {
  private initialized = false;
  private initPromise: Promise<void> | null = null;
  private provider: ethers.Provider | null = null;
  private signer: ethers.Signer | null = null;
  private onInit: FHEInitCallback | null = null;

  configure(provider: ethers.Provider, signer: ethers.Signer, onInit?: FHEInitCallback): void {
    this.provider = provider;
    this.signer = signer;
    this.onInit = onInit ?? null;
  }

  async initialize(provider?: ethers.Provider, signer?: ethers.Signer): Promise<void> {
    if (this.initialized) return;

    const p = provider ?? this.provider;
    const s = signer ?? this.signer;
    if (!p || !s) {
      throw new FHEInitError("FHE cannot initialize: no provider/signer configured.");
    }

    if (!this.initPromise) {
      this.initPromise = this.doInit(p, s);
    }
    await this.initPromise;
  }

  get isInitialized(): boolean {
    return this.initialized;
  }

  async encryptAddress(address: string): Promise<unknown> {
    await this.autoInit();
    try {
      const { Encryptable } = await loadSdk();
      const client = this.requireClient();
      const result = await client.encryptInputs([Encryptable.address(address)]).execute();
      if (!result || !Array.isArray(result) || result.length === 0) {
        throw new EncryptionError("Failed to encrypt address: empty result");
      }
      return result[0];
    } catch (error) {
      if (error instanceof EncryptionError) throw error;
      throw new EncryptionError(
        `Failed to encrypt address: ${error instanceof Error ? error.message : String(error)}`,
        error,
      );
    }
  }

  async encryptUint64(value: bigint): Promise<unknown> {
    await this.autoInit();
    try {
      const { Encryptable } = await loadSdk();
      const client = this.requireClient();
      const result = await client.encryptInputs([Encryptable.uint64(value)]).execute();
      if (!result || !Array.isArray(result) || result.length === 0) {
        throw new EncryptionError("Failed to encrypt uint64: empty result");
      }
      return result[0];
    } catch (error) {
      if (error instanceof EncryptionError) throw error;
      throw new EncryptionError(
        `Failed to encrypt uint64: ${error instanceof Error ? error.message : String(error)}`,
        error,
      );
    }
  }

  private async autoInit(): Promise<void> {
    if (this.initialized || _cofheInjected) return;
    if (!this.provider || !this.signer) {
      throw new FHEInitError(
        "FHE not initialized and no provider/signer configured. Call sdk.initialize() first.",
      );
    }
    await this.initialize();
  }

  private requireClient(): any {
    if (cachedClient) return cachedClient;
    throw new FHEInitError("FHE client not connected. Call sdk.initialize() first.");
  }

  private async doInit(provider: ethers.Provider, signer: ethers.Signer): Promise<void> {
    this.onInit?.("starting");
    try {
      const { createCofheConfig, createCofheClient, arbSepolia, Ethers6Adapter } = await loadSdk();
      const { publicClient, walletClient } = await Ethers6Adapter(provider, signer);
      const client = createCofheClient(createCofheConfig({ supportedChains: [arbSepolia] }));
      await client.connect(publicClient, walletClient);
      cachedClient = client;
      this.initialized = true;
      this.onInit?.("done");
    } catch (error) {
      this.initPromise = null;
      this.onInit?.("error");
      if (error instanceof FHEInitError) throw error;
      throw new FHEInitError(
        `FHE initialization failed: ${error instanceof Error ? error.message : String(error)}`,
        error,
      );
    }
  }
}
