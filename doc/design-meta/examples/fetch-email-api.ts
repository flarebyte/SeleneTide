/**
 * Language-neutral design reference for SeleneTide on-demand email fetching.
 *
 * TypeScript keeps the contract concise. The production API will use
 * equivalent Swift Sendable values, async functions, AsyncSequence events,
 * file URLs, and cooperative cancellation.
 */

import type {
  ISO8601DateTime,
  MessageIdentity,
} from "./sync-api";

export type FetchID = string;
export type ContentLeaseID = string;
export type MIMEPartID = string;

/** Selection is explicit so metadata sync can never fetch content by accident. */
export type EmailContentSelection =
  | { kind: "raw-message" }
  | {
      kind: "body";
      preference: "plain-text" | "html" | "best-available";
      includeInlineResources: boolean;
    }
  | { kind: "mime-parts"; partIDs: readonly MIMEPartID[] }
  | { kind: "attachments"; attachmentIDs: readonly MIMEPartID[] | "all" };

export type ContentTransform =
  | { kind: "none" }
  | { kind: "extract-body"; output: "plain-text" | "html" }
  | { kind: "html-to-markdown" };

/**
 * Downloaded content always has a finite lease. Callers may release it sooner;
 * the implementation may discard it after the lease expires.
 */
export type TemporaryRetention =
  | { kind: "while-in-use" }
  | { kind: "time-to-live"; seconds: number };

export interface FetchEmailRequest {
  message: MessageIdentity;
  selection: EmailContentSelection;
  transform?: ContentTransform;
  retention: TemporaryRetention;

  /** Reject a transfer before writing content when its known size is larger. */
  maximumBytes?: number;
}

export type FetchState =
  | "pending"
  | "fetching"
  | "processing"
  | "completed"
  | "failed"
  | "cancelled";

export interface FetchProgress {
  phase: "connecting" | "downloading" | "processing" | "publishing";
  receivedBytes: number;
  expectedBytes?: number;
}

export interface FetchSnapshot {
  fetchID: FetchID;
  message: MessageIdentity;
  state: FetchState;
  progress: FetchProgress;
  createdAt: ISO8601DateTime;
  startedAt?: ISO8601DateTime;
  finishedAt?: ISO8601DateTime;
  failure?: FetchFailure;
}

export interface FetchFailure {
  code:
    | "message-not-found"
    | "mailbox-identity-changed"
    | "part-not-found"
    | "size-limit-exceeded"
    | "authentication-failed"
    | "imap-protocol-error"
    | "network-error"
    | "storage-error"
    | "transform-error"
    | "cancelled"
    | "unexpected";
  message: string;
  retryable: boolean;
}

export interface MIMEType {
  type: string;
  subtype: string;
  parameters: Readonly<Record<string, string>>;
}

export interface TemporaryArtifact {
  artifactID: string;
  role:
    | "raw-message"
    | "plain-text-body"
    | "html-body"
    | "markdown-body"
    | "inline-resource"
    | "attachment";
  mimeType: MIMEType;
  filename?: string;
  byteCount: number;

  /** Path relative to the owning account's temporary-content directory. */
  relativePath: string;

  /** IMAP section identifier when the artifact represents a MIME part. */
  partID?: MIMEPartID;
  contentID?: string;
  sha256?: string;
}

/**
 * A result owns a lease over published artifacts. Artifacts are complete and
 * atomically visible; partial downloads are never returned.
 */
export interface FetchedEmailContent {
  fetchID: FetchID;
  message: MessageIdentity;
  leaseID: ContentLeaseID;
  expiresAt?: ISO8601DateTime;
  artifacts: readonly TemporaryArtifact[];
}

export type FetchEvent =
  | { kind: "state-changed"; snapshot: FetchSnapshot }
  | { kind: "progress"; fetchID: FetchID; progress: FetchProgress }
  | {
      kind: "artifact-published";
      fetchID: FetchID;
      artifact: TemporaryArtifact;
    }
  | { kind: "warning"; fetchID: FetchID; code: string; message: string };

export interface CleanupReport {
  releasedLeaseIDs: readonly ContentLeaseID[];
  removedArtifactCount: number;
  reclaimedBytes: number;
}

export interface CleanupExpiredOptions {
  /** Also remove abandoned partial downloads older than this duration. */
  partialDownloadAgeSeconds: number;
}

export interface FetchEmailClient {
  /** Starts a fetch and returns once its durable operation record exists. */
  start(request: FetchEmailRequest): Promise<FetchSnapshot>;

  status(fetchID: FetchID): Promise<FetchSnapshot>;

  /** Emits the current snapshot followed by ordered events until termination. */
  events(fetchID: FetchID): AsyncIterable<FetchEvent>;

  /** Returns content only after the fetch has completed successfully. */
  result(fetchID: FetchID): Promise<FetchedEmailContent>;

  /** Cooperative cancellation discards unpublished partial content. */
  cancel(fetchID: FetchID): Promise<FetchSnapshot>;

  /** Releases one result and makes its artifacts eligible for removal. */
  release(leaseID: ContentLeaseID): Promise<CleanupReport>;

  /** Removes expired leases and abandoned partial downloads. */
  cleanupExpired(options: CleanupExpiredOptions): Promise<CleanupReport>;
}

// Example: fetch selected attachments and release them after processing.
export async function withAttachments<T>(
  client: FetchEmailClient,
  message: MessageIdentity,
  attachmentIDs: readonly MIMEPartID[],
  use: (artifacts: readonly TemporaryArtifact[]) => Promise<T>,
): Promise<T> {
  const fetch = await client.start({
    message,
    selection: { kind: "attachments", attachmentIDs },
    transform: { kind: "none" },
    retention: { kind: "while-in-use" },
  });

  for await (const event of client.events(fetch.fetchID)) {
    if (event.kind !== "state-changed") continue;
    if (event.snapshot.state === "failed") {
      throw new Error(event.snapshot.failure?.message ?? "Fetch failed");
    }
    if (event.snapshot.state === "cancelled") {
      throw new Error("Fetch cancelled");
    }
    if (event.snapshot.state !== "completed") continue;

    const content = await client.result(fetch.fetchID);
    try {
      return await use(content.artifacts);
    } finally {
      await client.release(content.leaseID);
    }
  }

  throw new Error("Fetch event stream ended before completion");
}
