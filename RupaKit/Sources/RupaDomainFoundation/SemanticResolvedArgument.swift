import RupaAutomation

public indirect enum SemanticResolvedArgument: Sendable, Equatable, Hashable {
    case value(SemanticTypedValue)
    case source(SemanticSourceReference, preparedSlot: PreparedAutomationSlotID)
    case local(SemanticOutputReference, preparedSlot: PreparedAutomationSlotID)
    case array([SemanticResolvedArgument])
    case object([SemanticResolvedObjectEntry])

    public var type: SemanticValueType {
        switch self {
        case .value(let value): return value.type
        case .source(let reference, _): return reference.type
        case .local(let reference, _): return reference.kind
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
