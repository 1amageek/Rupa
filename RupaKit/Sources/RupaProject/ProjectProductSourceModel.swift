import RupaCore
import RupaCoreTypes
import SwiftCAD

/// Decoded Product authority without CAD or Authored Mesh payload ownership.
public struct ProjectProductSourceModel: Equatable, Sendable {
    public let documentID: DocumentID
    public let name: String?
    public let units: UnitSystem
    public let modelingSettings: DocumentModelingSettings
    public let productMetadata: ProductMetadata

    public var projectID: ProjectID {
        ProjectID(rawValue: "project.\(documentID.description)")
    }

    public init(
        documentID: DocumentID,
        name: String?,
        units: UnitSystem,
        modelingSettings: DocumentModelingSettings,
        productMetadata: ProductMetadata
    ) throws {
        try units.validate()
        try modelingSettings.validate()
        self.documentID = documentID
        self.name = name
        self.units = units
        self.modelingSettings = modelingSettings
        self.productMetadata = productMetadata
    }

    public init(document: DesignDocument) throws {
        try self.init(
            documentID: document.id,
            name: document.cadDocument.metadata.name,
            units: document.cadDocument.units,
            modelingSettings: document.modelingSettings,
            productMetadata: document.productMetadata
        )
    }
}
