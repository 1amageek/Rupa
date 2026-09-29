import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    @discardableResult
    public mutating func createInvoluteGear(name: String, gear: InvoluteGearFeature,
        objectRegistry: ObjectTypeRegistry = .builtIn) throws -> FeatureID {
        let name = try normalizedMetadataName(name, owner: "Gear")
        var candidate = self
        let feature = try FeatureNodeFactory.make(operation: .involuteGear(gear), name: name,
            in: candidate.cadDocument, tolerance: modelingSettings.tolerance)
        try candidate.appendFeature(feature)
        _ = try candidate.productMetadata.appendSceneNodeToFirstRoot(name: name,
            reference: .body(feature.id), object: .body(featureID: feature.id,
                documentID: cadDocument.id, sourceSection: nil, typeID: nil,
                objectRegistry: objectRegistry))
        try candidate.productMetadata.validate(against: candidate.cadDocument, objectRegistry: objectRegistry)
        self = candidate
        return feature.id
    }

    public mutating func setInvoluteGear(featureID: FeatureID, gear: InvoluteGearFeature,
        objectRegistry: ObjectTypeRegistry = .builtIn) throws {
        let validated = try validate(objectRegistry: objectRegistry)
        _ = try setInvoluteGear(featureID: featureID, gear: gear, validatedDocument: validated)
    }

    @discardableResult
    package mutating func setInvoluteGear(featureID: FeatureID, gear: InvoluteGearFeature,
        validatedDocument: ValidatedDesignDocument) throws -> ValidatedDesignDocument {
        guard validatedDocument.document.modelingSettings == modelingSettings,
              LiveDocumentEvaluationIdentity(document: validatedDocument.document.cadDocument).matches(cadDocument) else {
            throw EditorError(code: .commandInvalid, message: "Gear editing requires validation of the current document source.")
        }
        guard var feature = cadDocument.designGraph.nodes[featureID],
              case .involuteGear = feature.operation else {
            throw EditorError(code: .referenceUnresolved, message: "Gear source no longer exists.")
        }
        feature.operation = .involuteGear(gear)
        let updated = try validatedDocument.validatedCADDocument.replacingGraphStableFeature(feature)
        cadDocument = updated.document
        return ValidatedDesignDocument(document: self, validatedCADDocument: updated)
    }
}
