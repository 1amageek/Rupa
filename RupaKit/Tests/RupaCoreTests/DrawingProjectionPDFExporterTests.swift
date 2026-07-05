import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Test func drawingProjectionPDFExporterCreatesVectorLayers() {
    let result = drawingProjectionPDFExporterFixture()

    let data = DrawingProjectionPDFExporter(
        options: DrawingProjectionPDFExporter.Options(
            pageWidth: 200.0,
            pageHeight: 100.0,
            padding: 10.0
        )
    ).pdf(for: result)
    let pdf = String(decoding: data, as: UTF8.self)

    #expect(pdf.hasPrefix("%PDF-1.4"))
    #expect(pdf.contains("/Type /Page"))
    #expect(pdf.contains("/MediaBox [0 0 200.000000 100.000000]"))
    #expect(pdf.contains("% layer section-hatches"))
    #expect(pdf.contains("% layer hidden-segments"))
    #expect(pdf.contains("% layer visible-segments"))
    #expect(pdf.contains("% layer section-contours"))
    #expect(pdf.contains("[6 4] 0 d"))
    #expect(pdf.contains(" m\n"))
    #expect(pdf.contains(" l\n"))
    #expect(pdf.contains("S\n"))
    #expect(pdf.contains("xref\n"))
    #expect(pdf.contains("%%EOF"))
    #expect(!pdf.localizedCaseInsensitiveContains("nan"))
    #expect(!pdf.localizedCaseInsensitiveContains("inf"))
}

@Test func drawingProjectionPDFExporterHandlesEmptyProjection() {
    let result = DrawingProjectionResult(
        displayUnit: .millimeter,
        savedViewID: SavedViewID(),
        savedViewName: "Empty PDF View",
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

    let data = DrawingProjectionPDFExporter().pdf(for: result)
    let pdf = String(decoding: data, as: UTF8.self)

    #expect(pdf.hasPrefix("%PDF-1.4"))
    #expect(pdf.contains("% layer visible-segments"))
    #expect(pdf.contains("xref\n"))
    #expect(!pdf.localizedCaseInsensitiveContains("nan"))
    #expect(!pdf.localizedCaseInsensitiveContains("inf"))
}

private func drawingProjectionPDFExporterFixture() -> DrawingProjectionResult {
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

    return DrawingProjectionResult(
        displayUnit: .meter,
        savedViewID: SavedViewID(),
        savedViewName: "PDF Drawing View",
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
        bounds: nil,
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
        sectionContours: [sectionContour],
        sectionHatches: [sectionHatch],
        diagnostics: []
    )
}
