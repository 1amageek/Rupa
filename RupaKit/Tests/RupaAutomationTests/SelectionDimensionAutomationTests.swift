import Foundation
import RupaCore
import SwiftCAD
import Testing
@testable import RupaAutomation

@MainActor
@Test func automationAddsPersistentSelectionDimension() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Automation Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(12.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let targets = try lineEndpointTargets(in: document, featureID: featureID)
    let session = EditorSession(document: document)
    let runner = AutomationRunner()

    let result = try runner.execute(
        .addSelectionDimension(
            name: "Automation Length",
            kind: .distance,
            first: targets.start,
            second: targets.end,
            target: .length(12.0, .millimeter)
        ),
        in: session
    )

    let dimensionID = try #require(result.addedSelectionDimensionID)
    #expect(result.message == "Selection dimension added.")
    #expect(result.commandName == "addSelectionDimension")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.selectionDimensions.map(\.id) == [dimensionID])
    #expect(session.document.productMetadata.measurements.isEmpty)

    let evaluation = try SelectionDimensionService().evaluate(
        document: session.document,
        dimensionID: dimensionID
    )
    let measurement = try #require(evaluation.measurements.first)
    #expect(evaluation.measurements.count == 1)
    #expect(measurement.measured == .length(0.012, unit: .meter))
    #expect(abs(measurement.residual.value) <= 1.0e-12)
}

@MainActor
@Test func automationRemovesPersistentSelectionDimension() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Automation Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(12.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let targets = try lineEndpointTargets(in: document, featureID: featureID)
    let session = EditorSession(document: document)
    let runner = AutomationRunner()
    let addResult = try runner.execute(
        .addSelectionDimension(
            name: "Automation Length",
            kind: .distance,
            first: targets.start,
            second: targets.end,
            target: .length(12.0, .millimeter)
        ),
        in: session
    )
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    let setResult = try runner.execute(
        .setSelectionDimensionTarget(
            id: dimensionID,
            target: .length(10.0, .millimeter)
        ),
        in: session
    )

    #expect(setResult.message == "Selection dimension target updated.")
    #expect(setResult.commandName == "setSelectionDimensionTarget")
    #expect(setResult.didMutate)
    #expect(setResult.generation == DocumentGeneration(2))
    #expect(session.document.cadDocument.selectionDimensions.first?.target == .length(10.0, .millimeter))

    let applyResult = try runner.execute(
        .applySelectionDimensionTarget(id: dimensionID),
        in: session
    )
    let appliedEvaluation = try SelectionDimensionService().evaluate(
        document: session.document,
        dimensionID: dimensionID
    )
    let appliedMeasurement = try #require(appliedEvaluation.measurements.first)

    #expect(applyResult.message == "Selection dimension target applied.")
    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)
    #expect(applyResult.generation == DocumentGeneration(3))
    #expect(appliedMeasurement.measured == .length(0.010, unit: .meter))
    #expect(appliedMeasurement.target == .length(0.010, unit: .meter))
    #expect(abs(appliedMeasurement.residual.value) <= 1.0e-12)

    let removeResult = try runner.execute(
        .removeSelectionDimension(id: dimensionID),
        in: session
    )

    #expect(removeResult.message == "Selection dimension removed.")
    #expect(removeResult.commandName == "removeSelectionDimension")
    #expect(removeResult.didMutate)
    #expect(removeResult.generation == DocumentGeneration(4))
    #expect(session.document.cadDocument.selectionDimensions.isEmpty)
    #expect(session.document.productMetadata.measurements.isEmpty)
}

@MainActor
@Test func automationAppliesSelectionDimensionToCircleRadius() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createCircleSketch(
        name: "Automation Circle",
        plane: .xy,
        center: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        radius: .length(6.0, .millimeter)
    )
    let targets = try circleCenterAndCurveTargets(in: document, featureID: featureID)
    let session = EditorSession(document: document)
    let runner = AutomationRunner()
    let addResult = try runner.execute(
        .addSelectionDimension(
            name: "Automation Radius",
            kind: .distance,
            first: targets.center,
            second: targets.curve,
            target: .length(6.0, .millimeter)
        ),
        in: session
    )
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    _ = try runner.execute(
        .setSelectionDimensionTarget(
            id: dimensionID,
            target: .length(4.0, .millimeter)
        ),
        in: session
    )
    let applyResult = try runner.execute(
        .applySelectionDimensionTarget(id: dimensionID),
        in: session
    )
    let appliedEvaluation = try SelectionDimensionService().evaluate(
        document: session.document,
        dimensionID: dimensionID
    )
    let appliedMeasurement = try #require(appliedEvaluation.measurements.first)

    #expect(applyResult.message == "Selection dimension target applied.")
    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)
    #expect(abs(try circleRadius(in: session.document, featureID: featureID) - 0.004) <= 1.0e-12)
    #expect(appliedMeasurement.measured == .length(0.004, unit: .meter))
    #expect(appliedMeasurement.target == .length(0.004, unit: .meter))
    #expect(abs(appliedMeasurement.residual.value) <= 1.0e-12)
}

private func lineEndpointTargets(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> (start: SelectionTarget, end: SelectionTarget) {
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

private func circleCenterAndCurveTargets(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> (center: SelectionTarget, curve: SelectionTarget) {
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
