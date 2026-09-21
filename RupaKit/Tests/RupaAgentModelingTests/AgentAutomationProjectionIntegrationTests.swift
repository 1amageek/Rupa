import Foundation
import RupaAgentIntegrationTestFixtures
import RupaCore
import Testing
@testable import RupaAgentRuntime

@Test func agentListsRegisteredSessions() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    server.register(
        session: EditorSession(document: .empty(named: "Open Document")),
        path: URL(fileURLWithPath: "/tmp/open.swcad"),
        id: sessionID
    )

    let response = server.handle(.sessions)

    guard case .sessions(let sessions) = response else {
        #expect(Bool(false))
        return
    }
    #expect(sessions.count == 1)
    #expect(sessions[0].id == sessionID)
    #expect(sessions[0].displayName == "Open Document")
    #expect(sessions[0].authority.documentGeneration == DocumentGeneration(0))
}
