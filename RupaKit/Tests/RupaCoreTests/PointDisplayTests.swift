import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test func pointDisplayCommandNormalizesControlPointTargetsAndParticipatesInUndoRedo() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Point Display Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
                SketchPoint(x: .length(0.002, .meter), y: .length(0.004, .meter)),
                SketchPoint(x: .length(0.006, .meter), y: .length(0.004, .meter)),
                SketchPoint(x: .length(0.008, .meter), y: .length(0.0, .meter)),
            ])
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let curveTarget = try #require(spline.selectionTarget())
    let componentID = try #require(sketchEntityComponentID(from: curveTarget))
    let controlPoint = try #require(spline.controlPointTargets.first { $0.index == 1 })
    let controlPointTarget = try sketchEntitySelectionTarget(
        entry: spline,
        componentID: controlPoint.selectionComponentID
    )

    let hideResult = try session.execute(
        .setPointDisplay(target: controlPointTarget, isVisible: nil)
    )

    #expect(hideResult.commandName == "setPointDisplay")
    #expect(hideResult.didMutate)
    #expect(session.document.productMetadata.pointDisplays[componentID] == PointDisplay(
        componentID: componentID,
        isVisible: false
    ))

    _ = try session.undo()
    #expect(session.document.productMetadata.pointDisplays[componentID] == nil)

    _ = try session.redo()
    #expect(session.document.productMetadata.pointDisplays[componentID]?.isVisible == false)

    _ = try session.execute(
        .setPointDisplay(target: curveTarget, isVisible: nil)
    )
    #expect(session.document.productMetadata.pointDisplays[componentID]?.isVisible == true)
}

@MainActor
@Test func pointDisplayRejectsSourcePointTargets() async throws {
    let setup = try pointDisplayPointTargetDocument()
    let session = EditorSession(document: setup.document)
    let target = try pointDisplayPointSelectionTarget(
        featureID: setup.featureID,
        pointID: setup.pointID,
        document: session.document
    )

    var caught: EditorError?
    do {
        _ = try session.execute(
            .setPointDisplay(target: target, isVisible: true)
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(session.document.productMetadata.pointDisplays.isEmpty)
}

private func sketchEntityComponentID(from target: SelectionTarget) -> SelectionComponentID? {
    guard case .sketchEntity(let componentID) = target.component else {
        return nil
    }
    return componentID
}

private func sketchEntitySelectionTarget(
    entry: SketchEntitySummaryResult.EntityEntry,
    componentID: String
) throws -> SelectionTarget {
    guard let sceneNodeID = entry.sceneNodeID,
          let sceneNodeUUID = UUID(uuidString: sceneNodeID) else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Point display test requires a sketch scene node."
        )
    }
    return SelectionTarget(
        sceneNodeID: SceneNodeID(sceneNodeUUID),
        component: .sketchEntity(SelectionComponentID(rawValue: componentID))
    )
}

private func pointDisplayPointTargetDocument() throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    pointID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createSplineSketch(
        name: "Point Display Point Source",
        plane: .xy,
        spline: SketchSpline(controlPoints: [
            SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
            SketchPoint(x: .length(0.002, .meter), y: .length(0.003, .meter)),
            SketchPoint(x: .length(0.006, .meter), y: .length(0.003, .meter)),
            SketchPoint(x: .length(0.008, .meter), y: .length(0.0, .meter)),
        ])
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Point display test requires a source sketch."
        )
    }
    let pointID = SketchEntityID()
    sketch.entities[pointID] = .point(
        SketchPoint(x: .length(0.004, .meter), y: .length(0.002, .meter))
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, pointID)
}

private func pointDisplayPointSelectionTarget(
    featureID: FeatureID,
    pointID: SketchEntityID,
    document: DesignDocument
) throws -> SelectionTarget {
    let summary = try SketchEntitySummaryService().summarize(document: document)
    let point = try #require(summary.entries.first { entry in
        entry.sourceFeatureID == featureID.description &&
            entry.entityID == pointID.description
    })
    return try #require(point.selectionTarget())
}
