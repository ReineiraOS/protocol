import { Attestation } from '../entities/attestation.entity'

export interface AttestationProviderPort {
  getAttestation(txHash: string, sourceDomain: number): Promise<Attestation | null>
  waitForAttestation(
    txHash: string,
    sourceDomain: number,
    timeoutMs?: number,
    pollIntervalMs?: number,
  ): Promise<Attestation>
}

export const ATTESTATION_PROVIDER_PORT = Symbol('AttestationProviderPort')
