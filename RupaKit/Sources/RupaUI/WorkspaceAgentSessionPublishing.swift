import Foundation
import RupaCore

@MainActor
public protocol WorkspaceAgentSessionPublishing: AnyObject {
    @discardableResult
    func register(
        session: EditorSession,
        path: URL?,
        id: UUID
    ) -> UUID

    func unregister(id: UUID)
}

public extension WorkspaceAgentSessionPublishing {
    @discardableResult
    func register(
        session: EditorSession,
        path: URL? = nil
    ) -> UUID {
        register(session: session, path: path, id: UUID())
    }
}
