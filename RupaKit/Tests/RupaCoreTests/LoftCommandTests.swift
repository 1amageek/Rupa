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

@Test func createLoftUsesGuideEndpointToLockSectionSeam() throws {
    var document = DesignDocument.empty()
    let firstProfileID = try createLoftProfile(
        in: &document,
        name: "Guided Loft Bottom",
        width: 4.0,
        height: 2.0,
        z: 0.0
    )
    let secondProfileID = try createLoftProfile(
        in: &document,
        name: "Guided Loft Top",
        width: 4.0,
        height: 2.0,
        z: 10.0
    )
    let guideID = try document.createSketch(
        name: "Guided Loft Seam",
        sketch: loftVerticalGuideSketch(x: 2.0, y: -1.0, zStart: 0.0, zEnd: 10.0),
        geometryRole: .curve
    )

    let loftID = try document.createLoft(
        name: "Guided Loft",
        sections: [
            LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: secondProfileID)),
        ],
        guides: [
            LoftGuideReference(featureID: guideID),
        ]
    )
    let feature = try #require(document.cadDocument.designGraph.nodes[loftID])
    let evaluated = try CADPipeline.modelingDefault(for: document).evaluate(document.cadDocument)
    let vertexReference = try #require(evaluated.generatedNames[PersistentName(components: [
        .feature(loftID),
        .generated(GeneratedSubshapeRole.vertex.rawValue),
        .index(0),
    ])])
    guard case .loft(let loft) = feature.operation,
          case .vertex(let vertexID) = vertexReference,
          let vertex = evaluated.brep.vertices[vertexID] else {
        Issue.record("Guided Loft must create a loft feature and a generated vertex reference.")
        return
    }

    #expect(loft.guides == [LoftGuideReference(featureID: guideID)])
    #expect(feature.inputs.contains(FeatureInput(featureID: guideID, role: .guide)))
    #expect(vertex.point.isApproximatelyEqual(to: Point3D(x: 0.002, y: -0.001, z: 0.0), tolerance: 1.0e-12))
    try document.validate()
}

@Test func createLoftUsesCurvedGuideToCreateRailFollowingIntermediateRings() throws {
    var document = DesignDocument.empty()
    let firstProfileID = try createLoftProfile(
        in: &document,
        name: "Rail Loft Bottom",
        width: 4.0,
        height: 2.0,
        z: 0.0
    )
    let secondProfileID = try createLoftProfile(
        in: &document,
        name: "Rail Loft Top",
        width: 4.0,
        height: 2.0,
        z: 10.0
    )
    let guideID = try document.createSketch(
        name: "Rail Loft Guide",
        sketch: loftCurvedGuideSketch(x: 2.0, y: -1.0, zStart: 0.0, zEnd: 10.0),
        geometryRole: .curve
    )

    _ = try document.createLoft(
        name: "Rail Loft",
        sections: [
            LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: secondProfileID)),
        ],
        guides: [
            LoftGuideReference(featureID: guideID),
        ]
    )
    let evaluated = try CADPipeline.modelingDefault(for: document).evaluate(document.cadDocument)
    let body = try #require(evaluated.brep.bodies.values.first)
    let railVertices = evaluated.brep.vertices.values.filter { vertex in
        abs(vertex.point.y + 0.001) <= 1.0e-12
            && vertex.point.z > 0.0
            && vertex.point.z < 0.010
            && vertex.point.x > 0.0025
    }

    #expect(body.kind == .solid)
    #expect(evaluated.brep.vertices.count > 8)
    #expect(evaluated.brep.faces.count > 6)
    #expect(railVertices.isEmpty == false)
    try document.validate()
}

