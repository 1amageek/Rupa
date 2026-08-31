public indirect enum SemanticTypedValue: Sendable, Equatable, Hashable {
    case text(String)
    case boolean(Bool)
    case integer(Int64)
    case number(Double, unit: SemanticUnit)
    case point(SemanticPoint3D)
    case direction(SemanticDirection3D)
    case plane(SemanticPlane)
    case transform(SemanticTransform)
    case array([SemanticTypedValue])
    case object([SemanticObjectEntry])

    public var type: SemanticValueType {
        switch self {
        case .text: return .text
        case .boolean: return .boolean
        case .integer: return .integer
        case .number(_, let unit): return .number(unit: unit)
        case .point: return .point
        case .direction: return .direction
        case .plane: return .plane
        case .transform: return .transform
        case .array(let values):
            guard let firstType = values.first?.type else {
                return .array(element: nil)
            }
            guard values.dropFirst().allSatisfy({ $0.type == firstType }) else {
                return .array(element: nil)
            }
            return .array(element: firstType)
        case .object: return .object
        }
    }
}
