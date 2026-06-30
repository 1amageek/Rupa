import SwiftCAD

public struct BridgeCurveEndpoint: Codable, Equatable, Hashable, Sendable {
    public var reference: SketchReference
    public var parameter: CADExpression?
    public var reversesSense: Bool
    public var trimSide: BridgeCurveTrimSide
    public var tension: BridgeCurveTension

    public init(
        reference: SketchReference,
        parameter: CADExpression? = nil,
        reversesSense: Bool = false,
        trimSide: BridgeCurveTrimSide = .towardStart,
        tension: BridgeCurveTension = .balanced
    ) {
        self.reference = reference
        self.parameter = parameter
        self.reversesSense = reversesSense
        self.trimSide = trimSide
        self.tension = tension
    }

    private enum CodingKeys: String, CodingKey {
        case reference
        case parameter
        case reversesSense
        case trimSide
        case tension
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.reference = try container.decode(SketchReference.self, forKey: .reference)
        self.parameter = try container.decodeIfPresent(CADExpression.self, forKey: .parameter)
        self.reversesSense = try container.decode(Bool.self, forKey: .reversesSense)
        self.trimSide = try container.decodeIfPresent(BridgeCurveTrimSide.self, forKey: .trimSide) ?? .towardStart
        self.tension = try container.decode(BridgeCurveTension.self, forKey: .tension)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reference, forKey: .reference)
        try container.encodeIfPresent(parameter, forKey: .parameter)
        try container.encode(reversesSense, forKey: .reversesSense)
        try container.encode(trimSide, forKey: .trimSide)
        try container.encode(tension, forKey: .tension)
    }
}
