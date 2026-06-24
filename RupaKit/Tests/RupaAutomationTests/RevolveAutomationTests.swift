import Testing
import RupaAutomation
import RupaCore
import SwiftCAD

@MainActor
@Test func automationCreatesRevolveThroughEditorSession() async throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketchFromCorners(
        name: "Automation Revolve Profile",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(5.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    let session = EditorSession(document: document)

    let result = try AutomationRunner().execute(
        .createRevolve(
            name: "Automation Revolved Body",
            profile: ProfileReference(featureID: profileID),
            axis: RevolveAxis(origin: .origin, direction: .unitY),
            angle: .angle(270.0, .degree)
        ),
        in: session
    )

    let revolveID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[revolveID])
    guard case .revolve(let revolve) = feature.operation else {
        Issue.record("Automation must create a revolve feature.")
        return
    }

    #expect(result.message == "Revolve Automation Revolved Body source created.")
    #expect(result.commandName == "createRevolve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(revolve.profile == ProfileReference(featureID: profileID))
    #expect(revolve.axis.direction == .unitY)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}
