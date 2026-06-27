import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    public mutating func addSketchConstraint(
        featureID: FeatureID,
        constraint: SketchConstraint,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard var feature = cadDocument.designGraph.nodes[featureID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch constraint requires an existing sketch feature."
            )
        }
        guard case var .sketch(sketch) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch constraint requires a sketch feature."
            )
        }
        guard !sketch.constraints.contains(constraint) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch constraint already exists."
            )
        }

        var candidateSketch = sketch
        candidateSketch.constraints.append(constraint)
        var candidateFeature = feature
        candidateFeature.operation = .sketch(candidateSketch)
        var candidateCADDocument = cadDocument
        do {
            try candidateCADDocument.replaceFeature(candidateFeature)
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch constraint references invalid geometry: \(error)."
            )
        }

        let constraintPropagator = SketchPointConstraintPropagator(parameters: cadDocument.parameters)
        try constraintPropagator.satisfyAddingConstraint(
            constraint,
            in: &sketch,
            owner: "Sketch constraint"
        )
        feature.operation = .sketch(sketch)

        var updatedCADDocument = cadDocument
        do {
            try updatedCADDocument.replaceFeature(feature)
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch constraint references invalid geometry: \(error)."
            )
        }

        cadDocument = updatedCADDocument
        try synchronizeSketchObjectProperties(
            featureID: featureID,
            sketch: sketch,
            objectRegistry: objectRegistry
        )
        try synchronizeObjectPropertiesAffectedBySketch(
            featureID: featureID,
            objectRegistry: objectRegistry
        )
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func removeSketchConstraint(
        featureID: FeatureID,
        constraint: SketchConstraint,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard var feature = cadDocument.designGraph.nodes[featureID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch constraint removal requires an existing sketch feature."
            )
        }
        guard case var .sketch(sketch) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch constraint removal requires a sketch feature."
            )
        }
        guard let index = sketch.constraints.firstIndex(of: constraint) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch constraint does not exist."
            )
        }

        sketch.constraints.remove(at: index)
        feature.operation = .sketch(sketch)

        var updatedCADDocument = cadDocument
        do {
            try updatedCADDocument.replaceFeature(feature)
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch constraint removal leaves invalid geometry: \(error)."
            )
        }

        cadDocument = updatedCADDocument
        try synchronizeSketchObjectProperties(
            featureID: featureID,
            sketch: sketch,
            objectRegistry: objectRegistry
        )
        try synchronizeObjectPropertiesAffectedBySketch(
            featureID: featureID,
            objectRegistry: objectRegistry
        )
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }
}
