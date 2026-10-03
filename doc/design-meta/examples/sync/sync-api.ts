/**
 * Language-neutral design reference for the SeleneTide sync API.
 *
 * TypeScript is used to make the contract concise. The production library will
 * expose equivalent Swift Sendable values, async functions, AsyncSequence
 * progress events, and cooperative cancellation.
 */

/** Canonical string encodings of local UUIDs, distinct from provider IDs. */
export type AccountID = string;
export type MailboxID = string;
export type SyncPlanID = string;
export type SyncRunID = string;
export type SyncTaskID = string;
export type ISO8601DateTime = string;

export type ProviderMessageIdentity = {
  kind: "gmail";
  /** Decimal representation of Gmail X-GM-MSGID. */
  messageID: string;
};

/**
 * Durable mailbox-location identity. Sequence numbers must never be persisted.
 * A provider identity correlates locations but never replaces mailboxID,
 * UIDVALIDITY, and UID when fetching through IMAP.
 */
export interface MessageIdentity {
  accountID: AccountID;
  mailboxID: MailboxID;
  /** Nonzero unsigned 32-bit IMAP values, represented losslessly as numbers. */
  uidValidity: number;
  uid: number;
  providerIdentity?: ProviderMessageIdentity;
}

export type MailboxSelection =
  | { kind: "all" }
  /** Include requires a non-empty unique list owned by the selected account. */
  | { kind: "include"; mailboxIDs: readonly MailboxID[] };

export type SyncMode =
  | "initial"
  | "incremental"
  | "reconcile";

export type SyncPeriod =
  | { kind: "calendar-month"; month: string }
  | {
      kind: "date-range";
      start: ISO8601DateTime;
      endExclusive: ISO8601DateTime;
    };

/** Input used to produce a durable, inspectable sync plan. */
export interface PlanSyncRequest {
  accountID: AccountID;
  mailboxes: MailboxSelection;
  mode: SyncMode;
  /** UTC half-open period; calendar months use YYYY-MM. */
  period: SyncPeriod;

  /**
   * Metadata-only is the normal mode. This flag does not permit fetching
   * bodies or attachments; those belong to the separate on-demand API.
   */
  metadataOnly: true;
}

export interface SyncPlanSummary {
  planID: SyncPlanID;
  accountID: AccountID;
  mode: SyncMode;
  period: SyncPeriod;
  createdAt: ISO8601DateTime;
  mailboxCount: number;
  estimatedTaskCount: number;
  state: "ready" | "superseded";
}

export type SyncRunState =
  | "pending"
  | "running"
  | "blocked"
  | "completed"
  | "failed"
  | "cancelled";

export type SyncTaskState =
  | "pending"
  | "running"
  | "blocked"
  | "completed"
  | "failed"
  | "cancelled";

export interface SyncProgress {
  completedTasks: number;
  totalTasks: number;
  discoveredMessages: number;
  fetchedMetadataRecords: number;
  updatedMetadataRecords: number;
  removedMetadataRecords: number;
  processedMessages: number;
  exportedProcessingResults: number;
  /** Newly finalized batch rows across both datasets; replays add nothing. */
  archivedRecords: number;
}

/** Public snapshot backed by the offline Core Data workflow store. */
export interface SyncRunSnapshot {
  runID: SyncRunID;
  planID: SyncPlanID;
  accountID: AccountID;
  state: SyncRunState;
  progress: SyncProgress;
  createdAt: ISO8601DateTime;
  startedAt?: ISO8601DateTime;
  finishedAt?: ISO8601DateTime;
  blockingReason?: SyncBlockingReason;
  failure?: SyncFailure;
}

export type SyncBlockingReason =
  | { kind: "authentication-required"; accountID: AccountID }
  | { kind: "network-unavailable" }
  | { kind: "rate-limited"; retryAfter?: ISO8601DateTime }
  | { kind: "storage-unavailable"; detail: string }
  | { kind: "transformer-missing"; transformerName: string }
  | { kind: "transformer-incompatible"; transformerName: string }
  | { kind: "schema-incompatible"; detail: string }
  | { kind: "policy-required"; detail: string };

export interface SyncFailure {
  code:
    | "authentication-failed"
    | "imap-protocol-error"
    | "checkpoint-invalid"
    | "processing-failed"
    | "duckdb-export-failed"
    | "parquet-archive-failed"
    | "storage-error"
    | "cancelled"
    | "unexpected";
  message: string;
  retryable: boolean;
  taskID?: SyncTaskID;
}

