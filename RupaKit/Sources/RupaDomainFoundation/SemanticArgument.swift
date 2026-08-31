public indirect enum SemanticArgument: Sendable, Equatable, Hashable {
    case literal(SemanticTypedValue)
    case parameter(ProgramParameterID)
    case existing(SemanticSourceReference)
    case local(SemanticOutputReference)
    case expression(BoundedScalarExpression)
    case array([SemanticArgument])
    case object([SemanticArgumentObjectEntry])
}
