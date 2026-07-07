import Foundation
import RupaCore

@MainActor
public protocol WorkspaceAgentHost: AnyObject {
    @discardableResult
    func register(
        session: EditorSession,
        path: URL?,
        id: UUID
    ) -> UUID

    func unregister(id: UUID)
}

public extension WorkspaceAgentHost {
    @discardableResult
    func register(
        session: EditorSession,
        path: URL? = nil
    ) -> UUID {
        register(session: session, path: path, id: UUID())
    }
}
