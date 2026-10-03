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

export interface ProcessableEmail {
  accountID: AccountID;
  mailboxID: MailboxID;
  uidValidity: number;
  emailUID: number;
  /** UTC timestamp used by first-class Core Data date indexes. */
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
  | "succeeded"
  | "succeeded-with-warnings"
  | "failed"
  | "cancelled";

export type ProcessingStepState =
  | "pending"
  | "ready"
  | "running"
  | "retry-waiting"
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
  stepVersion: number;
  state: ProcessingStepState;
  required: boolean;
  attemptCount: number;
  maximumAttempts: number;
  nextAttemptAt?: ISO8601DateTime;
  reusedFromObjectID?: string;
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
  /** Successful or reused outputs for declared dependencies only. */
  dependencyOutputs: ReadonlyMap<ProcessingStepID, PersistedStepOutput>;
}

export type StepExecutionResult =
  | { kind: "succeeded"; output: PersistedStepOutput }
  | {
      kind: "failed";
      code: string;
      message: string;
      retryable: boolean;
    };

/** Executors are registered in Swift code by stable step ID. */
export interface ProcessingStepExecutor {
  readonly stepID: ProcessingStepID;
  execute(context: StepExecutionContext): Promise<StepExecutionResult>;
}

export type ProcessingEvent =
  | { kind: "job-changed"; job: ProcessingJobSnapshot }
  | { kind: "step-changed"; step: ProcessingStepSnapshot };

export interface StartProcessingRequest {
  email: ProcessableEmail;
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
