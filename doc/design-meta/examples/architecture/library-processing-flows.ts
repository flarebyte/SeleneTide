/** Sequence-diagram inputs for the principal SeleneTide workflows. */
export type FlowStep = {
  from: string;
  to: string;
  action: string;
  data?: string[];
  when?: string;
  notes?: string;
};

/** Library initialization and durable-work recovery. */
export const initializationFlow: FlowStep[] = [
  {
    from: "AppOrCLI",
    to: "SeleneTideLibrary",
    action: "initialize",
    data: ["configuration", "transformers"],
    notes: "Acquire exclusive process writer ownership for the shared Core Data store before starting recovery.",
  },
  {
    from: "SeleneTideLibrary",
    to: "TransformerRegistry",
    action: "registerAll",
    data: ["transformerName", "transformerVersion", "outputSchemaVersion"],
    notes: "Names must be non-empty and globally unique within the library instance.",
  },
  {
    from: "TransformerRegistry",
    to: "SeleneTideLibrary",
    action: "rejectInitialization",
    data: ["duplicateName", "invalidVersion", "pipelineMismatch"],
    when: "a transformer registration or current pipeline definition is invalid",
  },
  {
    from: "SeleneTideLibrary",
    to: "CoreDataStore",
    action: "loadPersistentStoresAndMigrate",
    data: ["coreDataModelVersion"],
  },
  {
    from: "SeleneTideLibrary",
    to: "DuckDBStore",
    action: "openAndMigrate",
    data: ["duckDBSchemaVersion"],
  },
  {
    from: "WorkflowCoordinator",
    to: "CoreDataStore",
    action: "findRecoverableWork",
    data: ["expiredLeases", "pendingTasks", "retryDueTasks", "blockedTasks"],
  },
  {
    from: "WorkflowCoordinator",
    to: "TransformerRegistry",
    action: "resolvePersistedTransformerNames",
    data: ["transformerName"],
  },
  {
    from: "WorkflowCoordinator",
    to: "CoreDataStore",
    action: "markBlocked",
    data: ["failureCode=transformer.missing"],
    when: "a historical persisted transformer name is not registered",
    notes: "The missing transformer does not consume an execution attempt.",
  },
  {
    from: "WorkflowCoordinator",
    to: "WorkflowCoordinator",
    action: "resumeEligibleWork",
    when: "stores and current pipeline definitions are valid",
  },
];

