import RupaCore

@MainActor
struct PatternArrayExpressionWritebackService {
    let document: DesignDocument
    let submit: (EditorCommand) -> Void
    let report: (String, EditorDiagnostic.Severity) -> Void

    func updateReferencedExpression(
        _ expression: CADExpression,
        quantity: Quantity
    ) -> PatternArrayExpressionWritebackResult? {
        guard case .reference(let parameterID) = expression else {
            return nil
        }
        guard let parameter = document.cadDocument.parameters.parameters[parameterID],
              parameter.kind == quantity.kind else {
            report(
                "Pattern Array parameter reference could not be updated.",
                .warning
            )
            return .blocked
        }
        submit(
            .upsertParameter(
                name: parameter.name,
                expression: .constant(quantity),
                kind: parameter.kind
            )
        )
        return .updated
    }
}

enum PatternArrayExpressionWritebackResult {
    case updated
    case blocked
}
