import RupaCoreTypes

/// Request-scoped diagnostic without an unrelated session-local UUID.
public struct ProjectSemanticDiagnostic: Sendable, Equatable {
    public let severity: EditorDiagnostic.Severity
    public let code: EditorDiagnostic.Code?
    public let message: String

    public init(
        severity: EditorDiagnostic.Severity,
        code: EditorDiagnostic.Code?,
        message: String
    ) {
        self.severity = severity
        self.code = code
        self.message = message
    }

    init(_ diagnostic: EditorDiagnostic) {
        self.init(
            severity: diagnostic.severity,
            code: diagnostic.code,
            message: diagnostic.message
        )
    }
}