/** Complete account/mailbox/period workflow, normally for one UTC month. */
export const periodProcessingFlow: FlowStep[] = [
  {
    from: "AppOrCLI",
    to: "SyncClient",
    action: "plan",
    data: ["accountID", "mailboxes", "period", "mode"],
  },
  {
    from: "SyncClient",
    to: "CoreDataStore",
    action: "persistPeriodPlan",
    data: ["periodStart", "periodEndExclusive", "partitionMonth"],
  },
  {
    from: "AppOrCLI",
    to: "WorkflowCoordinator",
    action: "startPlan",
    data: ["planID"],
  },
  {
    from: "WorkflowCoordinator",
    to: "IMAPClient",
    action: "discoverUIDPage",
    data: ["accountID", "mailboxID", "period", "pageCursor"],
    notes: "These are IMAP UIDs, not UUIDs.",
  },
  {
    from: "IMAPClient",
    to: "WorkflowCoordinator",
    action: "returnUIDPage",
    data: ["uidValidity", "uids", "nextPageCursor"],
  },
  {
    from: "WorkflowCoordinator",
    to: "CoreDataStore",
    action: "persistDiscoveryPageAndFanOut",
    data: ["discoveryCursor", "metadataFetchTasks"],
    notes: "Cursor and idempotent child tasks commit atomically; child tasks run immediately so bounded discovery can drain.",
  },
  {
    from: "WorkflowCoordinator",
    to: "IMAPClient",
    action: "fetchMessageMetadata",
    data: ["mailboxID", "uidValidity", "uid", "selectedHeaders", "bodyStructure"],
    when: "a metadata fetch task is ready",
  },
  {
    from: "IMAPClient",
    to: "IntermediateStore",
    action: "publishNormalizedMetadata",
    data: ["resultSchemaVersion", "resultFingerprint", "relativePath", "sourceVersion", "canonicalEmailDate"],
    notes: "No message body or attachment bytes are included.",
  },
  {
    from: "WorkflowCoordinator",
    to: "EmailProcessingPipeline",
    action: "startOrReuseJob",
    data: ["messageIdentity", "emailDate", "inputFingerprint", "pipelineVersion", "sourceRevision", "normalizedMetadata"],
  },
  {
    from: "EmailProcessingPipeline",
    to: "CoreDataStore",
    action: "persistTerminalJob",
    data: ["processingJobID", "jobState", "stepResults"],
    notes: "Per-email jobs may execute concurrently under configured limits.",
  },
  {
    from: "WorkflowCoordinator",
    to: "DuckDBExporter",
    action: "exportPeriod",
    data: ["accountID", "mailboxID", "period", "batchSize"],
    when: "discovery is complete and every included processing job succeeded or succeededWithWarnings",
  },
  {
    from: "DuckDBExporter",
    to: "DuckDBStore",
    action: "upsertMetadataAndProcessingResults",
    data: ["messageKeys", "transformerKeys", "sourceVersions"],
    notes: "Each configurable batch is one DuckDB transaction.",
  },
  {
    from: "DuckDBExporter",
    to: "WorkflowCoordinator",
    action: "confirmPeriodProjection",
    data: ["expectedCounts", "acknowledgedSourceVersions"],
  },
  {
    from: "WorkflowCoordinator",
    to: "ParquetArchiver",
    action: "archivePeriod",
    data: ["accountID", "mailboxID", "partitionMonth"],
    when: "the plan covers exactly one complete closed UTC month",
  },
  {
    from: "ParquetArchiver",
    to: "WorkflowCoordinator",
    action: "confirmArchive",
    when: "archive stages were instantiated",
    data: ["datasetNames", "manifestIDs", "rowCounts", "relativePaths", "sha256"],
  },
  {
    from: "WorkflowCoordinator",
    to: "CoreDataStore",
    action: "completePeriodRun",
    data: ["finalCounters", "periodCheckpoint", "finishedAt"],
    notes: "Open-month and partial/multi-month range runs complete after projection verification without archive stages.",
  },
];

/** One email's dependency-aware transformation pipeline. */
export const emailTransformationFlow: FlowStep[] = [
  {
    from: "WorkflowCoordinator",
    to: "EmailProcessingPipeline",
    action: "startOrResume",
    data: ["processingJobID", "messageIdentity", "inputFingerprint"],
  },
  {
    from: "EmailProcessingPipeline",
    to: "CoreDataStore",
    action: "loadJobAndSteps",
    data: ["pipelineVersion", "stepStates", "dependencyOutputs"],
  },
  {
    from: "EmailProcessingPipeline",
    to: "CoreDataStore",
    action: "reuseCompatibleResults",
    data: ["transformerName", "transformerVersion", "inputFingerprint", "outputSchemaVersion"],
    when: "a valid succeeded result already exists",
  },
  {
    from: "EmailProcessingPipeline",
    to: "TransformerRegistry",
    action: "resolve",
    data: ["transformerName", "stepVersion", "outputSchemaVersion"],
    notes: "Missing or incompatible implementations block work before consuming an attempt.",
  },
  {
    from: "EmailProcessingPipeline",
    to: "CoreDataStore",
    action: "claimReadySteps",
    data: ["leaseOwner", "leaseExpiresAt", "attemptCount"],
    notes: "The scheduler serializes claims; independent claimed dependency branches execute concurrently.",
  },
  {
    from: "TransformerRegistry",
    to: "EmailTransformer",
    action: "transform",
    data: ["messageIdentity", "normalizedMetadata", "dependencyOutputs", "idempotencyKey"],
    notes: "Synchronous transformers use the same async erased call surface.",
  },
  {
    from: "EmailTransformer",
    to: "EmailProcessingPipeline",
    action: "returnResult",
    data: ["officialStatus", "customStatus", "message", "typedOutput"],
  },
  {
    from: "EmailProcessingPipeline",
    to: "CoreDataStore",
    action: "commitStepResultAtomically",
    data: ["stepState", "officialStatus", "customStatus", "statusMessage", "outputData", "timestamps"],
    notes: "The terminal state and persisted output become visible in the same save.",
  },
  {
    from: "EmailProcessingPipeline",
    to: "CoreDataStore",
    action: "scheduleRetry",
    data: ["nextAttemptAt", "attemptCount", "failureCode"],
    when: "officialStatus is retry and attempts remain",
  },
  {
    from: "EmailProcessingPipeline",
    to: "CoreDataStore",
    action: "finishJob",
    data: ["succeeded", "succeededWithWarnings", "failed"],
    when: "every instantiated step is terminal and required-step outcomes determine success or failure",
  },
];

