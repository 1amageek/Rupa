import SwiftCAD

public struct BridgeCurveTension: Codable, Equatable, Hashable, Sendable {
    public var first: CADExpression
    public var second: CADExpression
    public var third: CADExpression

    public init(
        first: CADExpression,
        second: CADExpression,
        third: CADExpression
    ) {
        self.first = first
        self.second = second
        self.third = third
    }

    public static let balanced = BridgeCurveTension(
        first: .scalar(1.0),
        second: .scalar(1.0),
        third: .scalar(1.0)
    )
}
