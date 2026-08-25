import Foundation
import SwiftCAD
import RupaCoreTypes
import RupaProjectModel

public struct DesignDocument: Identifiable, Sendable {
    public var cadDocument: CADDocument
    public var modelingSettings: DocumentModelingSettings
    public var productMetadata: ProductMetadata
    public var authoredMeshAssets: [GeometrySourceID: AuthoredMeshAsset]

    public var id: DocumentID {
        cadDocument.id
    }

    public var projectID: ProjectID {
        Self.projectID(for: id)
    }

    public static func projectID(for documentID: DocumentID) -> ProjectID {
        ProjectID(rawValue: "project.\(documentID.description)")
    }

    public init(
        cadDocument: CADDocument,
        modelingSettings: DocumentModelingSettings = .standard,
        productMetadata: ProductMetadata = .empty(),
        authoredMeshAssets: [GeometrySourceID: AuthoredMeshAsset] = [:]
    ) {
        self.cadDocument = cadDocument
        self.modelingSettings = modelingSettings
        self.productMetadata = productMetadata
        self.authoredMeshAssets = authoredMeshAssets
    }

    public static func empty(named name: String = "Untitled") -> DesignDocument {
        return DesignDocument(
            cadDocument: CADDocument(
                units: .meters,
                metadata: DocumentMetadata(name: name)
            ),
            modelingSettings: .standard,
            productMetadata: .empty()
        )
    }

    public var hasAuthoritativeCADSource: Bool {
        let hasCADRepresentation = productMetadata.sceneNodes.values.contains { sceneNode in
            sceneNode.object?.geometryRepresentations.representations.values.contains {
                if case .cad = $0.source {
                    return true
                }
                return false
            } == true
        }
        return hasCADRepresentation
            || cadDocument.designGraph.nodes.isEmpty == false
            || cadDocument.parameters.parameters.isEmpty == false
            || cadDocument.selectionDimensions.isEmpty == false
    }

    @discardableResult
    public func validate(
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> ValidatedDesignDocument {
        try ValidatedDesignDocument(self, objectRegistry: objectRegistry)
    }
}
