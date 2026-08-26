import Foundation
import RupaAutomation
import RupaAgentIntegrationTestFixtures
import RupaCore
import SwiftCAD
import Testing
@testable import RupaAgent

@MainActor
@Test func agentAppliesRegionalWorkspaceScalePresetThroughCommandController() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    let sourceState = try AgentDocumentSourceState(document: session.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setWorkspaceScalePreset(.regionalPlanning),
            expectedGeneration: DocumentGeneration(0),
            expectedWorkspaceRevision: WorkspaceRevision(0)
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
    #expect(result.generation == DocumentGeneration(0))
    #expect(result.workspaceRevision == WorkspaceRevision(1))
    #expect(result.workspaceScale == nil)
    #expect(result.message.contains("Regional Planning"))

    let context = try agentWorkspaceContext(server: server, sessionID: sessionID, expectedGeneration: session.generation)
    #expect(context.workspaceScale?.matchedPreset == .regionalPlanning)
    #expect(context.workspaceScale?.displayUnit == .kilometer)
    #expect(context.workspaceScale?.visibleSpanMeters == 1_000_000.0)
    #expect(context.workspaceScale?.visibleSpanDisplayValue == 1_000.0)
    #expect(context.workspaceInteractionScale?.operationStep.meters == 1_000.0)
    #expect(context.workspaceInteractionScale?.operationStep.displayValue == 1.0)
    #expect(context.workspaceInteractionScale?.operationStep.displayUnitSymbol == "km")
    #expect(context.viewportGridScale?.visualSpacingMode == .adaptive)
    #expect(context.viewportGridScale?.snapStep.meters == 1_000.0)
    #expect(context.viewportGridScale?.snapStep.displayValue == 1.0)
    #expect(context.viewportGridScale?.workspaceSpan.text == "1,000 km")
    #expect(context.workspaceScalePresetOptions?.map(\.preset) == WorkspaceScalePreset.allCases)
    #expect(context.workspaceScalePresetOptions?.contains { option in
        option.preset == .regionalPlanning
            && option.visibleSpanTitle == "1,000 km"
            && option.comfortableModelSpanTitle == "10 km to 800 km"
    } == true)
    #expect(decodedResponse == response)
    #expect(try AgentDocumentSourceState(document: session.document) == sourceState)
    #expect(
        session.workspaceState.ruler == WorkspaceScalePreset.regionalPlanning.rulerConfiguration
            .normalizedForWorkspaceScale()
    )
}

@MainActor
@Test func agentAppliesUrbanWorkspaceScalePresetThroughCommandController() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    let sourceState = try AgentDocumentSourceState(document: session.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setWorkspaceScalePreset(.urbanPlanning),
            expectedGeneration: DocumentGeneration(0),
            expectedWorkspaceRevision: WorkspaceRevision(0)
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
    #expect(result.generation == DocumentGeneration(0))
    #expect(result.workspaceRevision == WorkspaceRevision(1))
    #expect(result.workspaceScale == nil)
    #expect(result.message.contains("Urban Planning"))

    let context = try agentWorkspaceContext(server: server, sessionID: sessionID, expectedGeneration: session.generation)
    #expect(context.workspaceScale?.matchedPreset == .urbanPlanning)
    #expect(context.workspaceScale?.displayUnit == .kilometer)
    #expect(context.workspaceScale?.visibleSpanMeters == 25_000.0)
    #expect(context.workspaceScale?.visibleSpanDisplayValue == 25.0)
    #expect(context.workspaceInteractionScale?.operationStep.meters == 10.0)
    #expect(context.workspaceInteractionScale?.operationStep.displayUnitSymbol == "m")
    #expect(context.viewportGridScale?.snapStep.meters == 10.0)
    #expect(context.viewportGridScale?.workspaceSpan.text == "25 km")
    #expect(context.workspaceScalePresetOptions?.map(\.preset) == WorkspaceScalePreset.allCases)
    #expect(decodedResponse == response)
    #expect(try AgentDocumentSourceState(document: session.document) == sourceState)
    #expect(
        session.workspaceState.ruler == WorkspaceScalePreset.urbanPlanning.rulerConfiguration
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
            expectedGeneration: DocumentGeneration(0),
            expectedWorkspaceRevision: WorkspaceRevision(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Expected viewport grid settings command response.")
        return
    }

    #expect(result.commandName == "setViewportGridSettings")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(0))
    #expect(result.workspaceRevision == WorkspaceRevision(1))
    #expect(session.workspaceState.viewportGridSettings == settings)

    let context = try agentWorkspaceContext(server: server, sessionID: sessionID, expectedGeneration: session.generation)
    #expect(context.viewportGridSettings == settings)
    #expect(context.viewportGridScale?.visualSpacingMode == .fixed)
    #expect(context.viewportGridScale?.snapStep.meters == session.workspaceState.ruler.minorTickMeters)
    #expect(context.viewportGridScale?.workspaceSpan.meters == session.workspaceState.ruler.visibleSpanMeters)
}

