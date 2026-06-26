import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Test func selectionDimensionCommandStoresCADSourceDimensionOnly() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Measured Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let targets = try lineEndpointTargets(in: document, featureID: featureID)

    let dimensionID = try document.addSelectionDimension(
        name: "Line Length",
        kind: .distance,
        first: targets.start,
        second: targets.end,
        target: .length(10.0, .millimeter)
    )

    #expect(document.cadDocument.selectionDimensions.count == 1)
    #expect(document.productMetadata.measurements.isEmpty)
    let dimension = try #require(document.cadDocument.selectionDimensions.first)
    #expect(dimension.id == dimensionID)
    #expect(dimension.name == "Line Length")
    #expect(dimension.kind == .distance)

    let evaluation = try SelectionDimensionService().evaluate(document: document)
    let measurement = try #require(evaluation.measurements.first)
    #expect(evaluation.measurements.count == 1)
    #expect(measurement.dimension.id == dimensionID)
    #expect(measurement.measured == .length(0.010, unit: .meter))
    #expect(abs(measurement.residual.value) <= 1.0e-12)
    #expect(try measurement.isSatisfied())
}

@Test func selectionDimensionTargetAndRemovalCommandsMutateThroughCommandPath() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Measured Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let targets = try lineEndpointTargets(in: document, featureID: featureID)
    let session = EditorSession(document: document)
    let addResult = try session.execute(
        .addSelectionDimension(
            name: "Line Length",
            kind: .distance,
            first: targets.start,
            second: targets.end,
            target: .length(10.0, .millimeter)
        )
    )
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    let setResult = try session.execute(
        .setSelectionDimensionTarget(
            id: dimensionID,
            target: .length(8.0, .millimeter)
        )
    )
    let setEvaluation = try SelectionDimensionService().evaluate(
        document: session.document,
        dimensionID: dimensionID
    )
    let setMeasurement = try #require(setEvaluation.measurements.first)

    #expect(setResult.commandName == "setSelectionDimensionTarget")
    #expect(setResult.didMutate)
    #expect(setResult.generation == DocumentGeneration(2))
    #expect(session.document.cadDocument.selectionDimensions.first?.target == .length(8.0, .millimeter))
    #expect(setMeasurement.dimension.id == dimensionID)
    #expect(setMeasurement.measured == .length(0.010, unit: .meter))
    #expect(setMeasurement.target == .length(0.008, unit: .meter))
    #expect(abs(setMeasurement.residual.value - 0.002) <= 1.0e-12)

    let applyResult = try session.execute(.applySelectionDimensionTarget(id: dimensionID))
    let appliedEvaluation = try SelectionDimensionService().evaluate(
        document: session.document,
        dimensionID: dimensionID
    )
    let appliedMeasurement = try #require(appliedEvaluation.measurements.first)
    let appliedLineLength = try lineLength(
        in: session.document,
        featureID: featureID
    )
    let appliedDimension = try #require(session.document.cadDocument.selectionDimensions.first)

    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)
    #expect(applyResult.generation == DocumentGeneration(3))
    #expect(abs(appliedLineLength - 0.008) <= 1.0e-12)
    #expect(appliedMeasurement.dimension.id == dimensionID)
    #expect(appliedMeasurement.measured == .length(0.008, unit: .meter))
    #expect(appliedMeasurement.target == .length(0.008, unit: .meter))
    #expect(abs(appliedMeasurement.residual.value) <= 1.0e-12)
    #expect(try appliedMeasurement.isSatisfied())
    assertLineEndpointReferences(
        appliedDimension,
        expectedLength: 0.008
    )

    let removeResult = try session.execute(.removeSelectionDimension(id: dimensionID))

    #expect(removeResult.commandName == "removeSelectionDimension")
    #expect(removeResult.didMutate)
    #expect(removeResult.generation == DocumentGeneration(4))
    #expect(session.document.cadDocument.selectionDimensions.isEmpty)
    #expect(session.document.productMetadata.measurements.isEmpty)
    #expect(session.evaluationStatus == .valid)

    _ = try session.undo()
    #expect(session.document.cadDocument.selectionDimensions.map(\.id) == [dimensionID])
    #expect(session.generation == DocumentGeneration(5))
}

