import Foundation
import Testing
import RupaAutomation
import RupaCore
import SwiftCAD
@testable import RupaAgent

private func contractSavedView() -> SavedView {
    SavedView(
        name: "Agent Iso",
        camera: SavedViewCamera(
            target: Point3D(x: 0.0, y: 0.0, z: 0.0),
            distanceMeters: 0.5,
            yawRadians: 30.0 * .pi / 180.0,
            pitchRadians: -25.0 * .pi / 180.0,
            rollRadians: 0.0
        ),
        projection: .orthographic(heightMeters: 0.2),
        displayScale: SavedViewDisplayScale(
            ruler: WorkspaceScalePreset.productDesign.rulerConfiguration
                .normalizedForWorkspaceScale(),
            scaleBarLengthMeters: nil
        )
    )
}

@Suite struct SavedViewCodecContractTests {
    @Test func createSavedViewRequestRoundTripsThroughCodec() throws {
        let request = AgentRequest.execute(
            sessionID: UUID(),
            command: .createSavedView(contractSavedView()),
            expectedGeneration: nil
        )

        let codec = AgentMessageCodec()
        let encoded = try codec.encode(request, id: "view-create-1")
        let decoded = try codec.decodeRequest(from: encoded)
        #expect(decoded == request)
    }

    @Test func describeSavedViewsRequestRoundTripsThroughCodec() throws {
        let request = AgentRequest.execute(
            sessionID: UUID(),
            command: .describeSavedViews,
            expectedGeneration: nil
        )

        let codec = AgentMessageCodec()
        let encoded = try codec.encode(request, id: "view-list-1")
        let decoded = try codec.decodeRequest(from: encoded)
        #expect(decoded == request)
    }

    @MainActor
    @Test func savedViewResponsesRoundTripThroughCodec() throws {
        let server = AgentCommandController()
        let sessionID = UUID()
        let session = EditorSession()
        server.register(session: session, id: sessionID)
        let codec = AgentMessageCodec()

        let createResponse = server.handle(
            .execute(
                sessionID: sessionID,
                command: .createSavedView(contractSavedView()),
                expectedGeneration: DocumentGeneration(0)
            )
        )
        let createEncoded = try codec.encode(createResponse, id: "r1", method: "command.apply")
        let createDecoded = try codec.decodeResponse(
            from: createEncoded,
            expectedID: "r1",
            expectedMethod: "command.apply"
        )
        #expect(createDecoded == createResponse)

        let listResponse = server.handle(
            .execute(
                sessionID: sessionID,
                command: .describeSavedViews,
                expectedGeneration: DocumentGeneration(1)
            )
        )
        let listEncoded = try codec.encode(listResponse, id: "r2", method: "command.apply")
        let listDecoded = try codec.decodeResponse(
            from: listEncoded,
            expectedID: "r2",
            expectedMethod: "command.apply"
        )
        #expect(listDecoded == listResponse)
        guard case .command(let result) = listDecoded else {
            Issue.record("describeSavedViews must decode as a command result.")
            return
        }
        #expect(result.savedViews?.count == 1)
    }
}
