import { AbiCoder, zeroPadValue } from "ethers";

const coder = AbiCoder.defaultAbiCoder();

export function encodeHookData(escrowId: bigint): string {
  return coder.encode(["uint256"], [escrowId]);
}

export function padAddress(address: string): string {
  return zeroPadValue(address, 32);
}

export function encodeResolverData(types: string[], values: unknown[]): string {
  return coder.encode(types, values);
}