@Test func selectionDimensionApplyUpdatesCircleRadiusFromCenterReference() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createCircleSketch(
        name: "Measured Circle",
        plane: .xy,
        center: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        radius: .length(6.0, .millimeter)
    )
    let targets = try circleCenterAndCurveTargets(in: document, featureID: featureID)
    let session = EditorSession(document: document)
    let addResult = try session.execute(
        .addSelectionDimension(
            name: "Circle Radius",
            kind: .distance,
            first: targets.center,
            second: targets.curve,
            target: .length(6.0, .millimeter)
        )
    )
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    let initialEvaluation = try SelectionDimensionService().evaluate(
        document: session.document,
        dimensionID: dimensionID
    )
    let initialMeasurement = try #require(initialEvaluation.measurements.first)
    #expect(initialMeasurement.measured == .length(0.006, unit: .meter))
    #expect(abs(initialMeasurement.residual.value) <= 1.0e-12)
    guard case .curve(.center(_)) = initialMeasurement.dimension.first,
          case .curve(.whole(_)) = initialMeasurement.dimension.second else {
        Issue.record("Expected circle center and whole curve selection references")
        return
    }

    _ = try session.execute(
        .setSelectionDimensionTarget(
            id: dimensionID,
            target: .length(4.0, .millimeter)
        )
    )
    let setEvaluation = try SelectionDimensionService().evaluate(
        document: session.document,
        dimensionID: dimensionID
    )
    let setMeasurement = try #require(setEvaluation.measurements.first)
    #expect(setMeasurement.measured == .length(0.006, unit: .meter))
    #expect(setMeasurement.target == .length(0.004, unit: .meter))
    #expect(abs(setMeasurement.residual.value - 0.002) <= 1.0e-12)

    let applyResult = try session.execute(.applySelectionDimensionTarget(id: dimensionID))
    let appliedEvaluation = try SelectionDimensionService().evaluate(
        document: session.document,
        dimensionID: dimensionID
    )
    let appliedMeasurement = try #require(appliedEvaluation.measurements.first)
    let radius = try circleRadius(
        in: session.document,
        featureID: featureID
    )

    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)
    #expect(abs(radius - 0.004) <= 1.0e-12)
    #expect(appliedMeasurement.measured == .length(0.004, unit: .meter))
    #expect(appliedMeasurement.target == .length(0.004, unit: .meter))
    #expect(abs(appliedMeasurement.residual.value) <= 1.0e-12)
    #expect(try appliedMeasurement.isSatisfied())
}

@Test func selectionDimensionApplyUpdatesArcRadiusFromCenterReference() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createArcSketch(
        name: "Measured Arc",
        plane: .xy,
        center: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        radius: .length(6.0, .millimeter),
        startAngle: .angle(0.0, .degree),
        endAngle: .angle(90.0, .degree)
    )
    let targets = try arcCenterAndCurveTargets(in: document, featureID: featureID)
    let session = EditorSession(document: document)
    let addResult = try session.execute(
        .addSelectionDimension(
            name: "Arc Radius",
            kind: .distance,
            first: targets.center,
            second: targets.curve,
            target: .length(6.0, .millimeter)
        )
    )
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    _ = try session.execute(
        .setSelectionDimensionTarget(
            id: dimensionID,
            target: .length(4.0, .millimeter)
        )
    )
    let applyResult = try session.execute(.applySelectionDimensionTarget(id: dimensionID))
    let appliedEvaluation = try SelectionDimensionService().evaluate(
        document: session.document,
        dimensionID: dimensionID
    )
    let appliedMeasurement = try #require(appliedEvaluation.measurements.first)
    let radius = try arcRadius(
        in: session.document,
        featureID: featureID
    )

    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)
    #expect(abs(radius - 0.004) <= 1.0e-12)
    #expect(appliedMeasurement.measured == .length(0.004, unit: .meter))
    #expect(appliedMeasurement.target == .length(0.004, unit: .meter))
    #expect(abs(appliedMeasurement.residual.value) <= 1.0e-12)
    #expect(try appliedMeasurement.isSatisfied())
}

