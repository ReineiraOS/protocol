export class ChainId {
  readonly value: number

  constructor(value: number) {
    if (!Number.isInteger(value) || value < 0) {
      throw new Error(`Invalid chain ID: ${value}. Must be a non-negative integer.`)
    }
    this.value = value
  }

  equals(other: ChainId): boolean {
    return this.value === other.value
  }

  toString(): string {
    return this.value.toString()
  }
}
