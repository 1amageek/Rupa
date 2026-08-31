import RupaProject

public struct ProjectSemanticProgramCommit: Sendable {
    public let authority: ProjectAuthorityCoordinate
    public let outputs: [ProjectSemanticOutputBinding]
    public let diagnostics: [ProjectSemanticDiagnostic]
    public let telemetry: ProjectSemanticTelemetry
    public let view: ProjectViewSnapshot

    public init(
        authority: ProjectAuthorityCoordinate,
        outputs: [ProjectSemanticOutputBinding],
        diagnostics: [ProjectSemanticDiagnostic],
        telemetry: ProjectSemanticTelemetry,
        view: ProjectViewSnapshot
    ) {
        self.authority = authority
        self.outputs = outputs
        self.diagnostics = diagnostics
        self.telemetry = telemetry
        self.view = view
    }
}
