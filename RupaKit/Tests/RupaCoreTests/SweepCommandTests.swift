import Testing
import RupaCore
import SwiftCAD

@Test func createSweepAddsSourceFeatureWithProfileAndPathReferences() throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Sweep Profile",
        plane: .xy,
        width: .length(4.0, .millimeter),
        height: .length(2.0, .millimeter)
    )
    let pathID = try document.createLineSketch(
        name: "Sweep Path",
        plane: .yz,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(20.0, .millimeter)
        )
    )

    let sweepID = try document.createSweep(
        name: "Profile Sweep",
        profiles: [ProfileReference(featureID: profileID)],
        path: SweepPathReference(featureID: pathID),
        options: SweepOptions(
            twistAngle: .angle(30.0, .degree),
            endScale: .constant(.scalar(1.25)),
            alignment: .parallel,
            distanceFraction: .constant(.scalar(0.75)),
            cornerStyle: .mitre,
            guideMethod: .point,
            booleanOperation: .newBody,
            keepTools: false,
            simplify: false,
            resultKind: .solid
        )
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[sweepID])
    guard case .sweep(let sweep) = feature.operation else {
        Issue.record("Sweep command must create a sweep feature.")
        return
    }
    let sceneNode = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference == .body(sweepID)
    })

    #expect(feature.name == "Profile Sweep")
    #expect(feature.inputs == [
        FeatureInput(featureID: profileID, role: .profile),
        FeatureInput(featureID: pathID, role: .path),
    ])
    #expect(feature.outputs == [FeatureOutput(role: .body)])
    #expect(document.cadDocument.designGraph.dependencies.contains(
        DependencyEdge(source: profileID, target: sweepID)
    ))
    #expect(document.cadDocument.designGraph.dependencies.contains(
        DependencyEdge(source: pathID, target: sweepID)
    ))
    #expect(sweep.profiles == [ProfileReference(featureID: profileID)])
    #expect(sweep.path == SweepPathReference(featureID: pathID))
    #expect(sweep.options.alignment == .parallel)
    #expect(sweep.options.cornerStyle == .mitre)
    #expect(sweep.options.keepTools == false)
    #expect(sweep.options.simplify == false)
    #expect(sceneNode.object?.category == .body)
    #expect(sceneNode.object?.sourceFeatureID == sweepID)
    #expect(sceneNode.object?.sourceProfileFeatureID == profileID)
    try document.validate()
}

@Test func createSweepAcceptsRoundCornerStyleWhenPathHasNoCornerTransition() throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Round Sweep Profile",
        plane: .xy,
        width: .length(4.0, .millimeter),
        height: .length(2.0, .millimeter)
    )
    let pathID = try document.createLineSketch(
        name: "Round Sweep Path",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(20.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )

    let sweepID = try document.createSweep(
        name: "Round Corner Sweep",
        profiles: [ProfileReference(featureID: profileID)],
        path: SweepPathReference(featureID: pathID),
        options: SweepOptions(cornerStyle: .round)
    )
    let sweepFeature = try #require(document.cadDocument.designGraph.nodes[sweepID])

    guard case .sweep(let sweep) = sweepFeature.operation else {
        Issue.record("Expected a sweep feature.")
        return
    }
    #expect(sweep.options.cornerStyle == .round)
    try document.validate()
}

@Test func createSweepAcceptsConnectedMultiEntityPathSketch() throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Connected Sweep Profile",
        plane: .xy,
        width: .length(2.0, .millimeter),
        height: .length(1.0, .millimeter)
    )
    let pathID = try document.createSketch(
        name: "Connected Sweep Path",
        sketch: connectedLinePathSketch(),
        geometryRole: .curve
    )

    let sweepID = try document.createSweep(
        name: "Connected Multi-Path Sweep",
        profiles: [ProfileReference(featureID: profileID)],
        path: SweepPathReference(featureID: pathID),
        options: SweepOptions(cornerStyle: .mitre)
    )
    let feature = try #require(document.cadDocument.designGraph.nodes[sweepID])
    let evaluated = try CADPipeline.modelingDefault(for: document).evaluate(document.cadDocument)

    guard case .sweep(let sweep) = feature.operation else {
        Issue.record("Expected a sweep feature.")
        return
    }
    #expect(sweep.path == SweepPathReference(featureID: pathID))
    #expect(evaluated.brep.vertices.count > 8)
    #expect(evaluated.brep.faces.count > 6)
    try document.validate()
}

