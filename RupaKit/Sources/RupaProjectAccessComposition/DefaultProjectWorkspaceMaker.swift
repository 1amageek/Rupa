import RupaKit

/// Adapts the production workspace factory to the composition-owned seam.
@MainActor
public struct DefaultProjectWorkspaceMaker: ProjectWorkspaceMaking {
    private let factory: DefaultProjectWorkspaceFactory

    public init(
        factory: DefaultProjectWorkspaceFactory = DefaultProjectWorkspaceFactory()
    ) {
        self.factory = factory
    }

    public func makeWorkspace() throws -> ProjectWorkspace {
        try factory.makeWorkspace(document: .empty())
    }
}
