import Foundation
import RupaCoreTypes

public struct ArtifactConfigurationIdentity: Codable, Hashable, Sendable {
    public let schemaID: String
    public let schemaVersion: String
    public let value: SemanticJSONValue
    public let fingerprint: ContentFingerprint

    public init(
        schemaID: String,
        schemaVersion: String,
        value: SemanticJSONValue
    ) throws {
        let schemaID = schemaID.trimmingCharacters(in: .whitespacesAndNewlines)
        let schemaVersion = schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !schemaID.isEmpty, !schemaVersion.isEmpty else {
            throw ReferenceValidationError(
                code: .invalidIdentity,
                message: "Artifact configurations require schema ID and version values."
            )
        }
        try value.validate()
        self.schemaID = schemaID
        self.schemaVersion = schemaVersion
        self.value = value
        var hasher = CanonicalIdentityHasher(domain: "artifact-configuration.v1")
        hasher.appendField("schemaID")
        hasher.appendString(schemaID)
        hasher.appendField("schemaVersion")
        hasher.appendString(schemaVersion)
        hasher.appendField("value")
        value.appendCanonicalIdentity(to: &hasher)
        self.fingerprint = try hasher.fingerprint(
            algorithm: "sha256-artifact-configuration-v1"
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaID
        case schemaVersion
        case value
        case fingerprint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let encodedFingerprint = try container.decode(ContentFingerprint.self, forKey: .fingerprint)
        try self.init(
            schemaID: container.decode(String.self, forKey: .schemaID),
            schemaVersion: container.decode(String.self, forKey: .schemaVersion),
            value: container.decode(SemanticJSONValue.self, forKey: .value)
        )
        guard fingerprint == encodedFingerprint else {
            throw ReferenceValidationError(
                code: .invalidIdentity,
                message: "Artifact configuration fingerprint does not match its typed value."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaID, forKey: .schemaID)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(value, forKey: .value)
        try container.encode(fingerprint, forKey: .fingerprint)
    }
}
