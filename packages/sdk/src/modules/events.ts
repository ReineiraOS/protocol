import { Contract } from "ethers";
import type { ethers } from "ethers";
import {
  CONFIDENTIAL_ESCROW_ABI,
  COVERAGE_MANAGER_ABI,
  POOL_FACTORY_ABI,
} from "../constants/abis.js";
import type { NetworkAddresses } from "../types/index.js";

export type EscrowEventName =
  | "EscrowCreated"
  | "EscrowFunded"
  | "EscrowRedeemed"
  | "EscrowBatchRedeemed"
  | "FeeStamped"
  | "FeeDistributed"
  | "CoverageManagerSet";

export type RecourseEventName =
  | "CoveragePurchased"
  | "DisputeFiled"
  | "CoverageClaimed"
  | "CoverageExpired"
  | "PoolCreated";

export type Unsubscribe = () => void;

/**
 * Event subscription module. Listens for contract events via ethers event filters.
 *
 * Usage:
 * ```ts
 * const unsub = sdk.events.onEscrowCreated((escrowId) => {
 *   console.log("New escrow:", escrowId);
 * });
 *
 * // Later:
 * unsub();
 * ```
 */
export class EventsModule {
  private readonly escrowContract: Contract;
  private readonly coverageContract: Contract;
  private readonly factoryContract: Contract;

  constructor(provider: ethers.Provider, addresses: NetworkAddresses) {
    this.escrowContract = new Contract(addresses.escrow, CONFIDENTIAL_ESCROW_ABI, provider);
    this.coverageContract = new Contract(addresses.coverageManager, COVERAGE_MANAGER_ABI, provider);
    this.factoryContract = new Contract(addresses.poolFactory, POOL_FACTORY_ABI, provider);
  }

  /** Listen for new escrow creations. */
  onEscrowCreated(callback: (escrowId: bigint) => void): Unsubscribe {
    const handler = (escrowId: bigint) => callback(escrowId);
    this.escrowContract.on("EscrowCreated", handler);
    return () => {
      this.escrowContract.off("EscrowCreated", handler);
    };
  }

  /** Listen for escrow fund events. */
  onEscrowFunded(
    callback: (escrowId: bigint, payer: string) => void,
    escrowId?: bigint,
  ): Unsubscribe {
    if (escrowId !== undefined) {
      const filter = this.escrowContract.filters.EscrowFunded(escrowId);
      const handler = (escrowId: bigint, payer: string) => callback(escrowId, payer);
      this.escrowContract.on(filter, handler);
      return () => {
        this.escrowContract.off(filter, handler);
      };
    }
    const handler = (escrowId: bigint, payer: string) => callback(escrowId, payer);
    this.escrowContract.on("EscrowFunded", handler);
    return () => {
      this.escrowContract.off("EscrowFunded", handler);
    };
  }

  /** Listen for escrow redemption events. */
  onEscrowRedeemed(callback: (escrowId: bigint) => void, escrowId?: bigint): Unsubscribe {
    if (escrowId !== undefined) {
      const filter = this.escrowContract.filters.EscrowRedeemed(escrowId);
      const handler = (escrowId: bigint) => callback(escrowId);
      this.escrowContract.on(filter, handler);
      return () => {
        this.escrowContract.off(filter, handler);
      };
    }
    const handler = (escrowId: bigint) => callback(escrowId);
    this.escrowContract.on("EscrowRedeemed", handler);
    return () => {
      this.escrowContract.off("EscrowRedeemed", handler);
    };
  }

  /** Listen for coverage purchases. */
  onCoveragePurchased(callback: (coverageId: bigint) => void): Unsubscribe {
    const handler = (coverageId: bigint) => callback(coverageId);
    this.coverageContract.on("CoveragePurchased", handler);
    return () => {
      this.coverageContract.off("CoveragePurchased", handler);
    };
  }

  /** Listen for dispute filings. */
  onDisputeFiled(callback: (coverageId: bigint) => void): Unsubscribe {
    const handler = (coverageId: bigint) => callback(coverageId);
    this.coverageContract.on("DisputeFiled", handler);
    return () => {
      this.coverageContract.off("DisputeFiled", handler);
    };
  }

  /** Listen for new pool creation. Args: poolId, pool, creator, manager, guardian, isOpen. */
  onPoolCreated(
    callback: (
      poolId: bigint,
      pool: string,
      creator: string,
      manager: string,
      guardian: string,
      isOpen: boolean,
    ) => void,
  ): Unsubscribe {
    const handler = (
      poolId: bigint,
      pool: string,
      creator: string,
      manager: string,
      guardian: string,
      isOpen: boolean,
    ) => callback(poolId, pool, creator, manager, guardian, isOpen);
    this.factoryContract.on("PoolCreated", handler);
    return () => {
      this.factoryContract.off("PoolCreated", handler);
    };
  }

  /** Query past escrow events. */
  async queryEscrowEvents(
    eventName: EscrowEventName,
    fromBlock?: number,
    toBlock?: number,
  ): Promise<ethers.Log[]> {
    const filter = this.escrowContract.filters[eventName]();
    return this.escrowContract.queryFilter(filter, fromBlock, toBlock) as Promise<ethers.Log[]>;
  }

  /** Query past recourse events. */
  async queryRecourseEvents(
    eventName: RecourseEventName,
    fromBlock?: number,
    toBlock?: number,
  ): Promise<ethers.Log[]> {
    const contract = eventName === "PoolCreated" ? this.factoryContract : this.coverageContract;
    const filter = contract.filters[eventName]();
    return contract.queryFilter(filter, fromBlock, toBlock) as Promise<ethers.Log[]>;
  }

  /** Remove all event listeners. */
  removeAllListeners(): void {
    this.escrowContract.removeAllListeners();
    this.coverageContract.removeAllListeners();
    this.factoryContract.removeAllListeners();
  }
}
