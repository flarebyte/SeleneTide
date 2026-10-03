import Foundation

/// The only transformer outcomes that affect pipeline scheduling.
public enum TransformerOfficialStatus: String, Codable, Sendable {
    case succeeded
    case retry
    case failed
    case skipped
}

public enum PersistedTransformerOutput: Sendable {
    case none
    case json(Data)
    case binary(Data)
    case utf8(Data)
}

public struct TransformerResult<Output: Sendable>: Sendable {
    public let status: TransformerOfficialStatus
    public let customStatus: String?
    public let message: String?
    public let output: Output?

    public init(
        status: TransformerOfficialStatus,
        customStatus: String? = nil,
        message: String? = nil,
        output: Output? = nil
    ) {
        self.status = status
        self.customStatus = customStatus
        self.message = message
        self.output = output
    }
}

/// Normalized metadata only; message bodies and attachment bytes are excluded.
public struct NormalizedEmailMetadata: Sendable {
    public let schemaVersion: Int32
    public let sourceVersion: Int64
    public let canonicalJSON: Data
}

/// Immutable Sendable input assembled from Core Data and a verified metadata file.
public struct TransformerInput: Sendable {
    public let accountID: String
    public let mailboxID: String
    public let uidValidity: Int64
    public let emailUID: Int64
    public let emailDate: Date
    public let metadata: NormalizedEmailMetadata
    public let idempotencyKey: String
    public let dependencyOutputs: [String: PersistedTransformerOutput]
}

/// Strongly typed implementation interface.
public protocol EmailTransformer: Sendable {
    associatedtype Output: Sendable

    /// Durable identifier. Once released, changing this requires data migration.
    static var name: String { get }
    static var version: Int { get }
    static var outputSchemaVersion: Int { get }

    func transform(_ input: TransformerInput) async throws -> TransformerResult<Output>

    /// Converts typed output into the only transformer-specific persisted field.
    func encodeForPersistence(_ output: Output) throws -> PersistedTransformerOutput
}

/// Optional convenience protocol for implementations that do not suspend.
public protocol SynchronousEmailTransformer: EmailTransformer {
    func transformSynchronously(
        _ input: TransformerInput
    ) throws -> TransformerResult<Output>
}

public extension SynchronousEmailTransformer {
    func transform(_ input: TransformerInput) async throws -> TransformerResult<Output> {
        try transformSynchronously(input)
    }
}

/// Library-internal normalized result returned through the registry boundary.
public struct EncodedTransformerResult: Sendable {
    public let status: TransformerOfficialStatus
    public let customStatus: String?
    public let message: String?
    public let output: PersistedTransformerOutput
    public let outputSchemaVersion: Int
}

/// Type erasure keeps implementations strongly typed while allowing one registry.
public struct AnyEmailTransformer: Sendable {
    public let name: String
    public let version: Int
    public let outputSchemaVersion: Int

    private let run: @Sendable (TransformerInput) async throws -> EncodedTransformerResult

    public init<T: EmailTransformer>(_ transformer: T) {
        name = T.name
        version = T.version
        outputSchemaVersion = T.outputSchemaVersion
        run = { input in
            let result = try await transformer.transform(input)
            let output = try result.output.map(transformer.encodeForPersistence) ?? .none
            return EncodedTransformerResult(
                status: result.status,
                customStatus: result.customStatus,
                message: result.message,
                output: output,
                outputSchemaVersion: T.outputSchemaVersion
            )
        }
    }

    public func transform(_ input: TransformerInput) async throws -> EncodedTransformerResult {
        try await run(input)
    }
}

public enum TransformerRegistryError: Error, Equatable {
    case invalidName(String)
    case invalidVersion(String)
    case duplicateName(String)
    case missingTransformer(String)
    case incompatibleVersion(String, expected: Int, actual: Int)
    case incompatibleOutputSchema(String, expected: Int, actual: Int)
}

/// Immutable registry injected when the library is initialized.
public struct TransformerRegistry: Sendable {
    private let transformersByName: [String: AnyEmailTransformer]

    public init(_ transformers: [AnyEmailTransformer]) throws {
        var indexed: [String: AnyEmailTransformer] = [:]

        for transformer in transformers {
            let name = transformer.name
            guard !name.isEmpty, name == name.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw TransformerRegistryError.invalidName(name)
            }
            guard transformer.version > 0, transformer.version <= Int(Int32.max),
                  transformer.outputSchemaVersion > 0,
                  transformer.outputSchemaVersion <= Int(Int32.max) else {
                throw TransformerRegistryError.invalidVersion(name)
            }
            guard indexed[name] == nil else {
                throw TransformerRegistryError.duplicateName(name)
            }
            indexed[name] = transformer
        }

        transformersByName = indexed
    }

    /// Resolve before claiming work; incompatible persisted contracts are blocked.
    public func resolve(
        name: String,
        version: Int,
        outputSchemaVersion: Int
    ) throws -> AnyEmailTransformer {
        guard let transformer = transformersByName[name] else {
            throw TransformerRegistryError.missingTransformer(name)
        }
        guard transformer.version == version else {
            throw TransformerRegistryError.incompatibleVersion(
                name, expected: version, actual: transformer.version
            )
        }
        guard transformer.outputSchemaVersion == outputSchemaVersion else {
            throw TransformerRegistryError.incompatibleOutputSchema(
                name, expected: outputSchemaVersion, actual: transformer.outputSchemaVersion
            )
        }
        return transformer
    }
}
