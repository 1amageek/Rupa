import Foundation
import RupaCore

@MainActor
public protocol WorkspaceAgentHost: AnyObject {
    func start() async

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
