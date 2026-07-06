import Testing
import RupaCore
import SwiftCAD

@Test func createBooleanAddsSourceFeatureWithTargetAndToolReferences() throws {
    var document = DesignDocument.empty()
    let targetID = try createBooleanBox(
        in: &document,
        name: "Boolean Target",
        minX: -20.0,
        minY: -10.0,
        maxX: 20.0,
        maxY: 10.0
    )
    let toolID = try createBooleanBox(
        in: &document,
        name: "Boolean Tool",
        minX: 20.0,
        minY: -10.0,
        maxX: 40.0,
        maxY: 10.0
    )

    let booleanID = try document.createBoolean(
        name: "Boolean Union",
        targets: [BooleanTargetReference(featureID: targetID)],
        tool: BooleanToolReference(featureID: toolID),
        operation: .union
    )
    let feature = try #require(document.cadDocument.designGraph.nodes[booleanID])
    let evaluated = try CADPipeline.modelingDefault(for: document).evaluate(document.cadDocument)

    guard case .boolean(let boolean) = feature.operation else {
        Issue.record("Boolean command must create a Boolean feature.")
        return
    }

    #expect(feature.name == "Boolean Union")
    #expect(feature.inputs == [
        FeatureInput(featureID: targetID, role: .target),
        FeatureInput(featureID: toolID, role: .body),
    ])
    #expect(feature.outputs == [FeatureOutput(role: .body)])
    #expect(document.cadDocument.designGraph.dependencies.contains(
        DependencyEdge(source: targetID, target: booleanID)
    ))
    #expect(document.cadDocument.designGraph.dependencies.contains(
        DependencyEdge(source: toolID, target: booleanID)
    ))
    #expect(boolean.targets == [BooleanTargetReference(featureID: targetID)])
    #expect(boolean.tool == BooleanToolReference(featureID: toolID))
    #expect(boolean.operation == .union)
    #expect(boolean.keepTools == false)
    #expect(evaluated.brep.bodies.count == 1)
    #expect(evaluated.brep.faces.count == 6)
    #expect(evaluated.generatedNames.keys.contains {
        $0.components.contains(.feature(targetID))
    } == false)
    #expect(evaluated.generatedNames.keys.contains {
        $0.components == [
            .feature(booleanID),
            .generated(GeneratedSubshapeRole.body.rawValue),
        ]
    })
    #expect(document.productMetadata.sceneNodes.values.contains {
        $0.reference == .body(booleanID)
    })
    try document.validate()
}

@Test func createBooleanCanKeepTargetAndToolBodies() throws {
    var document = DesignDocument.empty()
    let targetID = try createBooleanBox(
        in: &document,
        name: "Keep Target",
        minX: -20.0,
        minY: -10.0,
        maxX: 20.0,
        maxY: 10.0
    )
    let toolID = try createBooleanBox(
        in: &document,
        name: "Keep Tool",
        minX: 20.0,
        minY: -10.0,
        maxX: 40.0,
        maxY: 10.0
    )

    let booleanID = try document.createBoolean(
        name: "Kept Boolean Union",
        targets: [BooleanTargetReference(featureID: targetID)],
        tool: BooleanToolReference(featureID: toolID),
        operation: .union,
        keepTools: true
    )
    let evaluated = try CADPipeline.modelingDefault(for: document).evaluate(document.cadDocument)

    #expect(evaluated.brep.bodies.count == 3)
    #expect(evaluated.generatedNames.keys.contains {
        $0.components.contains(.feature(targetID))
    })
    #expect(evaluated.generatedNames.keys.contains {
        $0.components.contains(.feature(toolID))
            && $0.components.contains(.subshape("tool"))
    })
    #expect(evaluated.generatedNames.keys.contains {
        $0.components == [
            .feature(booleanID),
            .generated(GeneratedSubshapeRole.body.rawValue),
        ]
    })
}

