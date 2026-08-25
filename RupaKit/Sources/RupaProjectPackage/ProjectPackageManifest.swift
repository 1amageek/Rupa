import Foundation
import RupaCoreTypes

public struct ProjectPackageManifest: Codable, Equatable, Sendable {
    public static let format = "rupa.project"
    public static let currentSchemaVersion: UInt32 = 3
    public static let productSourcePath = "source/product.json"
    public static let cadSourcePath = "source/cad.json"
    public static let meshCatalogPath = "source/mesh-assets.json"

    public let packageFormat: String
    public let packageSchemaVersion: UInt32
    public let documentID: ProjectID
    public let sourceEntries: [ProjectPackageSourceEntry]
    public let documentContentIdentity: DocumentContentIdentity
    public let requiredFeatures: [String]

    public init(
        documentID: ProjectID,
        sourceEntries: [ProjectPackageSourceEntry],
        requiredFeatures: [String] = []
    ) throws {
        let sortedEntries = sourceEntries.sorted { $0.path < $1.path }
        try Self.validateEntries(sortedEntries)
        let sortedFeatures = try Self.validatedFeatures(requiredFeatures)
        self.packageFormat = Self.format
        self.packageSchemaVersion = Self.currentSchemaVersion
        self.documentID = documentID
        self.sourceEntries = sortedEntries
        self.documentContentIdentity = try ProjectPackageContentIdentityBuilder.identity(
            for: sortedEntries
        )
        self.requiredFeatures = sortedFeatures
    }

    private enum CodingKeys: String, CodingKey {
        case packageFormat
        case packageSchemaVersion
        case documentID
        case sourceEntries
        case documentContentIdentity
        case requiredFeatures
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let packageFormat = try container.decode(String.self, forKey: .packageFormat)
        let packageSchemaVersion = try container.decode(
            UInt32.self,
            forKey: .packageSchemaVersion
        )
        guard packageFormat == Self.format else {
            throw ProjectPackageError(
                code: .invalidManifest,
                message: "Project package format is unsupported."
            )
        }
        guard packageSchemaVersion == Self.currentSchemaVersion else {
            throw ProjectPackageError(
                code: .unsupportedSchema,
                message: "Project package schema version is unsupported."
            )
        }
        let documentID = try container.decode(ProjectID.self, forKey: .documentID)
        let entries = try container.decode(
            [ProjectPackageSourceEntry].self,
            forKey: .sourceEntries
        )
        let features = try container.decode([String].self, forKey: .requiredFeatures)
        let declaredIdentity = try container.decode(
            DocumentContentIdentity.self,
            forKey: .documentContentIdentity
        )
        let validated = try Self(
            documentID: documentID,
            sourceEntries: entries,
            requiredFeatures: features
        )
        guard declaredIdentity == validated.documentContentIdentity else {
            throw ProjectPackageError(
                code: .integrityMismatch,
                message: "Project package source identity does not match its declared entries."
            )
        }
        self = validated
    }

    public func sourceEntry(at path: String) -> ProjectPackageSourceEntry? {
        sourceEntries.first { $0.path == path }
    }

    private static func validateEntries(
        _ entries: [ProjectPackageSourceEntry]
    ) throws {
        guard !entries.isEmpty,
            entries.contains(where: { $0.path == productSourcePath })
        else {
            throw ProjectPackageError(
                code: .missingEntry,
                message: "Project packages require source/product.json."
            )
        }
        var paths: Set<String> = []
        for entry in entries {
            guard paths.insert(entry.path).inserted else {
                throw ProjectPackageError(
                    code: .duplicateEntry,
                    message: "Project package source entry appears more than once: \(entry.path)."
                )
            }
        }
    }

    private static func validatedFeatures(_ features: [String]) throws -> [String] {
        let sorted = features.sorted()
        guard Set(sorted).count == sorted.count else {
            throw ProjectPackageError(
                code: .invalidManifest,
                message: "Project package required features must be unique."
            )
        }
        for feature in sorted {
            guard !feature.isEmpty,
                feature == feature.trimmingCharacters(in: .whitespacesAndNewlines),
                feature.utf8.count <= 256,
                feature.utf8.allSatisfy({
                    (48...57).contains($0)
                        || (65...90).contains($0)
                        || (97...122).contains($0)
                        || $0 == 0x2D
                        || $0 == 0x2E
                })
            else {
                throw ProjectPackageError(
                    code: .invalidManifest,
                    message: "Project package required feature identifiers are invalid."
                )
            }
        }
        return sorted
    }
}