@Test func selectionDimensionApplyUpdatesFirstLineRelativeAngle() async throws {
    var document = DesignDocument.empty()
    let referenceFeatureID = try document.createLineSketch(
        name: "Reference Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let editableFeatureID = try document.createLineSketch(
        name: "Editable Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    let reference = try lineCurveTarget(in: document, featureID: referenceFeatureID)
    let editable = try lineCurveTarget(in: document, featureID: editableFeatureID)
    let session = EditorSession(document: document)
    let addResult = try session.execute(
        .addSelectionDimension(
            name: "Relative Angle",
            kind: .angle,
            first: editable,
            second: reference,
            target: .angle(90.0, .degree)
        )
    )
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    _ = try session.execute(
        .setSelectionDimensionTarget(
            id: dimensionID,
            target: .angle(45.0, .degree)
        )
    )
    let applyResult = try session.execute(.applySelectionDimensionTarget(id: dimensionID))
    let appliedEvaluation = try SelectionDimensionService().evaluate(
        document: session.document,
        dimensionID: dimensionID
    )
    let appliedMeasurement = try #require(appliedEvaluation.measurements.first)
    let angle = try lineAngle(
        in: session.document,
        featureID: editableFeatureID
    )

    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)
    #expect(abs(angle - Double.pi / 4.0) <= 1.0e-12)
    assertAngleQuantity(appliedMeasurement.measured, equals: Double.pi / 4.0)
    assertAngleQuantity(appliedMeasurement.target, equals: Double.pi / 4.0)
    #expect(abs(appliedMeasurement.residual.value) <= 1.0e-12)
    #expect(try appliedMeasurement.isSatisfied())
}

@Test func selectionDimensionApplyUpdatesArcSpanFromEndpointReferences() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createArcSketch(
        name: "Measured Arc Span",
        plane: .xy,
        center: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        radius: .length(6.0, .millimeter),
        startAngle: .angle(0.0, .degree),
        endAngle: .angle(90.0, .degree)
    )
    let targets = try arcEndpointTargets(in: document, featureID: featureID)
    let session = EditorSession(document: document)
    let addResult = try session.execute(
        .addSelectionDimension(
            name: "Arc Span",
            kind: .angle,
            first: targets.start,
            second: targets.end,
            target: .angle(90.0, .degree)
        )
    )
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    _ = try session.execute(
        .setSelectionDimensionTarget(
            id: dimensionID,
            target: .angle(60.0, .degree)
        )
    )
    let applyResult = try session.execute(.applySelectionDimensionTarget(id: dimensionID))
    let appliedEvaluation = try SelectionDimensionService().evaluate(
        document: session.document,
        dimensionID: dimensionID
    )
    let appliedMeasurement = try #require(appliedEvaluation.measurements.first)
    let span = try arcSpan(
        in: session.document,
        featureID: featureID
    )

    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)
    #expect(abs(span - Double.pi / 3.0) <= 1.0e-12)
    assertAngleQuantity(appliedMeasurement.measured, equals: Double.pi / 3.0)
    assertAngleQuantity(appliedMeasurement.target, equals: Double.pi / 3.0)
    #expect(abs(appliedMeasurement.residual.value) <= 1.0e-12)
    #expect(try appliedMeasurement.isSatisfied())
    assertArcEndpointReferences(
        appliedMeasurement.dimension,
        expectedSpan: Double.pi / 3.0
    )
}

