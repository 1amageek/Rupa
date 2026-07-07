import Foundation
import RupaCore

@MainActor
struct WorkspaceAgentSessionPublication {
    private var registration: Registration?

    mutating func publish(
        host: (any WorkspaceAgentHost)?,
        session: EditorSession,
        path: URL?
    ) {
        let key = Key(host: host, session: session, path: path)
        guard registration?.key != key else {
            return
        }

        deactivate()
        guard let host else {
            return
        }

        registration = Registration(
            host: host,
            id: host.register(session: session, path: path),
            key: key
        )
    }

    mutating func deactivate() {
        guard let registration else {
            return
        }

        registration.host.unregister(id: registration.id)
        self.registration = nil
    }
}

extension WorkspaceAgentSessionPublication {
    struct Key: Equatable {
        private var hostID: ObjectIdentifier?
        private var sessionID: ObjectIdentifier
        private var path: URL?

        init(
            host: (any WorkspaceAgentHost)?,
            session: EditorSession,
            path: URL?
        ) {
            self.hostID = host.map { ObjectIdentifier($0) }
            self.sessionID = ObjectIdentifier(session)
            self.path = path
        }
    }

    private struct Registration {
        var host: any WorkspaceAgentHost
        var id: UUID
        var key: Key
    }
}
