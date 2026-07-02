import Foundation
import RupaAutomation
import RupaCore
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
    #expect(result.message.contains("Regional Planning"))
    #expect(session.document.displayUnit == .kilometer)
    #expect(
        session.document.ruler == WorkspaceScalePreset.regionalPlanning.rulerConfiguration
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
    #expect(session.document.productMetadata.viewportGridSettings == settings)
}
