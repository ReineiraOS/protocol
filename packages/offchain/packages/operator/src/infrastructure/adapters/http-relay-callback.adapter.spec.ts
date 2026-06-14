import { ConfigService } from '@nestjs/config'
import { HttpRelayCallbackAdapter } from './http-relay-callback.adapter'

jest.mock('undici', () => ({
  request: jest.fn(),
}))

import { request } from 'undici'

const mockRequest = request as jest.MockedFunction<typeof request>

describe('HttpRelayCallbackAdapter', () => {
  let adapter: HttpRelayCallbackAdapter
  let mockConfigService: jest.Mocked<ConfigService>

  beforeEach(() => {
    jest.clearAllMocks()

    mockConfigService = {
      get: jest.fn().mockImplementation((key: string, defaultValue?: string) => {
        if (key === 'RELAY_CALLBACK_SECRET') return 'test-secret'
        return defaultValue
      }),
    } as unknown as jest.Mocked<ConfigService>

    adapter = new HttpRelayCallbackAdapter(mockConfigService)
  })

  it('should send POST request with correct body', async () => {
    mockRequest.mockResolvedValue({ statusCode: 200 } as never)

    await adapter.notifyCompletion(
      'https://api.example.com/callback',
      'wd-123',
      '0x' + 'a'.repeat(64),
    )

    expect(mockRequest).toHaveBeenCalledWith('https://api.example.com/callback', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Relay-Secret': 'test-secret',
      },
      body: JSON.stringify({
        withdrawal_id: 'wd-123',
        destination_tx_hash: '0x' + 'a'.repeat(64),
        status: 'COMPLETED',
      }),
    })
  })

  it('should retry on non-2xx status', async () => {
    mockRequest
      .mockResolvedValueOnce({ statusCode: 500 } as never)
      .mockResolvedValueOnce({ statusCode: 200 } as never)

    await adapter.notifyCompletion('https://api.example.com/callback', 'wd-123', '0xabc')

    expect(mockRequest).toHaveBeenCalledTimes(2)
  })

  it('should retry on network error', async () => {
    mockRequest
      .mockRejectedValueOnce(new Error('ECONNREFUSED'))
      .mockResolvedValueOnce({ statusCode: 200 } as never)

    await adapter.notifyCompletion('https://api.example.com/callback', 'wd-123', '0xabc')

    expect(mockRequest).toHaveBeenCalledTimes(2)
  })

  it('should exhaust retries without throwing', async () => {
    mockRequest.mockRejectedValue(new Error('ECONNREFUSED'))

    await expect(
      adapter.notifyCompletion('https://api.example.com/callback', 'wd-123', '0xabc'),
    ).resolves.toBeUndefined()

    expect(mockRequest).toHaveBeenCalledTimes(3)
  })

  it('should not include X-Relay-Secret header when secret is empty', async () => {
    mockConfigService.get = jest.fn().mockImplementation((key: string, defaultValue?: string) => {
      if (key === 'RELAY_CALLBACK_SECRET') return ''
      return defaultValue as string
    })

    adapter = new HttpRelayCallbackAdapter(mockConfigService)
    mockRequest.mockResolvedValue({ statusCode: 200 } as never)

    await adapter.notifyCompletion('https://api.example.com/callback', 'wd-123', '0xabc')

    const callArgs = mockRequest.mock.calls[0][1] as { headers: Record<string, string> }
    expect(callArgs.headers).not.toHaveProperty('X-Relay-Secret')
  })
})
