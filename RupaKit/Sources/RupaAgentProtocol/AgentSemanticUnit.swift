import RupaDomainFoundation

public enum AgentSemanticUnit: String, Codable, Equatable, Sendable {
    case unitless
    case meter
    case degree

    public init(_ value: SemanticUnit) {
        self = switch value {
        case .unitless: .unitless
        case .meter: .meter
        case .degree: .degree
        }
    }

    public var semanticValue: SemanticUnit {
        switch self {
        case .unitless: .unitless
        case .meter: .meter
        case .degree: .degree
        }
    }
}
