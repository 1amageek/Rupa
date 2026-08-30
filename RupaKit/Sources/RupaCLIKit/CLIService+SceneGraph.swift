import Foundation
import RupaAgentProtocol
import RupaAgentTransport
import RupaCore

public extension CLIService {
    func sceneGraphSnapshotLiveSession(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol
    ) throws -> SceneGraphSnapshotResult {
        let response = try client.send(
            .sceneGraphSnapshot(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration
            )
        )
        switch response {
        case .sceneGraphSnapshot(let snapshot):
            return snapshot
        case .failure(let error):
            throw error
        default:
            throw EditorError(
                code: .commandFailed,
                message: "Scene-graph snapshot request returned an unexpected response."
            )
        }
    }
}
