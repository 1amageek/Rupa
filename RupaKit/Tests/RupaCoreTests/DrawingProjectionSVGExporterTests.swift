import Foundation
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
    #expect(!drawingProjectionSVGContainsNonFiniteNumericToken(svg))
}

@Test func drawingProjectionSVGExporterAppliesPageAndStylePresets() {
    let result = DrawingProjectionResult(
        displayUnit: .meter,
        savedViewID: SavedViewID(),
        savedViewName: "Styled Drawing",
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
                visibilitySegments: []
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
                visibilitySegments: []
            ),
        ],
        diagnostics: []
    )

    let svg = DrawingProjectionSVGExporter(
        options: DrawingProjectionSVGExporter.Options(
            pagePreset: .a4Landscape,
            style: .preset(.presentation)
        )
    ).svg(for: result)

    #expect(svg.contains(#"width="841.889764" height="595.275590""#))
    #expect(svg.contains(##"stroke="#2563eb""##))
    #expect(svg.contains(#"stroke-dasharray="4 3""#))
    #expect(!drawingProjectionSVGContainsNonFiniteNumericToken(svg))
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
    #expect(!drawingProjectionSVGContainsNonFiniteNumericToken(svg))
}

@Test func drawingProjectionSVGExporterCreatesDrawingAnnotationLayer() {
    let result = drawingProjectionAnnotationResult()

    let svg = DrawingProjectionSVGExporter(
        options: DrawingProjectionSVGExporter.Options(width: 200.0, height: 120.0, padding: 10.0)
    ).svg(for: result)

    #expect(svg.contains(#"id="drawing-annotations" data-kind="drawingAnnotation""#))
    #expect(svg.contains(#"data-annotation-id="annotation-a""#))
    #expect(svg.contains(#"data-kind="distance""#))
    #expect(svg.contains(#"data-kind="annotationLeader" data-label-placement="manual""#))
    #expect(svg.contains(#"data-label-placement="manual""#))
    #expect(svg.contains(#"<text"#))
    #expect(svg.contains(#"2 &lt;m&gt;"#))
    #expect(svg.contains(#"data-anchor-index="0""#))
    #expect(svg.contains(#"data-anchor-index="1""#))
    #expect(!drawingProjectionSVGContainsNonFiniteNumericToken(svg))
}

@Test func drawingProjectionSVGExporterCreatesSectionHatchLayers() {
    let sectionContour = DrawingProjectionResult.SectionContour(
        id: "section-contour",
        sectionSourceID: "section-node",
        sectionSourceName: "Mid Cut",
        bodyID: "body-a",
        points: [
            Point3D(x: -1.0, y: -1.0, z: 0.0),
            Point3D(x: 1.0, y: -1.0, z: 0.0),
            Point3D(x: 1.0, y: 1.0, z: 0.0),
            Point3D(x: -1.0, y: 1.0, z: 0.0),
        ],
        sectionPlanePoints2D: [
            Point2D(x: -1.0, y: -1.0),
            Point2D(x: 1.0, y: -1.0),
            Point2D(x: 1.0, y: 1.0),
            Point2D(x: -1.0, y: 1.0),
        ],
        projectedPoints2D: [
            Point2D(x: -1.0, y: -1.0),
            Point2D(x: 1.0, y: -1.0),
            Point2D(x: 1.0, y: 1.0),
            Point2D(x: -1.0, y: 1.0),
        ],
        signedAreaSquareMeters: 4.0,
        lengthMeters: 8.0,
        segmentCount: 4
    )
    let sectionHatch = DrawingProjectionResult.SectionHatchSegment(
        id: "section-hatch",
        contourID: sectionContour.id,
        sectionSourceID: "section-node",
        sectionSourceName: "Mid Cut",
        bodyID: "body-a",
        start: Point3D(x: -0.5, y: -1.0, z: 0.0),
        end: Point3D(x: 1.0, y: 0.5, z: 0.0),
        start2D: Point2D(x: -0.5, y: -1.0),
        end2D: Point2D(x: 1.0, y: 0.5),
        spacingMeters: 0.1,
        angleDegrees: 45.0,
        lengthMeters: 2.12
    )
    let result = DrawingProjectionResult(
        displayUnit: .meter,
        savedViewID: SavedViewID(),
        savedViewName: "Section View",
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
        candidateEdgeCount: 0,
        truncatedStrokes: false,
        bounds: nil,
        strokes: [],
        sectionContours: [sectionContour],
        sectionHatches: [sectionHatch],
        diagnostics: []
    )

    let svg = DrawingProjectionSVGExporter().svg(for: result)

    #expect(svg.contains(#"id="section-hatches" data-kind="sectionHatch""#))
    #expect(svg.contains(#"id="section-contours" data-kind="sectionContour""#))
    #expect(svg.contains(#"data-hatch-id="section-hatch""#))
    #expect(svg.contains(#"data-contour-id="section-contour""#))
    #expect(svg.contains(#"data-section-source-id="section-node""#))
    #expect(svg.contains(#"data-section-source-name="Mid Cut""#))
    #expect(svg.contains(#"data-angle-degrees="45.000000""#))
    #expect(!drawingProjectionSVGContainsNonFiniteNumericToken(svg))
}

