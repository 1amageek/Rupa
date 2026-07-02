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

@Test func selectionDimensionEvaluationExposesDisplayUnitValues() async throws {
    var document = DesignDocument.empty()
    document.setDisplayUnit(.millimeter)
    let featureID = try document.createLineSketch(
        name: "Measured Display Line",
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
        name: "Line Length Display",
        kind: .distance,
        first: targets.start,
        second: targets.end,
        target: .length(8.0, .millimeter)
    )

    let evaluation = try SelectionDimensionService().evaluate(
        document: document,
        dimensionID: dimensionID
    )
    let measurement = try #require(evaluation.measurements.first)

    #expect(evaluation.displayUnit == .millimeter)
    #expect(evaluation.displayUnitSymbol == "mm")
    #expect(measurement.valueKind == .length)
    #expect(measurement.displayUnitSymbol == "mm")
    #expect(measurement.measured == .length(0.010, unit: .meter))
    #expect(measurement.target == .length(0.008, unit: .meter))
    #expect(abs(measurement.residual.value - 0.002) <= 1.0e-12)
    #expect(abs(measurement.measuredDisplayValue - 10.0) <= 1.0e-12)
    #expect(abs(measurement.targetDisplayValue - 8.0) <= 1.0e-12)
    #expect(abs(measurement.residualDisplayValue - 2.0) <= 1.0e-12)
}

@Test func selectionDimensionEvaluationUsesReadableLengthDisplayUnit() async throws {
    var document = DesignDocument.empty()
    document.setDisplayUnit(.millimeter)
    let featureID = try document.createLineSketch(
        name: "Measured Site Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .meter),
            y: .length(0.0, .meter)
        ),
        end: SketchPoint(
            x: .length(1_500.0, .meter),
            y: .length(0.0, .meter)
        )
    )
    let targets = try lineEndpointTargets(in: document, featureID: featureID)
    let dimensionID = try document.addSelectionDimension(
        name: "Site Line Length",
        kind: .distance,
        first: targets.start,
        second: targets.end,
        target: .length(1_200.0, .meter)
    )

    let evaluation = try SelectionDimensionService().evaluate(
        document: document,
        dimensionID: dimensionID
    )
    let measurement = try #require(evaluation.measurements.first)

    #expect(evaluation.displayUnit == .millimeter)
    #expect(evaluation.displayUnitSymbol == "mm")
    #expect(measurement.displayUnitSymbol == "m")
    #expect(abs(measurement.measuredDisplayValue - 1_500.0) <= 1.0e-12)
    #expect(abs(measurement.targetDisplayValue - 1_200.0) <= 1.0e-12)
    #expect(abs(measurement.residualDisplayValue - 300.0) <= 1.0e-12)
}

@Test func selectionDimensionEvaluationDecodesMissingDisplayValues() async throws {
    var document = DesignDocument.empty()
    document.setDisplayUnit(.millimeter)
    let featureID = try document.createLineSketch(
        name: "Measured Legacy Display Line",
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
        name: "Line Length Legacy Display",
        kind: .distance,
        first: targets.start,
        second: targets.end,
        target: .length(8.0, .millimeter)
    )
    let evaluation = try SelectionDimensionService().evaluate(
        document: document,
        dimensionID: dimensionID
    )
    let json = try JSONSerialization.jsonObject(
        with: try JSONEncoder().encode(evaluation)
    ) as? [String: Any]
    var legacyJSON = try #require(json)
    legacyJSON["displayUnitSymbol"] = nil
    var legacyMeasurement = try #require(
        (legacyJSON["measurements"] as? [[String: Any]])?.first
    )
    legacyMeasurement["valueKind"] = nil
    legacyMeasurement["measuredDisplayValue"] = nil
    legacyMeasurement["targetDisplayValue"] = nil
    legacyMeasurement["residualDisplayValue"] = nil
    legacyMeasurement["displayUnitSymbol"] = nil
    legacyJSON["measurements"] = [legacyMeasurement]

    let decoded = try JSONDecoder().decode(
        SelectionDimensionEvaluationResult.self,
        from: try JSONSerialization.data(withJSONObject: legacyJSON)
    )
    let measurement = try #require(decoded.measurements.first)

    #expect(decoded.displayUnit == .millimeter)
    #expect(decoded.displayUnitSymbol == "mm")
    #expect(measurement.valueKind == .length)
    #expect(measurement.displayUnitSymbol == "mm")
    #expect(abs(measurement.measuredDisplayValue - 10.0) <= 1.0e-12)
    #expect(abs(measurement.targetDisplayValue - 8.0) <= 1.0e-12)
    #expect(abs(measurement.residualDisplayValue - 2.0) <= 1.0e-12)
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

