import Foundation
import RupaCore

@MainActor
struct WorkspaceAgentSessionPublication {
    private var registration: Registration?

    mutating func publish(
        publisher: (any WorkspaceAgentSessionPublishing)?,
        session: EditorSession,
        path: URL?
    ) {
        let key = Key(publisher: publisher, session: session, path: path)
        guard registration?.key != key else {
            return
        }

        deactivate()
        guard let publisher else {
            return
        }

        registration = Registration(
            publisher: publisher,
            id: publisher.register(session: session, path: path),
            key: key
        )
    }

    mutating func deactivate() {
        guard let registration else {
            return
        }

        registration.publisher.unregister(id: registration.id)
        self.registration = nil
    }
}

extension WorkspaceAgentSessionPublication {
    struct Key: Equatable {
        private var publisherID: ObjectIdentifier?
        private var sessionID: ObjectIdentifier
        private var path: URL?

        init(
            publisher: (any WorkspaceAgentSessionPublishing)?,
            session: EditorSession,
            path: URL?
        ) {
            self.publisherID = publisher.map { ObjectIdentifier($0) }
            self.sessionID = ObjectIdentifier(session)
            self.path = path
        }
    }

    private struct Registration {
        var publisher: any WorkspaceAgentSessionPublishing
        var id: UUID
        var key: Key
    }
}