@Test func createLoftUsesMultipleCurvedGuidesToCreateDistinctRailConstrainedVertices() throws {
    var document = DesignDocument.empty()
    let firstProfileID = try createLoftProfile(
        in: &document,
        name: "Multi Rail Loft Bottom",
        width: 4.0,
        height: 2.0,
        z: 0.0
    )
    let secondProfileID = try createLoftProfile(
        in: &document,
        name: "Multi Rail Loft Top",
        width: 4.0,
        height: 2.0,
        z: 10.0
    )
    let rightGuideID = try document.createSketch(
        name: "Multi Rail Loft Right Guide",
        sketch: loftCurvedGuideSketch(x: 2.0, y: -1.0, zStart: 0.0, zEnd: 10.0, localXOffset: -0.003),
        geometryRole: .curve
    )
    let leftGuideID = try document.createSketch(
        name: "Multi Rail Loft Left Guide",
        sketch: loftCurvedGuideSketch(x: -2.0, y: 1.0, zStart: 0.0, zEnd: 10.0, localXOffset: 0.003),
        geometryRole: .curve
    )

    _ = try document.createLoft(
        name: "Multi Rail Loft",
        sections: [
            LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: secondProfileID)),
        ],
        guides: [
            LoftGuideReference(featureID: rightGuideID),
            LoftGuideReference(featureID: leftGuideID),
        ]
    )
    let evaluated = try CADPipeline.modelingDefault(for: document).evaluate(document.cadDocument)
    let body = try #require(evaluated.brep.bodies.values.first)
    let rightRailVertices = evaluated.brep.vertices.values.filter { vertex in
        abs(vertex.point.y + 0.001) <= 1.0e-12
            && vertex.point.z > 0.0
            && vertex.point.z < 0.010
            && vertex.point.x > 0.0025
    }
    let leftRailVertices = evaluated.brep.vertices.values.filter { vertex in
        abs(vertex.point.y - 0.001) <= 1.0e-12
            && vertex.point.z > 0.0
            && vertex.point.z < 0.010
            && vertex.point.x < -0.0025
    }

    #expect(body.kind == .solid)
    #expect(evaluated.brep.vertices.count > 8)
    #expect(evaluated.brep.faces.count > 6)
    #expect(rightRailVertices.isEmpty == false)
    #expect(leftRailVertices.isEmpty == false)
    try document.validate()
}

@Test func createLoftUsesCurvedGuideBetweenMultipleProfileSections() throws {
    var document = DesignDocument.empty()
    let firstProfileID = try createLoftProfile(
        in: &document,
        name: "Multi Section Rail Loft Bottom",
        width: 4.0,
        height: 2.0,
        z: 0.0
    )
    let middleProfileID = try createLoftProfile(
        in: &document,
        name: "Multi Section Rail Loft Middle",
        width: 4.0,
        height: 2.0,
        z: 5.0
    )
    let lastProfileID = try createLoftProfile(
        in: &document,
        name: "Multi Section Rail Loft Top",
        width: 4.0,
        height: 2.0,
        z: 10.0
    )
    let guideID = try document.createSketch(
        name: "Multi Section Rail Loft Guide",
        sketch: loftCurvedGuideSketch(x: 2.0, y: -1.0, zStart: 0.0, zEnd: 10.0),
        geometryRole: .curve
    )

    _ = try document.createLoft(
        name: "Multi Section Rail Loft",
        sections: [
            LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: middleProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: lastProfileID)),
        ],
        guides: [
            LoftGuideReference(featureID: guideID),
        ]
    )
    let evaluated = try CADPipeline.modelingDefault(for: document).evaluate(document.cadDocument)
    let body = try #require(evaluated.brep.bodies.values.first)
    let railVertices = evaluated.brep.vertices.values.filter { vertex in
        abs(vertex.point.y + 0.001) <= 1.0e-12
            && vertex.point.z > 0.0
            && vertex.point.z < 0.010
            && abs(vertex.point.z - 0.005) > 1.0e-6
            && vertex.point.x > 0.0025
    }
    let middleSectionVertices = evaluated.brep.vertices.values.filter { vertex in
        abs(vertex.point.x - 0.002) <= 1.0e-12
            && abs(vertex.point.y + 0.001) <= 1.0e-12
            && abs(vertex.point.z - 0.005) <= 1.0e-12
    }

    #expect(body.kind == .solid)
    #expect(evaluated.brep.vertices.count > 12)
    #expect(evaluated.brep.faces.count > 10)
    #expect(railVertices.isEmpty == false)
    #expect(middleSectionVertices.isEmpty == false)
    try document.validate()
}

