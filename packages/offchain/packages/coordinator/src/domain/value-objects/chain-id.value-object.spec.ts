import { ChainId } from './chain-id.value-object'

describe('ChainId', () => {
  describe('constructor', () => {
    it('should create a valid chain ID', () => {
      const chainId = new ChainId(1)
      expect(chainId.value).toBe(1)
    })

    it('should accept zero as valid chain ID', () => {
      const chainId = new ChainId(0)
      expect(chainId.value).toBe(0)
    })

    it('should accept large chain IDs', () => {
      const chainId = new ChainId(84532) // Base Sepolia
      expect(chainId.value).toBe(84532)
    })

    it('should throw error for negative chain ID', () => {
      expect(() => new ChainId(-1)).toThrow('Invalid chain ID: -1')
    })

    it('should throw error for non-integer chain ID', () => {
      expect(() => new ChainId(1.5)).toThrow('Invalid chain ID: 1.5')
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
