import RupaCore
import RupaProject

/// Builds the default in-process project authority and its MainActor UI adapter.
public struct DefaultProjectWorkspaceFactory: Sendable {
    public init() {}

    @MainActor
    public func makeWorkspace(
        document: DesignDocument = .empty()
    ) throws -> ProjectWorkspace {
        let controller = try ProjectController(
            document: document,
            evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
            projector: DesignDocumentProjectBridge()
        )
        return ProjectWorkspace(project: controller)
    }
}
