import SwiftCAD
import Testing
@testable import RupaCore

@Test func drawingProjectionSVGExporterCreatesVisibilityLayers() {
    let result = DrawingProjectionResult(
        displayUnit: .meter,
        savedViewID: SavedViewID(),
        savedViewName: "Drawing <View>",
        projectionMode: .orthographic,
        viewFrame: DrawingProjectionResult.ViewFrame(
            target: .origin,
            right: Vector3D(x: 1.0, y: 0.0, z: 0.0),
            up: Vector3D(x: 0.0, y: 1.0, z: 0.0),
            viewNormal: Vector3D(x: 0.0, y: 0.0, z: 1.0),
            visibleHeightMeters: 2.0,
            scaleBarLengthMeters: 1.0
        ),
        bodyCount: 1,
        triangleCount: 2,
        candidateEdgeCount: 2,
        truncatedStrokes: false,
        bounds: DrawingProjectionResult.Bounds2D(
            minX: -1.0,
            minY: -1.0,
            maxX: 1.0,
            maxY: 1.0
        ),
        strokes: [
            DrawingProjectionResult.Stroke(
                id: "visible-edge",
                bodyID: "body-a",
                kind: .crease,
                visibility: .visible,
                start: Point3D(x: -1.0, y: 0.0, z: 0.0),
                end: Point3D(x: 1.0, y: 0.0, z: 0.0),
                start2D: Point2D(x: -1.0, y: 0.0),
                end2D: Point2D(x: 1.0, y: 0.0),
                minimumDepthMeters: 0.0,
                maximumDepthMeters: 0.0,
                lengthMeters: 2.0,
                visibilitySegments: [
                    DrawingProjectionResult.VisibilitySegment(
                        id: "visible-edge-0",
                        visibility: .visible,
                        startFraction: 0.0,
                        endFraction: 1.0,
                        start2D: Point2D(x: -1.0, y: 0.0),
                        end2D: Point2D(x: 1.0, y: 0.0),
                        minimumDepthMeters: 0.0,
                        maximumDepthMeters: 0.0,
                        lengthMeters: 2.0
                    ),
                ]
            ),
            DrawingProjectionResult.Stroke(
                id: "hidden-edge",
                bodyID: "body-a",
                kind: .boundary,
                visibility: .hidden,
                start: Point3D(x: 0.0, y: -1.0, z: 0.0),
                end: Point3D(x: 0.0, y: 1.0, z: 0.0),
                start2D: Point2D(x: 0.0, y: -1.0),
                end2D: Point2D(x: 0.0, y: 1.0),
                minimumDepthMeters: 1.0,
                maximumDepthMeters: 1.0,
                lengthMeters: 2.0,
                visibilitySegments: [
                    DrawingProjectionResult.VisibilitySegment(
                        id: "hidden-edge-0",
                        visibility: .hidden,
                        startFraction: 0.0,
                        endFraction: 1.0,
                        start2D: Point2D(x: 0.0, y: -1.0),
                        end2D: Point2D(x: 0.0, y: 1.0),
                        minimumDepthMeters: 1.0,
                        maximumDepthMeters: 1.0,
                        lengthMeters: 2.0
                    ),
                ]
            ),
        ],
        diagnostics: []
    )

    let svg = DrawingProjectionSVGExporter(
        options: DrawingProjectionSVGExporter.Options(width: 200.0, height: 100.0, padding: 10.0)
    ).svg(for: result)

    #expect(svg.contains(#"<svg xmlns="http://www.w3.org/2000/svg""#))
    #expect(svg.contains(#"<title>Drawing &lt;View&gt;</title>"#))
    #expect(svg.contains(#"id="visible-segments" data-visibility="visible""#))
    #expect(svg.contains(#"id="hidden-segments" data-visibility="hidden""#))
    #expect(svg.contains(#"stroke-dasharray="6 4""#))
    #expect(svg.contains(#"data-stroke-id="visible-edge""#))
    #expect(svg.contains(#"data-stroke-id="hidden-edge""#))
    #expect(!svg.localizedCaseInsensitiveContains("nan"))
    #expect(!svg.localizedCaseInsensitiveContains("inf"))
}

@Test func drawingProjectionSVGExporterHandlesEmptyProjection() {
    let result = DrawingProjectionResult(
        displayUnit: .millimeter,
        savedViewID: SavedViewID(),
        savedViewName: "Empty View",
        projectionMode: .orthographic,
        viewFrame: DrawingProjectionResult.ViewFrame(
            target: .origin,
            right: Vector3D(x: 1.0, y: 0.0, z: 0.0),
            up: Vector3D(x: 0.0, y: 1.0, z: 0.0),
            viewNormal: Vector3D(x: 0.0, y: 0.0, z: 1.0),
            visibleHeightMeters: 1.0,
            scaleBarLengthMeters: 0.1
        ),
        bodyCount: 0,
        triangleCount: 0,
        candidateEdgeCount: 0,
        truncatedStrokes: false,
        bounds: nil,
        strokes: [],
        diagnostics: []
    )

    let svg = DrawingProjectionSVGExporter().svg(for: result)

    #expect(svg.contains(#"data-display-unit="mm""#))
    #expect(svg.contains(#"data-body-count="0""#))
    #expect(svg.contains(#"id="visible-segments""#))
    #expect(!svg.localizedCaseInsensitiveContains("nan"))
    #expect(!svg.localizedCaseInsensitiveContains("inf"))
}
