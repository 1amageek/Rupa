import Testing
import RupaAutomation
import RupaCore
import SwiftCAD

@MainActor
@Test func automationCreatesLoftThroughEditorSession() async throws {
    var document = DesignDocument.empty()
    let firstProfileID = try createAutomationLoftProfile(
        in: &document,
        name: "Automation Loft Bottom",
        width: 4.0,
        height: 2.0,
        z: 0.0
    )
    let secondProfileID = try createAutomationLoftProfile(
        in: &document,
        name: "Automation Loft Top",
        width: 6.0,
        height: 3.0,
        z: 10.0
    )
    let session = EditorSession(document: document)

    let result = try AutomationRunner().execute(
        .createLoft(
            name: "Automation Ruled Loft",
            sections: [
                LoftSectionReference(
                    profile: ProfileReference(featureID: firstProfileID),
                    startSampleIndex: 1
                ),
                LoftSectionReference(
                    profile: ProfileReference(featureID: secondProfileID),
                    startSampleIndex: 1
                ),
            ],
            options: LoftOptions(resultKind: .solid)
        ),
        in: session
    )

    let loftID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[loftID])
    guard case .loft(let loft) = feature.operation else {
        Issue.record("Automation must create a loft feature.")
        return
    }

    #expect(result.message == "Loft Automation Ruled Loft source created.")
    #expect(result.commandName == "createLoft")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(loft.sections.map(\.featureID) == [firstProfileID, secondProfileID])
    #expect(loft.sections.map(\.startSampleIndex) == [1, 1])
    #expect(feature.outputs == [FeatureOutput(role: .body)])
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

private func createAutomationLoftProfile(
    in document: inout DesignDocument,
    name: String,
    width: Double,
    height: Double,
    z: Double
) throws -> FeatureID {
    try document.createRectangleSketch(
        name: name,
        plane: automationLoftPlane(z: z),
        width: .length(width, .millimeter),
        height: .length(height, .millimeter)
    )
}

private func automationLoftPlane(z: Double) -> SketchPlane {
    if z == 0.0 {
        return .xy
    }
    return .plane(Plane3D(
        origin: Point3D(x: 0.0, y: 0.0, z: z / 1000.0),
        normal: .unitZ
    ))
}
