import Foundation

enum ProbeError: Error, Equatable { case schema, upsert, acknowledge, diagnostics }

actor ProbeDestination: DuckDBExportDestination {
    let suspendPreparation: Bool
    let failure: ProbeError?
    let replay: Bool
    private var release: CheckedContinuation<Void, Never>?
    private var waiting: CheckedContinuation<Void, Never>?
    private var preparing = false
    private(set) var writes = 0

    init(suspendPreparation: Bool = false, failure: ProbeError? = nil, replay: Bool = false) {
        self.suspendPreparation = suspendPreparation
        self.failure = failure
        self.replay = replay
    }

    func prepareSchema() async throws -> Int32 {
        if failure == .schema { throw ProbeError.schema }
        let shouldSuspend = suspendPreparation && !preparing
        preparing = true
        if shouldSuspend {
            await withCheckedContinuation { continuation in
                release = continuation
                waiting?.resume()
                waiting = nil
            }
        }
        return 1
    }

    func waitUntilPreparing() async {
        if preparing { return }
        await withCheckedContinuation { waiting = $0 }
    }

    func resumePreparation() { release?.resume(); release = nil }

    func upsertProcessingResults(_ rows: [DuckDBProcessingResultRow]) async throws -> Int {
        if failure == .upsert { throw ProbeError.upsert }
        writes += 1
        return replay ? 0 : rows.count
    }
}

actor ProbeStateStore: ProcessingExportStateStore {
    let batch: DuckDBExportBatch
    let failAcknowledgement: Bool
    let failDiagnostics: Bool
    private(set) var claims = 0
    private(set) var acknowledgements = 0
    private(set) var failures = 0

    init(failAcknowledgement: Bool = false, failDiagnostics: Bool = false) {
        let date = Date(timeIntervalSince1970: 0)
        let row = DuckDBProcessingResultRow(
            accountID: "account", mailboxID: "mailbox", uidValidity: 1,
            emailUID: 1, emailDate: date, pipelineID: "pipeline",
            pipelineVersion: 1, jobID: UUID(), jobState: "succeeded",
            jobCompletedAt: date, stepID: "step", transformerName: "probe",
            transformerVersion: 1, stepState: "succeeded", officialStatus: "succeeded",
            customStatus: nil, statusMessage: nil, attemptCount: 1,
            outputEncoding: "none", outputSchemaVersion: 1,
            outputJSON: nil, outputBinary: nil, failureCode: nil, failureMessage: nil,
            inputFingerprint: "input", outputFingerprint: nil, sourceVersion: 1,
            sourceUpdatedAt: date, extensionsJSON: Data("{}".utf8)
        )
        batch = DuckDBExportBatch(id: UUID(), rows: [row])
        self.failAcknowledgement = failAcknowledgement
        self.failDiagnostics = failDiagnostics
    }

    func claimBatch(limit: Int, maximumAttempts: Int, leaseDuration: Duration) async throws -> DuckDBExportBatch? {
        claims += 1
        return batch
    }

    func acknowledge(batch: DuckDBExportBatch, duckDBSchemaVersion: Int32, exportedAt: Date) async throws {
        if failAcknowledgement { throw ProbeError.acknowledge }
        acknowledgements += 1
    }

    func recordFailure(batch: DuckDBExportBatch, error: Error) async throws {
        failures += 1
        if failDiagnostics { throw ProbeError.diagnostics }
    }
}

struct ProbeTransformer: SynchronousEmailTransformer {
    static let name = "probe"
    static let version = 2
    static let outputSchemaVersion = 1
    func transformSynchronously(_ input: TransformerInput) throws -> TransformerResult<String> {
        .init(status: .succeeded, output: "ok")
    }
    func encodeForPersistence(_ output: String) throws -> PersistedTransformerOutput {
        .utf8(Data(output.utf8))
    }
}

