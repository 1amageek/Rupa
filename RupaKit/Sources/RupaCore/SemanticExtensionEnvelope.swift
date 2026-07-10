import Foundation
import SwiftCAD

public struct SemanticExtensionEnvelope: Codable, Hashable, Identifiable, Sendable {
    public var id: SemanticExtensionID
    public var namespace: SemanticNamespaceID
    public var schemaVersion: SemanticSchemaVersion
    public var payload: SemanticJSONValue
    public var projection: ProjectionManifest

    public init(
        id: SemanticExtensionID = SemanticExtensionID(),
        namespace: SemanticNamespaceID,
        schemaVersion: SemanticSchemaVersion,
        payload: SemanticJSONValue,
        projection: ProjectionManifest = ProjectionManifest()
    ) {
        self.id = id
        self.namespace = namespace
        self.schemaVersion = schemaVersion
        self.payload = payload
        self.projection = projection
    }

    public func validate(
        against cadDocument: CADDocument,
        metadata: ProductMetadata
    ) throws {
        try namespace.validate()
        try schemaVersion.validate()
        try payload.validate()
        for semanticEntity in projection.semanticEntities {
            for sourcePath in semanticEntity.sourcePaths {
                _ = try sourcePath.resolve(in: payload)
            }
        }
        try projection.validate(against: cadDocument, metadata: metadata)
    }
}
