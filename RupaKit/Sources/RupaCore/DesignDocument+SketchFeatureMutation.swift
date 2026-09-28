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
        worldTransform: Transform3D? = nil,
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
        let sceneNodeID = try productMetadata.appendSceneNodeToFirstRoot(
            name: name,
            reference: .sketch(featureID),
            object: .sketch(
                featureID: featureID,
                documentID: cadDocument.id,
                typeID: typeID,
                geometryRole: geometryRole,
                properties: properties,
                objectRegistry: objectRegistry
            )
        )
        if let worldTransform {
            let parent = try SceneNodeHierarchy(metadata: productMetadata).parentWorldTransform(of: sceneNodeID)
            try setSceneNodeTransform(id: sceneNodeID, localTransform: parent.inverse().composed(with: worldTransform), objectRegistry: objectRegistry)
        }
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommitSketch = true
        return featureID
    }
}