@Test func selectionDimensionApplyUpdatesArcSpanFromEndpointReferencesOnZXPlane() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createArcSketch(
        name: "Measured ZX Arc Span",
        plane: .zx,
        center: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        radius: .length(6.0, .millimeter),
        startAngle: .angle(0.0, .degree),
        endAngle: .angle(90.0, .degree)
    )
    let targets = try arcEndpointTargets(in: document, featureID: featureID)
    let session = EditorSession(document: document)
    let addResult = try session.execute(
        .addSelectionDimension(
            name: "ZX Arc Span",
            kind: .angle,
            first: targets.start,
            second: targets.end,
            target: .angle(90.0, .degree)
        )
    )
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    _ = try session.execute(
        .setSelectionDimensionTarget(
            id: dimensionID,
            target: .angle(60.0, .degree)
        )
    )
    let applyResult = try session.execute(.applySelectionDimensionTarget(id: dimensionID))
    let appliedEvaluation = try SelectionDimensionService().evaluate(
        document: session.document,
        dimensionID: dimensionID
    )
    let appliedMeasurement = try #require(appliedEvaluation.measurements.first)
    let span = try arcSpan(
        in: session.document,
        featureID: featureID
    )

    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)
    #expect(abs(span - Double.pi / 3.0) <= 1.0e-12)
    assertAngleQuantity(appliedMeasurement.measured, equals: Double.pi / 3.0)
    assertAngleQuantity(appliedMeasurement.target, equals: Double.pi / 3.0)
    #expect(abs(appliedMeasurement.residual.value) <= 1.0e-12)
    #expect(try appliedMeasurement.isSatisfied())
    assertArcEndpointReferences(
        appliedMeasurement.dimension,
        expectedSpan: Double.pi / 3.0
    )
}

@Test func selectionDimensionCommandMeasuresGeneratedFacePairDistance() async throws {
    var document = DesignDocument.empty()
    try document.createExtrudedRectangle(
        name: "Measured Box",
        plane: .xy,
        width: .length(20.0, .millimeter),
        height: .length(10.0, .millimeter),
        depth: .length(6.0, .millimeter),
        direction: .normal
    )
    let targets = try opposingFaceTargets(in: document)

    let dimensionID = try document.addSelectionDimension(
        name: "Box Depth",
        kind: .distance,
        first: targets.first,
        second: targets.second,
        target: .length(6.0, .millimeter)
    )

    #expect(document.cadDocument.selectionDimensions.count == 1)
    #expect(document.productMetadata.measurements.isEmpty)
    let dimension = try #require(document.cadDocument.selectionDimensions.first)
    #expect(dimension.id == dimensionID)
    #expect(dimension.kind == .distance)

    let evaluation = try SelectionDimensionService().evaluate(document: document)
    let measurement = try #require(evaluation.measurements.first)
    #expect(evaluation.measurements.count == 1)
    #expect(measurement.dimension.id == dimensionID)
    #expect(measurement.measured == .length(0.006, unit: .meter))
    #expect(abs(measurement.residual.value) <= 1.0e-12)
    #expect(try measurement.isSatisfied())
}

@Test func selectionDimensionCommandRejectsObjectWideTargets() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Measured Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let targets = try lineEndpointTargets(in: document, featureID: featureID)

    #expect(throws: EditorError.self) {
        try document.addSelectionDimension(
            name: nil,
            kind: .distance,
            first: SelectionTarget(sceneNodeID: targets.sceneNodeID),
            second: targets.end,
            target: .length(10.0, .millimeter)
        )
    }
}

private func lineEndpointTargets(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> (
    sceneNodeID: SceneNodeID,
    start: SelectionTarget,
    end: SelectionTarget
) {
    let summary = try SketchEntitySummaryService().summarize(document: document)
    let entry = try #require(summary.entries.first {
        $0.sourceFeatureID == featureID.description && $0.entityKind == "line"
    })
    let sceneNodeIDString = try #require(entry.sceneNodeID)
    let sceneNodeUUID = try #require(UUID(uuidString: sceneNodeIDString))
    let sceneNodeID = SceneNodeID(sceneNodeUUID)
    let startHandle = try #require(entry.pointHandles.first { $0.handle == .lineStart })
    let endHandle = try #require(entry.pointHandles.first { $0.handle == .lineEnd })
    return (
        sceneNodeID: sceneNodeID,
        start: SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .sketchEntity(SelectionComponentID(rawValue: startHandle.selectionComponentID))
        ),
        end: SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .sketchEntity(SelectionComponentID(rawValue: endHandle.selectionComponentID))
        )
    )
}