private func drawingProjectionSVGContainsNonFiniteNumericToken(_ svg: String) -> Bool {
    let separators = CharacterSet(charactersIn: " \n\t\r\"'=<>(),")
    let nonFiniteTokens: Set<String> = [
        "nan",
        "+nan",
        "-nan",
        "inf",
        "+inf",
        "-inf",
        "infinity",
        "+infinity",
        "-infinity",
    ]
    return svg
        .components(separatedBy: separators)
        .contains { token in
            nonFiniteTokens.contains(token.lowercased())
        }
}

private func drawingProjectionAnnotationResult() -> DrawingProjectionResult {
    let measurementID = MeasurementAnnotationID()
    let annotation = DrawingProjectionResult.Annotation(
        id: "annotation-a",
        measurementID: measurementID,
        sceneNodeID: nil,
        name: "Overall Width",
        kind: .distance,
        anchors: [
            DrawingProjectionResult.AnnotationAnchor(
                role: .start,
                kind: .worldPoint,
                worldPoint: Point3D(x: -1.0, y: 0.0, z: 0.0),
                point2D: Point2D(x: -1.0, y: 0.0)
            ),
            DrawingProjectionResult.AnnotationAnchor(
                role: .end,
                kind: .worldPoint,
                worldPoint: Point3D(x: 1.0, y: 0.0, z: 0.0),
                point2D: Point2D(x: 1.0, y: 0.0)
            ),
        ],
        labelWorldPoint: Point3D(x: 0.0, y: 0.2, z: 0.0),
        labelPoint2D: Point2D(x: 0.0, y: 0.2),
        measurementMeters: 2.0,
        displayText: "2 <m>",
        labelLayout: DrawingProjectionResult.AnnotationLabelLayout(
            placement: .manual,
            bounds2D: DrawingProjectionResult.Bounds2D(
                minX: -0.2,
                minY: 0.12,
                maxX: 0.2,
                maxY: 0.28
            ),
            leaderStart2D: Point2D(x: 0.0, y: 0.0),
            leaderEnd2D: Point2D(x: 0.0, y: 0.12),
            priorityIndex: 0
        )
    )
    return DrawingProjectionResult(
        displayUnit: .meter,
        savedViewID: SavedViewID(),
        savedViewName: "Annotated View",
        projectionMode: .orthographic,
        viewFrame: DrawingProjectionResult.ViewFrame(
            target: .origin,
            right: Vector3D(x: 1.0, y: 0.0, z: 0.0),
            up: Vector3D(x: 0.0, y: 1.0, z: 0.0),
            viewNormal: Vector3D(x: 0.0, y: 0.0, z: 1.0),
            visibleHeightMeters: 2.0,
            scaleBarLengthMeters: 1.0
        ),
        bodyCount: 0,
        triangleCount: 0,
        candidateEdgeCount: 0,
        truncatedStrokes: false,
        bounds: nil,
        strokes: [],
        annotations: [annotation],
        diagnostics: []
    )
}
