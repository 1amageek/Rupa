import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
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
            let sceneNodeID = try metadata.appendSceneNodeToFirstRoot(
                name: nextAnnotation.name,
                reference: nil,
                object: .annotation()
            )
            nextAnnotation.sceneNodeID = sceneNodeID
        }
        metadata.measurements[nextAnnotation.id] = nextAnnotation
        try metadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        productMetadata = metadata
        return nextAnnotation.id
    }
}