private func lineCurveTarget(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> SelectionTarget {
    let summary = try SketchEntitySummaryService().summarize(document: document)
    let entry = try #require(summary.entries.first {
        $0.sourceFeatureID == featureID.description && $0.entityKind == "line"
    })
    let sceneNodeIDString = try #require(entry.sceneNodeID)
    let sceneNodeUUID = try #require(UUID(uuidString: sceneNodeIDString))
    let curveComponentID = try #require(entry.selectionComponentID)
    return SelectionTarget(
        sceneNodeID: SceneNodeID(sceneNodeUUID),
        component: .sketchEntity(SelectionComponentID(rawValue: curveComponentID))
    )
}

private func circleCenterAndCurveTargets(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> (
    sceneNodeID: SceneNodeID,
    center: SelectionTarget,
    curve: SelectionTarget
) {
    let summary = try SketchEntitySummaryService().summarize(document: document)
    let entry = try #require(summary.entries.first {
        $0.sourceFeatureID == featureID.description && $0.entityKind == "circle"
    })
    let sceneNodeIDString = try #require(entry.sceneNodeID)
    let sceneNodeUUID = try #require(UUID(uuidString: sceneNodeIDString))
    let sceneNodeID = SceneNodeID(sceneNodeUUID)
    let centerHandle = try #require(entry.pointHandles.first { $0.handle == .circleCenter })
    let curveComponentID = try #require(entry.selectionComponentID)
    return (
        sceneNodeID: sceneNodeID,
        center: SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .sketchEntity(SelectionComponentID(rawValue: centerHandle.selectionComponentID))
        ),
        curve: SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .sketchEntity(SelectionComponentID(rawValue: curveComponentID))
        )
    )
}

private func arcCenterAndCurveTargets(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> (
    sceneNodeID: SceneNodeID,
    center: SelectionTarget,
    curve: SelectionTarget
) {
    let summary = try SketchEntitySummaryService().summarize(document: document)
    let entry = try #require(summary.entries.first {
        $0.sourceFeatureID == featureID.description && $0.entityKind == "arc"
    })
    let sceneNodeIDString = try #require(entry.sceneNodeID)
    let sceneNodeUUID = try #require(UUID(uuidString: sceneNodeIDString))
    let sceneNodeID = SceneNodeID(sceneNodeUUID)
    let centerHandle = try #require(entry.pointHandles.first { $0.handle == .arcCenter })
    let curveComponentID = try #require(entry.selectionComponentID)
    return (
        sceneNodeID: sceneNodeID,
        center: SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .sketchEntity(SelectionComponentID(rawValue: centerHandle.selectionComponentID))
        ),
        curve: SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .sketchEntity(SelectionComponentID(rawValue: curveComponentID))
        )
    )
}

private func arcEndpointTargets(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> (
    sceneNodeID: SceneNodeID,
    start: SelectionTarget,
    end: SelectionTarget
) {
    let summary = try SketchEntitySummaryService().summarize(document: document)
    let entry = try #require(summary.entries.first {
        $0.sourceFeatureID == featureID.description && $0.entityKind == "arc"
    })
    let sceneNodeIDString = try #require(entry.sceneNodeID)
    let sceneNodeUUID = try #require(UUID(uuidString: sceneNodeIDString))
    let sceneNodeID = SceneNodeID(sceneNodeUUID)
    let startHandle = try #require(entry.pointHandles.first { $0.handle == .arcStart })
    let endHandle = try #require(entry.pointHandles.first { $0.handle == .arcEnd })
    return (
        sceneNodeID: sceneNodeID,
        start: SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .sketchEntity(SelectionComponentID(rawValue: startHandle.selectionComponentID))
        ),
        end: SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .sketchEntity(SelectionComponentID(rawValue: endHandle.selectionComponentID))
        )
    )
}

