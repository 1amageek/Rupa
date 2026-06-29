import Testing
import Foundation
import RupaAutomation
import RupaCore
import SwiftCAD
@testable import RupaAgent

@MainActor
@Test func agentCreatesLoftSourceThroughAutomationAndCore() async throws {
    var document = DesignDocument.empty()
    let firstProfileID = try createAgentLoftProfile(
        in: &document,
        name: "Agent Loft Bottom",
        width: 4.0,
        height: 2.0,
        z: 0.0
    )
    let secondProfileID = try createAgentLoftProfile(
        in: &document,
        name: "Agent Loft Top",
        width: 6.0,
        height: 3.0,
        z: 10.0
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createLoft(
                name: "Agent Ruled Loft",
                sections: [
                    LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
                    LoftSectionReference(profile: ProfileReference(featureID: secondProfileID)),
                ],
                options: LoftOptions(resultKind: .solid)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a loft command result.")
        return
    }
    let loftID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[loftID])
    guard case .loft(let loft) = feature.operation else {
        Issue.record("Agent must create a loft feature.")
        return
    }

    #expect(result.commandName == "createLoft")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(loft.sections.map(\.featureID) == [firstProfileID, secondProfileID])
    #expect(loft.options.resultKind == .solid)
    #expect(feature.outputs == [FeatureOutput(role: .body)])
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(result.diagnostics.contains { diagnostic in diagnostic.severity == .error } == false)
}

private func createAgentLoftProfile(
    in document: inout DesignDocument,
    name: String,
    width: Double,
    height: Double,
    z: Double
) throws -> FeatureID {
    try document.createRectangleSketch(
        name: name,
        plane: agentLoftPlane(z: z),
        width: .length(width, .millimeter),
        height: .length(height, .millimeter)
    )
}

private func agentLoftPlane(z: Double) -> SketchPlane {
    if z == 0.0 {
        return .xy
    }
    return .plane(Plane3D(
        origin: Point3D(x: 0.0, y: 0.0, z: z / 1000.0),
        normal: .unitZ
    ))
}
