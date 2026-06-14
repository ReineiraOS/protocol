/* eslint-disable @typescript-eslint/no-unsafe-assignment, @typescript-eslint/no-unsafe-return */
import { ConfigService } from '@nestjs/config'
import { EthersMessageRelayAdapter } from './ethers-message-relay.adapter'

const mockWait = jest.fn()
const mockReceiveMessage = jest.fn()

jest.mock('ethers', () => {
  const actual = jest.requireActual('ethers')
  return {
    ...actual,
    JsonRpcProvider: jest.fn().mockImplementation(() => ({})),
    Wallet: jest.fn().mockImplementation(() => ({ address: '0x' + '1'.repeat(40) })),
    NonceManager: jest.fn().mockImplementation((wallet: unknown) => wallet),
    Contract: jest.fn().mockImplementation(() => ({
      receiveMessage: mockReceiveMessage,
    })),
  }
})

describe('EthersMessageRelayAdapter', () => {
  let adapter: EthersMessageRelayAdapter
  let mockConfigService: jest.Mocked<ConfigService>

  beforeEach(() => {
    jest.clearAllMocks()

    mockConfigService = {
      get: jest.fn().mockImplementation((key: string, defaultValue?: string) => {
        if (key === 'PRIVATE_KEY') return '0x' + 'f'.repeat(64)
        if (key === 'DESTINATION_RPC_URLS')
          return JSON.stringify({ '11155111': 'https://eth-sepolia.example.com' })
        if (key === 'MESSAGE_TRANSMITTER_V2_ADDRESS') return undefined
        return defaultValue
      }),
    } as unknown as jest.Mocked<ConfigService>

    adapter = new EthersMessageRelayAdapter(mockConfigService)
  })

  it('should call receiveMessage and return success', async () => {
    const txHash = '0x' + 'b'.repeat(64)
    mockReceiveMessage.mockResolvedValue({
      hash: txHash,
      wait: mockWait.mockResolvedValue({ hash: txHash }),
    })

    const result = await adapter.relayMessage(11155111, '0xmsg', '0xatt')

    expect(result.success).toBe(true)
    expect(result.transactionHash).toBe(txHash)
    expect(mockReceiveMessage).toHaveBeenCalledWith('0xmsg', '0xatt')
  })

  it('should return error on contract revert', async () => {
    mockReceiveMessage.mockRejectedValue(new Error('execution reverted: already received'))

    const result = await adapter.relayMessage(11155111, '0xmsg', '0xatt')

    expect(result.success).toBe(false)
    expect(result.error).toContain('already received')
  })

  it('should throw on missing RPC URL for chain', async () => {
    const result = await adapter.relayMessage(999999, '0xmsg', '0xatt')

    expect(result.success).toBe(false)
    expect(result.error).toContain('No RPC URL configured for chain 999999')
  })

  it('should throw on missing private key', async () => {
    mockConfigService.get = jest.fn().mockImplementation((key: string, defaultValue?: string) => {
      if (key === 'PRIVATE_KEY') return ''
      if (key === 'DESTINATION_RPC_URLS')
        return JSON.stringify({ '11155111': 'https://eth-sepolia.example.com' })
      return defaultValue
    })

    adapter = new EthersMessageRelayAdapter(mockConfigService)

    const result = await adapter.relayMessage(11155111, '0xmsg', '0xatt')

    expect(result.success).toBe(false)
    expect(result.error).toContain('Missing PRIVATE_KEY')
  })

  it('should reuse chain config on repeated calls', async () => {
    const txHash = '0x' + 'b'.repeat(64)
    mockReceiveMessage.mockResolvedValue({
      hash: txHash,
      wait: mockWait.mockResolvedValue({ hash: txHash }),
    })

    await adapter.relayMessage(11155111, '0xmsg1', '0xatt1')
    await adapter.relayMessage(11155111, '0xmsg2', '0xatt2')

    const { JsonRpcProvider } = jest.requireMock('ethers')
    expect(JsonRpcProvider).toHaveBeenCalledTimes(1)
  })
})
