import { describe, it, expect } from "vitest";
import { Wallet, JsonRpcProvider } from "ethers";
import { ReineiraSDK } from "../../src/sdk.js";
import { EscrowModule } from "../../src/modules/escrow.js";
import { RecourseModule } from "../../src/modules/recourse.js";
import { BridgeModule } from "../../src/modules/bridge.js";
import { EventsModule } from "../../src/modules/events.js";
import { TESTNET_ADDRESSES } from "../../src/constants/addresses.js";
import { ValidationError } from "../../src/errors/index.js";

const TEST_PRIVATE_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const TEST_RPC = "http://localhost:8545";

describe("ReineiraSDK", () => {
  it("should create from private key config", () => {
    const sdk = ReineiraSDK.create({
      network: "testnet",
      privateKey: TEST_PRIVATE_KEY,
      rpcUrl: TEST_RPC,
    });

    expect(sdk).toBeInstanceOf(ReineiraSDK);
    expect(sdk.escrow).toBeInstanceOf(EscrowModule);
    expect(sdk.recourse).toBeInstanceOf(RecourseModule);
    expect(sdk.bridge).toBeInstanceOf(BridgeModule);
    expect(sdk.events).toBeInstanceOf(EventsModule);
  });

  it("should create from signer config", () => {
    const provider = new JsonRpcProvider(TEST_RPC);
    const signer = new Wallet(TEST_PRIVATE_KEY, provider);

    const sdk = ReineiraSDK.create({ network: "testnet", signer });

    expect(sdk.signer).toBe(signer);
    expect(sdk.provider).toBe(provider);
  });

  it("should throw if signer has no provider", () => {
    const signer = new Wallet(TEST_PRIVATE_KEY);
    expect(() => ReineiraSDK.create({ network: "testnet", signer })).toThrow(ValidationError);
  });

  it("should accept explicit provider with signer", () => {
    const provider = new JsonRpcProvider(TEST_RPC);
    const signer = new Wallet(TEST_PRIVATE_KEY);
    const sdk = ReineiraSDK.create({ network: "testnet", signer, provider });
    expect(sdk.provider).toBe(provider);
  });

  it("should expose testnet addresses", () => {
    const sdk = ReineiraSDK.create({
      network: "testnet",
      privateKey: TEST_PRIVATE_KEY,
      rpcUrl: TEST_RPC,
    });
    expect(sdk.addresses).toStrictEqual(TESTNET_ADDRESSES);
  });

  it("should not be initialized before initialize()", () => {
    const sdk = ReineiraSDK.create({
      network: "testnet",
      privateKey: TEST_PRIVATE_KEY,
      rpcUrl: TEST_RPC,
    });
    expect(sdk.initialized).toBe(false);
  });

  it("should have escrow.build() returning a fresh builder each time", () => {
    const sdk = ReineiraSDK.create({
      network: "testnet",
      privateKey: TEST_PRIVATE_KEY,
      rpcUrl: TEST_RPC,
    });
    expect(sdk.escrow.build()).not.toBe(sdk.escrow.build());
  });

  it("should have escrow.get() returning an EscrowInstance", () => {
    const sdk = ReineiraSDK.create({
      network: "testnet",
      privateKey: TEST_PRIVATE_KEY,
      rpcUrl: TEST_RPC,
    });
    expect(sdk.escrow.get(42n).id).toBe(42n);
  });

  it("should have usdc() and formatUsdc() helpers", () => {
    const sdk = ReineiraSDK.create({
      network: "testnet",
      privateKey: TEST_PRIVATE_KEY,
      rpcUrl: TEST_RPC,
    });
    expect(sdk.usdc(1000)).toBe(1000_000000n);
    expect(sdk.formatUsdc(1000_000000n)).toBe("1,000.00");
  });
});
