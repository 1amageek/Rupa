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
    #expect(result.unclassifiedStrokeCount == 0)
    #expect(result.visibilitySegmentCount >= result.strokeCount)
    #expect(result.visibleSegmentCount > 0)
    #expect(result.hiddenSegmentCount > 0)
    #expect(result.unclassifiedSegmentCount == 0)
    #expect(
        result.visibleStrokeCount
            + result.hiddenStrokeCount
            + result.partiallyHiddenStrokeCount
            + result.unclassifiedStrokeCount == result.strokeCount
    )
    #expect(
        result.visibleSegmentCount
            + result.hiddenSegmentCount
            + result.partiallyHiddenSegmentCount
            + result.unclassifiedSegmentCount == result.visibilitySegmentCount
    )
    #expect(result.strokes.allSatisfy { $0.visibility != .unclassified })
    #expect(result.strokes.allSatisfy { $0.visibilitySegments.isEmpty == false })
    #expect(result.strokes.flatMap(\.visibilitySegments).allSatisfy { segment in
        segment.visibility != .unclassified
            && segment.startFraction >= 0.0
            && segment.endFraction <= 1.0
            && segment.endFraction > segment.startFraction
            && segment.lengthMeters > 0.0
    })
    #expect(result.strokes.allSatisfy { $0.lengthMeters > 0.0 })
    #expect(result.bounds != nil)
    #expect(result.diagnostics.contains {
        $0.message.contains("hidden-line classified")
    })
    #expect(result.diagnostics.contains {
        $0.message.contains("visibility segment")
    })
}

@MainActor
@Test func drawingProjectionGeneratesSectionContoursAndHatchesFromSavedViewSectionState() throws {
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Sectioned Drawing Box",
            plane: .xy,
            width: .length(2.0, .meter),
            height: .length(2.0, .meter),
            depth: .length(2.0, .meter),
            direction: .normal
        )
    )
    var document = session.document
    let sectionNodeID = try document.createSectionPlane(name: "Mid Height Section")
    try document.setSceneNodeTransform(
        id: sectionNodeID,
        localTransform: Transform3D(
            matrix: try Matrix4x4(values: [
                1.0, 0.0, 0.0, 0.0,
                0.0, 1.0, 0.0, 0.0,
                0.0, 0.0, 1.0, 0.0,
                0.0, 0.0, 1.0, 1.0,
            ])
        )
    )
    let savedView = SavedView(
        name: "Section Drawing View",
        camera: SavedViewCamera(
            target: Point3D(x: 0.0, y: 0.0, z: 1.0),
            distanceMeters: 6.0,
            yawRadians: .pi / 4.0,
            pitchRadians: 0.62
        ),
        projection: .orthographic(heightMeters: 6.0),
        sectionState: SavedViewSectionState(sectionSceneNodeIDs: [sectionNodeID]),
        displayScale: SavedViewDisplayScale(ruler: .standard(for: .meter))
    )
    _ = try document.createSavedView(savedView, objectRegistry: session.objectRegistry)

    let result = try DrawingProjectionService().generate(
        document: document,
        query: DrawingProjectionQuery(savedViewID: savedView.id),
        objectRegistry: session.objectRegistry,
        currentEvaluation: session.currentEvaluation,
        currentGeneration: session.generation
    )

    #expect(result.sectionContourCount > 0)
    #expect(result.sectionHatchSegmentCount > 0)
    #expect(result.sectionContours.allSatisfy { $0.sectionSourceID == sectionNodeID.description })
    #expect(result.sectionHatches.allSatisfy { $0.sectionSourceID == sectionNodeID.description })
    #expect(result.sectionHatches.allSatisfy { $0.lengthMeters > 0.0 })
    #expect(result.sectionHatches.allSatisfy { $0.spacingMeters > 0.0 })
    #expect(result.sectionHatches.allSatisfy { $0.angleDegrees == 45.0 })
    #expect(result.truncatedSectionHatches == false)
    #expect(result.bounds != nil)
    #expect(result.diagnostics.contains {
        $0.message.contains("section contour")
            && $0.message.contains("section hatch")
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
    #expect(result.visibilitySegmentCount >= result.strokeCount)
    #expect(
        result.visibleStrokeCount
            + result.hiddenStrokeCount
            + result.partiallyHiddenStrokeCount
            + result.unclassifiedStrokeCount == result.strokeCount
    )
    #expect(
        result.visibleSegmentCount
            + result.hiddenSegmentCount
            + result.partiallyHiddenSegmentCount
            + result.unclassifiedSegmentCount == result.visibilitySegmentCount
    )
    #expect(result.unclassifiedStrokeCount == 0)
    #expect(result.unclassifiedSegmentCount == 0)
    #expect(result.truncatedStrokes)
    #expect(result.diagnostics.contains {
        $0.message.contains("truncated")
    })
}

@MainActor
@Test func drawingProjectionSplitsPartiallyHiddenStrokesIntoVisibilitySegments() throws {
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "Back Rail",
            plane: .xy,
            firstCorner: drawingProjectionSketchPoint(x: -2.0, y: -0.1),
            oppositeCorner: drawingProjectionSketchPoint(x: 2.0, y: 0.1),
            depth: .length(0.1, .meter),
            direction: .normal
        )
    )
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "Occluder",
            plane: .xy,
            firstCorner: drawingProjectionSketchPoint(x: -0.5, y: -0.5),
            oppositeCorner: drawingProjectionSketchPoint(x: 0.5, y: 0.5),
            depth: .length(1.0, .meter),
            direction: .normal
        )
    )
    let savedView = SavedView(
        name: "Split View",
        camera: SavedViewCamera(
            target: Point3D(x: 0.0, y: 0.0, z: 0.5),
            distanceMeters: 6.0,
            yawRadians: 0.0,
            pitchRadians: 0.08
        ),
        projection: .orthographic(heightMeters: 5.0),
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

    let splitStroke = try #require(result.strokes.first { stroke in
        stroke.visibility == .partiallyHidden
            && stroke.visibilitySegments.contains { $0.visibility == .visible }
            && stroke.visibilitySegments.contains { $0.visibility == .hidden }
    })
    #expect(result.partiallyHiddenStrokeCount > 0)
    #expect(result.visibilitySegmentCount > result.strokeCount)
    #expect(result.visibleSegmentCount > 0)
    #expect(result.hiddenSegmentCount > 0)
    #expect(result.unclassifiedSegmentCount == 0)
    #expect(splitStroke.visibilitySegments.count > 1)
    #expect(splitStroke.visibilitySegments.allSatisfy { segment in
        segment.startFraction >= 0.0
            && segment.endFraction <= 1.0
            && segment.endFraction > segment.startFraction
            && segment.lengthMeters > 0.0
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

private func drawingProjectionSketchPoint(
    x: Double,
    y: Double
) -> SketchPoint {
    SketchPoint(
        x: .length(x, .meter),
        y: .length(y, .meter)
    )
}