@Test func createLoftSupportsNonParallelSectionsWithRuledBSplineSideSurfaces() throws {
    var document = DesignDocument.empty()
    let firstProfileID = try createLoftProfile(
        in: &document,
        name: "Non Parallel Loft Bottom",
        width: 4.0,
        height: 2.0,
        z: 0.0
    )
    let secondProfileID = try createTiltedLoftProfile(
        in: &document,
        name: "Non Parallel Loft Top",
        width: 6.0,
        height: 3.0,
        z: 10.0
    )

    _ = try document.createLoft(
        name: "Non Parallel Ruled Loft",
        sections: [
            LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: secondProfileID)),
        ]
    )
    let evaluated = try CADPipeline.modelingDefault(for: document).evaluate(document.cadDocument)
    let sideSurfaces = evaluated.brep.geometry.surfaces.values.compactMap(\.bSplineSurface)
    let capSurfaceCount = evaluated.brep.geometry.surfaces.values.filter(\.isPlaneSurface).count

    #expect(evaluated.brep.bodies.values.first?.kind == .solid)
    #expect(sideSurfaces.count == 4)
    #expect(capSurfaceCount == 2)
    #expect(sideSurfaces.allSatisfy { $0.uDegree == 1 && $0.vDegree == 1 })
    try document.validate()
}

@Test func createLoftSmoothSurfaceModeCreatesCubicSideSurfaces() throws {
    var document = DesignDocument.empty()
    let firstProfileID = try createLoftProfile(
        in: &document,
        name: "Smooth Loft Bottom",
        width: 4.0,
        height: 2.0,
        x: 0.0,
        z: 0.0
    )
    let middleProfileID = try createLoftProfile(
        in: &document,
        name: "Smooth Loft Middle",
        width: 5.0,
        height: 2.5,
        x: 3.0,
        z: 5.0
    )
    let lastProfileID = try createLoftProfile(
        in: &document,
        name: "Smooth Loft Top",
        width: 4.0,
        height: 2.0,
        x: 0.0,
        z: 10.0
    )

    let loftID = try document.createLoft(
        name: "Smooth Loft",
        sections: [
            LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: middleProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: lastProfileID)),
        ],
        options: LoftOptions(resultKind: .solid, surfaceMode: .smooth)
    )
    let feature = try #require(document.cadDocument.designGraph.nodes[loftID])
    let evaluated = try CADPipeline.modelingDefault(for: document).evaluate(document.cadDocument)
    let body = try #require(evaluated.brep.bodies.values.first)
    let sideSurfaces = evaluated.brep.geometry.surfaces.values.compactMap(\.bSplineSurface)
    let connectorCurves = evaluated.brep.geometry.curves.values.compactMap(\.bSplineCurve)

    guard case .loft(let loft) = feature.operation else {
        Issue.record("Smooth Loft command must create a loft feature.")
        return
    }

    #expect(loft.options.surfaceMode == .smooth)
    #expect(body.kind == .solid)
    #expect(sideSurfaces.count == 8)
    #expect(connectorCurves.count == 8)
    #expect(sideSurfaces.allSatisfy { surface in
        surface.uDegree == 1
            && surface.vDegree == 3
            && surface.uControlPointCount == 2
            && surface.vControlPointCount == 4
    })
    #expect(connectorCurves.allSatisfy { curve in
        curve.degree == 3 && curve.controlPointCount == 4
    })
    try document.validate()
}

@Test func createLoftCanCreateClosedSectionLoopSheetResult() throws {
    var document = DesignDocument.empty()
    let firstProfileID = try createLoftProfile(
        in: &document,
        name: "Loft Loop First",
        width: 4.0,
        height: 2.0,
        x: 0.0,
        z: 0.0
    )
    let secondProfileID = try createLoftProfile(
        in: &document,
        name: "Loft Loop Second",
        width: 4.0,
        height: 2.0,
        x: 6.0,
        z: 4.0
    )
    let thirdProfileID = try createLoftProfile(
        in: &document,
        name: "Loft Loop Third",
        width: 4.0,
        height: 2.0,
        x: 0.0,
        z: 8.0
    )

    let loftID = try document.createLoft(
        name: "Closed Loop Loft Sheet",
        sections: [
            LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: secondProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: thirdProfileID)),
        ],
        options: LoftOptions(resultKind: .sheet, closesSectionLoop: true)
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
        Issue.record("Closed loop Loft sheet command must create a loft feature.")
        return
    }

    #expect(feature.inputs == [
        FeatureInput(featureID: firstProfileID, role: .profile),
        FeatureInput(featureID: secondProfileID, role: .profile),
        FeatureInput(featureID: thirdProfileID, role: .profile),
    ])
    #expect(feature.outputs == [FeatureOutput(role: .sheet)])
    #expect(loft.options.resultKind == .sheet)
    #expect(loft.options.closesSectionLoop)
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