@Test func createSweepRejectsRoundCornerStyleForConnectedMultiEntityPathSketch() throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Round Multi-Path Sweep Profile",
        plane: .xy,
        width: .length(2.0, .millimeter),
        height: .length(1.0, .millimeter)
    )
    let pathID = try document.createSketch(
        name: "Round Multi-Path Sweep Path",
        sketch: connectedLinePathSketch(),
        geometryRole: .curve
    )
    let originalOrder = document.cadDocument.designGraph.order

    do {
        _ = try document.createSweep(
            name: "Round Multi-Path Sweep",
            profiles: [ProfileReference(featureID: profileID)],
            path: SweepPathReference(featureID: pathID),
            options: SweepOptions(cornerStyle: .round)
        )
        Issue.record("Round multi-curve sweep paths must be rejected until blend topology is implemented.")
    } catch let error as EditorError {
        #expect(error.message.contains("Round sweep corner style requires curved corner-transition topology"))
    } catch {
        Issue.record("Expected EditorError for round multi-curve sweep path, got \(error).")
    }
    #expect(document.cadDocument.designGraph.order == originalOrder)
}

@Test func createSweepRejectsUnsupportedEvaluationOptionsBeforeMutation() throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Unsupported Sweep Profile",
        plane: .xy,
        width: .length(4.0, .millimeter),
        height: .length(2.0, .millimeter)
    )
    let pathID = try document.createLineSketch(
        name: "Unsupported Sweep Path",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(20.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let originalOrder = document.cadDocument.designGraph.order

    do {
        _ = try document.createSweep(
            name: "Simplified Sweep",
            profiles: [ProfileReference(featureID: profileID)],
            path: SweepPathReference(featureID: pathID),
            options: SweepOptions(simplify: true)
        )
        Issue.record("Sweep command must reject unsupported simplify output.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("simplify"))
    }
    #expect(document.cadDocument.designGraph.order == originalOrder)
}

@Test func createSweepAcceptsCurvedPathParallelAlignmentThroughEvaluationGate() throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Curved Parallel Sweep Profile",
        plane: .xy,
        width: .length(4.0, .millimeter),
        height: .length(2.0, .millimeter)
    )
    let pathID = try document.createArcSketch(
        name: "Curved Parallel Sweep Path",
        plane: .yz,
        center: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        radius: .length(20.0, .millimeter),
        startAngle: .angle(0.0, .degree),
        endAngle: .angle(90.0, .degree)
    )

    let sweepID = try document.createSweep(
        name: "Curved Parallel Sweep",
        profiles: [ProfileReference(featureID: profileID)],
        path: SweepPathReference(featureID: pathID),
        options: SweepOptions(alignment: .parallel)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[sweepID])
    guard case .sweep(let sweep) = feature.operation else {
        Issue.record("Sweep command must create a sweep feature.")
        return
    }
    #expect(sweep.options.alignment == .parallel)
    try document.validate()
}

@Test func createSweepNormalAlignmentAcceptsProfilePlaneStraightPath() throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Profile Plane Normal Sweep Profile",
        plane: .xy,
        width: .length(4.0, .millimeter),
        height: .length(2.0, .millimeter)
    )
    let pathID = try document.createLineSketch(
        name: "Profile Plane Normal Sweep Path",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(20.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )

    let sweepID = try document.createSweep(
        name: "Profile Plane Normal Sweep",
        profiles: [ProfileReference(featureID: profileID)],
        path: SweepPathReference(featureID: pathID),
        options: SweepOptions(alignment: .normal)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[sweepID])
    guard case .sweep(let sweep) = feature.operation else {
        Issue.record("Sweep command must create a sweep feature.")
        return
    }
    #expect(sweep.options.alignment == .normal)
    try document.validate()
}

