import { describe, it, expect, beforeAll } from "vitest";
import { ReineiraSDK } from "../../src/index.js";
import { encodeHookData, padAddress } from "../../src/utils/encoding.js";
import {
  CCTP_ETHEREUM_SEPOLIA,
  CCTP_ARBITRUM_SEPOLIA_DOMAIN,
} from "../../src/constants/addresses.js";

const PRIVATE_KEY = process.env.PRIVATE_KEY;
const RPC_URL = process.env.ARBITRUM_SEPOLIA_RPC_URL;
const ETH_SEPOLIA_RPC = process.env.ETH_SEPOLIA_RPC_URL;
const SOURCE_PRIVATE_KEY = process.env.SOURCE_PRIVATE_KEY;

describe.skipIf(!PRIVATE_KEY || !RPC_URL)("Cross-Chain CCTP Flows (integration)", () => {
  let sdk: ReineiraSDK;
  let signerAddress: string;

  beforeAll(async () => {
    sdk = ReineiraSDK.create({
      network: "testnet",
      privateKey: PRIVATE_KEY!,
      rpcUrl: RPC_URL!,
    });
    await sdk.initialize();
    signerAddress = await sdk.signer.getAddress();
  });

  describe("CCTP Encoding", () => {
    it("should encode hook data for an escrow ID", () => {
      const hookData = encodeHookData(42n);
      expect(hookData).toBeTruthy();
      expect(hookData.startsWith("0x")).toBe(true);
      expect(hookData.length).toBe(66);
    });

    it("should pad escrow receiver address to 32 bytes", () => {
      const padded = padAddress(sdk.addresses.escrowReceiver);
      expect(padded.length).toBe(66);
    });

    it("should have correct CCTP constants", () => {
      expect(CCTP_ARBITRUM_SEPOLIA_DOMAIN).toBe(3);
      expect(CCTP_ETHEREUM_SEPOLIA.domain).toBe(0);
    });
  });

  describe.skipIf(!ETH_SEPOLIA_RPC || !SOURCE_PRIVATE_KEY)(
    "Cross-Chain Fund (Ethereum Sepolia -> Arbitrum Sepolia)",
    () => {
      it("should create escrow and fund cross-chain", async () => {
        const escrow = await sdk.escrow.create({
          amount: sdk.usdc(1),
          owner: signerAddress,
        });

        const result = await escrow.fund(sdk.usdc(1), {
          crossChain: {
            sourceRpc: ETH_SEPOLIA_RPC!,
            sourcePrivateKey: SOURCE_PRIVATE_KEY!,
          },
        });

        expect(result.tx.hash).toBeTruthy();
      }, 120_000);
    },
  );
});