@main
struct SwiftContractProbe {
    static func main() async throws {
        let registration = AnyEmailTransformer(ProbeTransformer())
        let registry = try TransformerRegistry([registration])
        _ = try registry.resolve(name: "probe", version: 2, outputSchemaVersion: 1)
        do {
            _ = try registry.resolve(name: "probe", version: 1, outputSchemaVersion: 1)
            preconditionFailure("Accepted incompatible persisted transformer version")
        } catch TransformerRegistryError.incompatibleVersion("probe", expected: 1, actual: 2) {}
        do {
            _ = try registry.resolve(name: "probe", version: 2, outputSchemaVersion: 2)
            preconditionFailure("Accepted incompatible output schema")
        } catch TransformerRegistryError.incompatibleOutputSchema("probe", expected: 2, actual: 1) {}
        do {
            _ = try TransformerRegistry([registration, registration])
            preconditionFailure("Accepted duplicate transformer")
        } catch TransformerRegistryError.duplicateName("probe") {}

        let input = TransformerInput(accountID: "account", mailboxID: "mailbox",
            uidValidity: 1, emailUID: 1, emailDate: Date(timeIntervalSince1970: 0),
            metadata: NormalizedEmailMetadata(schemaVersion: 1, sourceVersion: 1,
                canonicalJSON: Data("{}".utf8)),
            idempotencyKey: "probe", dependencyOutputs: [:])
        let result = try await registration.transform(input)
        guard case .utf8(let data) = result.output else { preconditionFailure("Missing encoded output") }
        precondition(String(decoding: data, as: UTF8.self) == "ok")

        let destination = ProbeDestination(suspendPreparation: true)
        let store = ProbeStateStore()
        let exporter = DuckDBExporter(stateStore: store, destination: destination)
        let first = Task { try await exporter.exportNextBatch() }
        await destination.waitUntilPreparing()
        do {
            _ = try await exporter.exportNextBatch()
            preconditionFailure("Concurrent batch crossed an await")
        } catch DuckDBExporterError.batchInProgress {}
        await destination.resumePreparation()
        let firstReport = try await first.value
        precondition(firstReport.committedCount == 1)
        let secondReport = try await exporter.exportNextBatch()
        precondition(secondReport.committedCount == 1, "In-flight gate was not released")

        let schemaStore = ProbeStateStore()
        let schemaExporter = DuckDBExporter(stateStore: schemaStore,
            destination: ProbeDestination(failure: .schema))
        do {
            _ = try await schemaExporter.exportNextBatch()
            preconditionFailure("Schema failure did not propagate")
        } catch ProbeError.schema {}
        let schemaClaims = await schemaStore.claims
        precondition(schemaClaims == 0, "Claimed work before validating the schema")

        for failure in [ProbeError.upsert, .acknowledge] {
            let failureStore = ProbeStateStore(failAcknowledgement: failure == .acknowledge, failDiagnostics: true)
            let failureExporter = DuckDBExporter(stateStore: failureStore,
                destination: ProbeDestination(failure: failure == .upsert ? .upsert : nil))
            do {
                _ = try await failureExporter.exportNextBatch()
                preconditionFailure("Expected primary failure")
            } catch let error as ProbeError {
                precondition(error == failure, "Diagnostic persistence masked the primary error")
            }
            let recordedFailures = await failureStore.failures
            precondition(recordedFailures == 1)
        }

        let replayStore = ProbeStateStore()
        let replayExporter = DuckDBExporter(stateStore: replayStore, destination: ProbeDestination(replay: true))
        let replay = try await replayExporter.exportNextBatch()
        precondition(replay.committedCount == 0 && replay.replayedCount == 1)
        let replayAcknowledgements = await replayStore.acknowledgements
        precondition(replayAcknowledgements == 1, "A successful no-op replay was not acknowledged")
        print("Swift contract probes passed: registry versions, type erasure, async batch gate, schema-before-claim, original errors, and replay acknowledgement.")
    }
}
