import CoreData
import Foundation

public struct DuckDBExporterConfiguration: Sendable {
    public let batchSize: Int
    public let maximumAttempts: Int
    public let leaseDuration: Duration

    public init(
        batchSize: Int = 250,
        maximumAttempts: Int = 5,
        leaseDuration: Duration = .seconds(120)
    ) {
        precondition(batchSize > 0)
        precondition(maximumAttempts > 0)
        self.batchSize = batchSize
        self.maximumAttempts = maximumAttempts
        self.leaseDuration = leaseDuration
    }
}

/// Immutable projection assembled inside a Core Data context.
public struct DuckDBProcessingResultRow: Sendable {
    public let accountID: String
    public let mailboxID: String
    public let uidValidity: Int64
    public let emailUID: Int64
    public let emailDate: Date
    public let pipelineID: String
    public let pipelineVersion: Int32
    public let jobID: UUID
    public let jobState: String
    public let jobCompletedAt: Date
    public let stepID: String
    public let transformerName: String
    public let transformerVersion: Int32
    public let stepState: String
    public let officialStatus: String?
    public let customStatus: String?
    public let statusMessage: String?
    public let attemptCount: Int32
    public let outputEncoding: String?
    public let outputSchemaVersion: Int32?
    public let outputJSON: Data?
    public let outputBinary: Data?
    public let failureCode: String?
    public let failureMessage: String?
    public let inputFingerprint: String
    public let outputFingerprint: String?
    public let sourceVersion: Int64
    public let sourceUpdatedAt: Date
    public let extensionsJSON: Data
}

public struct DuckDBExportBatch: Sendable {
    public let id: UUID
    public let rows: [DuckDBProcessingResultRow]
}

public struct DuckDBExportReport: Sendable {
    public let batchID: UUID?
    public let selectedCount: Int
    public let committedCount: Int
    public let replayedCount: Int
}

/// Adapter implemented by the embedded DuckDB bridge.
public protocol DuckDBExportDestination: Sendable {
    var schemaVersion: Int32 { get async throws }

    /// One DuckDB transaction using prepared parameterized upserts.
    func upsertProcessingResults(
        _ rows: [DuckDBProcessingResultRow]
    ) async throws -> Int
}

/// Core Data remains authoritative; this store only manages export checkpoints.
public protocol ProcessingExportStateStore: Sendable {
    func claimBatch(
        limit: Int,
        maximumAttempts: Int,
        leaseDuration: Duration
    ) async throws -> DuckDBExportBatch?

    func acknowledge(
        batch: DuckDBExportBatch,
        duckDBSchemaVersion: Int32,
        exportedAt: Date
    ) async throws

    func recordFailure(
        batch: DuckDBExportBatch,
        error: Error
    ) async throws
}

/// Dedicated serial coordinator; transformers never write DuckDB directly.
public actor DuckDBExporter {
    private let stateStore: any ProcessingExportStateStore
    private let destination: any DuckDBExportDestination
    private let configuration: DuckDBExporterConfiguration

    public init(
        stateStore: any ProcessingExportStateStore,
        destination: any DuckDBExportDestination,
        configuration: DuckDBExporterConfiguration = .init()
    ) {
        self.stateStore = stateStore
        self.destination = destination
        self.configuration = configuration
    }

    /// Exports at most one batch. Replaying a claimed batch is always safe.
    public func exportNextBatch() async throws -> DuckDBExportReport {
        guard let batch = try await stateStore.claimBatch(
            limit: configuration.batchSize,
            maximumAttempts: configuration.maximumAttempts,
            leaseDuration: configuration.leaseDuration
        ) else {
            return DuckDBExportReport(
                batchID: nil,
                selectedCount: 0,
                committedCount: 0,
                replayedCount: 0
            )
        }

        do {
            let schemaVersion = try await destination.schemaVersion
            let committed = try await destination.upsertProcessingResults(batch.rows)
            try await stateStore.acknowledge(
                batch: batch,
                duckDBSchemaVersion: schemaVersion,
                exportedAt: Date()
            )
            return DuckDBExportReport(
                batchID: batch.id,
                selectedCount: batch.rows.count,
                committedCount: committed,
                replayedCount: batch.rows.count - committed
            )
        } catch {
            try await stateStore.recordFailure(batch: batch, error: error)
            throw error
        }
    }
}
