import { describe, it, expect } from "vitest";
import { FHEClient } from "../../src/crypto/fhe.js";
import { FHEInitError } from "../../src/errors/index.js";

describe("FHEClient", () => {
  it("should not be initialized by default", () => {
    const client = new FHEClient();
    expect(client.isInitialized).toBe(false);
  });

  it("should throw on encrypt without configure or initialize", async () => {
    const client = new FHEClient();
    await expect(
      client.encryptAddress("0x1234567890123456789012345678901234567890"),
    ).rejects.toThrow(FHEInitError);
    await expect(
      client.encryptAddress("0x1234567890123456789012345678901234567890"),
    ).rejects.toThrow("no provider/signer configured");
  });

  it("should throw on initialize without provider/signer", async () => {
    const client = new FHEClient();
    await expect(client.initialize()).rejects.toThrow(FHEInitError);
  });

  it("should accept configure() for deferred auto-init", () => {
    const client = new FHEClient();
    // Just verifying it doesn't throw — actual init requires a real provider
    const mockProvider = {} as any;
    const mockSigner = {} as any;
    client.configure(mockProvider, mockSigner);
    expect(client.isInitialized).toBe(false);
  });
});