@Test func createSweepParallelAlignmentRejectsProfilePlaneDegenerateSolidSweep() throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Profile Plane Parallel Sweep Profile",
        plane: .xy,
        width: .length(4.0, .millimeter),
        height: .length(2.0, .millimeter)
    )
    let pathID = try document.createLineSketch(
        name: "Profile Plane Parallel Sweep Path",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(20.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let originalOrder = document.cadDocument.designGraph.order

    do {
        _ = try document.createSweep(
            name: "Profile Plane Parallel Sweep",
            profiles: [ProfileReference(featureID: profileID)],
            path: SweepPathReference(featureID: pathID),
            options: SweepOptions(alignment: .parallel)
        )
        Issue.record("Sweep command must reject profile-plane parallel solid sweeps.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("nonzero profile-normal component"))
    }
    #expect(document.cadDocument.designGraph.order == originalOrder)
}

@Test func createSweepAcceptsObliqueParallelAlignmentWithEndScaleThroughEvaluationGate() throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Oblique Parallel Sweep Profile",
        plane: .xy,
        width: .length(4.0, .millimeter),
        height: .length(2.0, .millimeter)
    )
    let pathID = try document.createLineSketch(
        name: "Oblique Parallel Sweep Path",
        plane: .yz,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(20.0, .millimeter)
        )
    )

    let sweepID = try document.createSweep(
        name: "Oblique Parallel Sweep",
        profiles: [ProfileReference(featureID: profileID)],
        path: SweepPathReference(featureID: pathID),
        options: SweepOptions(
            endScale: .constant(.scalar(0.5)),
            alignment: .parallel
        )
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[sweepID])
    guard case .sweep(let sweep) = feature.operation else {
        Issue.record("Sweep command must create a sweep feature.")
        return
    }
    #expect(sweep.options.alignment == .parallel)
    try document.validate()
}

@Test func createSweepAcceptsBilinearCornerRailPointGuidesThroughEvaluationGate() throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Bilinear Rail Sweep Profile",
        plane: .xy,
        width: .length(40.0, .millimeter),
        height: .length(20.0, .millimeter)
    )
    let pathID = try document.createLineSketch(
        name: "Bilinear Rail Sweep Path",
        plane: .yz,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    let bottomLeftGuideID = try createWorldLineSketch(
        in: &document,
        name: "Bilinear Rail Bottom Left Guide",
        start: Point3D(x: -0.020, y: -0.010, z: 0.0),
        end: Point3D(x: -0.030, y: -0.008, z: 0.010)
    )
    let bottomRightGuideID = try createWorldLineSketch(
        in: &document,
        name: "Bilinear Rail Bottom Right Guide",
        start: Point3D(x: 0.020, y: -0.010, z: 0.0),
        end: Point3D(x: 0.028, y: -0.012, z: 0.010)
    )
    let topRightGuideID = try createWorldLineSketch(
        in: &document,
        name: "Bilinear Rail Top Right Guide",
        start: Point3D(x: 0.020, y: 0.010, z: 0.0),
        end: Point3D(x: 0.034, y: 0.024, z: 0.010)
    )
    let topLeftGuideID = try createWorldLineSketch(
        in: &document,
        name: "Bilinear Rail Top Left Guide",
        start: Point3D(x: -0.020, y: 0.010, z: 0.0),
        end: Point3D(x: -0.018, y: 0.016, z: 0.010)
    )

    let sweepID = try document.createSweep(
        name: "Bilinear Rail Sweep",
        profiles: [ProfileReference(featureID: profileID)],
        path: SweepPathReference(featureID: pathID),
        guides: [
            SweepGuideReference(featureID: bottomLeftGuideID),
            SweepGuideReference(featureID: bottomRightGuideID),
            SweepGuideReference(featureID: topRightGuideID),
            SweepGuideReference(featureID: topLeftGuideID),
        ],
        options: SweepOptions(guideMethod: .point)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[sweepID])
    guard case .sweep(let sweep) = feature.operation else {
        Issue.record("Sweep command must create a sweep feature.")
        return
    }
    #expect(sweep.guides == [
        SweepGuideReference(featureID: bottomLeftGuideID),
        SweepGuideReference(featureID: bottomRightGuideID),
        SweepGuideReference(featureID: topRightGuideID),
        SweepGuideReference(featureID: topLeftGuideID),
    ])
    #expect(sweep.options.guideMethod == .point)
    #expect(feature.inputs.filter { $0.role == .guide }.count == 4)
    try document.validate()
}

