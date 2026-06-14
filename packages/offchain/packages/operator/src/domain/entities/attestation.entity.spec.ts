import { Attestation } from './attestation.entity'

describe('Attestation', () => {
  const validProps = {
    message: '0x000000010000000600000000abcdef',
    attestation: '0xabcdef1234567890',
    status: 'complete',
    eventNonce: '0x1234567890abcdef',
  }

  describe('constructor', () => {
    it('should create a valid attestation', () => {
      const attestation = new Attestation(validProps)

      expect(attestation.message).toBe(validProps.message)
      expect(attestation.attestation).toBe(validProps.attestation)
      expect(attestation.status).toBe(validProps.status)
      expect(attestation.eventNonce).toBe(validProps.eventNonce)
    })

    it('should throw for message without 0x prefix', () => {
      expect(
        () =>
          new Attestation({
            ...validProps,
            message: 'invalid',
          }),
      ).toThrow('Invalid message')
    })

    it('should throw for empty message', () => {
      expect(
        () =>
          new Attestation({
            ...validProps,
            message: '',
          }),
      ).toThrow('Invalid message')
    })

    it('should throw for attestation without 0x prefix', () => {
      expect(
        () =>
          new Attestation({
            ...validProps,
            attestation: 'invalid',
          }),
      ).toThrow('Invalid attestation')
    })

    it('should throw for empty attestation', () => {
      expect(
        () =>
          new Attestation({
            ...validProps,
            attestation: '',
          }),
      ).toThrow('Invalid attestation')
    })

    it('should throw for empty event nonce', () => {
      expect(
        () =>
          new Attestation({
            ...validProps,
            eventNonce: '',
          }),
      ).toThrow('Event nonce is required')
    })
  })

  describe('isComplete', () => {
    it('should return true when status is complete', () => {
      const attestation = new Attestation(validProps)
      expect(attestation.isComplete).toBe(true)
    })

    it('should return false when status is not complete', () => {
      const attestation = new Attestation({
        ...validProps,
        status: 'pending',
      })
      expect(attestation.isComplete).toBe(false)
    })
  })

  describe('toJSON', () => {
    it('should serialize to JSON', () => {
      const attestation = new Attestation(validProps)
      const json = attestation.toJSON()

      expect(json.message).toBe(validProps.message)
      expect(json.attestation).toBe(validProps.attestation)
      expect(json.status).toBe(validProps.status)
      expect(json.eventNonce).toBe(validProps.eventNonce)
    })
  })
})
