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
                    startSampleIndex: 1,
                    smoothTangentScale: 0.75,
                    smoothTangentMode: .zero
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
    #expect(loft.sections.map(\.smoothTangentScale) == [0.75, nil])
    #expect(loft.sections.map(\.smoothTangentMode) == [.zero, .automatic])
    #expect(feature.outputs == [FeatureOutput(role: .body)])
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func automationCreatesClosedSectionLoopLoftSheetThroughEditorSession() async throws {
    var document = DesignDocument.empty()
    // Three sections standing around a ring, each facing along it, so the loop through them
    // closes; parallel sections stacked in a zig-zag are refused by the kernel.
    let h = 3.0.squareRoot() / 2
    let planes: [Plane3D] = [
        Plane3D(origin: Point3D(x: 0.02, y: 0, z: 0), normal: .unitZ),
        Plane3D(origin: Point3D(x: -0.01, y: 0, z: 0.02 * h), normal: Vector3D(x: -h, y: 0, z: -0.5)),
        Plane3D(origin: Point3D(x: -0.01, y: 0, z: -0.02 * h), normal: Vector3D(x: h, y: 0, z: -0.5)),
    ]
    let profileIDs = try planes.enumerated().map { index, plane in
        try document.createRectangleSketch(
            name: "Automation Loop \(index + 1)",
            plane: .plane(plane),
            width: .length(4.0, .millimeter),
            height: .length(2.0, .millimeter)
        )
    }
    let (firstProfileID, secondProfileID, thirdProfileID) = (profileIDs[0], profileIDs[1], profileIDs[2])
    let session = EditorSession(document: document)

    let result = try AutomationRunner().execute(
        .createLoft(
            name: "Automation Closed Loop Loft Sheet",
            sections: [
                LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
                LoftSectionReference(profile: ProfileReference(featureID: secondProfileID)),
                LoftSectionReference(profile: ProfileReference(featureID: thirdProfileID)),
            ],
            options: LoftOptions(resultKind: .sheet, closesSectionLoop: true)
        ),
        in: session
    )

    let loftID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[loftID])
    guard case .loft(let loft) = feature.operation else {
        Issue.record("Automation must create a closed loop loft feature.")
        return
    }

    #expect(result.commandName == "createLoft")
    #expect(result.didMutate)
    #expect(loft.options.resultKind == .sheet)
    #expect(loft.options.closesSectionLoop)
    #expect(feature.outputs == [FeatureOutput(role: .sheet)])
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

private func createAutomationLoftProfile(
    in document: inout DesignDocument,
    name: String,
    width: Double,
    height: Double,
    x: Double = 0.0,
    z: Double
) throws -> FeatureID {
    try document.createRectangleSketch(
        name: name,
        plane: automationLoftPlane(x: x, z: z),
        width: .length(width, .millimeter),
        height: .length(height, .millimeter)
    )
}

private func automationLoftPlane(x: Double = 0.0, z: Double) -> SketchPlane {
    if x == 0.0 && z == 0.0 {
        return .xy
    }
    return .plane(Plane3D(
        origin: Point3D(x: x / 1000.0, y: 0.0, z: z / 1000.0),
        normal: .unitZ
    ))
}