@Test func selectionDimensionApplyUpdatesSourcePointDistanceBetweenLineEndpoints() async throws {
    var document = DesignDocument.empty()
    let anchorFeatureID = try document.createLineSketch(
        name: "Anchor Line",
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
    let editableFeatureID = try document.createLineSketch(
        name: "Editable Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    let anchorTargets = try lineEndpointTargets(in: document, featureID: anchorFeatureID)
    let editableTargets = try lineEndpointTargets(in: document, featureID: editableFeatureID)
    let session = EditorSession(document: document)
    let addResult = try session.execute(
        .addSelectionDimension(
            name: "Point Distance",
            kind: .distance,
            first: editableTargets.start,
            second: anchorTargets.start,
            target: .length(10.0, .millimeter)
        )
    )
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    _ = try session.execute(
        .setSelectionDimensionTarget(
            id: dimensionID,
            target: .length(6.0, .millimeter)
        )
    )
    let applyResult = try session.execute(.applySelectionDimensionTarget(id: dimensionID))
    let appliedEvaluation = try SelectionDimensionService().evaluate(
        document: session.document,
        dimensionID: dimensionID
    )
    let appliedMeasurement = try #require(appliedEvaluation.measurements.first)
    let editableEndpoints = try lineEndpoints(
        in: session.document,
        featureID: editableFeatureID
    )

    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)
    #expect(abs(editableEndpoints.start.x - 0.006) <= 1.0e-12)
    #expect(abs(editableEndpoints.start.y) <= 1.0e-12)
    #expect(abs(editableEndpoints.end.x - 0.010) <= 1.0e-12)
    #expect(abs(editableEndpoints.end.y - 0.010) <= 1.0e-12)
    #expect(appliedMeasurement.measured == .length(0.006, unit: .meter))
    #expect(appliedMeasurement.target == .length(0.006, unit: .meter))
    #expect(abs(appliedMeasurement.residual.value) <= 1.0e-12)
    #expect(try appliedMeasurement.isSatisfied())
    guard case .curve(.parameter(let firstParameter)) = appliedMeasurement.dimension.first,
          case .curve(.parameter(let secondParameter)) = appliedMeasurement.dimension.second else {
        Issue.record("Expected point distance endpoint parameter references")
        return
    }
    #expect(firstParameter.curve.featureID == editableFeatureID)
    #expect(secondParameter.curve.featureID == anchorFeatureID)
    #expect(abs(firstParameter.parameter) <= 1.0e-12)
    #expect(abs(secondParameter.parameter) <= 1.0e-12)
}

@Test func selectionDimensionApplyUpdatesArcEndpointPointDistanceBySolvingEndpointAngle() async throws {
    var document = DesignDocument.empty()
    let arcFeatureID = try document.createArcSketch(
        name: "Arc Endpoint",
        plane: .xy,
        center: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        radius: .length(6.0, .millimeter),
        startAngle: .angle(0.0, .degree),
        endAngle: .angle(90.0, .degree)
    )
    let anchorFeatureID = try document.createLineSketch(
        name: "Anchor Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(6.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    let arcTargets = try arcEndpointTargets(in: document, featureID: arcFeatureID)
    let anchorTargets = try lineEndpointTargets(in: document, featureID: anchorFeatureID)
    let session = EditorSession(document: document)
    let addResult = try session.execute(
        .addSelectionDimension(
            name: "Arc Endpoint Distance",
            kind: .distance,
            first: arcTargets.start,
            second: anchorTargets.start,
            target: .length(sqrt(72.0), .millimeter)
        )
    )
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    _ = try session.execute(
        .setSelectionDimensionTarget(
            id: dimensionID,
            target: .length(6.0, .millimeter)
        )
    )
    let applyResult = try session.execute(.applySelectionDimensionTarget(id: dimensionID))
    let appliedEvaluation = try SelectionDimensionService().evaluate(
        document: session.document,
        dimensionID: dimensionID
    )
    let appliedMeasurement = try #require(appliedEvaluation.measurements.first)
    let startAngle = try arcStartAngle(in: session.document, featureID: arcFeatureID)

    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)
    #expect(abs(startAngle - Double.pi / 6.0) <= 1.0e-12)
    assertLengthQuantity(appliedMeasurement.measured, equals: 0.006)
    assertLengthQuantity(appliedMeasurement.target, equals: 0.006)
    #expect(abs(appliedMeasurement.residual.value) <= 1.0e-12)
    #expect(try appliedMeasurement.isSatisfied())
    assertArcEndpointAndLineStartReferences(
        appliedMeasurement.dimension,
        arcFeatureID: arcFeatureID,
        lineFeatureID: anchorFeatureID,
        expectedArcParameter: Double.pi / 6.0
    )
}

@Test func selectionDimensionApplyUpdatesSplineControlPointDistance() async throws {
    var document = DesignDocument.empty()
    let splineFeatureID = try document.createSplineSketch(
        name: "Editable Spline",
        plane: .xy,
        spline: SketchSpline(controlPoints: [
            SketchPoint(x: .length(10.0, .millimeter), y: .length(0.0, .millimeter)),
            SketchPoint(x: .length(12.0, .millimeter), y: .length(3.0, .millimeter)),
            SketchPoint(x: .length(14.0, .millimeter), y: .length(3.0, .millimeter)),
            SketchPoint(x: .length(16.0, .millimeter), y: .length(0.0, .millimeter)),
        ])
    )
    let anchorFeatureID = try document.createLineSketch(
        name: "Anchor Line",
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
    let splineTargets = try splineControlPointTargets(in: document, featureID: splineFeatureID)
    let anchorTargets = try lineEndpointTargets(in: document, featureID: anchorFeatureID)
    let session = EditorSession(document: document)
    let addResult = try session.execute(
        .addSelectionDimension(
            name: "Spline CV Distance",
            kind: .distance,
            first: splineTargets[0],
            second: anchorTargets.start,
            target: .length(10.0, .millimeter)
        )
    )
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    _ = try session.execute(
        .setSelectionDimensionTarget(
            id: dimensionID,
            target: .length(6.0, .millimeter)
        )
    )
    let applyResult = try session.execute(.applySelectionDimensionTarget(id: dimensionID))
    let appliedEvaluation = try SelectionDimensionService().evaluate(
        document: session.document,
        dimensionID: dimensionID
    )
    let appliedMeasurement = try #require(appliedEvaluation.measurements.first)
    let controlPoints = try splineControlPoints(in: session.document, featureID: splineFeatureID)

    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)
    #expect(abs(controlPoints[0].x - 0.006) <= 1.0e-12)
    #expect(abs(controlPoints[0].y) <= 1.0e-12)
    #expect(abs(controlPoints[1].x - 0.012) <= 1.0e-12)
    #expect(abs(controlPoints[1].y - 0.003) <= 1.0e-12)
    assertLengthQuantity(appliedMeasurement.measured, equals: 0.006)
    assertLengthQuantity(appliedMeasurement.target, equals: 0.006)
    #expect(abs(appliedMeasurement.residual.value) <= 1.0e-12)
    #expect(try appliedMeasurement.isSatisfied())
    assertSplineControlPointAndLineStartReferences(
        appliedMeasurement.dimension,
        splineFeatureID: splineFeatureID,
        expectedControlPointIndex: 0,
        lineFeatureID: anchorFeatureID
    )
}

@Test func selectionDimensionApplyUpdatesStandaloneSketchPointDistance() async throws {
    var document = DesignDocument.empty()
    let pointFeatureID = try createStandalonePointSketch(
        in: &document,
        name: "Editable Point",
        plane: .xy,
        point: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let anchorFeatureID = try document.createLineSketch(
        name: "Anchor Line",
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
    let pointTarget = try standalonePointTarget(in: document, featureID: pointFeatureID)
    let anchorTargets = try lineEndpointTargets(in: document, featureID: anchorFeatureID)
    let session = EditorSession(document: document)
    let addResult = try session.execute(
        .addSelectionDimension(
            name: "Point Distance",
            kind: .distance,
            first: pointTarget,
            second: anchorTargets.start,
            target: .length(10.0, .millimeter)
        )
    )
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    _ = try session.execute(
        .setSelectionDimensionTarget(
            id: dimensionID,
            target: .length(6.0, .millimeter)
        )
    )
    let applyResult = try session.execute(.applySelectionDimensionTarget(id: dimensionID))
    let appliedEvaluation = try SelectionDimensionService().evaluate(
        document: session.document,
        dimensionID: dimensionID
    )
    let appliedMeasurement = try #require(appliedEvaluation.measurements.first)
    let movedPoint = try standalonePoint(in: session.document, featureID: pointFeatureID)

    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)
    #expect(abs(movedPoint.x - 0.006) <= 1.0e-12)
    #expect(abs(movedPoint.y) <= 1.0e-12)
    assertLengthQuantity(appliedMeasurement.measured, equals: 0.006)
    assertLengthQuantity(appliedMeasurement.target, equals: 0.006)
    #expect(abs(appliedMeasurement.residual.value) <= 1.0e-12)
    #expect(try appliedMeasurement.isSatisfied())
    assertStandalonePointAndLineStartReferences(
        appliedMeasurement.dimension,
        pointFeatureID: pointFeatureID,
        lineFeatureID: anchorFeatureID
    )
}

@Test func selectionDimensionApplyUpdatesStandalonePointToWholeSourceLineDistance() async throws {
    var document = DesignDocument.empty()
    let pointFeatureID = try createStandalonePointSketch(
        in: &document,
        name: "Editable Point",
        plane: .xy,
        point: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(5.0, .millimeter)
        )
    )
    let lineFeatureID = try document.createLineSketch(
        name: "Reference Line",
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
    let pointTarget = try standalonePointTarget(in: document, featureID: pointFeatureID)
    let lineTarget = try lineCurveTarget(in: document, featureID: lineFeatureID)
    let session = EditorSession(document: document)
    let addResult = try session.execute(
        .addSelectionDimension(
            name: "Point To Line Distance",
            kind: .distance,
            first: pointTarget,
            second: lineTarget,
            target: .length(10.0, .millimeter)
        )
    )
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    _ = try session.execute(
        .setSelectionDimensionTarget(
            id: dimensionID,
            target: .length(6.0, .millimeter)
        )
    )
    let applyResult = try session.execute(.applySelectionDimensionTarget(id: dimensionID))
    let appliedEvaluation = try SelectionDimensionService().evaluate(
        document: session.document,
        dimensionID: dimensionID
    )
    let appliedMeasurement = try #require(appliedEvaluation.measurements.first)
    let movedPoint = try standalonePoint(in: session.document, featureID: pointFeatureID)

    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)
    #expect(abs(movedPoint.x - 0.006) <= 1.0e-12)
    #expect(abs(movedPoint.y - 0.005) <= 1.0e-12)
    assertLengthQuantity(appliedMeasurement.measured, equals: 0.006)
    assertLengthQuantity(appliedMeasurement.target, equals: 0.006)
    #expect(abs(appliedMeasurement.residual.value) <= 1.0e-12)
    #expect(try appliedMeasurement.isSatisfied())
    guard case .sketchPoint(let pointReference) = appliedMeasurement.dimension.first,
          case .curve(.whole(let lineReference)) = appliedMeasurement.dimension.second else {
        Issue.record("Expected point-to-whole-line selection dimension references")
        return
    }
    #expect(pointReference.featureID == pointFeatureID)
    #expect(lineReference.featureID == lineFeatureID)
}

@Test func selectionDimensionApplyTranslatesWholeSourceLineWhenPointIsFixed() async throws {
    var document = DesignDocument.empty()
    let pointFeatureID = try createStandalonePointSketch(
        in: &document,
        name: "Fixed Point",
        plane: .xy,
        point: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(5.0, .millimeter)
        )
    )
    let lineFeatureID = try document.createLineSketch(
        name: "Movable Reference Line",
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
    let pointEntityID = try standalonePointEntityID(in: document, featureID: pointFeatureID)
    try document.addSketchConstraint(
        featureID: pointFeatureID,
        constraint: .fixed(.entity(pointEntityID))
    )
    let pointTarget = try standalonePointTarget(in: document, featureID: pointFeatureID)
    let lineTarget = try lineCurveTarget(in: document, featureID: lineFeatureID)
    let session = EditorSession(document: document)
    let addResult = try session.execute(
        .addSelectionDimension(
            name: "Fixed Point To Movable Line Distance",
            kind: .distance,
            first: pointTarget,
            second: lineTarget,
            target: .length(10.0, .millimeter)
        )
    )
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    _ = try session.execute(
        .setSelectionDimensionTarget(
            id: dimensionID,
            target: .length(6.0, .millimeter)
        )
    )
    let applyResult = try session.execute(.applySelectionDimensionTarget(id: dimensionID))
    let fixedPoint = try standalonePoint(in: session.document, featureID: pointFeatureID)
    let movedLine = try lineEndpoints(in: session.document, featureID: lineFeatureID)
    let appliedEvaluation = try SelectionDimensionService().evaluate(
        document: session.document,
        dimensionID: dimensionID
    )
    let appliedMeasurement = try #require(appliedEvaluation.measurements.first)

    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)
    #expect(abs(fixedPoint.x - 0.010) <= 1.0e-12)
    #expect(abs(fixedPoint.y - 0.005) <= 1.0e-12)
    #expect(abs(movedLine.start.x - 0.004) <= 1.0e-12)
    #expect(abs(movedLine.start.y) <= 1.0e-12)
    #expect(abs(movedLine.end.x - 0.004) <= 1.0e-12)
    #expect(abs(movedLine.end.y - 0.010) <= 1.0e-12)
    assertLengthQuantity(appliedMeasurement.measured, equals: 0.006)
    assertLengthQuantity(appliedMeasurement.target, equals: 0.006)
    #expect(abs(appliedMeasurement.residual.value) <= 1.0e-12)
    #expect(try appliedMeasurement.isSatisfied())
    guard case .sketchPoint(let pointReference) = appliedMeasurement.dimension.first,
          case .curve(.whole(let lineReference)) = appliedMeasurement.dimension.second else {
        Issue.record("Expected point-to-whole-line selection dimension references")
        return
    }
    #expect(pointReference.featureID == pointFeatureID)
    #expect(lineReference.featureID == lineFeatureID)
}

