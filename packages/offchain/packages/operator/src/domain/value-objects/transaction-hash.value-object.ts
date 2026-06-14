export class TransactionHash {
  readonly value: string

  constructor(value: string) {
    const normalized = value.toLowerCase()
    if (!/^0x[a-f0-9]{64}$/.test(normalized)) {
      throw new Error(
        `Invalid transaction hash: ${value}. Must be 0x followed by 64 hex characters.`,
      )
    }
    this.value = normalized
  }

  equals(other: TransactionHash): boolean {
    return this.value === other.value
  }

  toString(): string {
    return this.value
  }
}
