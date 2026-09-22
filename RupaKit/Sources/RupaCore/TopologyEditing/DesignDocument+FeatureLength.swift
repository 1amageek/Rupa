import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    public mutating func setFeatureLength(
        featureID: FeatureID, expression: CADExpression,
        using editor: any FeatureLengthEditing = NativeFeatureLengthEditor(),
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let validated = try validate(objectRegistry: objectRegistry)
        _ = try setFeatureLength(featureID: featureID, expression: expression,
            using: editor, validatedDocument: validated)
    }

    @discardableResult
    package mutating func setFeatureLength(
        featureID: FeatureID, expression: CADExpression,
        using editor: any FeatureLengthEditing = NativeFeatureLengthEditor(),
        validatedDocument: ValidatedDesignDocument
    ) throws -> ValidatedDesignDocument {
        guard validatedDocument.document.modelingSettings == modelingSettings,
              LiveDocumentEvaluationIdentity(document: validatedDocument.document.cadDocument).matches(cadDocument) else {
            throw EditorError(code: .commandInvalid, message: "Dimension editing requires validation for the current document source.")
        }
        guard var feature = cadDocument.designGraph.nodes[featureID] else {
            throw EditorError(code: .referenceUnresolved, message: "Dimension editing requires an existing feature.")
        }
        _ = try resolvedLengthValue(expression, owner: "Feature length")
        feature.operation = try editor.replacingLength(in: feature.operation, with: expression)
        let updated = try validatedDocument.validatedCADDocument.replacingGraphStableFeature(feature)
        cadDocument = updated.document
        return ValidatedDesignDocument(document: self, validatedCADDocument: updated)
    }
}
