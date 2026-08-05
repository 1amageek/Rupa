import Testing
import RupaCore
import SwiftCAD

@Test func createRevolveAddsSourceFeatureWithProfileAxisAndAngle() throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketchFromCorners(
        name: "Revolve Profile",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(4.0, .millimeter),
            y: .length(12.0, .millimeter)
        )
    )
    let axis = RevolveAxis(origin: .origin, direction: .unitY)

    let revolveID = try document.createRevolve(
        name: "Revolved Body",
        profile: ProfileReference(featureID: profileID),
        axis: axis,
        angle: .angle(180.0, .degree)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[revolveID])
    guard case .revolve(let revolve) = feature.operation else {
        Issue.record("Revolve command must create a revolve feature.")
        return
    }
    let sceneNode = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference == .body(revolveID)
    })

    #expect(feature.name == "Revolved Body")
    #expect(feature.inputs == [FeatureInput(featureID: profileID, role: .profile)])
    #expect(feature.outputs == [FeatureOutput(role: .body)])
    #expect(document.cadDocument.designGraph.dependencies.contains(
        DependencyEdge(source: profileID, target: revolveID)
    ))
    #expect(revolve.profile == ProfileReference(featureID: profileID))
    #expect(revolve.axis == axis)
    #expect(revolve.angle == .angle(180.0, .degree))
    #expect(sceneNode.object?.category == .body)
    #expect(sceneNode.object?.sourceFeatureID == revolveID)
    #expect(sceneNode.object?.sourceSection == .profile(ProfileReference(featureID: profileID)))
    try document.validate()
}

@Test func createRevolveRejectsUnsupportedConicalProfileBeforeMutation() throws {
    var document = DesignDocument.empty()
    let profileID = try document.createSketch(
        name: "Conical Revolve Profile",
        sketch: Sketch(
            plane: .xy,
            entities: [
                SketchEntityID(): .line(SketchLine(
                    start: SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                    end: SketchPoint(x: .length(6.0, .millimeter), y: .length(0.0, .millimeter))
                )),
                SketchEntityID(): .line(SketchLine(
                    start: SketchPoint(x: .length(6.0, .millimeter), y: .length(0.0, .millimeter)),
                    end: SketchPoint(x: .length(3.0, .millimeter), y: .length(12.0, .millimeter))
                )),
                SketchEntityID(): .line(SketchLine(
                    start: SketchPoint(x: .length(3.0, .millimeter), y: .length(12.0, .millimeter)),
                    end: SketchPoint(x: .length(0.0, .millimeter), y: .length(12.0, .millimeter))
                )),
                SketchEntityID(): .line(SketchLine(
                    start: SketchPoint(x: .length(0.0, .millimeter), y: .length(12.0, .millimeter)),
                    end: SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter))
                )),
            ]
        ),
        geometryRole: .sketchProfile
    )
    let revolveID = try document.createRevolve(
        name: "Conical Revolve",
        profile: ProfileReference(featureID: profileID),
        axis: RevolveAxis(origin: .origin, direction: .unitY),
        angle: .angle(180.0, .degree)
    )
    let evaluated = try CADPipeline.modelingDefault(for: document).evaluate(document.cadDocument)

    #expect(document.cadDocument.designGraph.order.last == revolveID)
    #expect(evaluated.brep.bodies.count == 1)
    try document.validate()
}

@Test func createRevolveRejectsAxisOutsideProfilePlaneBeforeMutation() throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketchFromCorners(
        name: "Revolve Profile",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(4.0, .millimeter),
            y: .length(12.0, .millimeter)
        )
    )
    _ = try document.createRevolve(
        name: "Rejected Revolve",
        profile: ProfileReference(featureID: profileID),
        axis: RevolveAxis(origin: .origin, direction: .unitZ),
        angle: .angle(180.0, .degree)
    )

    do {
        _ = try CADPipeline.modelingDefault(for: document).evaluate(document.cadDocument)
        Issue.record("Exact kernel must reject a revolve axis outside the profile plane.")
    } catch let error as KernelError {
        #expect(error.message.contains("Revolve axis direction must lie in the profile plane."))
    }
}
