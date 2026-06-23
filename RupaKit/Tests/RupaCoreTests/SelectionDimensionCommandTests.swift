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
