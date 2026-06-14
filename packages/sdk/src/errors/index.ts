export class ReineiraError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly cause?: unknown,
  ) {
    super(message);
    this.name = "ReineiraError";
  }
}

export class FHEInitError extends ReineiraError {
  constructor(message: string, cause?: unknown) {
    super(message, "FHE_INIT_FAILED", cause);
    this.name = "FHEInitError";
  }
}

export class EncryptionError extends ReineiraError {
  constructor(message: string, cause?: unknown) {
    super(message, "ENCRYPTION_FAILED", cause);
    this.name = "EncryptionError";
  }
}

export class EscrowNotFoundError extends ReineiraError {
  constructor(escrowId: bigint) {
    super(`Escrow ${escrowId} does not exist`, "ESCROW_NOT_FOUND");
    this.name = "EscrowNotFoundError";
  }
}

export class InsufficientFundsError extends ReineiraError {
  constructor(message: string) {
    super(message, "INSUFFICIENT_FUNDS");
    this.name = "InsufficientFundsError";
  }
}

export class TransactionFailedError extends ReineiraError {
  /** The transaction hash, if available. */
  public readonly txHash?: string;

  constructor(message: string, opts?: { txHash?: string; cause?: unknown }) {
    super(message, "TX_FAILED", opts?.cause);
    this.name = "TransactionFailedError";
    this.txHash = opts?.txHash;
  }
}

export class ConditionNotMetError extends ReineiraError {
  constructor(escrowId: bigint) {
    super(`Condition not met for escrow ${escrowId}`, "CONDITION_NOT_MET");
    this.name = "ConditionNotMetError";
  }
}

export class CoverageNotActiveError extends ReineiraError {
  constructor(coverageId: bigint) {
    super(`Coverage ${coverageId} is not active`, "COVERAGE_NOT_ACTIVE");
    this.name = "CoverageNotActiveError";
  }
}

export class ValidationError extends ReineiraError {
  constructor(message: string) {
    super(message, "VALIDATION_FAILED");
    this.name = "ValidationError";
  }
}

export class TimeoutError extends ReineiraError {
  constructor(message: string) {
    super(message, "TIMEOUT");
    this.name = "TimeoutError";
  }
}

export class ApprovalRequiredError extends ReineiraError {
  constructor(
    public readonly spender: string,
    public readonly holder: string,
  ) {
    super(
      `Operator approval required. Call .approve() first, or pass { autoApprove: true }. ` +
        `Spender: ${spender}, Holder: ${holder}`,
      "APPROVAL_REQUIRED",
    );
    this.name = "ApprovalRequiredError";
  }
}
