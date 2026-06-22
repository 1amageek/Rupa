import SwiftCAD

public struct BridgeCurveEndpoint: Codable, Equatable, Hashable, Sendable {
    public var reference: SketchReference
    public var parameter: CADExpression?
    public var reversesSense: Bool
    public var tension: BridgeCurveTension

    public init(
        reference: SketchReference,
        parameter: CADExpression? = nil,
        reversesSense: Bool = false,
        tension: BridgeCurveTension = .balanced
    ) {
        self.reference = reference
        self.parameter = parameter
        self.reversesSense = reversesSense
        self.tension = tension
    }
}
