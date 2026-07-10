import RupaCore

public struct DomainPayloadDecodingResult: Codable, Equatable, Sendable {
    public var extensionID: SemanticExtensionID
    public var namespace: SemanticNamespaceID
    public var schemaVersion: SemanticSchemaVersion
    public var semanticEntityCount: Int

    public init(
        extensionID: SemanticExtensionID,
        namespace: SemanticNamespaceID,
        schemaVersion: SemanticSchemaVersion,
        semanticEntityCount: Int
    ) {
        self.extensionID = extensionID
        self.namespace = namespace
        self.schemaVersion = schemaVersion
        self.semanticEntityCount = semanticEntityCount
    }
}
