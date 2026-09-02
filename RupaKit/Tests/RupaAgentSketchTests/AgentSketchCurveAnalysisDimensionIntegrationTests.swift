import Foundation
import RupaAgentIntegrationTestFixtures
import RupaAutomation
import RupaCore
import SwiftCAD
import Testing
@testable import RupaAgent

@MainActor
@Test func agentAnalyzesOpenSessionCurvesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Agent Analysis Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .curveAnalysis(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )

    guard case .curveAnalysis(let analysis) = response else {
        #expect(Bool(false))
        return
    }
    #expect(analysis.counts.curveCount == 1)
    let spline = try #require(analysis.curves.first { $0.curveKind == .spline })
    #expect(spline.samples.count == 17)
    #expect(spline.maxAbsCurvature > 1.0)
    #expect(spline.selectionComponentID?.hasPrefix(SelectionComponentID.sketchEntityPrefix) == true)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentAnalyzesConstrainedEndpointContinuityWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoLineUnconstrainedSketchDocument(name: "Agent Curve Continuity")
    let session = EditorSession(document: setup.document)
    _ = try session.execute(
        .addSketchConstraint(
            featureID: setup.featureID,
            constraint: .coincident(.lineEnd(setup.firstLineID), .lineStart(setup.secondLineID))
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .curveAnalysis(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )

    guard case .curveAnalysis(let analysis) = response else {
        #expect(Bool(false))
        return
    }
    #expect(analysis.counts.curveCount == 2)
    #expect(analysis.counts.continuityJoinCount == 1)
    let join = try #require(analysis.continuityJoins.first)
    #expect(join.joinKind == .constrainedEndpoint)
    #expect(join.constraintKinds == ["coincident"])
    #expect(join.requiredContinuity == .g0)
    #expect(join.firstReference == "lineEnd:\(setup.firstLineID.description)")
    #expect(join.secondReference == "lineStart:\(setup.secondLineID.description)")
    #expect(join.continuity == .g0)
    #expect(abs(join.positionGap) < 1.0e-12)
    #expect((join.tangentAngle ?? 0.0) > 1.0e-4)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}
