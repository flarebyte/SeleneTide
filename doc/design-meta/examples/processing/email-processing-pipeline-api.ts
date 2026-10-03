/**
 * Language-neutral design reference for the Core Data email-processing
 * pipeline. Production code uses equivalent Swift Sendable values, actors,
 * async functions, and NSManagedObjectID boundaries.
 */

export type AccountID = string;
export type MailboxID = string;
export type ProcessingJobID = string;
export type ProcessingStepID = string;
export type ISO8601DateTime = string;

/** Same metadata-only envelope as the Swift transformer input. */
export interface NormalizedEmailMetadata {
  schemaVersion: number;
  /** Positive Int64 decimal string; identifies the accepted metadata snapshot. */
  sourceVersion: string;
  canonicalJSON: Uint8Array;
}

export interface ProcessableEmail {
  accountID: AccountID;
  mailboxID: MailboxID;
  uidValidity: number;
  emailUID: number;
  /** Persisted canonical UTC email_date; unchanged across metadata refreshes. */
  emailDate: ISO8601DateTime;
  /** Digest of the source data visible to the pipeline. */
  inputFingerprint: string;
}

export type ExecutionKind = "local" | "cpu" | "io" | "network";

export interface RetryPolicy {
  maximumAttempts: number;
  initialDelaySeconds: number;
  maximumDelaySeconds: number;
  multiplier: number;
  jitter: "full";
}

/** Static, code-defined configuration; this is not stored as dynamic workflow data. */
export interface ProcessingStepDefinition {
  id: ProcessingStepID;
  /** Exact durable lookup key in the injected transformer registry. */
  transformerName: string;
  /** Positive Int32; must equal the registered EmailTransformer.version. */
  version: number;
  outputSchemaVersion: number;
  required: boolean;
  executionKind: ExecutionKind;
  dependencyIDs: readonly ProcessingStepID[];
  retry: RetryPolicy;
}

export interface EmailPipelineDefinition {
  id: string;
  version: number;
  steps: readonly ProcessingStepDefinition[];
}

export type ProcessingJobState =
  | "pending"
  | "running"
  | "blocked"
  | "succeeded"
  | "succeededWithWarnings"
  | "failed"
  | "cancelled";

export type ProcessingStepState =
  | "pending"
  | "ready"
  | "running"
  | "retryWaiting"
  | "blocked"
  | "succeeded"
  | "failed"
  | "skipped"
  | "cancelled"
  | "reused";

export interface ProcessingJobSnapshot {
  jobID: ProcessingJobID;
  email: ProcessableEmail;
  pipelineID: string;
  pipelineVersion: number;
  /** Positive Int64 decimal string reserved before execution; never reset across jobs. */
  sourceRevision: string;
  state: ProcessingJobState;
  requiredStepCount: number;
  completedRequiredStepCount: number;
  failedOptionalStepCount: number;
  createdAt: ISO8601DateTime;
  updatedAt: ISO8601DateTime;
  completedAt?: ISO8601DateTime;
}

export interface ProcessingStepSnapshot {
  stepObjectID: string;
  jobID: ProcessingJobID;
  stepID: ProcessingStepID;
  transformerName: string;
  stepVersion: number;
  state: ProcessingStepState;
  required: boolean;
  attemptCount: number;
  maximumAttempts: number;
  nextAttemptAt?: ISO8601DateTime;
  reusedFromObjectID?: string;
  officialStatus?: TransformerOfficialStatus;
  customStatus?: string;
  statusMessage?: string;
  failureCode?: string;
  failureMessage?: string;
}

export type PersistedStepOutput =
  | { encoding: "none"; schemaVersion: number }
  | { encoding: "json"; schemaVersion: number; data: Uint8Array }
  | { encoding: "binary"; schemaVersion: number; data: Uint8Array }
  | { encoding: "utf8"; schemaVersion: number; data: Uint8Array };

export interface StepExecutionContext {
  job: ProcessingJobSnapshot;
  step: ProcessingStepSnapshot;
  idempotencyKey: string;
  metadata: NormalizedEmailMetadata;
  /**
   * Outputs for declared dependencies only. An optional failed/skipped
   * predecessor is absent only when the consumer explicitly allows no output.
   */
  dependencyOutputs: ReadonlyMap<ProcessingStepID, PersistedStepOutput>;
}

export type TransformerOfficialStatus =
  | "succeeded"
  | "retry"
  | "failed"
  | "skipped";

export interface TransformerExecutionResult {
  officialStatus: TransformerOfficialStatus;
  customStatus?: string;
  message?: string;
  output?: PersistedStepOutput;
}

export type ProcessingEvent =
  | { kind: "job-changed"; job: ProcessingJobSnapshot }
  | { kind: "step-changed"; step: ProcessingStepSnapshot };

export interface StartProcessingRequest {
  email: ProcessableEmail;
  /** Persist a verified managed-file locator before accepting the job. */
  metadata: NormalizedEmailMetadata;
  pipelineID: string;
  /** Reuse a matching existing job or create one idempotently. */
  ifExists: "reuse";
}

/**
 * A small actor-backed coordinator. Core Data remains the source of truth;
 * this interface does not imply an external queue or general workflow engine.
 */
export interface EmailProcessingPipeline {
  start(request: StartProcessingRequest): Promise<ProcessingJobSnapshot>;
  resume(jobID: ProcessingJobID): Promise<ProcessingJobSnapshot>;
  cancel(jobID: ProcessingJobID): Promise<ProcessingJobSnapshot>;
  status(jobID: ProcessingJobID): Promise<ProcessingJobSnapshot>;
  steps(jobID: ProcessingJobID): Promise<readonly ProcessingStepSnapshot[]>;
  events(jobID: ProcessingJobID): AsyncIterable<ProcessingEvent>;
}
