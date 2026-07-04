import Foundation
import RupaAutomation
import RupaCore
import SwiftCAD
import Testing
@testable import RupaAgent

@Test func agentCreatesUpdatesReadsAndRemovesSavedViews() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)
    let viewID = SavedViewID()
    let savedView = agentSavedView(id: viewID, name: " Agent Site View ")

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSavedView(savedView),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        #expect(Bool(false))
        return
    }
    #expect(createResult.commandName == "createSavedView")
    #expect(createResult.didMutate)
    #expect(createResult.savedViewID == viewID)
    #expect(createResult.savedViews?.first?.name == "Agent Site View")
    #expect(createResult.savedViews?.first?.displayScale.matchedPreset == .sitePlanning)

    let snapshotResponse = server.handle(
        .designDisplaySnapshot(
            sessionID: sessionID,
            expectedGeneration: createResult.generation
        )
    )
    guard case .designDisplaySnapshot(let snapshot) = snapshotResponse else {
        #expect(Bool(false))
        return
    }
    let snapshotView = try #require(snapshot.savedViews.first)
    #expect(snapshotView.id == viewID)
    #expect(snapshotView.displayScale.scaleBarLengthMeters == 1_000.0)

    var updatedView = snapshotView
    updatedView.name = "Agent Regional View"
    updatedView.projection = .perspective(fieldOfViewRadians: Double.pi / 3.0)
    updatedView.displayScale = SavedViewDisplayScale(
        ruler: WorkspaceScalePreset.regionalPlanning.rulerConfiguration,
        scaleBarLengthMeters: 10_000.0
    )
    let updateResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .updateSavedView(updatedView),
            expectedGeneration: createResult.generation
        )
    )
    guard case .command(let updateResult) = updateResponse else {
        #expect(Bool(false))
        return
    }
    #expect(updateResult.commandName == "updateSavedView")
    #expect(updateResult.savedViews?.first?.name == "Agent Regional View")
    #expect(updateResult.savedViews?.first?.projection.mode == .perspective)
    #expect(updateResult.savedViews?.first?.displayScale.matchedPreset == .regionalPlanning)

    let describeResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .describeSavedViews,
            expectedGeneration: updateResult.generation
        )
    )
    guard case .command(let describeResult) = describeResponse else {
        #expect(Bool(false))
        return
    }
    #expect(describeResult.commandName == nil)
    #expect(!describeResult.didMutate)
    #expect(describeResult.savedViews?.map(\.id) == [viewID])

    let removeResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .removeSavedView(id: viewID),
            expectedGeneration: updateResult.generation
        )
    )
    guard case .command(let removeResult) = removeResponse else {
        #expect(Bool(false))
        return
    }
    #expect(removeResult.commandName == "removeSavedView")
    #expect(removeResult.didMutate)
    #expect(removeResult.savedViewID == viewID)
    #expect(removeResult.savedViews?.isEmpty == true)
}

private func agentSavedView(
    id: SavedViewID,
    name: String
) -> SavedView {
    SavedView(
        id: id,
        name: name,
        camera: SavedViewCamera(
            target: Point3D(x: 2_500.0, y: 50.0, z: 1_250.0),
            distanceMeters: 8_000.0,
            yawRadians: 0.4,
            pitchRadians: -0.5
        ),
        projection: .orthographic(heightMeters: 5_000.0),
        clipping: SavedViewClipping(
            nearDistanceMeters: 5.0,
            farDistanceMeters: 50_000.0
        ),
        displayScale: SavedViewDisplayScale(
            ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration,
            scaleBarLengthMeters: 1_000.0
        )
    )
}
