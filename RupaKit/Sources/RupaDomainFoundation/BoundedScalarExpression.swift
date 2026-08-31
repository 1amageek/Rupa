public indirect enum BoundedScalarExpression: Sendable, Equatable, Hashable {
    case literal(SemanticTypedValue)
    case parameter(ProgramParameterID)
    case add(BoundedScalarExpression, BoundedScalarExpression)
    case subtract(BoundedScalarExpression, BoundedScalarExpression)
    case multiply(BoundedScalarExpression, BoundedScalarExpression)
    case divide(BoundedScalarExpression, BoundedScalarExpression)
    case negate(BoundedScalarExpression)
}