/** Per-mailbox durable state used for interruption recovery and reconciliation. */
export interface MailboxCheckpoint {
  accountID: AccountID;
  mailboxID: MailboxID;
  uidValidity: number;
  /** Discovery hint only; does not prove coverage of another date range. */
  highestObservedUID?: number;
  lastSuccessfulSyncAt?: ISO8601DateTime;
  requiresReconciliation: boolean;
}

export interface SyncPeriodCheckpoint {
  accountID: AccountID;
  mailboxID: MailboxID;
  uidValidity: number;
  periodStart: ISO8601DateTime;
  periodEndExclusive: ISO8601DateTime;
  runID: SyncRunID;
  completedAt: ISO8601DateTime;
}

export type SyncEvent =
  | { kind: "run-state-changed"; snapshot: SyncRunSnapshot }
  | {
      kind: "task-state-changed";
      runID: SyncRunID;
      taskID: SyncTaskID;
      state: SyncTaskState;
    }
  | {
      kind: "mailbox-progress";
      runID: SyncRunID;
      mailboxID: MailboxID;
      progress: SyncProgress;
    }
  | {
      kind: "checkpoint-saved";
      runID: SyncRunID;
      checkpoint: MailboxCheckpoint;
    }
  | {
      kind: "period-checkpoint-saved";
      runID: SyncRunID;
      checkpoint: SyncPeriodCheckpoint;
    }
  | {
      kind: "duckdb-batch-committed";
      runID: SyncRunID;
      batchID: string;
      recordCount: number;
    }
  | {
      kind: "partition-published";
      runID: SyncRunID;
      mailboxID: MailboxID;
      dataset: "email_metadata" | "processing_results";
      /** UTC calendar month of the fixed canonical email_date, as YYYY-MM. */
      month: string;
      relativePath: string;
      recordCount: number;
    }
  | { kind: "warning"; runID: SyncRunID; code: string; message: string };

export interface StartSyncOptions {
  /** Return an existing active run for this plan instead of duplicating it. */
  idempotency: "reuse-active-run";
}

/**
 * Primary sync boundary.
 *
 * Planning and execution are separate so the CLI or an app can inspect work
 * before starting it. Plans, runs, tasks, attempts, and checkpoints survive
 * process termination in the offline Core Data store. Open-month and arbitrary
 * date-range plans complete after DuckDB verification; only complete closed
 * month plans instantiate archive stages.
 */
export interface SyncClient {
  plan(request: PlanSyncRequest): Promise<SyncPlanSummary>;

  start(
    planID: SyncPlanID,
    options?: StartSyncOptions,
  ): Promise<SyncRunSnapshot>;

  /** Resume pending and retryable work; completed tasks are not repeated. */
  resume(runID: SyncRunID): Promise<SyncRunSnapshot>;

  /** Cooperative cancellation leaves the run in a resumable durable state. */
  cancel(runID: SyncRunID): Promise<SyncRunSnapshot>;

  status(runID: SyncRunID): Promise<SyncRunSnapshot>;

  /** Emits an initial snapshot followed by ordered events until termination. */
  events(runID: SyncRunID): AsyncIterable<SyncEvent>;

  checkpoint(
    accountID: AccountID,
    mailboxID: MailboxID,
  ): Promise<MailboxCheckpoint | undefined>;

  periodCheckpoint(
    accountID: AccountID,
    mailboxID: MailboxID,
    period: SyncPeriod,
  ): Promise<SyncPeriodCheckpoint | undefined>;
}

// Example: plan an incremental metadata refresh and observe it to completion.
export async function refreshAccount(
  sync: SyncClient,
  accountID: AccountID,
  period: SyncPeriod,
): Promise<SyncRunSnapshot> {
  const plan = await sync.plan({
    accountID,
    mailboxes: { kind: "all" },
    mode: "incremental",
    period,
    metadataOnly: true,
  });

  const run = await sync.start(plan.planID, {
    idempotency: "reuse-active-run",
  });

  for await (const event of sync.events(run.runID)) {
    if (event.kind !== "run-state-changed") continue;

    const { snapshot } = event;
    if (
      snapshot.state === "completed" ||
      snapshot.state === "failed" ||
      snapshot.state === "cancelled"
    ) {
      return snapshot;
    }
  }

  return sync.status(run.runID);
}
