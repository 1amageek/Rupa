import RupaCore

@MainActor
struct PatternArrayExpressionWritebackService {
    let session: EditorSession

    func updateReferencedExpression(
        _ expression: CADExpression,
        quantity: Quantity
    ) -> PatternArrayExpressionWritebackResult? {
        guard case .reference(let parameterID) = expression else {
            return nil
        }
        guard let parameter = session.document.cadDocument.parameters.parameters[parameterID],
              parameter.kind == quantity.kind else {
            session.reportToolStatus(
                "Pattern Array parameter reference could not be updated.",
                severity: .warning
            )
            return .blocked
        }
        let commandResult = session.perform(
            .upsertParameter(
                name: parameter.name,
                expression: .constant(quantity),
                kind: parameter.kind
            )
        )
        return .updated(commandResult)
    }
}

enum PatternArrayExpressionWritebackResult {
    case updated(CommandExecutionResult?)
    case blocked
}
