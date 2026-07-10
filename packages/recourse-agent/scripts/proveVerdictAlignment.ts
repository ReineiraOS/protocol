import { Contract, id as keccakId, JsonRpcProvider } from "ethers";
import { verdictDigest, verdictDomain, type Verdict } from "../src/verdict.js";

const RPC = process.env.RPC ?? "https://sepolia-rollup.arbitrum.io/rpc";
const POLICY = process.env.POLICY ?? "0x2334B114E70A355698240B5A0467025103Be9fEf";

const ABI = [
  "function hashVerdict((uint256 coverageId,bool breach,uint256 amount,uint256 nonce,uint256 issuedAt,bytes32 termsHash,bytes32 triggerSpecHash) v) view returns (bytes32)",
  "function trustedSigner() view returns (address)",
];

const provider = new JsonRpcProvider(RPC);
const net = await provider.getNetwork();
const policy = new Contract(POLICY, ABI, provider);

const v: Verdict = {
  coverageId: 42n,
  breach: true,
  amount: 100_000n,
  nonce: 7n,
  issuedAt: 1_700_000_000n,
  termsHash: keccakId("skill-terms"),
  triggerSpecHash: keccakId("deadline-missed"),
};

const domain = verdictDomain(net.chainId, POLICY);
const jsDigest = verdictDigest(domain, v);
const onchainDigest: string = await policy.hashVerdict([
  v.coverageId,
  v.breach,
  v.amount,
  v.nonce,
  v.issuedAt,
  v.termsHash,
  v.triggerSpecHash,
]);

console.log("chainId          :", net.chainId.toString());
console.log("policy           :", POLICY);
console.log("trustedSigner    :", await policy.trustedSigner());
console.log("JS EIP-712 digest:", jsDigest);
console.log("on-chain digest  :", onchainDigest);
console.log("MATCH            :", jsDigest === onchainDigest);

if (jsDigest !== onchainDigest) {
  console.error("MISMATCH — off-chain signer domain/struct disagrees with the deployed policy.");
  process.exit(1);
}
console.log("OK: an off-chain JS-signed verdict will be accepted by the deployed VerdictUnderwriterPolicy.");
