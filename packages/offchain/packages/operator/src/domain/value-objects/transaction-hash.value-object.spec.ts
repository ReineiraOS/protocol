import { TransactionHash } from './transaction-hash.value-object'

describe('TransactionHash', () => {
  const validHash = '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'

  describe('constructor', () => {
    it('should create a valid transaction hash', () => {
      const hash = new TransactionHash(validHash)
      expect(hash.value).toBe(validHash)
    })

    it('should normalize to lowercase', () => {
      const upperHash = '0x1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF'
      const hash = new TransactionHash(upperHash)
      expect(hash.value).toBe(validHash)
    })

    it('should throw for hash without 0x prefix', () => {
      expect(
        () =>
          new TransactionHash('1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'),
      ).toThrow('Invalid transaction hash')
    })

    it('should throw for short hash', () => {
      expect(() => new TransactionHash('0x1234')).toThrow('Invalid transaction hash')
    })

    it('should throw for long hash', () => {
      expect(() => new TransactionHash(validHash + 'ff')).toThrow('Invalid transaction hash')
    })

    it('should throw for invalid characters', () => {
      expect(
        () =>
          new TransactionHash('0x123456789gabcdef1234567890abcdef1234567890abcdef1234567890abcdef'),
      ).toThrow('Invalid transaction hash')
    })

    it('should throw for empty string', () => {
      expect(() => new TransactionHash('')).toThrow('Invalid transaction hash')
    })
  })

  describe('equals', () => {
    it('should return true for equal hashes', () => {
      const hash1 = new TransactionHash(validHash)
      const hash2 = new TransactionHash(validHash)
      expect(hash1.equals(hash2)).toBe(true)
    })

    it('should return true for same hash different case', () => {
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
      const hash = new TransactionHash(validHash)
      expect(hash.toString()).toBe(validHash)
    })
  })
})
