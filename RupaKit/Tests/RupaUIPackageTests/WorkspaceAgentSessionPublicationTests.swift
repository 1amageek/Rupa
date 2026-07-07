import Foundation
import RupaCore
import Testing
@testable import RupaUI

@MainActor
@Test func workspaceAgentSessionPublicationRegistersOnceForStableSession() {
    let publisher = RecordingWorkspaceAgentSessionPublisher()
    let session = EditorSession(document: .empty(named: "Agent Publication"))
    var publication = WorkspaceAgentSessionPublication()

    publication.publish(publisher: publisher, session: session, path: nil)
    publication.publish(publisher: publisher, session: session, path: nil)

    #expect(publisher.registrations.count == 1)
    #expect(publisher.unregisteredIDs.isEmpty)
}

@MainActor
@Test func workspaceAgentSessionPublicationRepublishesWhenPathChanges() {
    let publisher = RecordingWorkspaceAgentSessionPublisher()
    let session = EditorSession(document: .empty(named: "Agent Publication"))
    let path = URL(fileURLWithPath: "/tmp/rupa-agent-publication.swcad")
    var publication = WorkspaceAgentSessionPublication()

    publication.publish(publisher: publisher, session: session, path: nil)
    let firstID = publisher.registrations[0].id
    publication.publish(publisher: publisher, session: session, path: path)

    #expect(publisher.registrations.count == 2)
    #expect(publisher.unregisteredIDs == [firstID])
    #expect(publisher.registrations[1].path == path)
}

@MainActor
@Test func workspaceAgentSessionPublicationMovesRegistrationWhenPublisherChanges() {
    let firstPublisher = RecordingWorkspaceAgentSessionPublisher()
    let secondPublisher = RecordingWorkspaceAgentSessionPublisher()
    let session = EditorSession(document: .empty(named: "Agent Publication"))
    var publication = WorkspaceAgentSessionPublication()

    publication.publish(publisher: firstPublisher, session: session, path: nil)
    let firstID = firstPublisher.registrations[0].id
    publication.publish(publisher: secondPublisher, session: session, path: nil)

    #expect(firstPublisher.unregisteredIDs == [firstID])
    #expect(secondPublisher.registrations.count == 1)
}

@MainActor
@Test func workspaceAgentSessionPublicationDeactivatesWhenPublisherBecomesUnavailable() {
    let publisher = RecordingWorkspaceAgentSessionPublisher()
    let session = EditorSession(document: .empty(named: "Agent Publication"))
    var publication = WorkspaceAgentSessionPublication()

    publication.publish(publisher: publisher, session: session, path: nil)
    let firstID = publisher.registrations[0].id
    publication.publish(publisher: nil, session: session, path: nil)

    #expect(publisher.unregisteredIDs == [firstID])
}

@MainActor
private final class RecordingWorkspaceAgentSessionPublisher: WorkspaceAgentSessionPublishing {
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