@Test func selectionDimensionApplyRejectsFixedPointToFixedSourceLineDistance() async throws {
    var document = DesignDocument.empty()
    let pointFeatureID = try createStandalonePointSketch(
        in: &document,
        name: "Fixed Point",
        plane: .xy,
        point: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(5.0, .millimeter)
        )
    )
    let lineFeatureID = try document.createLineSketch(
        name: "Fixed Reference Line",
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
    let pointEntityID = try standalonePointEntityID(in: document, featureID: pointFeatureID)
    let lineEntityID = try lineEntityID(in: document, featureID: lineFeatureID)
    try document.addSketchConstraint(
        featureID: pointFeatureID,
        constraint: .fixed(.entity(pointEntityID))
    )
    try document.addSketchConstraint(
        featureID: lineFeatureID,
        constraint: .fixed(.lineStart(lineEntityID))
    )
    let pointTarget = try standalonePointTarget(in: document, featureID: pointFeatureID)
    let lineTarget = try lineCurveTarget(in: document, featureID: lineFeatureID)
    let session = EditorSession(document: document)
    let addResult = try session.execute(
        .addSelectionDimension(
            name: "Fixed Point To Fixed Line Distance",
            kind: .distance,
            first: pointTarget,
            second: lineTarget,
            target: .length(10.0, .millimeter)
        )
    )
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    _ = try session.execute(
        .setSelectionDimensionTarget(
            id: dimensionID,
            target: .length(6.0, .millimeter)
        )
    )
    #expect(throws: EditorError.self) {
        try session.execute(.applySelectionDimensionTarget(id: dimensionID))
    }
    let fixedPoint = try standalonePoint(in: session.document, featureID: pointFeatureID)
    let fixedLine = try lineEndpoints(in: session.document, featureID: lineFeatureID)
    let unappliedEvaluation = try SelectionDimensionService().evaluate(
        document: session.document,
        dimensionID: dimensionID
    )
    let unappliedMeasurement = try #require(unappliedEvaluation.measurements.first)

    #expect(abs(fixedPoint.x - 0.010) <= 1.0e-12)
    #expect(abs(fixedPoint.y - 0.005) <= 1.0e-12)
    #expect(abs(fixedLine.start.x) <= 1.0e-12)
    #expect(abs(fixedLine.start.y) <= 1.0e-12)
    #expect(abs(fixedLine.end.x) <= 1.0e-12)
    #expect(abs(fixedLine.end.y - 0.010) <= 1.0e-12)
    assertLengthQuantity(unappliedMeasurement.measured, equals: 0.010)
    assertLengthQuantity(unappliedMeasurement.target, equals: 0.006)
    #expect(abs(unappliedMeasurement.residual.value - 0.004) <= 1.0e-12)
}

