import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { BridgeModule } from "../../src/modules/bridge.js";
import { TESTNET_ADDRESSES } from "../../src/constants/addresses.js";
import { ValidationError, TransactionFailedError } from "../../src/errors/index.js";

describe("BridgeModule", () => {
  let bridge: BridgeModule;
  let fetchSpy: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    bridge = new BridgeModule(TESTNET_ADDRESSES);
    fetchSpy = vi.fn();
    vi.stubGlobal("fetch", fetchSpy);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  describe("submitToCoordinator", () => {
    it("should throw if coordinatorUrl not set", async () => {
      await expect(bridge.submitToCoordinator("0xabc")).rejects.toThrow(ValidationError);
    });

    it("should POST with transactionHash (not txHash)", async () => {
      bridge.setCoordinatorUrl("https://coordinator.example.com");

      fetchSpy.mockResolvedValue({
        ok: true,
        json: async () => ({ id: "task-123", status: "queued", message: "ok" }),
      });

      const taskId = await bridge.submitToCoordinator("0xdeadbeef");
      expect(taskId).toBe("task-123");

      const body = JSON.parse(fetchSpy.mock.calls[0][1].body);
      expect(body.transactionHash).toBe("0xdeadbeef");
      expect(body.txHash).toBeUndefined();
      expect(body.sourceChainId).toBe(11155111);
      expect(body.destinationChainId).toBeUndefined();
    });

    it("should strip trailing slash from URL", async () => {
      bridge.setCoordinatorUrl("https://coord.example.com///");
      fetchSpy.mockResolvedValue({
        ok: true,
        json: async () => ({ id: "t-1", status: "queued", message: "ok" }),
      });

      await bridge.submitToCoordinator("0x123");
      expect(fetchSpy.mock.calls[0][0]).toBe("https://coord.example.com/bridges/cctp/transactions");
    });

    it("should throw on non-OK response", async () => {
      bridge.setCoordinatorUrl("https://coordinator.example.com");
      fetchSpy.mockResolvedValue({ ok: false, status: 500, text: async () => "err" });

      await expect(bridge.submitToCoordinator("0xabc")).rejects.toThrow(TransactionFailedError);
    });
  });

  describe("checkHealth", () => {
    it("should return not reachable if no coordinatorUrl", async () => {
      const health = await bridge.checkHealth();
      expect(health.reachable).toBe(false);
      expect(health.connectedOperators).toBe(0);
    });

    it("should parse subscribedCount from coordinator stats", async () => {
      bridge.setCoordinatorUrl("https://coordinator.example.com");
      fetchSpy.mockResolvedValue({
        ok: true,
        json: async () => ({ subscribedCount: 3, operators: ["0xa", "0xb", "0xc"] }),
      });

      const health = await bridge.checkHealth();
      expect(health.reachable).toBe(true);
      expect(health.connectedOperators).toBe(3);
      expect(health.operators).toEqual(["0xa", "0xb", "0xc"]);
    });

    it("should handle unreachable coordinator gracefully", async () => {
      bridge.setCoordinatorUrl("https://coordinator.example.com");
      fetchSpy.mockRejectedValue(new Error("ECONNREFUSED"));

      const health = await bridge.checkHealth();
      expect(health.reachable).toBe(false);
      expect(health.connectedOperators).toBe(0);
    });
  });

  describe("isCoordinatorConfigured", () => {
    it("should be false by default", () => {
      expect(bridge.isCoordinatorConfigured).toBe(false);
    });

    it("should be true after setCoordinatorUrl", () => {
      bridge.setCoordinatorUrl("https://coordinator.example.com");
      expect(bridge.isCoordinatorConfigured).toBe(true);
    });
  });
});
