import Foundation
import RupaAutomation
import RupaCore
import RupaAgentIntegrationTestFixtures
import SwiftCAD
import Testing
@testable import RupaAgent

@Test(.timeLimit(.minutes(1)))
func agentCanRebaseFarOriginWorkspaceThroughAutomationCommand() throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(
        document: try agentFarFromOriginRectangleDocument(),
        workspaceState: WorkspaceState(
            ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration
        )
    )
    server.register(session: session, id: sessionID)

    let initialMeasurementResponse = server.handle(.measure(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(0)
    ))
    guard case .measurement(let initialMeasurement) = initialMeasurementResponse else {
        Issue.record("Expected initial measurement response.")
        return
    }
    #expect(initialMeasurement.workspacePrecision?.recommendedRebaseTranslation == Vector3D(
        x: -(1.0e12 + 5.0),
        y: -(1.0e12 + 5.0),
        z: 0.0
    ))

    let response = server.handle(.execute(
        sessionID: sessionID,
        command: .rebaseWorkspaceOrigin(
            translation: Vector3D(x: -1.0e12, y: -1.0e12, z: 0.0)
        ),
        expectedGeneration: DocumentGeneration(0)
    ))

    guard case .command(let result) = response else {
        Issue.record("Expected rebase command result.")
        return
    }
    #expect(result.commandName == "rebaseWorkspaceOrigin")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(result.diagnostics.contains { $0.code == .workspacePrecisionWarning } == false)

    let measurementResponse = server.handle(.measure(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(1)
    ))
    guard case .measurement(let measurement) = measurementResponse else {
        Issue.record("Expected measurement response.")
        return
    }
    #expect(measurement.diagnostics.contains { $0.code == .workspacePrecisionWarning } == false)
    #expect(measurement.workspacePrecision == nil)
}

@Test(.timeLimit(.minutes(1)))
func agentMeasureReportsWorkspaceScaleRecommendationForLargeModel() throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: try agentLargeSiteDocument())
    server.register(session: session, id: sessionID)

    let response = server.handle(.measure(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(0)
    ))

    guard case .measurement(let measurement) = response else {
        Issue.record("Expected measurement response.")
        return
    }
    #expect(measurement.workspaceScaleRecommendation?.reason == .modelExceedsComfortableSpan)
    #expect(measurement.workspaceScaleRecommendation?.recommendedPreset == .sitePlanning)
    #expect(measurement.workspaceScaleRecommendation?.recommendedScale.displayUnit == .kilometer)
    #expect(measurement.workspaceScaleRecommendation?.recommendedScaleProfile.useCaseTitle == "site, campus, and civil-scale coordination")
    #expect(measurement.workspaceScaleRecommendation?.recommendedScaleProfile.comfortableModelSpanTitle == "1 km to 80 km")
    #expect(measurement.workspaceScaleRecommendation?.currentComfortableModelSpanTitle == "10 mm to 800 mm")
}

private func agentFarFromOriginRectangleDocument() throws -> DesignDocument {
    var document = DesignDocument.empty(named: "Agent Remote Site")
    let profileID = try document.createRectangleSketchFromCorners(
        name: "Remote Profile",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(1.0e12, .meter),
            y: .length(1.0e12, .meter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(1.0e12 + 10.0, .meter),
            y: .length(1.0e12 + 10.0, .meter)
        )
    )
    _ = try document.extrudeProfile(
        name: "Remote Solid",
        profile: ProfileReference(featureID: profileID),
        distance: .length(10.0, .meter),
        direction: .normal
    )
    return document
}

private func agentLargeSiteDocument() throws -> DesignDocument {
    var document = DesignDocument.empty(named: "Agent Site")
    let profileID = try document.createRectangleSketchFromCorners(
        name: "Site Footprint",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(0.0, .meter),
            y: .length(0.0, .meter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(25_000.0, .meter),
            y: .length(10_000.0, .meter)
        )
    )
    _ = try document.extrudeProfile(
        name: "Site Mass",
        profile: ProfileReference(featureID: profileID),
        distance: .length(100.0, .meter),
        direction: .normal
    )
    return document
}
