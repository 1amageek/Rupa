import SwiftCAD

public extension DesignDocument {
    mutating func rebaseWorkspaceOrigin(
        translation: Vector3D,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommit = false
        defer {
            if didCommit == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }

        let tolerance = modelingSettings.tolerance
        cadDocument = try cadDocument.translatingSources(
            by: translation,
            tolerance: tolerance
        )
        for featureID in cadDocument.designGraph.order {
            guard let node = cadDocument.designGraph.nodes[featureID],
                  case .extrude = node.operation else {
                continue
            }
            try synchronizeObjectPropertiesFromSource(
                featureID: featureID,
                objectRegistry: objectRegistry
            )
        }
        try cadDocument.validate(tolerance: tolerance)
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommit = true
    }
}
