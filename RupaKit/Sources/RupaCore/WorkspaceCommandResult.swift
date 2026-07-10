public struct WorkspaceCommandResult: Sendable {
    public let commandName: String
    public let revision: WorkspaceRevision
    public let diagnostics: [EditorDiagnostic]

    public init(
        commandName: String,
        revision: WorkspaceRevision,
        diagnostics: [EditorDiagnostic] = []
    ) {
        self.commandName = commandName
        self.revision = revision
        self.diagnostics = diagnostics
    }
}
