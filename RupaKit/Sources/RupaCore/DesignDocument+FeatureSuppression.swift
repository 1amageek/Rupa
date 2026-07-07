import SwiftCAD

public extension DesignDocument {
    @discardableResult
    mutating func setFeatureSuppression(
        featureID: FeatureID,
        isSuppressed: Bool,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> Bool {
        guard var feature = cadDocument.designGraph.nodes[featureID] else {
            throw DocumentValidationError.invalidProductMetadata(
                "Feature suppression requires an existing feature."
            )
        }
        guard feature.isSuppressed != isSuppressed else {
            return false
        }

        var updatedCADDocument = cadDocument
        feature.isSuppressed = isSuppressed
        try updatedCADDocument.replaceFeature(feature)

        var updatedDocument = self
        updatedDocument.cadDocument = updatedCADDocument
        try updatedDocument.validate(objectRegistry: objectRegistry)
        self = updatedDocument
        return true
    }
}
