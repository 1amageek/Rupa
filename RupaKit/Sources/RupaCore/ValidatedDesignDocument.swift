import SwiftCAD
import RupaCoreTypes

public struct ValidatedDesignDocument: Sendable {
    public let document: DesignDocument
    public let validatedCADDocument: ValidatedCADDocument

    public init(
        _ document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        try document.modelingSettings.validate()
        let validatedCADDocument = try ValidatedCADDocument(
            document.cadDocument,
            tolerance: document.modelingSettings.tolerance
        )
        try document.productMetadata.validate(
            against: document.cadDocument,
            objectRegistry: objectRegistry
        )
        try Self.validateAuthoredMeshAuthority(in: document)
        self.document = document
        self.validatedCADDocument = validatedCADDocument
    }

    package init(
        document: DesignDocument,
        validatedCADDocument: ValidatedCADDocument
    ) {
        self.document = document
        self.validatedCADDocument = validatedCADDocument
    }

    private static func validateAuthoredMeshAuthority(
        in document: DesignDocument
    ) throws {
        for (sourceID, asset) in document.authoredMeshAssets {
            guard sourceID == asset.id else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Authored Mesh asset dictionary keys must match source identities."
                )
            }
            do {
                try asset.validate()
            } catch {
                throw DocumentValidationError.invalidProductMetadata(
                    "Authored Mesh asset \(sourceID) is invalid: \(error)."
                )
            }
            if case let .derivedFromCAD(representationID, _) = asset.provenance {
                let matchingCADRepresentations = document.productMetadata.sceneNodes.values
                    .compactMap(\.object)
                    .flatMap { $0.geometryRepresentations.representations.values }
                    .filter { representation in
                        representation.id == representationID && {
                            if case .cad = representation.source {
                                return true
                            }
                            return false
                        }()
                    }
                guard matchingCADRepresentations.count == 1 else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "CAD-derived Authored Mesh provenance must resolve to exactly one retained CAD representation."
                    )
                }
            }
        }
        for sceneNode in document.productMetadata.sceneNodes.values {
            guard let object = sceneNode.object else {
                continue
            }
            for representation in object.geometryRepresentations.representations.values {
                let sourceID: GeometrySourceID
                switch representation.source {
                case .authoredMesh(let id):
                    sourceID = id
                case .cad, .external:
                    continue
                }
                guard document.authoredMeshAssets[sourceID] != nil else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Scene objects must reference retained authored Mesh assets."
                    )
                }
            }
        }
    }
}