/** Idempotent Core Data to DuckDB export, including the dual-commit crash gap. */
export const duckDBProjectionRecoveryFlow: FlowStep[] = [
  {
    from: "DuckDBExporter",
    to: "DuckDBStore",
    action: "prepareSchema",
    notes: "Open migrate and validate before claiming Core Data work; retain the in-flight gate across awaits.",
  },
  {
    from: "DuckDBExporter",
    to: "CoreDataStore",
    action: "claimStableResultBatch",
    data: ["batchID", "leaseOwner", "leaseExpiresAt", "sourceVersions"],
  },
  {
    from: "CoreDataStore",
    to: "DuckDBExporter",
    action: "returnImmutableRows",
    data: ["metadataRows", "processingResultRows"],
  },
  {
    from: "DuckDBExporter",
    to: "DuckDBStore",
    action: "beginTransaction",
  },
  {
    from: "DuckDBExporter",
    to: "DuckDBStore",
    action: "parameterizedUpsert",
    data: ["logicalKey", "sourceVersion", "analyticalColumns", "extensionsJSON"],
    notes: "Update only for strictly newer revisions; equal or newer destination versions are acknowledged no-ops.",
  },
  {
    from: "DuckDBExporter",
    to: "DuckDBStore",
    action: "commitTransaction",
  },
  {
    from: "DuckDBExporter",
    to: "CoreDataStore",
    action: "acknowledgeExport",
    data: ["batchID", "claimedSourceVersions", "exportedAt", "duckDBSchemaVersion"],
    notes: "Fence by batchID and preserve newer source revisions as pending.",
  },
  {
    from: "System",
    to: "DuckDBExporter",
    action: "restartAfterCommitGap",
    when: "DuckDB committed but Core Data acknowledgement did not",
  },
  {
    from: "DuckDBExporter",
    to: "CoreDataStore",
    action: "reclaimExpiredBatch",
    data: ["batchID", "sourceVersions"],
  },
  {
    from: "DuckDBExporter",
    to: "DuckDBStore",
    action: "replayIdempotentUpsert",
    data: ["logicalKeys", "sourceVersions"],
    notes: "Equal or newer destination versions make the replay a successful no-op.",
  },
  {
    from: "DuckDBExporter",
    to: "CoreDataStore",
    action: "acknowledgeRecoveredExport",
  },
];

