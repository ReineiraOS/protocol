import { Contract, JsonRpcProvider } from "ethers";
import { SequentialNonceWallet } from "./utils/sequential-nonce-wallet.js";
import type { ethers } from "ethers";
import { FHEClient } from "./crypto/fhe.js";
import { EscrowModule } from "./modules/escrow.js";
import { RecourseModule } from "./modules/recourse.js";
import { BridgeModule } from "./modules/bridge.js";
import { EventsModule } from "./modules/events.js";
import { PlainEscrowModule } from "./modules/escrow-plain.js";
import { PlainRecourseModule } from "./modules/recourse-plain.js";
import { getAddresses } from "./constants/addresses.js";
import { FHERC20_ABI, ERC20_ABI } from "./constants/abis.js";
import { usdc, formatUsdc } from "./utils/amounts.js";
import type {
  SDKConfig,
  SDKConfigWithKey,
  SDKConfigWithSigner,
  NetworkAddresses,
  TokenBalances,
} from "./types/index.js";
import { ValidationError } from "./errors/index.js";

function isKeyConfig(config: SDKConfig): config is SDKConfigWithKey {
  return "privateKey" in config;
}

export class ReineiraSDK {
  public readonly escrow: EscrowModule;
  public readonly recourse: RecourseModule;
  public readonly bridge: BridgeModule;
  public readonly events: EventsModule;
  /** Plain (non-FHE) escrow — mainnet launch path. */
  public readonly escrowPlain: PlainEscrowModule;
  /** Plain (non-FHE) recourse — mainnet launch path. */
  public readonly recoursePlain: PlainRecourseModule;
  public readonly addresses: NetworkAddresses;
  public readonly signer: ethers.Signer;
  public readonly provider: ethers.Provider;

  private readonly fhe: FHEClient;

  private constructor(
    signer: ethers.Signer,
    provider: ethers.Provider,
    addresses: NetworkAddresses,
  ) {
    this.signer = signer;
    this.provider = provider;
    this.addresses = addresses;
    this.fhe = new FHEClient();

    this.escrow = new EscrowModule(signer, this.fhe, addresses);
    this.recourse = new RecourseModule(signer, this.fhe, addresses);
    this.bridge = new BridgeModule(addresses);
    this.events = new EventsModule(provider, addresses);
    this.escrowPlain = new PlainEscrowModule(signer, addresses);
    this.recoursePlain = new PlainRecourseModule(signer, addresses);

    this.escrow.setRecourseModule(this.recourse);
    this.escrow.setBridgeModule(this.bridge);
  }

  private setCoordinatorUrl(url: string): void {
    this.bridge.setCoordinatorUrl(url);
  }

  static create(config: SDKConfig): ReineiraSDK {
    const addresses = { ...getAddresses(config.network), ...config.addresses };

    let sdk: ReineiraSDK;

    if (isKeyConfig(config)) {
      const provider = new JsonRpcProvider(config.rpcUrl);
      const signer = new SequentialNonceWallet(config.privateKey, provider);
      sdk = new ReineiraSDK(signer, provider, addresses);
    } else {
      const signerConfig = config as SDKConfigWithSigner;
      const provider = signerConfig.provider ?? signerConfig.signer.provider;
      if (!provider) {
        throw new ValidationError(
          "SDKConfig with signer requires either a provider or a signer with an attached provider.",
        );
      }
      sdk = new ReineiraSDK(signerConfig.signer, provider, addresses);
    }

    // Wire FHE with progress callback
    sdk.fhe.configure(sdk.provider, sdk.signer, config.onFHEInit);

    if (config.coordinatorUrl) {
      sdk.setCoordinatorUrl(config.coordinatorUrl);
    }

    return sdk;
  }

  async initialize(): Promise<void> {
    await this.fhe.initialize();
  }

  get initialized(): boolean {
    return this.fhe.isInitialized;
  }

  // ─── Amount helpers ───────────────────────────────────────

  /**
   * Convert human-readable USDC to base units (6 decimals).
   * ```ts
   * sdk.usdc(1000)   // → 1000_000000n
   * sdk.usdc(0.5)    // → 500000n
   * ```
   */
  usdc(amount: number | string): bigint {
    return usdc(amount);
  }

  /**
   * Format base-unit USDC to human-readable string.
   * ```ts
   * sdk.formatUsdc(1000_000000n)  // → "1,000.00"
   * ```
   */
  formatUsdc(baseUnits: bigint): string {
    return formatUsdc(baseUnits);
  }

  // ─── Balance / Approval ───────────────────────────────────

  async balances(address?: string): Promise<TokenBalances> {
    const target = address ?? (await this.signer.getAddress());

    const cUsdcContract = new Contract(this.addresses.confidentialUSDC, FHERC20_ABI, this.provider);
    const usdcContract = new Contract(this.addresses.usdc, ERC20_ABI, this.provider);

    const [confidentialUSDC, usdcBal, eth] = await Promise.all([
      cUsdcContract.confidentialBalanceOf(target) as Promise<bigint>,
      usdcContract.balanceOf(target) as Promise<bigint>,
      this.provider.getBalance(target),
    ]);

    return { confidentialUSDC, usdc: usdcBal, eth };
  }

  async isOperatorApproved(spender: string, holder?: string): Promise<boolean> {
    const target = holder ?? (await this.signer.getAddress());
    const cUsdcContract = new Contract(this.addresses.confidentialUSDC, FHERC20_ABI, this.provider);
    return cUsdcContract.isOperator(target, spender);
  }
}