@MainActor
@Test func agentWorkspaceMutationRequiresCurrentWorkspaceRevision() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let missingRevisionResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setDisplayUnit(.meter),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .failure(let missingRevisionError) = missingRevisionResponse else {
        Issue.record("Workspace mutation without a revision must fail.")
        return
    }
    #expect(missingRevisionError.code == .commandInvalid)
    #expect(session.workspaceState.revision == WorkspaceRevision(0))

    let acceptedResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setDisplayUnit(.meter),
            expectedGeneration: DocumentGeneration(0),
            expectedWorkspaceRevision: WorkspaceRevision(0)
        )
    )
    guard case .command = acceptedResponse else {
        Issue.record("Workspace mutation with the current revision must succeed.")
        return
    }
    #expect(session.workspaceState.revision == WorkspaceRevision(1))

    let staleRevisionResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setViewportGridSettings(.standard),
            expectedGeneration: DocumentGeneration(0),
            expectedWorkspaceRevision: WorkspaceRevision(0)
        )
    )
    guard case .failure(let staleRevisionError) = staleRevisionResponse else {
        Issue.record("Workspace mutation with a stale revision must fail.")
        return
    }
    #expect(staleRevisionError.code == .workspaceRevisionMismatch)
    #expect(session.workspaceState.revision == WorkspaceRevision(1))
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
    #expect(result.workspaceBounds == nil)
    #expect(decodedResponse == response)

    let context = try agentWorkspaceContext(server: server, sessionID: sessionID, expectedGeneration: session.generation)
    #expect(context.workspaceBounds?.sizeX == 25_000.0)
    #expect(context.workspaceBounds?.sizeY == 10_000.0)
    #expect(context.workspaceBounds?.sizeZ == 100.0)
    #expect(context.workspaceBounds?.maximumSpan == 25_000.0)
    #expect(context.workspaceScaleRecommendation?.reason == .modelExceedsComfortableSpan)
    #expect(context.workspaceScaleRecommendation?.recommendedPreset == .sitePlanning)
    #expect(context.workspaceScaleRecommendation?.recommendedScale.displayUnit == .kilometer)
    #expect(context.workspaceScalePresetOptions?.map(\.preset) == WorkspaceScalePreset.allCases)
}