@Test func createBooleanCanUsePreviousCellUnionBooleanAsTarget() throws {
    var document = DesignDocument.empty()
    let targetID = try createBooleanBox(
        in: &document,
        name: "Chained Target",
        minX: -20.0,
        minY: -20.0,
        maxX: 20.0,
        maxY: 20.0
    )
    let firstToolID = try createBooleanBox(
        in: &document,
        name: "Chained First Tool",
        minX: -5.0,
        minY: -5.0,
        maxX: 25.0,
        maxY: 25.0
    )
    let firstBooleanID = try document.createBoolean(
        name: "First Chained Boolean",
        targets: [BooleanTargetReference(featureID: targetID)],
        tool: BooleanToolReference(featureID: firstToolID),
        operation: .difference
    )
    let secondToolID = try createBooleanBox(
        in: &document,
        name: "Chained Second Tool",
        minX: -20.0,
        minY: -20.0,
        maxX: -10.0,
        maxY: 0.0
    )

    let secondBooleanID = try document.createBoolean(
        name: "Second Chained Boolean",
        targets: [BooleanTargetReference(featureID: firstBooleanID)],
        tool: BooleanToolReference(featureID: secondToolID),
        operation: .difference
    )
    let evaluated = try CADPipeline.modelingDefault(for: document).evaluate(document.cadDocument)

    #expect(evaluated.brep.bodies.count == 1)
    #expect(evaluated.brep.faces.count > 6)
    #expect(evaluated.generatedNames.keys.contains {
        $0.components.contains(.feature(firstBooleanID))
    } == false)
    #expect(evaluated.generatedNames.keys.contains {
        $0.components == [
            .feature(secondBooleanID),
            .generated(GeneratedSubshapeRole.body.rawValue),
        ]
    })
    #expect(evaluated.generatedNames.values.filter { $0.isBody }.count == 1)
    #expect(evaluated.generatedNames.values.filter { $0.isFace }.count == evaluated.brep.faces.count)
    #expect(evaluated.generatedNames.values.filter { $0.isEdge }.count == evaluated.brep.edges.count)
    #expect(evaluated.generatedNames.values.filter { $0.isVertex }.count == evaluated.brep.vertices.count)
    try document.validate()
}

@Test func createBooleanRejectsToolUsedAsTargetBeforeMutation() throws {
    var document = DesignDocument.empty()
    let boxID = try createBooleanBox(
        in: &document,
        name: "Self Boolean Box",
        minX: -10.0,
        minY: -10.0,
        maxX: 10.0,
        maxY: 10.0
    )
    let initialOrder = document.cadDocument.designGraph.order

    #expect(throws: EditorError.self) {
        _ = try document.createBoolean(
            name: "Invalid Boolean",
            targets: [BooleanTargetReference(featureID: boxID)],
            tool: BooleanToolReference(featureID: boxID),
            operation: .difference
        )
    }
    #expect(document.cadDocument.designGraph.order == initialOrder)
}

@Test func measureExcludesStandaloneBooleanOperands() throws {
    var document = DesignDocument.empty()
    let targetID = try createBooleanBox(
        in: &document,
        name: "Boolean Measure Target",
        minX: -20.0,
        minY: -10.0,
        maxX: 20.0,
        maxY: 10.0
    )
    let toolID = try createBooleanBox(
        in: &document,
        name: "Boolean Measure Tool",
        minX: 0.0,
        minY: -10.0,
        maxX: 20.0,
        maxY: 10.0
    )
    let booleanID = try document.createBoolean(
        name: "Boolean Measure Difference",
        targets: [BooleanTargetReference(featureID: targetID)],
        tool: BooleanToolReference(featureID: toolID),
        operation: .difference
    )

    let result = try MeasurementService().measure(document: document)
    let solid = try #require(result.solids.first)

    // 40x20x10 mm target minus the overlapping 20x20x10 mm tool half leaves
    // 4000 mm^3; both consumed operands must leave the measurable set.
    #expect(result.counts.solids == 1)
    #expect(solid.featureID == booleanID.description)
    #expect(result.solids.contains { $0.featureID == targetID.description } == false)
    #expect(result.solids.contains { $0.featureID == toolID.description } == false)
    #expect(abs(solid.volumeCubicMeters - 4.0e-6) < 1.0e-9)
    #expect(abs(result.totals.solidVolumeCubicMeters - 4.0e-6) < 1.0e-9)
}

@discardableResult
private func createBooleanBox(
    in document: inout DesignDocument,
    name: String,
    minX: Double,
    minY: Double,
    maxX: Double,
    maxY: Double,
    depth: Double = 10.0
) throws -> FeatureID {
    let sketchID = try document.createRectangleSketchFromCorners(
        name: "\(name) Sketch",
        plane: .xy,
        firstCorner: booleanSketchPoint(x: minX, y: minY),
        oppositeCorner: booleanSketchPoint(x: maxX, y: maxY)
    )
    return try document.extrudeProfile(
        name: name,
        profile: ProfileReference(featureID: sketchID),
        distance: .length(depth, .millimeter),
        direction: .normal
    )
}

private func booleanSketchPoint(x: Double, y: Double) -> SketchPoint {
    SketchPoint(
        x: .length(x, .millimeter),
        y: .length(y, .millimeter)
    )
}

private extension TopologyReference {
    var isBody: Bool {
        if case .body = self {
            return true
        }
        return false
    }

    var isFace: Bool {
        if case .face = self {
            return true
        }
        return false
    }

    var isEdge: Bool {
        if case .edge = self {
            return true
        }
        return false
    }

    var isVertex: Bool {
        if case .vertex = self {
            return true
        }
        return false
    }
}
