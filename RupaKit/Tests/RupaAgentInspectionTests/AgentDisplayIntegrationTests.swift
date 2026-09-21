import Foundation
import RupaAgentIntegrationTestFixtures
import RupaAgentProtocol
import RupaCore
import Testing
@testable import RupaAgentRuntime

@Test func agentReturnsCADInteractionQualityAssessmentWithoutSession() async throws {
    let response = AgentCommandController().handle(.cadInteractionQualityAssessment)

    guard case .cadInteractionQualityAssessment(let assessment) = response else {
        #expect(Bool(false))
        return
    }
    #expect(assessment.counts.entryCount == assessment.entries.count)
    #expect(assessment.entries.contains { $0.area == .dimensions })
    #expect(assessment.entries.contains { $0.area == .agentOperability })
    #expect(Set(assessment.entries.map(\.area)) == Set(CADInteractionQualityArea.allCases))
    #expect(assessment.entries.map(\.area).count == Set(assessment.entries.map(\.area)).count)
}

@MainActor
@Test func agentReturnsDesignDisplaySnapshotForViewportPlanning() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let gridSettings = ViewportGridSettings(visualSpacingMode: .fixed)
    _ = try session.execute(.setViewportGridSettings(gridSettings))
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .designDisplaySnapshot(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    let codec = AgentMessageCodec()
    let decodedResponse = try codec.decodeResponse(from: try codec.encode(response))

    guard case .designDisplaySnapshot(let snapshot) = response else {
        #expect(Bool(false))
        return
    }
    let sketch = try #require(snapshot.sketches.first)
    let extrude = try #require(snapshot.extrudes.first)
    let body = try #require(snapshot.bodies.first)

    #expect(snapshot.generation == session.generation)
    #expect(snapshot.dirty == session.isDirty)
    #expect(snapshot.viewportGridSettings == gridSettings)
    #expect(snapshot.viewportGridScale.visualSpacingMode == .fixed)
    #expect(snapshot.sketches.count == 1)
    #expect(snapshot.extrudes.count == 1)
    #expect(snapshot.bodies.count == 1)
    #expect(snapshot.componentDefinitions.isEmpty)
    #expect(snapshot.componentInstances.isEmpty)
    #expect(snapshot.patternArrays.isEmpty)
    #expect(sketch.primitives.count == 4)
    #expect(sketch.regions.count == 1)
    #expect(extrude.profileFeatureID == sketch.featureID)
    #expect(extrude.depthMeters > 0.0)
    #expect(body.mesh.positions.isEmpty == false)
    #expect(body.topology.faces.count == 6)
    #expect(body.topology.edges.count == 12)
    #expect(body.topology.vertices.count == 8)
    #expect(decodedResponse == response)
}
