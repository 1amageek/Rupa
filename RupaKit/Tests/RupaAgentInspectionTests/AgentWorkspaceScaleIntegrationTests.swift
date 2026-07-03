import Foundation
import RupaAutomation
import RupaCore
import SwiftCAD
import Testing
@testable import RupaAgent

@MainActor
@Test func agentAppliesRegionalWorkspaceScalePresetThroughCommandController() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setWorkspaceScalePreset(.regionalPlanning),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    let codec = AgentMessageCodec()
    let decodedResponse = try codec.decodeResponse(from: try codec.encode(response))

    guard case .command(let result) = response else {
        Issue.record("Expected regional workspace scale command response.")
        return
    }

    #expect(result.commandName == "setRulerConfiguration")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(result.workspaceScale?.matchedPreset == .regionalPlanning)
    #expect(result.workspaceScale?.displayUnit == .kilometer)
    #expect(result.workspaceScale?.visibleSpanMeters == 1_000_000.0)
    #expect(result.workspaceScale?.visibleSpanDisplayValue == 1_000.0)
    #expect(result.workspaceInteractionScale?.operationStep.meters == 1_000.0)
    #expect(result.workspaceInteractionScale?.operationStep.displayValue == 1.0)
    #expect(result.workspaceInteractionScale?.operationStep.displayUnitSymbol == "km")
    #expect(result.viewportGridScale?.visualSpacingMode == .adaptive)
    #expect(result.viewportGridScale?.snapStep.meters == 1_000.0)
    #expect(result.viewportGridScale?.snapStep.displayValue == 1.0)
    #expect(result.viewportGridScale?.workspaceSpan.text == "1,000 km")
    #expect(result.workspaceScalePresetOptions?.map(\.preset) == WorkspaceScalePreset.allCases)
    #expect(result.workspaceScalePresetOptions?.contains { option in
        option.preset == .regionalPlanning
            && option.visibleSpanTitle == "1,000 km"
            && option.comfortableModelSpanTitle == "10 km to 800 km"
    } == true)
    #expect(result.message.contains("Regional Planning"))
    #expect(decodedResponse == response)
    #expect(session.document.displayUnit == .kilometer)
    #expect(
        session.document.ruler == WorkspaceScalePreset.regionalPlanning.rulerConfiguration
            .normalizedForWorkspaceScale()
    )
}

@MainActor
@Test func agentAppliesUrbanWorkspaceScalePresetThroughCommandController() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setWorkspaceScalePreset(.urbanPlanning),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    let codec = AgentMessageCodec()
    let decodedResponse = try codec.decodeResponse(from: try codec.encode(response))

    guard case .command(let result) = response else {
        Issue.record("Expected urban workspace scale command response.")
        return
    }

    #expect(result.commandName == "setRulerConfiguration")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(result.workspaceScale?.matchedPreset == .urbanPlanning)
    #expect(result.workspaceScale?.displayUnit == .kilometer)
    #expect(result.workspaceScale?.visibleSpanMeters == 25_000.0)
    #expect(result.workspaceScale?.visibleSpanDisplayValue == 25.0)
    #expect(result.workspaceInteractionScale?.operationStep.meters == 10.0)
    #expect(result.workspaceInteractionScale?.operationStep.displayUnitSymbol == "m")
    #expect(result.viewportGridScale?.snapStep.meters == 10.0)
    #expect(result.viewportGridScale?.workspaceSpan.text == "25 km")
    #expect(result.workspaceScalePresetOptions?.map(\.preset) == WorkspaceScalePreset.allCases)
    #expect(result.message.contains("Urban Planning"))
    #expect(decodedResponse == response)
    #expect(session.document.displayUnit == .kilometer)
    #expect(
        session.document.ruler == WorkspaceScalePreset.urbanPlanning.rulerConfiguration
            .normalizedForWorkspaceScale()
    )
}

