import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test func curveCurvatureDisplayCommandPersistsScaleAndParticipatesInUndoRedo() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createCircleSketch(
            name: "Curvature Display Circle",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter)
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let circle = try #require(summary.entries.first { $0.entityKind == "circle" })
    let target = try #require(circle.selectionTarget())
    let componentID = try #require(sketchEntityComponentID(from: target))

    let result = try session.execute(
        .setCurveCurvatureDisplay(
            target: target,
            isVisible: true,
            combScale: 0.25
        )
    )

    #expect(result.commandName == "setCurveCurvatureDisplay")
    #expect(result.didMutate)
    #expect(session.document.productMetadata.curveCurvatureDisplays[componentID] == CurveCurvatureDisplay(
        componentID: componentID,
        combScale: 0.25
    ))

    _ = try session.undo()
    #expect(session.document.productMetadata.curveCurvatureDisplays[componentID] == nil)

    _ = try session.redo()
    #expect(session.document.productMetadata.curveCurvatureDisplays[componentID]?.combScale == 0.25)

    _ = try session.execute(
        .setCurveCurvatureDisplay(
            target: target,
            isVisible: false,
            combScale: nil
        )
    )
    #expect(session.document.productMetadata.curveCurvatureDisplays[componentID] == nil)
}

@MainActor
@Test func curveCurvatureDisplayRejectsSourcePointTargets() async throws {
    let setup = try pointTargetDocument()
    let session = EditorSession(document: setup.document)
    let target = try pointSelectionTarget(
        featureID: setup.featureID,
        pointID: setup.pointID,
        document: session.document
    )

    var caught: EditorError?
    do {
        _ = try session.execute(
            .setCurveCurvatureDisplay(
                target: target,
                isVisible: true,
                combScale: CurveCurvatureDisplay.defaultCombScale
            )
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(session.document.productMetadata.curveCurvatureDisplays.isEmpty)
}

private func sketchEntityComponentID(from target: SelectionTarget) -> SelectionComponentID? {
    guard case .sketchEntity(let componentID) = target.component else {
        return nil
    }
    return componentID
}

private func pointTargetDocument() throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    pointID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createSplineSketch(
        name: "Curvature Display Point Source",
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
            message: "Point target setup requires a source sketch."
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

private func pointSelectionTarget(
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
