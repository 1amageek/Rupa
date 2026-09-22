import SwiftCAD

public struct FeatureLengthDefinition: Equatable, Sendable {
    public let title: String
    public let expression: CADExpression

    public init(title: String, expression: CADExpression) {
        self.title = title
        self.expression = expression
    }
}
