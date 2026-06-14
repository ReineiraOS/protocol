import { ChainId } from './chain-id.value-object'

describe('ChainId', () => {
  describe('constructor', () => {
    it('should create a valid chain ID', () => {
      const chainId = new ChainId(1)
      expect(chainId.value).toBe(1)
    })

    it('should accept zero as valid', () => {
      const chainId = new ChainId(0)
      expect(chainId.value).toBe(0)
    })

    it('should accept large chain IDs', () => {
      const chainId = new ChainId(84532)
      expect(chainId.value).toBe(84532)
    })

    it('should throw for negative numbers', () => {
      expect(() => new ChainId(-1)).toThrow('Invalid chain ID')
    })

    it('should throw for non-integers', () => {
      expect(() => new ChainId(1.5)).toThrow('Invalid chain ID')
    })

    it('should throw for NaN', () => {
      expect(() => new ChainId(NaN)).toThrow('Invalid chain ID')
    })
  })

  describe('equals', () => {
    it('should return true for equal chain IDs', () => {
      const chainId1 = new ChainId(1)
      const chainId2 = new ChainId(1)
      expect(chainId1.equals(chainId2)).toBe(true)
    })

    it('should return false for different chain IDs', () => {
      const chainId1 = new ChainId(1)
      const chainId2 = new ChainId(2)
      expect(chainId1.equals(chainId2)).toBe(false)
    })
  })

  describe('toString', () => {
    it('should return string representation', () => {
      const chainId = new ChainId(84532)
      expect(chainId.toString()).toBe('84532')
    })
  })
})