@MainActor
@Test func agentSetsViewportGridSettingsThroughCommandController() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)
    let settings = ViewportGridSettings(visualSpacingMode: .fixed)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setViewportGridSettings(settings),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Expected viewport grid settings command response.")
        return
    }

    #expect(result.commandName == "setViewportGridSettings")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(result.viewportGridSettings == settings)
    #expect(result.viewportGridScale?.visualSpacingMode == .fixed)
    #expect(result.viewportGridScale?.snapStep.meters == session.document.ruler.minorTickMeters)
    #expect(result.viewportGridScale?.workspaceSpan.meters == session.document.ruler.visibleSpanMeters)
    #expect(session.document.productMetadata.viewportGridSettings == settings)
}

@MainActor
@Test func agentLargeGeometryCommandReportsWorkspaceRangeThroughCommandController() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangleFromCorners(
                name: "Agent Site Mass",
                plane: .xy,
                firstCorner: SketchPoint(
                    x: .length(0.0, .meter),
                    y: .length(0.0, .meter)
                ),
                oppositeCorner: SketchPoint(
                    x: .length(25_000.0, .meter),
                    y: .length(10_000.0, .meter)
                ),
                depth: .length(100.0, .meter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    let codec = AgentMessageCodec()
    let decodedResponse = try codec.decodeResponse(from: try codec.encode(response))

    guard case .command(let result) = response else {
        Issue.record("Expected large geometry command response.")
        return
    }

    #expect(result.commandName == "createExtrudedRectangleFromCorners")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(result.workspaceBounds?.sizeX == 25_000.0)
    #expect(result.workspaceBounds?.sizeY == 10_000.0)
    #expect(result.workspaceBounds?.sizeZ == 100.0)
    #expect(result.workspaceBounds?.maximumSpan == 25_000.0)
    #expect(result.workspaceScaleRecommendation?.reason == .modelExceedsComfortableSpan)
    #expect(result.workspaceScaleRecommendation?.recommendedPreset == .sitePlanning)
    #expect(result.workspaceScaleRecommendation?.recommendedScale.displayUnit == .kilometer)
    #expect(result.workspaceScalePresetOptions?.map(\.preset) == WorkspaceScalePreset.allCases)
    #expect(decodedResponse == response)
}

@MainActor
@Test func agentFitsWorkspaceScaleToLargeModelThroughCommandController() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: try agentSiteDocument())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .fitWorkspaceScaleToModel,
            expectedGeneration: session.generation
        )
    )
    let codec = AgentMessageCodec()
    let decodedResponse = try codec.decodeResponse(from: try codec.encode(response))

    guard case .command(let result) = response else {
        Issue.record("Expected workspace scale fit command response.")
        return
    }

    #expect(result.commandName == "setRulerConfiguration")
    #expect(result.didMutate)
    #expect(result.workspaceScale?.matchedPreset == .sitePlanning)
    #expect(result.workspaceScale?.displayUnit == .kilometer)
    #expect(result.workspaceScale?.visibleSpanDisplayValue == 100.0)
    #expect(result.viewportGridScale?.snapStep.meters == 100.0)
    #expect(result.viewportGridScale?.snapStep.displayValue == 0.1)
    #expect(result.viewportGridScale?.workspaceSpan.text == "100 km")
    #expect(result.workspaceBounds?.maximumSpan == 25_000.0)
    #expect(result.workspaceScaleRecommendation == nil)
    #expect(result.workspaceScalePresetOptions?.map(\.preset) == WorkspaceScalePreset.allCases)
    #expect(result.message.contains("Workspace scale fitted to Site Planning"))
    #expect(session.document.displayUnit == .kilometer)
    #expect(
        session.document.ruler == WorkspaceScalePreset.sitePlanning.rulerConfiguration
            .normalizedForWorkspaceScale()
    )
    #expect(decodedResponse == response)
}

