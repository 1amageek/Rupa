import SwiftCAD

/// Describes and replaces the length expression of a supported native operation.
public protocol FeatureLengthEditing: Sendable {
    func length(in operation: FeatureOperation) -> FeatureLengthDefinition?
    func replacingLength(in operation: FeatureOperation, with expression: CADExpression) throws -> FeatureOperation
}
