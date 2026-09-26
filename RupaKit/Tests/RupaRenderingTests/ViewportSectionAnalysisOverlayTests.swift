import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@Test func viewportSectionAnalysisOverlayBuildsPlaneAndSegments() throws {
    let ruler = WorkspaceScalePreset.architecture.rulerConfiguration
    let result = viewportSectionAnalysisResult(
        segments: [
            viewportSectionSegment(bodyID: "body-a", startX: -2.0, endX: 2.0, z: 0.0),
            viewportSectionSegment(bodyID: "body-a", startX: -1.0, endX: 1.0, z: 1.0),
        ]
    )

    let overlay = ViewportSectionAnalysisOverlay.build(
        result: result,
        ruler: ruler,
        maximumVisibleSegments: 32
    )

    let plane = try #require(overlay.plane)
    #expect(overlay.segments.count == 2)
    #expect(overlay.sourceSegmentCount == 2)
    #expect(overlay.omittedSegmentCount == 0)
    #expect(!overlay.hasTruncatedSourcePayload)
    #expect(plane.corners.count == 4)
    #expect(plane.halfExtentMeters >= ruler.normalizedForWorkspaceScale().majorTickMeters)
    #expect(plane.normalEnd.y > plane.origin.y)
    #expect(overlay.segments.allSatisfy { $0.bodyID == "body-a" })
}

@Test func viewportSectionAnalysisOverlayKeepsPlaneVisibleWithoutSegments() throws {
    let ruler = WorkspaceScalePreset.urbanPlanning.rulerConfiguration
    let result = viewportSectionAnalysisResult(segments: [])

    let overlay = ViewportSectionAnalysisOverlay.build(
        result: result,
        ruler: ruler
    )

    let plane = try #require(overlay.plane)
    let normalizedRuler = ruler.normalizedForWorkspaceScale()
    #expect(overlay.segments.isEmpty)
    #expect(overlay.sourceSegmentCount == 0)
    #expect(plane.halfExtentMeters >= normalizedRuler.visibleSpanMeters * 0.04)
}

@Test func viewportSectionAnalysisOverlayCapsVisibleSegmentsForCanvasBudget() throws {
    let ruler = WorkspaceScalePreset.productDesign.rulerConfiguration
    let segments = (0..<5).map { index in
        viewportSectionSegment(
            bodyID: "body-\(index)",
            startX: Double(index),
            endX: Double(index) + 0.5,
            z: Double(index) * 0.25
        )
    }
    let result = viewportSectionAnalysisResult(
        segments: segments,
        truncatedIntersectionSegments: true
    )

    let overlay = ViewportSectionAnalysisOverlay.build(
        result: result,
        ruler: ruler,
        maximumVisibleSegments: 2
    )

    #expect(overlay.segments.count == 2)
    #expect(overlay.sourceSegmentCount == 5)
    #expect(overlay.omittedSegmentCount == 3)
    #expect(overlay.hasTruncatedSourcePayload)
    #expect(overlay.segments.map(\.bodyID) == ["body-0", "body-1"])
}

@Test func viewportSectionAnalysisOverlayBuildsClosedContourHatches() throws {
    let ruler = WorkspaceScalePreset.architecture.rulerConfiguration
    let contour = viewportSectionContour(
        points2D: [
            Point2D(x: -1.0, y: -1.0),
            Point2D(x: 1.0, y: -1.0),
            Point2D(x: 1.0, y: 1.0),
            Point2D(x: -1.0, y: 1.0),
        ]
    )
    let result = viewportSectionAnalysisResult(
        segments: [],
        contours: [contour]
    )

    let overlay = ViewportSectionAnalysisOverlay.build(
        result: result,
        ruler: ruler,
        maximumVisibleHatches: 16
    )

    #expect(overlay.contours.count == 1)
    #expect(overlay.sourceContourCount == 1)
    #expect(overlay.omittedContourCount == 0)
    #expect(overlay.contours.first?.isClosed == true)
    #expect(overlay.hatches.isEmpty == false)
    #expect(overlay.hatches.count <= 16)
    #expect(overlay.hatches.allSatisfy { $0.contourID == contour.id })
}

@Test func viewportSectionAnalysisOverlayMarksInterferingContoursAndTheirHatches() throws {
    let square = [Point2D(x: -1, y: -1), Point2D(x: 1, y: -1), Point2D(x: 1, y: 1), Point2D(x: -1, y: 1)]
    let first = viewportSectionContour(points2D: square, bodyID: "body-a")
    let second = viewportSectionContour(points2D: square.map { Point2D(x: $0.x + 1, y: $0.y) }, bodyID: "body-b")
    let apart = viewportSectionContour(points2D: square.map { Point2D(x: $0.x + 5, y: $0.y) }, bodyID: "body-c")
    let result = viewportSectionAnalysisResult(
        segments: [],
        contours: [first, second, apart],
        interferences: [SectionAnalysisResult.Interference(
            firstBodyID: "body-a", secondBodyID: "body-b", contourIDs: [first.id, second.id]
        )]
    )

    let overlay = ViewportSectionAnalysisOverlay.build(result: result, ruler: WorkspaceScalePreset.architecture.rulerConfiguration)

    #expect(overlay.contours.map(\.isInterfering) == [true, true, false])
    #expect(overlay.hatches.contains { $0.contourID == apart.id && !$0.isInterfering })
    #expect(overlay.hatches.filter { $0.contourID != apart.id }.allSatisfy { $0.isInterfering })
}

private func viewportSectionAnalysisResult(
    segments: [SectionAnalysisResult.IntersectionSegment],
    contours: [SectionAnalysisResult.IntersectionContour] = [],
    interferences: [SectionAnalysisResult.Interference] = [],
    truncatedIntersectionSegments: Bool = false
) -> SectionAnalysisResult {
    SectionAnalysisResult(
        displayUnit: .millimeter,
        plane: SectionAnalysisResult.Plane(
            sourceKind: .sceneNode,
            sourceID: "section-plane",
            sourceName: "Section Plane",
            origin: Point3D(x: 0.0, y: 0.0, z: 0.0),
            normal: Vector3D.unitY,
            u: Vector3D.unitX,
            v: Vector3D.unitZ
        ),
        toleranceMeters: 0.001,
        bodies: [],
        intersectionSegments: segments,
        intersectionContours: contours,
        interferences: interferences,
        truncatedIntersectionSegments: truncatedIntersectionSegments,
        diagnostics: []
    )
}

private func viewportSectionSegment(
    bodyID: String,
    startX: Double,
    endX: Double,
    z: Double
) -> SectionAnalysisResult.IntersectionSegment {
    SectionAnalysisResult.IntersectionSegment(
        bodyID: bodyID,
        start: Point3D(x: startX, y: 0.0, z: z),
        end: Point3D(x: endX, y: 0.0, z: z),
        start2D: Point2D(x: startX, y: z),
        end2D: Point2D(x: endX, y: z)
    )
}

private func viewportSectionContour(
    points2D: [Point2D],
    bodyID: String = "body-a"
) -> SectionAnalysisResult.IntersectionContour {
    SectionAnalysisResult.IntersectionContour(
        id: "\(bodyID):contour:0",
        bodyID: bodyID,
        points: points2D.map { point in
            Point3D(x: point.x, y: 0.0, z: point.y)
        },
        points2D: points2D,
        isClosed: true,
        signedAreaSquareMeters: 4.0,
        lengthMeters: 8.0,
        segmentCount: points2D.count
    )
}
