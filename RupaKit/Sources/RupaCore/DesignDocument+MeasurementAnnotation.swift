import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// The group saved measurements are listed under.
    public static let measurementsGroupName = "Measurements"

    @discardableResult
    public mutating func addMeasurementAnnotation(
        _ annotation: MeasurementAnnotation,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> MeasurementAnnotationID {
        var nextAnnotation = annotation
        nextAnnotation.name = try normalizedMetadataName(
            annotation.name,
            owner: "Measurement annotation"
        )
        var metadata = productMetadata
        guard metadata.measurements[nextAnnotation.id] == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Measurement annotation IDs must be unique."
            )
        }
        if let sceneNodeID = nextAnnotation.sceneNodeID {
            guard metadata.sceneNodes[sceneNodeID]?.object?.category == .annotation else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Measurement annotation scene node must exist and use an annotation object."
                )
            }
        } else {
            // Saved measurements are listed together under one Measurements group.
            guard let rootID = metadata.rootSceneNodeIDs.first, metadata.sceneNodes[rootID] != nil else {
                throw EditorError(code: .referenceUnresolved, message: "Measurement annotations require a document root.")
            }
            let groupID: SceneNodeID
            if let existing = metadata.sceneNodes[rootID]?.childIDs.first(where: {
                metadata.sceneNodes[$0]?.name == Self.measurementsGroupName
                    && metadata.sceneNodes[$0]?.object?.category == .group
            }) {
                groupID = existing
            } else {
                let group = SceneNode(name: Self.measurementsGroupName, object: .group())
                metadata.sceneNodes[group.id] = group
                metadata.sceneNodes[rootID]?.childIDs.append(group.id)
                groupID = group.id
            }
            let node = SceneNode(name: nextAnnotation.name, object: .annotation())
            metadata.sceneNodes[node.id] = node
            metadata.sceneNodes[groupID]?.childIDs.append(node.id)
            nextAnnotation.sceneNodeID = node.id
        }
        metadata.measurements[nextAnnotation.id] = nextAnnotation
        try metadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        productMetadata = metadata
        return nextAnnotation.id
    }
}