@Test func createSweepAcceptsBilinearQuadrilateralRailPointGuidesThroughEvaluationGate() throws {
    var document = DesignDocument.empty()
    let profileID = try document.createPolygonSketch(
        name: "Bilinear Quadrilateral Rail Sweep Profile",
        plane: .xy,
        center: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        radius: .length(20.0, .millimeter),
        sides: 4
    )
    let pathID = try document.createLineSketch(
        name: "Bilinear Quadrilateral Rail Sweep Path",
        plane: .yz,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    let bottomGuideID = try createWorldLineSketch(
        in: &document,
        name: "Bilinear Quadrilateral Rail Bottom Guide",
        start: Point3D(x: 0.0, y: -0.020, z: 0.0),
        end: Point3D(x: -0.006, y: -0.026, z: 0.010)
    )
    let rightGuideID = try createWorldLineSketch(
        in: &document,
        name: "Bilinear Quadrilateral Rail Right Guide",
        start: Point3D(x: 0.020, y: 0.0, z: 0.0),
        end: Point3D(x: 0.030, y: -0.006, z: 0.010)
    )
    let topGuideID = try createWorldLineSketch(
        in: &document,
        name: "Bilinear Quadrilateral Rail Top Guide",
        start: Point3D(x: 0.0, y: 0.020, z: 0.0),
        end: Point3D(x: 0.008, y: 0.028, z: 0.010)
    )
    let leftGuideID = try createWorldLineSketch(
        in: &document,
        name: "Bilinear Quadrilateral Rail Left Guide",
        start: Point3D(x: -0.020, y: 0.0, z: 0.0),
        end: Point3D(x: -0.028, y: 0.004, z: 0.010)
    )

    let sweepID = try document.createSweep(
        name: "Bilinear Quadrilateral Rail Sweep",
        profiles: [ProfileReference(featureID: profileID)],
        path: SweepPathReference(featureID: pathID),
        guides: [
            SweepGuideReference(featureID: bottomGuideID),
            SweepGuideReference(featureID: rightGuideID),
            SweepGuideReference(featureID: topGuideID),
            SweepGuideReference(featureID: leftGuideID),
        ],
        options: SweepOptions(guideMethod: .point)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[sweepID])
    guard case .sweep(let sweep) = feature.operation else {
        Issue.record("Sweep command must create a sweep feature.")
        return
    }
    #expect(sweep.guides == [
        SweepGuideReference(featureID: bottomGuideID),
        SweepGuideReference(featureID: rightGuideID),
        SweepGuideReference(featureID: topGuideID),
        SweepGuideReference(featureID: leftGuideID),
    ])
    #expect(sweep.options.guideMethod == .point)
    #expect(feature.inputs.filter { $0.role == .guide }.count == 4)
    try document.validate()
}