@MainActor
@Test func agentFitsWorkspaceScaleToLargeModelThroughCommandController() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: try agentSiteDocument())
    let sourceState = try AgentDocumentSourceState(document: session.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .fitWorkspaceScaleToModel,
            expectedGeneration: session.generation,
            expectedWorkspaceRevision: session.workspaceState.revision
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
    #expect(result.workspaceScale == nil)
    #expect(result.message.contains("Workspace scale fitted to Site Planning"))

    let context = try agentWorkspaceContext(server: server, sessionID: sessionID, expectedGeneration: session.generation)
    #expect(context.workspaceScale?.matchedPreset == .sitePlanning)
    #expect(context.workspaceScale?.displayUnit == .kilometer)
    #expect(context.workspaceScale?.visibleSpanDisplayValue == 100.0)
    #expect(context.viewportGridScale?.snapStep.meters == 100.0)
    #expect(context.viewportGridScale?.snapStep.displayValue == 0.1)
    #expect(context.viewportGridScale?.workspaceSpan.text == "100 km")
    #expect(context.workspaceBounds?.maximumSpan == 25_000.0)
    #expect(context.workspaceScaleRecommendation == nil)
    #expect(context.workspaceScalePresetOptions?.map(\.preset) == WorkspaceScalePreset.allCases)
    #expect(result.generation == DocumentGeneration(0))
    #expect(result.workspaceRevision == WorkspaceRevision(1))
    #expect(try AgentDocumentSourceState(document: session.document) == sourceState)
    #expect(
        session.workspaceState.ruler == WorkspaceScalePreset.sitePlanning.rulerConfiguration
            .normalizedForWorkspaceScale()
    )
    #expect(decodedResponse == response)
}

@MainActor
@Test func agentFitsWorkspaceScaleToUrbanModelThroughCommandController() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: try agentUrbanDocument())
    let sourceState = try AgentDocumentSourceState(document: session.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .fitWorkspaceScaleToModel,
            expectedGeneration: session.generation,
            expectedWorkspaceRevision: session.workspaceState.revision
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
    #expect(result.workspaceScale == nil)
    #expect(result.message.contains("Workspace scale fitted to Urban Planning"))

    let context = try agentWorkspaceContext(server: server, sessionID: sessionID, expectedGeneration: session.generation)
    #expect(context.workspaceScale?.matchedPreset == .urbanPlanning)
    #expect(context.workspaceScale?.displayUnit == .kilometer)
    #expect(context.workspaceScale?.visibleSpanDisplayValue == 25.0)
    #expect(context.viewportGridScale?.snapStep.meters == 10.0)
    #expect(context.viewportGridScale?.workspaceSpan.text == "25 km")
    #expect(context.workspaceBounds?.maximumSpan == 5_000.0)
    #expect(context.workspaceScaleRecommendation == nil)
    #expect(context.workspaceScalePresetOptions?.map(\.preset) == WorkspaceScalePreset.allCases)
    #expect(result.generation == DocumentGeneration(0))
    #expect(result.workspaceRevision == WorkspaceRevision(1))
    #expect(try AgentDocumentSourceState(document: session.document) == sourceState)
    #expect(
        session.workspaceState.ruler == WorkspaceScalePreset.urbanPlanning.rulerConfiguration
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


/// Rich workspace context is attached only to a trailing describeDocument
/// request under the incremental agent transaction contract.
@MainActor
private func agentWorkspaceContext(
    server: AgentCommandController,
    sessionID: UUID,
    expectedGeneration: DocumentGeneration
) throws -> AutomationResult {
    let response = server.handle(
        .executeBatch(
            sessionID: sessionID,
            batch: AutomationBatch(
                commands: [.describeDocument],
                expectedGeneration: expectedGeneration
            )
        )
    )
    guard case .batch(let batchResult) = response,
          let context = batchResult.results.last else {
        throw EditorError(
            code: .commandFailed,
            message: "Agent workspace context request must return a batch result."
        )
    }
    return context
}

private struct AgentDocumentSourceState: Equatable {
    var fingerprint: CADDocumentSourceFingerprint
    var modelingSettings: DocumentModelingSettings
    var productMetadata: ProductMetadata

    init(document: DesignDocument) throws {
        fingerprint = try document.cadDocument.sourceFingerprint(
            tolerance: document.modelingSettings.tolerance
        )
        modelingSettings = document.modelingSettings
        productMetadata = document.productMetadata
    }
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