@Test func createLoftRejectsClosedSectionLoopSolidWithoutMutation() throws {
    var document = DesignDocument.empty()
    let firstProfileID = try createLoftProfile(
        in: &document,
        name: "Invalid Loop Solid First",
        width: 4.0,
        height: 2.0,
        z: 0.0
    )
    let secondProfileID = try createLoftProfile(
        in: &document,
        name: "Invalid Loop Solid Second",
        width: 4.0,
        height: 2.0,
        x: 6.0,
        z: 4.0
    )
    let thirdProfileID = try createLoftProfile(
        in: &document,
        name: "Invalid Loop Solid Third",
        width: 4.0,
        height: 2.0,
        z: 8.0
    )
    let orderBeforeLoft = document.cadDocument.designGraph.order

    #expect(throws: EditorError.self) {
        _ = try document.createLoft(
            name: "Invalid Closed Loop Solid Loft",
            sections: [
                LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
                LoftSectionReference(profile: ProfileReference(featureID: secondProfileID)),
                LoftSectionReference(profile: ProfileReference(featureID: thirdProfileID)),
            ],
            options: LoftOptions(resultKind: .solid, closesSectionLoop: true)
        )
    }
    #expect(document.cadDocument.designGraph.order == orderBeforeLoft)
}

@Test func createLoftRejectsClosedSectionLoopWithTwoSectionsWithoutMutation() throws {
    var document = DesignDocument.empty()
    let firstProfileID = try createLoftProfile(
        in: &document,
        name: "Invalid Loop First",
        width: 4.0,
        height: 2.0,
        z: 0.0
    )
    let secondProfileID = try createLoftProfile(
        in: &document,
        name: "Invalid Loop Second",
        width: 4.0,
        height: 2.0,
        z: 10.0
    )
    let orderBeforeLoft = document.cadDocument.designGraph.order

    #expect(throws: EditorError.self) {
        _ = try document.createLoft(
            name: "Invalid Two Section Loop Loft",
            sections: [
                LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
                LoftSectionReference(profile: ProfileReference(featureID: secondProfileID)),
            ],
            options: LoftOptions(resultKind: .sheet, closesSectionLoop: true)
        )
    }
    #expect(document.cadDocument.designGraph.order == orderBeforeLoft)
}

@Test func createLoftRejectsSmoothClosedSectionLoopWithoutMutation() throws {
    var document = DesignDocument.empty()
    let firstProfileID = try createLoftProfile(
        in: &document,
        name: "Invalid Smooth Loop First",
        width: 4.0,
        height: 2.0,
        z: 0.0
    )
    let secondProfileID = try createLoftProfile(
        in: &document,
        name: "Invalid Smooth Loop Second",
        width: 4.0,
        height: 2.0,
        x: 6.0,
        z: 4.0
    )
    let thirdProfileID = try createLoftProfile(
        in: &document,
        name: "Invalid Smooth Loop Third",
        width: 4.0,
        height: 2.0,
        z: 8.0
    )
    let orderBeforeLoft = document.cadDocument.designGraph.order

    #expect(throws: EditorError.self) {
        _ = try document.createLoft(
            name: "Invalid Smooth Closed Loop Loft",
            sections: [
                LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
                LoftSectionReference(profile: ProfileReference(featureID: secondProfileID)),
                LoftSectionReference(profile: ProfileReference(featureID: thirdProfileID)),
            ],
            options: LoftOptions(
                resultKind: .sheet,
                closesSectionLoop: true,
                surfaceMode: .smooth
            )
        )
    }
    #expect(document.cadDocument.designGraph.order == orderBeforeLoft)
}

