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
            name: "Round Corner Sweep",
            profiles: [ProfileReference(featureID: profileID)],
            path: SweepPathReference(featureID: pathID),
            options: SweepOptions(cornerStyle: .round)
        )
        Issue.record("Sweep command must reject unsupported round corners.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("round"))
    }
    #expect(document.cadDocument.designGraph.order == originalOrder)

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
