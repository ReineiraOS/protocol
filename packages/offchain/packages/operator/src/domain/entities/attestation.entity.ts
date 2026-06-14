export interface AttestationProps {
  message: string
  attestation: string
  status: string
  eventNonce: string
}

export class Attestation {
  readonly message: string
  readonly attestation: string
  readonly status: string
  readonly eventNonce: string

  constructor(props: AttestationProps) {
    if (!props.message || !props.message.startsWith('0x')) {
      throw new Error('Invalid message: must be a hex string starting with 0x')
    }
    if (!props.attestation || !props.attestation.startsWith('0x')) {
      throw new Error('Invalid attestation: must be a hex string starting with 0x')
    }
    if (!props.eventNonce) {
      throw new Error('Event nonce is required')
    }

    this.message = props.message
    this.attestation = props.attestation
    this.status = props.status
    this.eventNonce = props.eventNonce
  }

  get isComplete(): boolean {
    return this.status === 'complete'
  }

  toJSON(): Record<string, unknown> {
    return {
      message: this.message,
      attestation: this.attestation,
      status: this.status,
      eventNonce: this.eventNonce,
    }
  }
}