/** DuckDB live data to verified monthly Parquet archives. */
export const parquetArchiveFlow: FlowStep[] = [
  {
    from: "WorkflowCoordinator",
    to: "ParquetArchiver",
    action: "requestArchive",
    data: ["accountID", "mailboxID", "partitionMonth"],
  },
  {
    from: "ParquetArchiver",
    to: "DuckDBStore",
    action: "claimArchiveBatch",
    data: ["dataset", "archiveBatchID", "sourceVersions"],
    notes: "One transaction claims a complete month per dataset; exporting remains queryable and dataset-specific manifests track separate paths and counts.",
  },
  {
    from: "ParquetArchiver",
    to: "DuckDBStore",
    action: "readImmutableExportingBatch",
    data: ["emailMetadataRows", "processingResultRows", "schemaVersions"],
  },
  {
    from: "ParquetArchiver",
    to: "ParquetFileSystem",
    action: "writeTemporaryFiles",
    data: ["emailMetadataDataset", "processingResultDataset"],
  },
  {
    from: "ParquetArchiver",
    to: "ParquetFileSystem",
    action: "verifyAndPublishAtomically",
    notes: "Publish to immutable batch-specific paths; persist published state and verify the digest on restart before making a generation current.",
    data: ["rowCounts", "schemaVersions", "sha256", "relativePaths"],
  },
  {
    from: "ParquetArchiver",
    to: "DuckDBStore",
    action: "commitManifestAndDeleteStaging",
    data: ["archiveBatchID", "manifest", "currentGeneration", "exportingRows"],
    when: "Parquet publication was verified",
  },
  {
    from: "ParquetArchiver",
    to: "DuckDBStore",
    action: "retainBatchForRetry",
    data: ["archiveBatchID", "failure"],
    when: "writing or verification failed",
  },
  {
    from: "SyncReconciler",
    to: "DuckDBCorrectionOverlay",
    action: "upsertArchivedPeriodCorrection",
    data: ["logicalKey", "sourceVersion", "changeOrTombstone"],
    when: "an already archived message changes",
  },
  {
    from: "ParquetCompactor",
    to: "ParquetFileSystem",
    action: "atomicallyReplaceCorrectedPartition",
    notes: "Merge the prior committed partition and fixed overlay revisions into a new generation; preserve newer corrections and retain old files until readers release them.",
    when: "correction compaction policy is satisfied",
  },
];

/** Explicit on-demand body or attachment retrieval. */
export const onDemandContentFlow: FlowStep[] = [
  {
    from: "AppOrCLI",
    to: "FetchEmailClient",
    action: "start",
    data: ["messageIdentity", "selection", "transform", "retention", "maximumBytes"],
  },
  {
    from: "FetchEmailClient",
    to: "CoreDataStore",
    action: "persistFetchOperation",
    data: ["fetchID", "state=pending"],
  },
  {
    from: "FetchEmailClient",
    to: "IMAPClient",
    action: "fetchSelectedContent",
    data: ["mailboxID", "uidValidity", "uid", "mimePartIDs"],
  },
  {
    from: "IMAPClient",
    to: "TemporaryContentStore",
    action: "writeUnpublishedPartialContent",
  },
  {
    from: "FetchEmailClient",
    to: "TemporaryContentStore",
    action: "publishCompleteArtifactsAtomically",
    data: ["relativePaths", "byteCounts", "sha256"],
  },
  {
    from: "FetchEmailClient",
    to: "CoreDataStore",
    action: "persistContentLeaseAndResult",
    data: ["leaseID", "ownerSessionID", "expiresAt", "artifacts", "state=completed"],
  },
  {
    from: "AppOrCLI",
    to: "FetchEmailClient",
    action: "release",
    data: ["leaseID"],
    when: "the caller has finished using the content",
  },
  {
    from: "FetchEmailClient",
    to: "TemporaryContentStore",
    action: "removeEligibleArtifacts",
    data: ["leaseID"],
  },
];

export const libraryProcessingFlows = {
  initialization: initializationFlow,
  periodProcessing: periodProcessingFlow,
  emailTransformation: emailTransformationFlow,
  duckDBProjectionRecovery: duckDBProjectionRecoveryFlow,
  parquetArchive: parquetArchiveFlow,
  onDemandContent: onDemandContentFlow,
};
