import Foundation
import RupaAgentProtocol
import RupaCore

public extension CLIService {
    func viewportSnapshotLiveSession(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol
    ) throws -> AgentProjectViewportSnapshot {
        let response = try client.send(
            .viewportSnapshot(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration
            )
        )
        switch response {
        case .viewportSnapshot(let snapshot):
            return snapshot
        case .failure(let error):
            throw error
        default:
            throw EditorError(
                code: .commandFailed,
                message: "Viewport snapshot request returned an unexpected response."
            )
        }
    }
}
