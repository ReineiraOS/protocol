import { TransactionHash } from './transaction-hash.value-object'

describe('TransactionHash', () => {
  const validHash = '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'

  describe('constructor', () => {
    it('should create a valid transaction hash', () => {
      const txHash = new TransactionHash(validHash)
      expect(txHash.value).toBe(validHash)
    })

    it('should normalize to lowercase', () => {
      const upperCaseHash = '0x1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF'
      const txHash = new TransactionHash(upperCaseHash)
      expect(txHash.value).toBe(validHash)
    })

    it('should throw error for hash without 0x prefix', () => {
      expect(
        () =>
          new TransactionHash('1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'),
      ).toThrow('Invalid transaction hash')
    })

    it('should throw error for hash with wrong length', () => {
      expect(() => new TransactionHash('0x1234')).toThrow('Invalid transaction hash')
    })

    it('should throw error for hash with invalid characters', () => {
      expect(
        () =>
          new TransactionHash('0xgggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg'),
      ).toThrow('Invalid transaction hash')
    })

    it('should throw error for empty string', () => {
      expect(() => new TransactionHash('')).toThrow('Invalid transaction hash')
    })
  })

  describe('equals', () => {
    it('should return true for equal hashes', () => {
      const hash1 = new TransactionHash(validHash)
      const hash2 = new TransactionHash(validHash)
      expect(hash1.equals(hash2)).toBe(true)
    })

    it('should return true for equal hashes with different case', () => {
      const hash1 = new TransactionHash(validHash)
      const hash2 = new TransactionHash(validHash.toUpperCase())
      expect(hash1.equals(hash2)).toBe(true)
    })

    it('should return false for different hashes', () => {
      const hash1 = new TransactionHash(validHash)
      const hash2 = new TransactionHash(
        '0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321',
      )
      expect(hash1.equals(hash2)).toBe(false)
    })
  })

  describe('toString', () => {
    it('should return the hash value', () => {
      const txHash = new TransactionHash(validHash)
      expect(txHash.toString()).toBe(validHash)
    })
  })
})