@Test func createSweepAcceptsMeanValueCageRailPointGuidesThroughEvaluationGate() throws {
    var document = DesignDocument.empty()
    let profileID = try document.createPolygonSketch(
        name: "Mean Value Cage Rail Sweep Profile",
        plane: .xy,
        center: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        radius: .length(20.0, .millimeter),
        sides: 5
    )
    let pathID = try document.createLineSketch(
        name: "Mean Value Cage Rail Sweep Path",
        plane: .yz,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    let guideDefinitions = [
        (
            name: "Mean Value Cage Rail Right Guide",
            start: Point3D(x: 0.020000000000, y: 0.000000000000, z: 0.0),
            end: Point3D(x: 0.030, y: -0.002, z: 0.010)
        ),
        (
            name: "Mean Value Cage Rail Upper Right Guide",
            start: Point3D(x: 0.006180339887, y: 0.019021130326, z: 0.0),
            end: Point3D(x: 0.010, y: 0.024, z: 0.010)
        ),
        (
            name: "Mean Value Cage Rail Upper Left Guide",
            start: Point3D(x: -0.016180339887, y: 0.011755705045, z: 0.0),
            end: Point3D(x: -0.020, y: 0.018, z: 0.010)
        ),
        (
            name: "Mean Value Cage Rail Lower Left Guide",
            start: Point3D(x: -0.016180339887, y: -0.011755705045, z: 0.0),
            end: Point3D(x: -0.024, y: -0.010, z: 0.010)
        ),
        (
            name: "Mean Value Cage Rail Lower Right Guide",
            start: Point3D(x: 0.006180339887, y: -0.019021130326, z: 0.0),
            end: Point3D(x: 0.002, y: -0.026, z: 0.010)
        ),
    ]
    let guideIDs = try guideDefinitions.map {
        try createWorldLineSketch(
            in: &document,
            name: $0.name,
            start: $0.start,
            end: $0.end
        )
    }

    let sweepID = try document.createSweep(
        name: "Mean Value Cage Rail Sweep",
        profiles: [ProfileReference(featureID: profileID)],
        path: SweepPathReference(featureID: pathID),
        guides: guideIDs.map { SweepGuideReference(featureID: $0) },
        options: SweepOptions(guideMethod: .point)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[sweepID])
    guard case .sweep(let sweep) = feature.operation else {
        Issue.record("Sweep command must create a sweep feature.")
        return
    }
    #expect(sweep.guides == guideIDs.map { SweepGuideReference(featureID: $0) })
    #expect(sweep.options.guideMethod == .point)
    #expect(feature.inputs.filter { $0.role == .guide }.count == 5)
    try document.validate()
}

@Test func createSweepBooleanStoresTargetBodyInput() throws {
    var document = DesignDocument.empty()
    let targetProfileID = try document.createRectangleSketch(
        name: "Sweep Boolean Target Profile",
        plane: .xy,
        width: .length(8.0, .millimeter),
        height: .length(4.0, .millimeter)
    )
    let targetBodyID = try document.extrudeProfile(
        name: "Sweep Boolean Target",
        profile: ProfileReference(featureID: targetProfileID),
        distance: .length(4.0, .millimeter),
        direction: .normal
    )
    let profileID = try document.createRectangleSketch(
        name: "Sweep Boolean Tool Profile",
        plane: .xy,
        width: .length(4.0, .millimeter),
        height: .length(2.0, .millimeter)
    )
    let pathID = try document.createLineSketch(
        name: "Sweep Boolean Path",
        plane: .yz,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )

    let sweepID = try document.createSweep(
        name: "Boolean Sweep",
        profiles: [ProfileReference(featureID: profileID)],
        path: SweepPathReference(featureID: pathID),
        targets: [SweepTargetReference(featureID: targetBodyID)],
        options: SweepOptions(booleanOperation: .union)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[sweepID])
    guard case .sweep(let sweep) = feature.operation else {
        Issue.record("Sweep command must create a sweep feature.")
        return
    }

    #expect(feature.inputs.contains(FeatureInput(featureID: targetBodyID, role: .target)))
    #expect(document.cadDocument.designGraph.dependencies.contains(
        DependencyEdge(source: targetBodyID, target: sweepID)
    ))
    #expect(sweep.targets == [SweepTargetReference(featureID: targetBodyID)])
    #expect(sweep.options.booleanOperation == .union)
    try document.validate()
}

@Test func createSweepCanCreateSheetSurfaceOutput() throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Sweep Sheet Profile",
        plane: .xy,
        width: .length(4.0, .millimeter),
        height: .length(2.0, .millimeter)
    )
    let pathID = try document.createLineSketch(
        name: "Sweep Sheet Path",
        plane: .yz,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(20.0, .millimeter)
        )
    )

    let sweepID = try document.createSweep(
        name: "Profile Sweep Sheet",
        profiles: [ProfileReference(featureID: profileID)],
        path: SweepPathReference(featureID: pathID),
        options: SweepOptions(resultKind: .sheet)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[sweepID])
    let sceneNode = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference == .body(sweepID)
    })

    #expect(feature.outputs == [FeatureOutput(role: .sheet)])
    #expect(sceneNode.object?.category == .body)
    #expect(sceneNode.object?.geometryRole == .surface)
    #expect(sceneNode.object?.sourceFeatureID == sweepID)
    #expect(sceneNode.object?.sourceProfileFeatureID == profileID)
    try document.validate()
}

