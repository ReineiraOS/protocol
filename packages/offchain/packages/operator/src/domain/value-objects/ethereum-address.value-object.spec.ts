import { EthereumAddress } from './ethereum-address.value-object'

describe('EthereumAddress', () => {
  const validAddress = '0x1234567890abcdef1234567890abcdef12345678'

  describe('constructor', () => {
    it('should create a valid address', () => {
      const address = new EthereumAddress(validAddress)
      expect(address.value).toBe(validAddress)
    })

    it('should normalize to lowercase', () => {
      const upperAddress = '0x1234567890ABCDEF1234567890ABCDEF12345678'
      const address = new EthereumAddress(upperAddress)
      expect(address.value).toBe(validAddress)
    })

    it('should throw for address without 0x prefix', () => {
      expect(() => new EthereumAddress('1234567890abcdef1234567890abcdef12345678')).toThrow(
        'Invalid Ethereum address',
      )
    })

    it('should throw for short address', () => {
      expect(() => new EthereumAddress('0x1234')).toThrow('Invalid Ethereum address')
    })

    it('should throw for long address', () => {
      expect(() => new EthereumAddress(validAddress + 'ff')).toThrow('Invalid Ethereum address')
    })

    it('should throw for invalid characters', () => {
      expect(() => new EthereumAddress('0x123456789gabcdef1234567890abcdef12345678')).toThrow(
        'Invalid Ethereum address',
      )
    })
  })

  describe('equals', () => {
    it('should return true for equal addresses', () => {
      const addr1 = new EthereumAddress(validAddress)
      const addr2 = new EthereumAddress(validAddress)
      expect(addr1.equals(addr2)).toBe(true)
    })

    it('should return true for same address different case', () => {
      const addr1 = new EthereumAddress(validAddress)
      const addr2 = new EthereumAddress(validAddress.toUpperCase())
      expect(addr1.equals(addr2)).toBe(true)
    })

    it('should return false for different addresses', () => {
      const addr1 = new EthereumAddress(validAddress)
      const addr2 = new EthereumAddress('0xfedcba0987654321fedcba0987654321fedcba09')
      expect(addr1.equals(addr2)).toBe(false)
    })
  })

  describe('toString', () => {
    it('should return the address value', () => {
      const address = new EthereumAddress(validAddress)
      expect(address.toString()).toBe(validAddress)
    })
  })
})
