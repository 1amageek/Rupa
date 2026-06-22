public enum SketchDimensionInputValueError: Error, Equatable, Sendable {
    case nonFiniteLength
    case nonPositiveLength
    case nonFiniteAngle
    case nonFiniteWidth
    case nonPositiveWidth
    case nonFiniteHeight
    case nonPositiveHeight

    public var message: String {
        switch self {
        case .nonFiniteLength:
            return "Sketch dimension length input requires a finite value."
        case .nonPositiveLength:
            return "Sketch dimension length input requires a positive value."
        case .nonFiniteAngle:
            return "Sketch dimension angle input requires a finite value."
        case .nonFiniteWidth:
            return "Sketch dimension width input requires a finite value."
        case .nonPositiveWidth:
            return "Sketch dimension width input requires a positive value."
        case .nonFiniteHeight:
            return "Sketch dimension height input requires a finite value."
        case .nonPositiveHeight:
            return "Sketch dimension height input requires a positive value."
        }
    }
}
