import Foundation
import RupaCore
import Testing
@testable import RupaUI

@MainActor
@Test func workspaceAgentSessionPublicationRegistersOnceForStableSession() {
    let host = RecordingWorkspaceAgentHost()
    let session = EditorSession(document: .empty(named: "Agent Publication"))
    var publication = WorkspaceAgentSessionPublication()

    publication.publish(host: host, session: session, path: nil)
    publication.publish(host: host, session: session, path: nil)

    #expect(host.registrations.count == 1)
    #expect(host.unregisteredIDs.isEmpty)
}

@MainActor
@Test func workspaceAgentSessionPublicationRepublishesWhenPathChanges() {
    let host = RecordingWorkspaceAgentHost()
    let session = EditorSession(document: .empty(named: "Agent Publication"))
    let path = URL(fileURLWithPath: "/tmp/rupa-agent-publication.swcad")
    var publication = WorkspaceAgentSessionPublication()

    publication.publish(host: host, session: session, path: nil)
    let firstID = host.registrations[0].id
    publication.publish(host: host, session: session, path: path)

    #expect(host.registrations.count == 2)
    #expect(host.unregisteredIDs == [firstID])
    #expect(host.registrations[1].path == path)
}

@MainActor
@Test func workspaceAgentSessionPublicationMovesRegistrationWhenHostChanges() {
    let firstHost = RecordingWorkspaceAgentHost()
    let secondHost = RecordingWorkspaceAgentHost()
    let session = EditorSession(document: .empty(named: "Agent Publication"))
    var publication = WorkspaceAgentSessionPublication()

    publication.publish(host: firstHost, session: session, path: nil)
    let firstID = firstHost.registrations[0].id
    publication.publish(host: secondHost, session: session, path: nil)

    #expect(firstHost.unregisteredIDs == [firstID])
    #expect(secondHost.registrations.count == 1)
}

@MainActor
@Test func workspaceAgentSessionPublicationDeactivatesWhenHostBecomesUnavailable() {
    let host = RecordingWorkspaceAgentHost()
    let session = EditorSession(document: .empty(named: "Agent Publication"))
    var publication = WorkspaceAgentSessionPublication()

    publication.publish(host: host, session: session, path: nil)
    let firstID = host.registrations[0].id
    publication.publish(host: nil, session: session, path: nil)

    #expect(host.unregisteredIDs == [firstID])
}

@MainActor
private final class RecordingWorkspaceAgentHost: WorkspaceAgentHost {
    struct Registration {
        var id: UUID
        var session: EditorSession
        var path: URL?
    }

    private(set) var registrations: [Registration] = []
    private(set) var unregisteredIDs: [UUID] = []

    @discardableResult
    func register(
        session: EditorSession,
        path: URL?,
        id: UUID
    ) -> UUID {
        registrations.append(Registration(
            id: id,
            session: session,
            path: path
        ))
        return id
    }

    func unregister(id: UUID) {
        unregisteredIDs.append(id)
    }
}