@Test func createLoftSupportsMismatchedProfileSampleCountsWithBoundaryResampling() throws {
    var document = DesignDocument.empty()
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

    let loftID = try document.createLoft(
        name: "Resampled Loft",
        sections: [
            LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: triangleProfileID)),
        ]
    )
    let evaluated = try CADPipeline.modelingDefault(for: document).evaluate(document.cadDocument)
    let body = try #require(evaluated.brep.bodies.values.first)
    let sideSurfaces = evaluated.brep.geometry.surfaces.values.compactMap(\.bSplineSurface)

    #expect(document.cadDocument.designGraph.order.last == loftID)
    #expect(body.kind == .solid)
    #expect(evaluated.brep.faces.count == 6)
    #expect(evaluated.brep.vertices.count == 8)
    #expect(sideSurfaces.count == 4)
    try document.validate()
}

private func createLoftProfile(
    in document: inout DesignDocument,
    name: String,
    width: Double,
    height: Double,
    x: Double = 0.0,
    z: Double
) throws -> FeatureID {
    try document.createRectangleSketch(
        name: name,
        plane: loftPlane(x: x, z: z),
        width: .length(width, .millimeter),
        height: .length(height, .millimeter)
    )
}

private func createTiltedLoftProfile(
    in document: inout DesignDocument,
    name: String,
    width: Double,
    height: Double,
    z: Double
) throws -> FeatureID {
    try document.createRectangleSketch(
        name: name,
        plane: .plane(Plane3D(
            origin: Point3D(x: 0.0, y: 0.0, z: z / 1000.0),
            normal: Vector3D(x: 0.0, y: -0.3713906763541037, z: 0.9284766908852594)
        )),
        width: .length(width, .millimeter),
        height: .length(height, .millimeter)
    )
}

private func loftPlane(x: Double = 0.0, z: Double) -> SketchPlane {
    if x == 0.0 && z == 0.0 {
        return .xy
    }
    return .plane(Plane3D(
        origin: Point3D(x: x / 1000.0, y: 0.0, z: z / 1000.0),
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

private func loftVerticalGuideSketch(x: Double, y: Double, zStart: Double, zEnd: Double) -> Sketch {
    let lineID = SketchEntityID()
    return Sketch(
        plane: .plane(Plane3D(
            origin: Point3D(x: x / 1000.0, y: y / 1000.0, z: zStart / 1000.0),
            normal: .unitY
        )),
        entities: [
            lineID: .line(SketchLine(
                start: SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
                end: SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length((zEnd - zStart) / 1000.0, unit: .meter)))
            )),
        ],
        constraints: [],
        dimensions: []
    )
}

private func loftCurvedGuideSketch(
    x: Double,
    y: Double,
    zStart: Double,
    zEnd: Double,
    localXOffset: Double = -0.003
) -> Sketch {
    let splineID = SketchEntityID()
    return Sketch(
        plane: .plane(Plane3D(
            origin: Point3D(x: x / 1000.0, y: y / 1000.0, z: zStart / 1000.0),
            normal: .unitY
        )),
        entities: [
            splineID: .spline(SketchSpline(controlPoints: [
                SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
                SketchPoint(x: .constant(.length(localXOffset, unit: .meter)), y: .constant(.length(0.0025, unit: .meter))),
                SketchPoint(x: .constant(.length(localXOffset, unit: .meter)), y: .constant(.length(0.0075, unit: .meter))),
                SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length((zEnd - zStart) / 1000.0, unit: .meter))),
            ])),
        ],
        constraints: [],
        dimensions: []
    )
}

private extension Surface3D {
    var isPlaneSurface: Bool {
        if case .plane = self {
            return true
        }
        return false
    }

    var bSplineSurface: BSplineSurface3D? {
        if case .bSpline(let surface) = self {
            return surface
        }
        return nil
    }
}

private extension Curve3D {
    var bSplineCurve: BSplineCurve3D? {
        if case .bSpline(let curve) = self {
            return curve
        }
        return nil
    }
}
