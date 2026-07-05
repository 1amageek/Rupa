import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test func drawingProjectionGeneratesSavedViewStrokesWithoutFaceDiagonals() throws {
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Drawing Box",
            plane: .xy,
            width: .length(2.0, .meter),
            height: .length(2.0, .meter),
            depth: .length(2.0, .meter),
            direction: .normal
        )
    )
    let savedView = SavedView(
        name: "Drawing View",
        camera: SavedViewCamera(
            target: .origin,
            distanceMeters: 6.0,
            yawRadians: .pi / 4.0,
            pitchRadians: 0.62
        ),
        projection: .orthographic(heightMeters: 6.0),
        displayScale: SavedViewDisplayScale(ruler: .standard(for: .meter))
    )
    _ = try session.execute(.createSavedView(savedView))

    let result = try DrawingProjectionService().generate(
        document: session.document,
        query: DrawingProjectionQuery(savedViewID: savedView.id),
        objectRegistry: session.objectRegistry,
        currentEvaluation: session.currentEvaluation,
        currentGeneration: session.generation
    )

    #expect(result.savedViewID == savedView.id)
    #expect(result.savedViewName == "Drawing View")
    #expect(result.projectionMode == .orthographic)
    #expect(result.bodyCount == 1)
    #expect(result.triangleCount == 12)
    #expect(result.strokeCount == 12)
    #expect(result.strokes.allSatisfy { $0.kind == .crease })
    #expect(result.visibleStrokeCount > 0)
    #expect(result.hiddenStrokeCount > 0)
    #expect(result.unclassifiedStrokeCount == 0)
    #expect(
        result.visibleStrokeCount
            + result.hiddenStrokeCount
            + result.partiallyHiddenStrokeCount
            + result.unclassifiedStrokeCount == result.strokeCount
    )
    #expect(result.strokes.allSatisfy { $0.visibility != .unclassified })
    #expect(result.strokes.allSatisfy { $0.lengthMeters > 0.0 })
    #expect(result.bounds != nil)
    #expect(result.diagnostics.contains {
        $0.message.contains("hidden-line classified")
    })
}

@MainActor
@Test func drawingProjectionTruncatesAtRequestedStrokeLimit() throws {
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Drawing Box",
            plane: .xy,
            width: .length(2.0, .meter),
            height: .length(2.0, .meter),
            depth: .length(2.0, .meter),
            direction: .normal
        )
    )
    let savedView = SavedView(
        name: "Limited View",
        camera: SavedViewCamera(
            target: .origin,
            distanceMeters: 6.0,
            yawRadians: .pi / 4.0,
            pitchRadians: 0.62
        ),
        projection: .orthographic(heightMeters: 6.0),
        displayScale: SavedViewDisplayScale(ruler: .standard(for: .meter))
    )
    _ = try session.execute(.createSavedView(savedView))

    let result = try DrawingProjectionService().generate(
        document: session.document,
        query: DrawingProjectionQuery(
            savedViewID: savedView.id,
            maximumStrokeCount: 3
        ),
        objectRegistry: session.objectRegistry,
        currentEvaluation: session.currentEvaluation,
        currentGeneration: session.generation
    )

    #expect(result.strokeCount == 3)
    #expect(
        result.visibleStrokeCount
            + result.hiddenStrokeCount
            + result.partiallyHiddenStrokeCount
            + result.unclassifiedStrokeCount == result.strokeCount
    )
    #expect(result.unclassifiedStrokeCount == 0)
    #expect(result.truncatedStrokes)
    #expect(result.diagnostics.contains {
        $0.message.contains("truncated")
    })
}

@MainActor
@Test func drawingProjectionRejectsPerspectiveSavedViewsBeforeProjection() throws {
    let session = EditorSession()
    let savedView = SavedView(
        name: "Perspective View",
        camera: SavedViewCamera(
            target: .origin,
            distanceMeters: 6.0,
            yawRadians: .pi / 4.0,
            pitchRadians: 0.62
        ),
        projection: .perspective(fieldOfViewRadians: .pi / 3.0),
        displayScale: SavedViewDisplayScale(ruler: .standard(for: .meter))
    )
    _ = try session.execute(.createSavedView(savedView))

    #expect(throws: EditorError.self) {
        _ = try DrawingProjectionService().generate(
            document: session.document,
            query: DrawingProjectionQuery(savedViewID: savedView.id),
            objectRegistry: session.objectRegistry,
            currentEvaluation: session.currentEvaluation,
            currentGeneration: session.generation
        )
    }
}