@Test func createSweepRejectsInvalidOptionQuantitiesBeforeMutation() throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Invalid Sweep Profile",
        plane: .xy,
        width: .length(4.0, .millimeter),
        height: .length(2.0, .millimeter)
    )
    let pathID = try document.createLineSketch(
        name: "Invalid Sweep Path",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(20.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let originalOrder = document.cadDocument.designGraph.order

    do {
        _ = try document.createSweep(
            name: "Invalid Sweep",
            profiles: [ProfileReference(featureID: profileID)],
            path: SweepPathReference(featureID: pathID),
            options: SweepOptions(
                endScale: .length(1.0, .millimeter)
            )
        )
        Issue.record("Sweep command must reject a length-valued end scale.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("end scale"))
    }

    do {
        _ = try document.createSweep(
            name: "Zero Distance Sweep",
            profiles: [ProfileReference(featureID: profileID)],
            path: SweepPathReference(featureID: pathID),
            options: SweepOptions(
                distanceFraction: .constant(.scalar(0.0))
            )
        )
        Issue.record("Sweep command must reject zero distance fraction before mutation.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("distance fraction"))
        #expect(error.message.contains("greater than 0"))
    }

    #expect(document.cadDocument.designGraph.order == originalOrder)
}

@Test func createSweepRejectsBooleanOperationWithoutTargetBeforeMutation() throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Invalid Boolean Sweep Profile",
        plane: .xy,
        width: .length(4.0, .millimeter),
        height: .length(2.0, .millimeter)
    )
    let pathID = try document.createLineSketch(
        name: "Invalid Boolean Sweep Path",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(20.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let originalOrder = document.cadDocument.designGraph.order

    #expect(throws: FeatureEvaluationError.self) {
        _ = try document.createSweep(
            name: "Invalid Boolean Sweep",
            profiles: [ProfileReference(featureID: profileID)],
            path: SweepPathReference(featureID: pathID),
            options: SweepOptions(booleanOperation: .union)
        )
    }
    #expect(document.cadDocument.designGraph.order == originalOrder)
}

private func createWorldLineSketch(
    in document: inout DesignDocument,
    name: String,
    start: Point3D,
    end: Point3D
) throws -> FeatureID {
    let tolerance = ModelingTolerance.standard
    let delta = end - start
    let direction = try delta.normalized(tolerance: tolerance.distance)
    let helper = abs(direction.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
    let normal = try direction.cross(helper).normalized(tolerance: tolerance.distance)
    let basis = try sketchPlaneBasis(for: normal, tolerance: tolerance)
    let localEnd = Point2D(
        x: delta.dot(basis.u),
        y: delta.dot(basis.v)
    )
    return try document.createLineSketch(
        name: name,
        plane: .plane(Plane3D(origin: start, normal: normal)),
        start: SketchPoint(
            x: .length(0.0, .meter),
            y: .length(0.0, .meter)
        ),
        end: SketchPoint(
            x: .length(localEnd.x, .meter),
            y: .length(localEnd.y, .meter)
        )
    )
}

private func connectedLinePathSketch() -> Sketch {
    let firstLineID = SketchEntityID()
    let secondLineID = SketchEntityID()
    return Sketch(
        plane: .yz,
        entities: [
            firstLineID: .line(SketchLine(
                start: SketchPoint(
                    x: .length(0.0, .millimeter),
                    y: .length(0.0, .millimeter)
                ),
                end: SketchPoint(
                    x: .length(0.0, .millimeter),
                    y: .length(15.0, .millimeter)
                )
            )),
            secondLineID: .line(SketchLine(
                start: SketchPoint(
                    x: .length(0.0, .millimeter),
                    y: .length(15.0, .millimeter)
                ),
                end: SketchPoint(
                    x: .length(8.0, .millimeter),
                    y: .length(25.0, .millimeter)
                )
            )),
        ]
    )
}

private func sketchPlaneBasis(
    for planeNormal: Vector3D,
    tolerance: ModelingTolerance
) throws -> (u: Vector3D, v: Vector3D) {
    let normal = try planeNormal.normalized(tolerance: tolerance.distance)
    let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
    let u = try helper.cross(normal).normalized(tolerance: tolerance.distance)
    let v = normal.cross(u)
    return (u, v)
}