@MainActor
@Test func agentFitsWorkspaceScaleToUrbanModelThroughCommandController() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: try agentUrbanDocument())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .fitWorkspaceScaleToModel,
            expectedGeneration: session.generation
        )
    )
    let codec = AgentMessageCodec()
    let decodedResponse = try codec.decodeResponse(from: try codec.encode(response))

    guard case .command(let result) = response else {
        Issue.record("Expected urban workspace scale fit command response.")
        return
    }

    #expect(result.commandName == "setRulerConfiguration")
    #expect(result.didMutate)
    #expect(result.workspaceScale?.matchedPreset == .urbanPlanning)
    #expect(result.workspaceScale?.displayUnit == .kilometer)
    #expect(result.workspaceScale?.visibleSpanDisplayValue == 25.0)
    #expect(result.viewportGridScale?.snapStep.meters == 10.0)
    #expect(result.viewportGridScale?.workspaceSpan.text == "25 km")
    #expect(result.workspaceBounds?.maximumSpan == 5_000.0)
    #expect(result.workspaceScaleRecommendation == nil)
    #expect(result.workspaceScalePresetOptions?.map(\.preset) == WorkspaceScalePreset.allCases)
    #expect(result.message.contains("Workspace scale fitted to Urban Planning"))
    #expect(session.document.displayUnit == .kilometer)
    #expect(
        session.document.ruler == WorkspaceScalePreset.urbanPlanning.rulerConfiguration
            .normalizedForWorkspaceScale()
    )
    #expect(decodedResponse == response)
}

@MainActor
@Test func agentDesignDisplaySnapshotReportsWorkspaceScaleRecommendationThroughCommandController() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: try agentSiteDocument())
    _ = try session.execute(.setViewportGridSettings(.standard))
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
        Issue.record("Expected Agent design display snapshot response.")
        return
    }

    #expect(snapshot.workspaceScaleRecommendation?.reason == .modelExceedsComfortableSpan)
    #expect(snapshot.workspaceScaleRecommendation?.recommendedPreset == .sitePlanning)
    #expect(snapshot.workspaceScaleRecommendation?.recommendedScale.displayUnit == .kilometer)
    #expect(snapshot.workspaceScaleRecommendation?.recommendedScaleProfile.comfortableModelSpanTitle == "1 km to 80 km")
    #expect(snapshot.workspaceScalePresetOptions.map(\.preset) == WorkspaceScalePreset.allCases)
    #expect(snapshot.workspaceScalePresetOptions.contains { option in
        option.preset == .regionalPlanning
            && option.visibleSpanTitle == "1,000 km"
            && option.comfortableModelSpanTitle == "10 km to 800 km"
    })
    #expect(snapshot.workspaceBounds?.sizeX == 25_000.0)
    #expect(snapshot.workspaceBounds?.sizeY == 10_000.0)
    #expect(snapshot.workspaceBounds?.sizeZ == 100.0)
    #expect(snapshot.workspaceBounds?.maximumSpan == 25_000.0)
    #expect(snapshot.workspaceInteractionScale.displayUnit == .millimeter)
    #expect(snapshot.workspaceInteractionScale.operationStep.meters == 0.001)
    #expect(snapshot.workspaceInteractionScale.operationStep.displayValue == 1.0)
    #expect(snapshot.workspaceInteractionScale.operationStep.displayUnitSymbol == "mm")
    #expect(decodedResponse == response)
}

private func agentSiteDocument() throws -> DesignDocument {
    var document = DesignDocument.empty(named: "Agent Site")
    let profileID = try document.createRectangleSketchFromCorners(
        name: "Agent Site Footprint",
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
        name: "Agent Site Mass",
        profile: ProfileReference(featureID: profileID),
        distance: .length(100.0, .meter),
        direction: .normal
    )
    return document
}

private func agentUrbanDocument() throws -> DesignDocument {
    var document = DesignDocument.empty(named: "Agent Urban")
    let profileID = try document.createRectangleSketchFromCorners(
        name: "Agent Urban Footprint",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(0.0, .meter),
            y: .length(0.0, .meter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(5_000.0, .meter),
            y: .length(2_000.0, .meter)
        )
    )
    _ = try document.extrudeProfile(
        name: "Agent Urban Mass",
        profile: ProfileReference(featureID: profileID),
        distance: .length(100.0, .meter),
        direction: .normal
    )
    return document
}
