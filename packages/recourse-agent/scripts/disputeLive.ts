import { Contract, JsonRpcProvider, Wallet } from "ethers";
import { settleWithVerdict } from "../src/relayer.js";

const RPC = process.env.RPC ?? "https://sepolia-rollup.arbitrum.io/rpc";
const USDC = "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d";

const CM = required("COVERAGE_MANAGER");
const POLICY = required("VERDICT_POLICY");
const COVERAGE_ID = BigInt(required("COVERAGE_ID"));
const AMOUNT = BigInt(process.env.COVERAGE_AMOUNT ?? "100000");

function required(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`missing env ${name}`);
  return v;
}

const provider = new JsonRpcProvider(RPC);
const net = await provider.getNetwork();
const holder = new Wallet(required("CLIENT_PK"), provider);
const verdictSigner = new Wallet(required("VERDICT_SIGNER_PK"), provider);

const usdc = new Contract(USDC, ["function balanceOf(address) view returns (uint256)"], provider);
const before: bigint = await usdc.balanceOf(holder.address);

console.log("judge: deadline missed (deliveredAt=null) => breach; signing verdict off-chain (ethers)...");
const res = await settleWithVerdict({
  coverageManager: CM,
  policy: POLICY,
  chainId: net.chainId,
  coverageId: COVERAGE_ID,
  amount: AMOUNT,
  nonce: 1n,
  issuedAt: Math.floor(Date.now() / 1000),
  fields: { deadline: 1, deliveredAt: null },
  verdictSigner,
  holder,
});

const after: bigint = await usdc.balanceOf(holder.address);

console.log("relayer submitted dispute as holder:", holder.address);
console.log("dispute tx  :", `https://sepolia.arbiscan.io/tx/${res.txHash}`);
console.log("client USDC :", before.toString(), "->", after.toString(), `(+${(after - before).toString()})`);

if (after - before !== AMOUNT) {
  console.error(`payout mismatch: expected +${AMOUNT}, got +${after - before}`);
  process.exit(1);
}
console.log("OK: JS judge signed the verdict, JS relayer disputed as holder, real USDC paid on-chain.");
