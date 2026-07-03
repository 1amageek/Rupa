import Foundation
import RupaAutomation
import RupaCore
import SwiftCAD
import Testing
@testable import RupaAgent

@MainActor
@Test func agentAnalyzesSectionThroughAutomationCommand() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: try agentSectionAnalysisTestDocument())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .analyzeSection(
                query: SectionAnalysisQuery(
                    source: .sketchPlane(.yz),
                    toleranceMeters: 1.0e-8
                )
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    let codec = AgentMessageCodec()
    let decodedResponse = try codec.decodeResponse(from: try codec.encode(response))

    guard case .command(let result) = response else {
        Issue.record("Expected Agent section analysis command response.")
        return
    }
    let sectionAnalysis = try #require(result.sectionAnalysis)

    #expect(result.commandName == "analyzeSection")
    #expect(!result.didMutate)
    #expect(result.generation == DocumentGeneration(0))
    #expect(sectionAnalysis.plane.sourceKind == .sketchPlane)
    #expect(sectionAnalysis.intersectingBodyCount == 1)
    #expect(sectionAnalysis.intersectionSegments.isEmpty == false)
    #expect(decodedResponse == response)
}

private func agentSectionAnalysisTestDocument() throws -> DesignDocument {
    var document = DesignDocument.empty(named: "Agent Section Fixture")
    let profileID = try document.createRectangleSketchFromCorners(
        name: "Agent Section Profile",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(-1.0, .meter),
            y: .length(-1.0, .meter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(1.0, .meter),
            y: .length(1.0, .meter)
        )
    )
    _ = try document.extrudeProfile(
        name: "Agent Section Body",
        profile: ProfileReference(featureID: profileID),
        distance: .length(2.0, .meter),
        direction: .normal
    )
    return document
}
