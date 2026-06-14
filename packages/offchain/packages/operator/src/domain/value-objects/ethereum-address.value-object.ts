export class EthereumAddress {
  readonly value: string

  constructor(value: string) {
    const normalized = value.toLowerCase()
    if (!/^0x[a-f0-9]{40}$/.test(normalized)) {
      throw new Error(
        `Invalid Ethereum address: ${value}. Must be 0x followed by 40 hex characters.`,
      )
    }
    this.value = normalized
  }

  equals(other: EthereumAddress): boolean {
    return this.value === other.value
  }

  toString(): string {
    return this.value
  }
}