private func opposingFaceTargets(
    in document: DesignDocument
) throws -> (first: SelectionTarget, second: SelectionTarget) {
    let topology = try TopologySummaryService().summarize(document: document)
    let faceEntries = try topology.entries.compactMap { entry -> (centerZ: Double, target: SelectionTarget)? in
        guard entry.kind == .face,
              let centerZ = entry.center?.z else {
            return nil
        }
        return (centerZ, try #require(entry.selectionTarget()))
    }
    let lowerFace = try #require(faceEntries.min { $0.centerZ < $1.centerZ })
    let upperFace = try #require(faceEntries.max { $0.centerZ < $1.centerZ })
    #expect(upperFace.centerZ - lowerFace.centerZ > 0.0)
    return (lowerFace.target, upperFace.target)
}

private func lineLength(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> Double {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation,
          case let .line(line) = sketch.entities.values.first else {
        Issue.record("Expected one source line")
        return 0.0
    }
    let start = try point(line.start, in: document)
    let end = try point(line.end, in: document)
    let dx = end.x - start.x
    let dy = end.y - start.y
    return (dx * dx + dy * dy).squareRoot()
}

private func lineAngle(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> Double {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation,
          case let .line(line) = sketch.entities.values.first else {
        Issue.record("Expected one source line")
        return 0.0
    }
    let start = try point(line.start, in: document)
    let end = try point(line.end, in: document)
    return atan2(end.y - start.y, end.x - start.x)
}

private func circleRadius(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> Double {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation,
          case let .circle(circle) = sketch.entities.values.first else {
        Issue.record("Expected one source circle")
        return 0.0
    }
    return try document.cadDocument.parameters.resolvedValue(for: circle.radius).value
}

private func arcRadius(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> Double {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation,
          case let .arc(arc) = sketch.entities.values.first else {
        Issue.record("Expected one source arc")
        return 0.0
    }
    return try document.cadDocument.parameters.resolvedValue(for: arc.radius).value
}

private func arcSpan(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> Double {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation,
          case let .arc(arc) = sketch.entities.values.first else {
        Issue.record("Expected one source arc")
        return 0.0
    }
    let start = try document.cadDocument.parameters.resolvedValue(for: arc.startAngle).value
    let end = try document.cadDocument.parameters.resolvedValue(for: arc.endAngle).value
    var span = end - start
    while span <= 0.0 {
        span += Double.pi * 2.0
    }
    while span > Double.pi * 2.0 {
        span -= Double.pi * 2.0
    }
    return span
}

private func point(
    _ point: SketchPoint,
    in document: DesignDocument
) throws -> Point2D {
    Point2D(
        x: try document.cadDocument.parameters.resolvedValue(for: point.x).value,
        y: try document.cadDocument.parameters.resolvedValue(for: point.y).value
    )
}

private func assertAngleQuantity(
    _ quantity: Quantity,
    equals expectedValue: Double,
    tolerance: Double = 1.0e-12
) {
    #expect(quantity.kind == .angle)
    #expect(abs(quantity.value - expectedValue) <= tolerance)
}

private func assertLineEndpointReferences(
    _ dimension: SelectionDimension,
    expectedLength: Double
) {
    guard case .curve(.parameter(let first)) = dimension.first,
          case .curve(.parameter(let second)) = dimension.second else {
        Issue.record("Expected line endpoint parameter references")
        return
    }
    let parameters = [first.parameter, second.parameter].sorted()
    #expect(abs(parameters[0]) <= 1.0e-12)
    #expect(abs(parameters[1] - expectedLength) <= 1.0e-12)
}

private func assertArcEndpointReferences(
    _ dimension: SelectionDimension,
    expectedSpan: Double
) {
    guard case .curve(.parameter(let first)) = dimension.first,
          case .curve(.parameter(let second)) = dimension.second else {
        Issue.record("Expected arc endpoint parameter references")
        return
    }
    let parameters = [first.parameter, second.parameter].sorted()
    #expect(abs((parameters[1] - parameters[0]) - expectedSpan) <= 1.0e-12)
}
