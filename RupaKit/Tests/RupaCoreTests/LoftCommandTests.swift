import Testing
import RupaCore
import SwiftCAD

@Test func createLoftAddsSourceFeatureSceneObjectAndEvaluatedSolid() throws {
    var document = DesignDocument.empty()
    let firstProfileID = try createLoftProfile(
        in: &document,
        name: "Loft Bottom Profile",
        width: 4.0,
        height: 2.0,
        z: 0.0
    )
    let secondProfileID = try createLoftProfile(
        in: &document,
        name: "Loft Top Profile",
        width: 6.0,
        height: 3.0,
        z: 10.0
    )

    let loftID = try document.createLoft(
        name: "Ruled Loft",
        sections: [
            LoftSectionReference(
                profile: ProfileReference(featureID: firstProfileID),
                startSampleIndex: 1
            ),
            LoftSectionReference(
                profile: ProfileReference(featureID: secondProfileID),
                startSampleIndex: 1
            ),
        ]
    )
    let feature = try #require(document.cadDocument.designGraph.nodes[loftID])
    let sceneNode = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference == .body(loftID)
    })
    let evaluated = try CADPipeline.modelingDefault(for: document).evaluate(document.cadDocument)
    let body = try #require(evaluated.brep.bodies.values.first)
    let measurement = try MeasurementService().measure(document: document)
    let solid = try #require(measurement.solids.first)

    guard case .loft(let loft) = feature.operation else {
        Issue.record("Loft command must create a loft feature.")
        return
    }

    #expect(feature.name == "Ruled Loft")
    #expect(feature.inputs == [
        FeatureInput(featureID: firstProfileID, role: .profile),
        FeatureInput(featureID: secondProfileID, role: .profile),
    ])
    #expect(feature.outputs == [FeatureOutput(role: .body)])
    #expect(loft.sections.map(\.featureID) == [firstProfileID, secondProfileID])
    #expect(loft.sections.map(\.startSampleIndex) == [1, 1])
    #expect(loft.options.resultKind == .solid)
    #expect(document.cadDocument.designGraph.dependencies.contains(
        DependencyEdge(source: firstProfileID, target: loftID)
    ))
    #expect(document.cadDocument.designGraph.dependencies.contains(
        DependencyEdge(source: secondProfileID, target: loftID)
    ))
    #expect(sceneNode.object?.category == .body)
    #expect(sceneNode.object?.geometryRole == .solid)
    #expect(sceneNode.object?.sourceFeatureID == loftID)
    #expect(sceneNode.object?.sourceSection == .profile(ProfileReference(featureID: firstProfileID)))
    #expect(body.kind == .solid)
    #expect(measurement.counts.solids == 1)
    #expect(measurement.counts.sheets == 0)
    #expect(measurement.diagnostics.isEmpty)
    #expect(solid.featureID == loftID.description)
    #expect(solid.sourceFeatureID == firstProfileID.description)
    #expect(solid.volumeCubicMeters > 0.0)
    #expect(solid.surfaceAreaSquareMeters ?? 0.0 > 0.0)
    try document.validate()
}

@Test func createLoftCanCreateSheetResult() throws {
    var document = DesignDocument.empty()
    let firstProfileID = try createLoftProfile(
        in: &document,
        name: "Loft Sheet Bottom",
        width: 4.0,
        height: 2.0,
        z: 0.0
    )
    let secondProfileID = try createLoftProfile(
        in: &document,
        name: "Loft Sheet Top",
        width: 6.0,
        height: 3.0,
        z: 10.0
    )

    let loftID = try document.createLoft(
        name: "Ruled Loft Sheet",
        sections: [
            LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: secondProfileID)),
        ],
        options: LoftOptions(resultKind: .sheet)
    )
    let feature = try #require(document.cadDocument.designGraph.nodes[loftID])
    let sceneNode = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference == .body(loftID)
    })
    let evaluated = try CADPipeline.modelingDefault(for: document).evaluate(document.cadDocument)
    let body = try #require(evaluated.brep.bodies.values.first)
    let measurement = try MeasurementService().measure(document: document)
    let sheet = try #require(measurement.sheets.first)

    guard case .loft(let loft) = feature.operation else {
        Issue.record("Loft sheet command must create a loft feature.")
        return
    }

    #expect(feature.outputs == [FeatureOutput(role: .sheet)])
    #expect(loft.options.resultKind == .sheet)
    #expect(sceneNode.object?.geometryRole == .surface)
    #expect(body.kind == .sheet)
    #expect(measurement.counts.solids == 0)
    #expect(measurement.counts.sheets == 1)
    #expect(measurement.diagnostics.isEmpty)
    #expect(sheet.featureID == loftID.description)
    #expect(sheet.sourceFeatureID == firstProfileID.description)
    #expect(sheet.surfaceAreaSquareMeters > 0.0)
    try document.validate()
}

@Test func createLoftRejectsUnsupportedMismatchedProfileSampleCountsWithoutMutation() throws {
    var document = DesignDocument.empty()
    let originalOrder = document.cadDocument.designGraph.order
    let firstProfileID = try createLoftProfile(
        in: &document,
        name: "Loft Rect Profile",
        width: 4.0,
        height: 2.0,
        z: 0.0
    )
    let triangleProfileID = try document.createSketch(
        name: "Loft Triangle Profile",
        sketch: loftTriangleProfileSketch(z: 10.0),
        geometryRole: .sketchProfile
    )
    let orderBeforeLoft = document.cadDocument.designGraph.order

    #expect(throws: EditorError.self) {
        _ = try document.createLoft(
            name: "Invalid Loft",
            sections: [
                LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
                LoftSectionReference(profile: ProfileReference(featureID: triangleProfileID)),
            ]
        )
    }
    #expect(document.cadDocument.designGraph.order == orderBeforeLoft)
    #expect(document.cadDocument.designGraph.order != originalOrder)
}

private func createLoftProfile(
    in document: inout DesignDocument,
    name: String,
    width: Double,
    height: Double,
    z: Double
) throws -> FeatureID {
    try document.createRectangleSketch(
        name: name,
        plane: loftPlane(z: z),
        width: .length(width, .millimeter),
        height: .length(height, .millimeter)
    )
}

private func loftPlane(z: Double) -> SketchPlane {
    if z == 0.0 {
        return .xy
    }
    return .plane(Plane3D(
        origin: Point3D(x: 0.0, y: 0.0, z: z / 1000.0),
        normal: .unitZ
    ))
}

private func loftTriangleProfileSketch(z: Double) -> Sketch {
    let first = SketchPoint(x: .length(-2.0, .millimeter), y: .length(-1.0, .millimeter))
    let second = SketchPoint(x: .length(2.0, .millimeter), y: .length(-1.0, .millimeter))
    let third = SketchPoint(x: .length(0.0, .millimeter), y: .length(2.0, .millimeter))
    let firstID = SketchEntityID()
    let secondID = SketchEntityID()
    let thirdID = SketchEntityID()
    return Sketch(
        plane: loftPlane(z: z),
        entities: [
            firstID: .line(SketchLine(start: first, end: second)),
            secondID: .line(SketchLine(start: second, end: third)),
            thirdID: .line(SketchLine(start: third, end: first)),
        ],
        constraints: [
            .coincident(.lineEnd(firstID), .lineStart(secondID)),
            .coincident(.lineEnd(secondID), .lineStart(thirdID)),
            .coincident(.lineEnd(thirdID), .lineStart(firstID)),
        ],
        dimensions: []
    )
}
