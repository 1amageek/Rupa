import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test func pointDisplayCommandNormalizesControlPointTargetsWithoutMutatingSourceHistory() async throws {
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
    let summary = try SketchEntitySnapshotService().snapshot(document: session.document)
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let curveTarget = try #require(spline.selectionTarget())
    let componentID = try #require(sketchEntityComponentID(from: curveTarget))
    let controlPoint = try #require(spline.controlPointTargets.first { $0.index == 1 })
    let controlPointTarget = try sketchEntitySelectionTarget(
        entry: spline,
        componentID: controlPoint.selectionComponentID
    )
    let sourceMetadata = session.document.productMetadata
    let sourceFingerprint = try session.document.cadDocument.sourceFingerprint(
        tolerance: session.document.modelingSettings.tolerance
    )
    let sourceGeneration = session.generation
    let sourceUndoCount = session.commandStack.undoEntries.count
    let sourceDirtyState = session.isDirty
    let workspaceRevision = session.workspaceState.revision
    let expectedWorkspaceRevision = try workspaceRevision.advanced()

    let hideResult = try session.execute(
        .setPointDisplay(target: controlPointTarget, isVisible: nil)
    )

    #expect(hideResult.commandName == "setPointDisplay")
    #expect(hideResult.revision == expectedWorkspaceRevision)
    #expect(session.workspaceState.pointDisplays[componentID] == PointDisplay(
        componentID: componentID,
        isVisible: false
    ))
    #expect(session.document.productMetadata == sourceMetadata)
    #expect(try session.document.cadDocument.sourceFingerprint(
        tolerance: session.document.modelingSettings.tolerance
    ) == sourceFingerprint)
    #expect(session.generation == sourceGeneration)
    #expect(session.commandStack.undoEntries.count == sourceUndoCount)
    #expect(session.isDirty == sourceDirtyState)

    _ = try session.execute(
        .setPointDisplay(target: curveTarget, isVisible: nil)
    )
    #expect(session.workspaceState.pointDisplays[componentID]?.isVisible == true)
    #expect(session.document.productMetadata == sourceMetadata)
    #expect(try session.document.cadDocument.sourceFingerprint(
        tolerance: session.document.modelingSettings.tolerance
    ) == sourceFingerprint)
    #expect(session.generation == sourceGeneration)
    #expect(session.commandStack.undoEntries.count == sourceUndoCount)
}

@MainActor
@Test func pointDisplayRejectsSourcePointTargets() async throws {
    let setup = try pointDisplayPointTargetDocument()
    let session = EditorSession(document: setup.document)
    let workspaceRevision = session.workspaceState.revision
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
    #expect(session.workspaceState.pointDisplays.isEmpty)
    #expect(session.workspaceState.revision == workspaceRevision)
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
    let summary = try SketchEntitySnapshotService().snapshot(document: document)
    let point = try #require(summary.entries.first { entry in
        entry.sourceFeatureID == featureID.description &&
            entry.entityID == pointID.description
    })
    return try #require(point.selectionTarget())
}
