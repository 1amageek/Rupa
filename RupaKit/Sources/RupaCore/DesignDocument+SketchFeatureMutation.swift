import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    @discardableResult
    mutating func appendSketchFeature(
        name: String,
        sketch: Sketch,
        typeID: ObjectTypeID? = nil,
        geometryRole: ObjectDescriptor.GeometryRole = .sketchProfile,
        properties: ObjectPropertySet = ObjectPropertySet(),
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: name,
            operation: .sketch(sketch),
            outputs: [
                FeatureOutput(role: .profile),
                FeatureOutput(role: .curve),
            ]
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitSketch = false
        defer {
            if didCommitSketch == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }

        try appendFeature(feature)
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: name,
            reference: .sketch(featureID),
            object: .sketch(
                featureID: featureID,
                typeID: typeID,
                geometryRole: geometryRole,
                properties: properties,
                objectRegistry: objectRegistry
            )
        )
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommitSketch = true
        return featureID
    }
}
