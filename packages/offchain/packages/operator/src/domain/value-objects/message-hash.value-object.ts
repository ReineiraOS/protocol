import { keccak256 } from 'ethers'

export class MessageHash {
  readonly value: string

  constructor(value: string) {
    const normalized = value.toLowerCase()
    if (!/^0x[a-f0-9]{64}$/.test(normalized)) {
      throw new Error(`Invalid message hash: ${value}. Must be 0x followed by 64 hex characters.`)
    }
    this.value = normalized
  }

  static fromMessage(message: string): MessageHash {
    return new MessageHash(keccak256(message))
  }

  equals(other: MessageHash): boolean {
    return this.value === other.value
  }

  toString(): string {
    return this.value
  }
}