@Test func selectionDimensionApplyMovesSecondStandalonePointWhenFirstIsFixed() async throws {
    var document = DesignDocument.empty()
    let fixedFeatureID = try createStandalonePointSketch(
        in: &document,
        name: "Fixed Point",
        plane: .xy,
        point: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let movingFeatureID = try createStandalonePointSketch(
        in: &document,
        name: "Moving Point",
        plane: .xy,
        point: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let fixedPointID = try standalonePointEntityID(in: document, featureID: fixedFeatureID)
    try document.addSketchConstraint(
        featureID: fixedFeatureID,
        constraint: .fixed(.entity(fixedPointID))
    )
    let fixedTarget = try standalonePointTarget(in: document, featureID: fixedFeatureID)
    let movingTarget = try standalonePointTarget(in: document, featureID: movingFeatureID)
    let session = EditorSession(document: document)
    let addResult = try session.execute(
        .addSelectionDimension(
            name: "Fixed To Moving Point Distance",
            kind: .distance,
            first: fixedTarget,
            second: movingTarget,
            target: .length(10.0, .millimeter)
        )
    )
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    _ = try session.execute(
        .setSelectionDimensionTarget(
            id: dimensionID,
            target: .length(6.0, .millimeter)
        )
    )
    let applyResult = try session.execute(.applySelectionDimensionTarget(id: dimensionID))
    let fixedPoint = try standalonePoint(in: session.document, featureID: fixedFeatureID)
    let movedPoint = try standalonePoint(in: session.document, featureID: movingFeatureID)
    let appliedEvaluation = try SelectionDimensionService().evaluate(
        document: session.document,
        dimensionID: dimensionID
    )
    let appliedMeasurement = try #require(appliedEvaluation.measurements.first)

    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)
    #expect(abs(fixedPoint.x) <= 1.0e-12)
    #expect(abs(fixedPoint.y) <= 1.0e-12)
    #expect(abs(movedPoint.x - 0.006) <= 1.0e-12)
    #expect(abs(movedPoint.y) <= 1.0e-12)
    assertLengthQuantity(appliedMeasurement.measured, equals: 0.006)
    assertLengthQuantity(appliedMeasurement.target, equals: 0.006)
    #expect(abs(appliedMeasurement.residual.value) <= 1.0e-12)
    #expect(try appliedMeasurement.isSatisfied())
}

@Test func selectionDimensionApplyAllowsSatisfiedZeroDistanceBetweenFixedStandalonePoints() async throws {
    var document = DesignDocument.empty()
    let firstFeatureID = try createStandalonePointSketch(
        in: &document,
        name: "First Fixed Point",
        plane: .xy,
        point: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let secondFeatureID = try createStandalonePointSketch(
        in: &document,
        name: "Second Fixed Point",
        plane: .xy,
        point: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let firstPointID = try standalonePointEntityID(in: document, featureID: firstFeatureID)
    let secondPointID = try standalonePointEntityID(in: document, featureID: secondFeatureID)
    try document.addSketchConstraint(
        featureID: firstFeatureID,
        constraint: .fixed(.entity(firstPointID))
    )
    try document.addSketchConstraint(
        featureID: secondFeatureID,
        constraint: .fixed(.entity(secondPointID))
    )
    let firstTarget = try standalonePointTarget(in: document, featureID: firstFeatureID)
    let secondTarget = try standalonePointTarget(in: document, featureID: secondFeatureID)
    let session = EditorSession(document: document)
    let addResult = try session.execute(
        .addSelectionDimension(
            name: "Fixed Coincident Point Distance",
            kind: .distance,
            first: firstTarget,
            second: secondTarget,
            target: .length(0.0, .millimeter)
        )
    )
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    let applyResult = try session.execute(.applySelectionDimensionTarget(id: dimensionID))
    let firstPoint = try standalonePoint(in: session.document, featureID: firstFeatureID)
    let secondPoint = try standalonePoint(in: session.document, featureID: secondFeatureID)
    let appliedEvaluation = try SelectionDimensionService().evaluate(
        document: session.document,
        dimensionID: dimensionID
    )
    let appliedMeasurement = try #require(appliedEvaluation.measurements.first)

    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(abs(firstPoint.x) <= 1.0e-12)
    #expect(abs(firstPoint.y) <= 1.0e-12)
    #expect(abs(secondPoint.x) <= 1.0e-12)
    #expect(abs(secondPoint.y) <= 1.0e-12)
    assertLengthQuantity(appliedMeasurement.measured, equals: 0.0)
    assertLengthQuantity(appliedMeasurement.target, equals: 0.0)
    #expect(abs(appliedMeasurement.residual.value) <= 1.0e-12)
    #expect(try appliedMeasurement.isSatisfied())
}

@Test func selectionDimensionApplyRejectsImpossibleArcEndpointPointDistance() async throws {
    var document = DesignDocument.empty()
    let arcFeatureID = try document.createArcSketch(
        name: "Arc Endpoint",
        plane: .xy,
        center: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        radius: .length(6.0, .millimeter),
        startAngle: .angle(0.0, .degree),
        endAngle: .angle(90.0, .degree)
    )
    let anchorFeatureID = try document.createLineSketch(
        name: "Anchor Line",
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
    let arcTargets = try arcEndpointTargets(in: document, featureID: arcFeatureID)
    let anchorTargets = try lineEndpointTargets(in: document, featureID: anchorFeatureID)
    let session = EditorSession(document: document)
    let addResult = try session.execute(
        .addSelectionDimension(
            name: "Impossible Arc Endpoint Distance",
            kind: .distance,
            first: arcTargets.start,
            second: anchorTargets.start,
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
    #expect(throws: EditorError.self) {
        try session.execute(.applySelectionDimensionTarget(id: dimensionID))
    }
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

@Test func selectionDimensionApplyUpdatesGeneratedFacePairObjectDistance() async throws {
    var document = DesignDocument.empty()
    try document.createExtrudedRectangle(
        name: "Editable Box",
        plane: .xy,
        width: .length(20.0, .millimeter),
        height: .length(10.0, .millimeter),
        depth: .length(6.0, .millimeter),
        direction: .normal
    )
    let targets = try opposingFaceTargets(in: document)
    let session = EditorSession(document: document)
    let addResult = try session.execute(
        .addSelectionDimension(
            name: "Editable Box Depth",
            kind: .distance,
            first: targets.first,
            second: targets.second,
            target: .length(6.0, .millimeter)
        )
    )
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    _ = try session.execute(
        .setSelectionDimensionTarget(
            id: dimensionID,
            target: .length(9.0, .millimeter)
        )
    )
    let applyResult = try session.execute(.applySelectionDimensionTarget(id: dimensionID))
    let appliedEvaluation = try SelectionDimensionService().evaluate(
        document: session.document,
        dimensionID: dimensionID
    )
    let appliedMeasurement = try #require(appliedEvaluation.measurements.first)
    let objectSummary = try ObjectDimensionSummaryService().summarize(
        document: session.document,
        targets: [targets.first]
    )
    let depthEntry = try #require(objectSummary.entries.first { $0.kind == .sizeY })

    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)
    assertLengthQuantity(appliedMeasurement.measured, equals: 0.009)
    assertLengthQuantity(appliedMeasurement.target, equals: 0.009)
    #expect(abs(appliedMeasurement.residual.value) <= 1.0e-12)
    #expect(try appliedMeasurement.isSatisfied())
    #expect(abs(depthEntry.resolvedMeters - 0.009) <= 1.0e-12)
}

@Test func selectionDimensionApplyLeavesNonFaceTopologyPairsUnsupported() async throws {
    var document = DesignDocument.empty()
    try document.createExtrudedRectangle(
        name: "Editable Box",
        plane: .xy,
        width: .length(20.0, .millimeter),
        height: .length(10.0, .millimeter),
        depth: .length(6.0, .millimeter),
        direction: .normal
    )
    let targets = try generatedEdgeTargets(in: document)
    let session = EditorSession(document: document)
    let addResult = try session.execute(
        .addSelectionDimension(
            name: "Unsupported Edge Pair",
            kind: .distance,
            first: targets.first,
            second: targets.second,
            target: .length(1.0, .millimeter)
        )
    )
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    do {
        _ = try session.execute(.applySelectionDimensionTarget(id: dimensionID))
        Issue.record("Expected generated edge pair selection dimension application to remain unsupported.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("supported object face-distance dimensions"))
    }
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

private func lineEntityID(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> SketchEntityID {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation,
          let entityID = sketch.entities.first(where: { _, entity in
              if case .line = entity {
                  return true
              }
              return false
          })?.key else {
        Issue.record("Expected one source line entity ID")
        return SketchEntityID()
    }
    return entityID
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

private func splineControlPointTargets(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> [SelectionTarget] {
    let summary = try SketchEntitySummaryService().summarize(document: document)
    let entry = try #require(summary.entries.first {
        $0.sourceFeatureID == featureID.description && $0.entityKind == "spline"
    })
    let sceneNodeIDString = try #require(entry.sceneNodeID)
    let sceneNodeUUID = try #require(UUID(uuidString: sceneNodeIDString))
    let sceneNodeID = SceneNodeID(sceneNodeUUID)
    return entry.controlPointTargets
        .sorted { $0.index < $1.index }
        .map { controlPoint in
            SelectionTarget(
                sceneNodeID: sceneNodeID,
                component: .sketchEntity(SelectionComponentID(rawValue: controlPoint.selectionComponentID))
            )
        }
}

private func createStandalonePointSketch(
    in document: inout DesignDocument,
    name: String,
    plane: SketchPlane,
    point: SketchPoint
) throws -> FeatureID {
    let featureID = try document.createLineSketch(
        name: name,
        plane: plane,
        start: SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
        end: SketchPoint(x: .length(1.0, .millimeter), y: .length(0.0, .millimeter))
    )
    let pointID = SketchEntityID()
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Standalone point test requires a sketch feature."
        )
    }
    sketch.entities[pointID] = .point(point)
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return featureID
}

private func standalonePointTarget(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> SelectionTarget {
    let summary = try SketchEntitySummaryService().summarize(document: document)
    let entry = try #require(summary.entries.first {
        $0.sourceFeatureID == featureID.description && $0.entityKind == "point"
    })
    let sceneNodeIDString = try #require(entry.sceneNodeID)
    let sceneNodeUUID = try #require(UUID(uuidString: sceneNodeIDString))
    let pointHandle = try #require(entry.pointHandles.first { $0.handle == .point })
    return SelectionTarget(
        sceneNodeID: SceneNodeID(sceneNodeUUID),
        component: .sketchEntity(SelectionComponentID(rawValue: pointHandle.selectionComponentID))
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

private func generatedEdgeTargets(
    in document: DesignDocument
) throws -> (first: SelectionTarget, second: SelectionTarget) {
    let topology = try TopologySummaryService().summarize(document: document)
    let edgeTargets = try topology.entries.compactMap { entry -> SelectionTarget? in
        guard entry.kind == .edge else {
            return nil
        }
        return try #require(entry.selectionTarget())
    }
    let first = try #require(edgeTargets.first)
    let second = try #require(edgeTargets.dropFirst().first)
    return (first, second)
}

private func lineLength(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> Double {
    let endpoints = try lineEndpoints(in: document, featureID: featureID)
    let dx = endpoints.end.x - endpoints.start.x
    let dy = endpoints.end.y - endpoints.start.y
    return (dx * dx + dy * dy).squareRoot()
}

private func lineEndpoints(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> (start: Point2D, end: Point2D) {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation,
          case let .line(line) = sketch.entities.values.first else {
        Issue.record("Expected one source line")
        return (Point2D(x: 0.0, y: 0.0), Point2D(x: 0.0, y: 0.0))
    }
    return (
        start: try point(line.start, in: document),
        end: try point(line.end, in: document)
    )
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

private func splineControlPoints(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> [Point2D] {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation,
          case let .spline(spline) = sketch.entities.values.first else {
        Issue.record("Expected one source spline")
        return []
    }
    return try spline.controlPoints.map { try point($0, in: document) }
}

private func standalonePoint(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> Point2D {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation,
          let pointEntity = sketch.entities.values.first(where: { entity in
              if case .point = entity {
                  return true
              }
              return false
          }),
          case let .point(sketchPoint) = pointEntity else {
        Issue.record("Expected one standalone source point")
        return Point2D(x: 0.0, y: 0.0)
    }
    return try point(sketchPoint, in: document)
}

private func standalonePointEntityID(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> SketchEntityID {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation,
          let entityID = sketch.entities.first(where: { _, entity in
              if case .point = entity {
                  return true
              }
              return false
          })?.key else {
        Issue.record("Expected one standalone source point entity ID")
        return SketchEntityID()
    }
    return entityID
}

private func arcStartAngle(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> Double {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation,
          case let .arc(arc) = sketch.entities.values.first else {
        Issue.record("Expected one source arc")
        return 0.0
    }
    return try document.cadDocument.parameters.resolvedValue(for: arc.startAngle).value
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

private func assertLengthQuantity(
    _ quantity: Quantity,
    equals expectedValue: Double,
    tolerance: Double = 1.0e-12
) {
    #expect(quantity.kind == .length)
    #expect(abs(quantity.value - expectedValue) <= tolerance)
}

private func assertArcEndpointAndLineStartReferences(
    _ dimension: SelectionDimension,
    arcFeatureID: FeatureID,
    lineFeatureID: FeatureID,
    expectedArcParameter: Double
) {
    guard case .curve(.parameter(let arcEndpoint)) = dimension.first,
          case .curve(.parameter(let lineStart)) = dimension.second else {
        Issue.record("Expected arc endpoint and line start parameter references")
        return
    }
    #expect(arcEndpoint.curve.featureID == arcFeatureID)
    #expect(abs(arcEndpoint.parameter - expectedArcParameter) <= 1.0e-12)
    #expect(lineStart.curve.featureID == lineFeatureID)
    #expect(abs(lineStart.parameter) <= 1.0e-12)
}

private func assertSplineControlPointAndLineStartReferences(
    _ dimension: SelectionDimension,
    splineFeatureID: FeatureID,
    expectedControlPointIndex: Int,
    lineFeatureID: FeatureID
) {
    guard case .curve(.controlPoint(let controlPoint)) = dimension.first,
          case .curve(.parameter(let lineStart)) = dimension.second else {
        Issue.record("Expected spline control point and line start references")
        return
    }
    #expect(controlPoint.curve.featureID == splineFeatureID)
    #expect(controlPoint.controlPointIndex == expectedControlPointIndex)
    #expect(lineStart.curve.featureID == lineFeatureID)
    #expect(abs(lineStart.parameter) <= 1.0e-12)
}

private func assertStandalonePointAndLineStartReferences(
    _ dimension: SelectionDimension,
    pointFeatureID: FeatureID,
    lineFeatureID: FeatureID
) {
    guard case .sketchPoint(let point) = dimension.first,
          case .curve(.parameter(let lineStart)) = dimension.second else {
        Issue.record("Expected standalone point and line start references")
        return
    }
    #expect(point.featureID == pointFeatureID)
    #expect(lineStart.curve.featureID == lineFeatureID)
    #expect(abs(lineStart.parameter) <= 1.0e-12)
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
