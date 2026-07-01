import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Test func snapResolverReturnsGridCandidateForEmptyDocument() async throws {
    let document = DesignDocument.empty()
    let result = try SnapResolver().resolve(
        point: Point2D(x: 0.0014, y: 0.0026),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: true,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.001,
            maximumCandidateCount: 4
        )
    )

    #expect(result.resolvedPoint == Point2D(x: 0.001, y: 0.003))
    #expect(result.selectedCandidate?.kind == .grid)
    #expect(result.candidates.map(\.kind) == [.grid])
}

@Test func snapResolverUsesDocumentRulerForDefaultGridInterval() async throws {
    var document = DesignDocument.empty()
    try document.setRulerConfiguration(WorkspaceScalePreset.sitePlanning.rulerConfiguration)

    let result = try SnapResolver().resolve(
        point: Point2D(x: 149.0, y: 251.0),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: true,
            usesObjects: false,
            maximumCandidateCount: 4
        )
    )

    #expect(result.resolvedPoint == Point2D(x: 100.0, y: 300.0))
    #expect(result.selectedCandidate?.kind == .grid)
}

@Test func snapResolverKeepsExplicitGridIntervalAsFixedSnapSpacing() async throws {
    var document = DesignDocument.empty()
    try document.setRulerConfiguration(WorkspaceScalePreset.sitePlanning.rulerConfiguration)

    let result = try SnapResolver().resolve(
        point: Point2D(x: 149.004, y: 251.006),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: true,
            usesObjects: false,
            gridIntervalMeters: 0.01,
            maximumCandidateCount: 4
        )
    )

    #expect(result.resolvedPoint == Point2D(x: 149.0, y: 251.01))
    #expect(result.selectedCandidate?.kind == .grid)
}

@Test func snapResolverPrefersNearbyObjectCandidateOverGrid() async throws {
    var document = DesignDocument.empty()
    _ = try document.createLineSketch(
        name: "Snap Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(10.3, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )

    let result = try SnapResolver().resolve(
        point: Point2D(x: 0.01031, y: 0.00002),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: true,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 4
        )
    )

    #expect(result.selectedCandidate?.kind == .lineEnd)
    #expect(result.selectedCandidate?.source?.selectionTarget != nil)
    #expect(abs(result.resolvedPoint.x - 0.0103) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y) <= 1.0e-12)
    #expect(result.candidates.contains { $0.kind == .grid })
}

@Test func snapResolverCanTemporarilyForceObjectTargeting() async throws {
    var document = DesignDocument.empty()
    _ = try document.createLineSketch(
        name: "Forced Object Snap Line",
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

    let disabled = try SnapResolver().resolve(
        point: Point2D(x: 0.01002, y: 0.00001),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: true,
            usesObjects: false,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 4
        )
    )
    #expect(disabled.selectedCandidate?.kind == .grid)

    let forced = try SnapResolver().resolve(
        point: Point2D(x: 0.01002, y: 0.00001),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: true,
            usesObjects: false,
            objectTargetingOverride: .forceEnabled,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 4
        )
    )

    #expect(forced.selectedCandidate?.kind == .lineEnd)
    #expect(abs(forced.resolvedPoint.x - 0.01) <= 1.0e-12)
    #expect(abs(forced.resolvedPoint.y) <= 1.0e-12)
}

@Test func snapResolverCanTemporarilySuppressCandidateKinds() async throws {
    var document = DesignDocument.empty()
    _ = try document.createLineSketch(
        name: "Suppressed Object Snap Line",
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

    let result = try SnapResolver().resolve(
        point: Point2D(x: 0.01002, y: 0.00001),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: true,
            usesObjects: true,
            suppressedCandidateKinds: [.lineEnd, .lineClosest],
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 4
        )
    )

    #expect(result.selectedCandidate?.kind == .grid)
    #expect(result.candidates.contains { $0.kind == .lineEnd } == false)
    #expect(result.candidates.contains { $0.kind == .lineClosest } == false)
}

@Test func snapResolverReportsCircleCenterAndQuarterCandidates() async throws {
    var document = DesignDocument.empty()
    _ = try document.createCircleSketch(
        name: "Snap Circle",
        plane: .xy,
        center: SketchPoint(
            x: .length(1.0, .millimeter),
            y: .length(2.0, .millimeter)
        ),
        radius: .length(4.0, .millimeter)
    )

    let result = try SnapResolver().resolve(
        point: Point2D(x: 0.00505, y: 0.00203),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 8
        )
    )

    #expect(result.selectedCandidate?.kind == .circleQuarter)
    #expect(abs(result.resolvedPoint.x - 0.005) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - 0.002) <= 1.0e-12)
    #expect(result.candidates.contains { $0.kind == .circleCenter } == false)
}

@Test func snapResolverReportsLineClosestCandidateAwayFromSpecialPoints() async throws {
    var document = DesignDocument.empty()
    _ = try document.createLineSketch(
        name: "Snap Closest Line",
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

    let result = try SnapResolver().resolve(
        point: Point2D(x: 0.0071, y: 0.00004),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 8
        )
    )

    #expect(result.selectedCandidate?.kind == .lineClosest)
    #expect(abs(result.resolvedPoint.x - 0.0071) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y) <= 1.0e-12)
}

@Test func snapResolverProjectsSourceSketchCandidatesOntoActiveConstructionPlane() async throws {
    var document = DesignDocument.empty()
    _ = try document.createLineSketch(
        name: "Projected Snap Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    _ = try document.createConstructionPlane(
        name: "Right CPlane",
        plane: .yz
    )

    let result = try SnapResolver().resolve(
        point: Point2D(x: 0.006, y: 0.00005),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            usesConstructionPlaneProjection: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 8
        )
    )

    #expect(result.selectedCandidate?.kind == .lineClosest)
    #expect(abs(result.resolvedPoint.x - 0.006) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y) <= 1.0e-12)
}

@Test func snapResolverReportsCircleClosestCandidateAwayFromQuarterPoints() async throws {
    var document = DesignDocument.empty()
    _ = try document.createCircleSketch(
        name: "Snap Closest Circle",
        plane: .xy,
        center: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        radius: .length(4.0, .millimeter)
    )

    let query = Point2D(x: 0.0029, y: 0.00285)
    let queryLength = hypot(query.x, query.y)
    let expected = Point2D(
        x: query.x / queryLength * 0.004,
        y: query.y / queryLength * 0.004
    )
    let result = try SnapResolver().resolve(
        point: query,
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 8
        )
    )

    #expect(result.selectedCandidate?.kind == .circleClosest)
    #expect(abs(result.resolvedPoint.x - expected.x) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - expected.y) <= 1.0e-12)
}

@Test func snapResolverReportsCurveIntersectionWithRelatedSource() async throws {
    var document = DesignDocument.empty()
    _ = try document.createLineSketch(
        name: "Snap Horizontal",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(4.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(4.0, .millimeter)
        )
    )
    _ = try document.createLineSketch(
        name: "Snap Vertical",
        plane: .xy,
        start: SketchPoint(
            x: .length(6.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(6.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )

    let result = try SnapResolver().resolve(
        point: Point2D(x: 0.00604, y: 0.00403),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 8
        )
    )

    #expect(result.selectedCandidate?.kind == .curveIntersection)
    #expect(result.selectedCandidate?.source != nil)
    #expect(result.selectedCandidate?.relatedSource != nil)
    #expect(abs(result.resolvedPoint.x - 0.006) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - 0.004) <= 1.0e-12)
}

@Test func snapResolverReportsLinePerpendicularFromReferencePoint() async throws {
    var document = DesignDocument.empty()
    _ = try document.createLineSketch(
        name: "Snap Perpendicular Line",
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

    let result = try SnapResolver().resolve(
        point: Point2D(x: 0.00702, y: 0.00003),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 8,
            referencePoint: Point2D(x: 0.007, y: 0.003)
        )
    )

    #expect(result.selectedCandidate?.kind == .curvePerpendicular)
    #expect(abs(result.resolvedPoint.x - 0.007) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y) <= 1.0e-12)
}

@Test func snapResolverReportsCurveAxisCandidateFromReferencePoint() async throws {
    var document = DesignDocument.empty()
    _ = try document.createLineSketch(
        name: "Snap X Axis Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(5.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(5.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )

    let referencePoint = Point2D(x: 0.0, y: 0.004)
    let result = try SnapResolver().resolve(
        point: Point2D(x: 0.00502, y: 0.00401),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 8,
            referencePoint: referencePoint
        )
    )

    #expect(result.selectedCandidate?.kind == .curveAxis)
    #expect(result.selectedCandidate?.label == "X")
    #expect(result.selectedCandidate?.axisSource?.kind == .x)
    #expect(result.selectedCandidate?.axisSource?.referencePoint == referencePoint)
    #expect(abs(result.resolvedPoint.x - 0.005) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - 0.004) <= 1.0e-12)
}

@Test func snapResolverLabelsAxisCandidateUsingSketchPlaneWorldAxis() async throws {
    var document = DesignDocument.empty()
    _ = try document.createLineSketch(
        name: "Snap Y Axis Line",
        plane: .yz,
        start: SketchPoint(
            x: .length(5.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(5.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )

    let result = try SnapResolver().resolve(
        point: Point2D(x: 0.00502, y: 0.00401),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 8,
            referencePoint: Point2D(x: 0.0, y: 0.004)
        )
    )

    #expect(result.selectedCandidate?.kind == .curveAxis)
    #expect(result.selectedCandidate?.label == "Y")
    #expect(result.selectedCandidate?.axisSource?.kind == .y)
    #expect(abs(result.resolvedPoint.x - 0.005) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - 0.004) <= 1.0e-12)
}

@Test func snapResolverLabelsAxisCandidateUsingZXCanvasAxes() async throws {
    var document = DesignDocument.empty()
    _ = try document.createLineSketch(
        name: "Snap X Axis Line On ZX",
        plane: .zx,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(5.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(5.0, .millimeter)
        )
    )

    let result = try SnapResolver().resolve(
        point: Point2D(x: 0.00502, y: 0.00401),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 8,
            referencePoint: Point2D(x: 0.0, y: 0.004)
        )
    )

    #expect(result.selectedCandidate?.kind == .curveAxis)
    #expect(result.selectedCandidate?.label == "X")
    #expect(result.selectedCandidate?.axisSource?.kind == .x)
    #expect(abs(result.resolvedPoint.x - 0.005) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - 0.004) <= 1.0e-12)
}

@Test func snapResolverReportsCoordinatePlaneCandidateFromReferencePoint() async throws {
    var document = DesignDocument.empty()
    _ = try document.createLineSketch(
        name: "Snap YZ Plane Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(4.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(4.0, .millimeter)
        )
    )

    let referencePoint = Point2D(x: 0.005, y: 0.0)
    let result = try SnapResolver().resolve(
        point: Point2D(x: 0.00502, y: 0.00401),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            suppressedCandidateKinds: [.curveAxis],
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 8,
            referencePoint: referencePoint
        )
    )

    #expect(result.selectedCandidate?.kind == .curveCoordinatePlane)
    #expect(result.selectedCandidate?.label == "YZ")
    #expect(result.selectedCandidate?.coordinatePlaneSource?.kind == .yz)
    #expect(result.selectedCandidate?.coordinatePlaneSource?.referencePoint == referencePoint)
    #expect(abs(result.resolvedPoint.x - 0.005) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - 0.004) <= 1.0e-12)
}

@Test func snapResolverReportsCoordinatePlaneCandidateOnConstructionPlane() async throws {
    var document = DesignDocument.empty()
    _ = try document.createLineSketch(
        name: "Snap ZX Plane Line On YZ CPlane",
        plane: .yz,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(4.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(4.0, .millimeter)
        )
    )

    let referencePoint = Point2D(x: 0.005, y: 0.0)
    let result = try SnapResolver().resolve(
        point: Point2D(x: 0.00502, y: 0.00401),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            suppressedCandidateKinds: [.curveAxis, .curvePerpendicular],
            usesConstructionPlaneProjection: true,
            constructionPlane: .yz,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 8,
            referencePoint: referencePoint
        )
    )

    #expect(result.selectedCandidate?.kind == .curveCoordinatePlane)
    #expect(result.selectedCandidate?.label == "ZX")
    #expect(result.selectedCandidate?.coordinatePlaneSource?.kind == .zx)
    #expect(result.selectedCandidate?.coordinatePlaneSource?.referencePoint == referencePoint)
    #expect(abs(result.resolvedPoint.x - 0.005) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - 0.004) <= 1.0e-12)
}

@Test func snapResolverReportsCirclePerpendicularFromReferencePoint() async throws {
    var document = DesignDocument.empty()
    _ = try document.createCircleSketch(
        name: "Snap Perpendicular Circle",
        plane: .xy,
        center: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        radius: .length(4.0, .millimeter)
    )

    let expected = 0.004 / sqrt(2.0)
    let result = try SnapResolver().resolve(
        point: Point2D(x: expected + 0.00002, y: expected + 0.00001),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 8,
            referencePoint: Point2D(x: 0.008, y: 0.008)
        )
    )

    #expect(result.selectedCandidate?.kind == .curvePerpendicular)
    #expect(abs(result.resolvedPoint.x - expected) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - expected) <= 1.0e-12)
}

@Test func snapResolverReportsCircleTangentFromReferencePoint() async throws {
    var document = DesignDocument.empty()
    _ = try document.createCircleSketch(
        name: "Snap Tangent Circle",
        plane: .xy,
        center: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        radius: .length(4.0, .millimeter)
    )

    let expected = Point2D(
        x: cos(Double.pi / 6.0) * 0.004,
        y: sin(Double.pi / 6.0) * 0.004
    )
    let result = try SnapResolver().resolve(
        point: Point2D(x: expected.x + 0.00002, y: expected.y + 0.00001),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 8,
            referencePoint: Point2D(x: 0.0, y: 0.008)
        )
    )

    #expect(result.selectedCandidate?.kind == .curveTangent)
    #expect(abs(result.resolvedPoint.x - expected.x) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - expected.y) <= 1.0e-12)
}

@Test func snapResolverSnapsToReferenceLineAnchor() async throws {
    let document = DesignDocument.empty()
    let result = try SnapResolver().resolve(
        point: Point2D(x: 0.0069, y: 0.00204),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: true,
            usesObjects: false,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 8,
            referenceLineAnchors: [
                SketchReferenceLineAnchor(point: Point2D(x: 0.005, y: 0.002)),
            ]
        )
    )

    #expect(result.selectedCandidate?.kind == .referenceLine)
    #expect(result.selectedCandidate?.label == "Reference X")
    #expect(abs(result.resolvedPoint.x - 0.0069) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - 0.002) <= 1.0e-12)
    #expect(result.candidates.contains { $0.kind == .grid })
}

@Test func snapResolverReportsSourceRegionCenterCandidate() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createRectangleSketch(
        name: "Region Snap Rectangle",
        plane: .xy,
        width: .length(10.0, .millimeter),
        height: .length(6.0, .millimeter)
    )

    let result = try SnapResolver().resolve(
        point: Point2D(x: 0.00002, y: -0.00001),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 8
        )
    )

    #expect(result.selectedCandidate?.kind == .regionCenter)
    #expect(result.selectedCandidate?.label == "Region Center")
    #expect(result.selectedCandidate?.regionSource?.featureID == featureID)
    #expect(result.selectedCandidate?.regionSource?.sceneNodeID != nil)
    #expect(abs(result.resolvedPoint.x) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y) <= 1.0e-12)
}

@Test func snapResolverReportsMeasurementAnnotationPointCandidates() async throws {
    var document = DesignDocument.empty()
    let measurementID = try document.addMeasurementAnnotation(
        MeasurementAnnotation(
            name: "Measured Gap",
            kind: .distance,
            anchors: [
                .worldPoint(Point3D(x: 0.002, y: 0.003, z: 0.0), role: .start),
                .worldPoint(Point3D(x: 0.009, y: 0.003, z: 0.0), role: .end),
            ]
        )
    )
    let measurement = try #require(document.productMetadata.measurements[measurementID])

    let result = try SnapResolver().resolve(
        point: Point2D(x: 0.00201, y: 0.00301),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 8
        )
    )

    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .measurementPoint &&
            candidate.measurementSource?.measurementID == measurementID &&
            candidate.measurementSource?.anchorIndex == 0
    })
    #expect(result.selectedCandidate?.kind == .measurementPoint)
    #expect(candidate.label == "Measurement")
    #expect(candidate.measurementSource?.sceneNodeID == measurement.sceneNodeID)
    #expect(candidate.measurementSource?.name == "Measured Gap")
    #expect(candidate.measurementSource?.kind == .distance)
    #expect(candidate.measurementSource?.role == .start)
    #expect(candidate.measurementSource?.worldPoint == Point3D(x: 0.002, y: 0.003, z: 0.0))
    #expect(abs(candidate.point.x - 0.002) <= 1.0e-12)
    #expect(abs(candidate.point.y - 0.003) <= 1.0e-12)
}

@Test func snapResolverProjectsMeasurementAnnotationPointsOntoConstructionPlane() async throws {
    var document = DesignDocument.empty()
    let measurementID = try document.addMeasurementAnnotation(
        MeasurementAnnotation(
            name: "Projected Measure",
            kind: .distance,
            anchors: [
                .worldPoint(Point3D(x: 0.001, y: 0.006, z: 0.004), role: .start),
                .worldPoint(Point3D(x: 0.001, y: 0.010, z: 0.004), role: .end),
            ]
        )
    )

    let result = try SnapResolver().resolve(
        point: Point2D(x: 0.00601, y: 0.00401),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            usesConstructionPlaneProjection: true,
            constructionPlane: .yz,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 8
        )
    )

    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .measurementPoint &&
            candidate.measurementSource?.measurementID == measurementID &&
            candidate.measurementSource?.anchorIndex == 0
    })
    #expect(result.selectedCandidate?.kind == .measurementPoint)
    #expect(abs(candidate.point.x - 0.006) <= 1.0e-12)
    #expect(abs(candidate.point.y - 0.004) <= 1.0e-12)
    #expect(candidate.measurementSource?.worldPoint == Point3D(x: 0.001, y: 0.006, z: 0.004))
}

@Test func snapResolverResolvesMeasurementSketchReferencesFromCurrentGeometry() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Measured Source Line",
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
    let lineID = try snapResolverSingleLineID(in: document, featureID: featureID)
    let measurementID = try document.addMeasurementAnnotation(
        MeasurementAnnotation(
            name: "Measured Source Edge",
            kind: .distance,
            anchors: [
                .sketchReference(featureID: featureID, reference: .lineStart(lineID), role: .start),
                .sketchReference(featureID: featureID, reference: .lineEnd(lineID), role: .end),
            ]
        )
    )

    let initial = try SnapResolver().resolve(
        point: Point2D(x: 0.01001, y: 0.00001),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 16
        )
    )
    let initialCandidate = try #require(initial.candidates.first { candidate in
        candidate.kind == .measurementPoint &&
            candidate.measurementSource?.measurementID == measurementID &&
            candidate.measurementSource?.anchorIndex == 1
    })
    #expect(initialCandidate.measurementSource?.anchorKind == .sketchReference)
    #expect(initialCandidate.measurementSource?.sketchReference?.featureID == featureID)
    #expect(initialCandidate.measurementSource?.sketchReference?.reference == .lineEnd(lineID))
    #expect(abs((initialCandidate.measurementSource?.worldPoint.x ?? 0.0) - 0.010) <= 1.0e-12)

    try document.moveSketchEntityPoint(
        target: SelectionTarget(
            sceneNodeID: snapResolverSketchSceneNodeID(in: document, featureID: featureID),
            component: .sketchEntity(
                SelectionComponentID.sketchEntity(featureID: featureID, entityID: lineID)
            )
        ),
        handle: .lineEnd,
        deltaX: .length(2.0, .millimeter),
        deltaY: .length(0.0, .millimeter)
    )

    let updated = try SnapResolver().resolve(
        point: Point2D(x: 0.01201, y: 0.00001),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 16
        )
    )
    let updatedCandidate = try #require(updated.candidates.first { candidate in
        candidate.kind == .measurementPoint &&
            candidate.measurementSource?.measurementID == measurementID &&
            candidate.measurementSource?.anchorIndex == 1
    })
    #expect(abs(updatedCandidate.point.x - 0.012) <= 1.0e-12)
    #expect(abs(updatedCandidate.point.y) <= 1.0e-12)
    #expect(abs((updatedCandidate.measurementSource?.worldPoint.x ?? 0.0) - 0.012) <= 1.0e-12)
}

@Test func snapResolverResolvesMeasurementSketchCurveParametersFromCurrentGeometry() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Measured Source Curve Parameter",
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
    let lineID = try snapResolverSingleLineID(in: document, featureID: featureID)
    let measurementID = try document.addMeasurementAnnotation(
        MeasurementAnnotation(
            name: "Measured Source Curve Parameter",
            kind: .distance,
            anchors: [
                .sketchCurveParameter(featureID: featureID, entityID: lineID, parameter: 0.25, role: .point),
                .worldPoint(Point3D(x: 0.0, y: 0.0, z: 0.0), role: .start),
            ]
        )
    )

    let initial = try SnapResolver().resolve(
        point: Point2D(x: 0.00251, y: 0.00001),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 16
        )
    )
    let initialCandidate = try #require(initial.candidates.first { candidate in
        candidate.kind == .measurementPoint &&
            candidate.measurementSource?.measurementID == measurementID &&
            candidate.measurementSource?.anchorIndex == 0
    })
    #expect(initialCandidate.measurementSource?.anchorKind == .sketchCurveParameter)
    #expect(initialCandidate.measurementSource?.sketchCurveParameter?.featureID == featureID)
    #expect(initialCandidate.measurementSource?.sketchCurveParameter?.entityID == lineID)
    #expect(initialCandidate.measurementSource?.sketchCurveParameter?.parameter == 0.25)
    #expect(abs(initialCandidate.point.x - 0.0025) <= 1.0e-12)
    #expect(abs(initialCandidate.point.y) <= 1.0e-12)
    #expect(abs((initialCandidate.measurementSource?.worldPoint.x ?? 0.0) - 0.0025) <= 1.0e-12)

    try document.moveSketchEntityPoint(
        target: SelectionTarget(
            sceneNodeID: snapResolverSketchSceneNodeID(in: document, featureID: featureID),
            component: .sketchEntity(
                SelectionComponentID.sketchEntity(featureID: featureID, entityID: lineID)
            )
        ),
        handle: .lineEnd,
        deltaX: .length(10.0, .millimeter),
        deltaY: .length(0.0, .millimeter)
    )

    let updated = try SnapResolver().resolve(
        point: Point2D(x: 0.00501, y: 0.00001),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 16
        )
    )
    let updatedCandidate = try #require(updated.candidates.first { candidate in
        candidate.kind == .measurementPoint &&
            candidate.measurementSource?.measurementID == measurementID &&
            candidate.measurementSource?.anchorIndex == 0
    })
    #expect(updatedCandidate.measurementSource?.anchorKind == .sketchCurveParameter)
    #expect(abs(updatedCandidate.point.x - 0.005) <= 1.0e-12)
    #expect(abs(updatedCandidate.point.y) <= 1.0e-12)
    #expect(abs((updatedCandidate.measurementSource?.worldPoint.x ?? 0.0) - 0.005) <= 1.0e-12)
}

@Test func snapCandidateKindAllowsReferenceLineAnchorsOnlyFromGeometry() async throws {
    #expect(SnapCandidateKind.lineStart.isReferenceLineAnchorSource)
    #expect(SnapCandidateKind.circleCenter.isReferenceLineAnchorSource)
    #expect(SnapCandidateKind.controlVertex.isReferenceLineAnchorSource)
    #expect(SnapCandidateKind.measurementPoint.isReferenceLineAnchorSource)
    #expect(SnapCandidateKind.regionCenter.isReferenceLineAnchorSource)
    #expect(SnapCandidateKind.edgeMidpoint.isReferenceLineAnchorSource)
    #expect(SnapCandidateKind.faceCenter.isReferenceLineAnchorSource)
    #expect(SnapCandidateKind.surfaceFrame.isReferenceLineAnchorSource)
    #expect(SnapCandidateKind.grid.isReferenceLineAnchorSource == false)
    #expect(SnapCandidateKind.referenceLine.isReferenceLineAnchorSource == false)
}

@MainActor
@Test func snapResolverReportsGeneratedTopologyEdgeMiddleCandidate() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let topology = try TopologySummaryService().summarize(document: session.document)
    let edge = try #require(topology.entries.first { entry in
        entry.kind == .edge && entry.start != nil && entry.end != nil && entry.selectionTarget() != nil
    })
    let start = try #require(edge.start)
    let end = try #require(edge.end)
    let midpoint = Point2D(
        x: (start.x + end.x) * 0.5,
        y: (start.y + end.y) * 0.5
    )
    let edgeTarget = try #require(edge.selectionTarget())

    let result = try SnapResolver().resolve(
        point: Point2D(x: midpoint.x + 0.00001, y: midpoint.y + 0.00001),
        in: session.document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 32
        )
    )

    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .edgeMidpoint &&
            candidate.topologySource?.persistentName == edge.persistentName
    })
    let selectedWorldPoint = try #require(result.selectedTopologyWorldPoint)
    #expect(candidate.label == "Edge Middle")
    #expect(candidate.source == nil)
    #expect(candidate.topologySource?.selectionTarget == edgeTarget)
    #expect(abs(candidate.point.x - midpoint.x) <= 1.0e-12)
    #expect(abs(candidate.point.y - midpoint.y) <= 1.0e-12)
    #expect(abs(selectedWorldPoint.x - midpoint.x) <= 1.0e-12)
    #expect(abs(selectedWorldPoint.y - midpoint.y) <= 1.0e-12)
    #expect(abs(selectedWorldPoint.z - ((start.z + end.z) * 0.5)) <= 1.0e-12)
}

@MainActor
@Test func snapResolverProjectsGeneratedTopologyCandidatesOntoConstructionPlane() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let topology = try TopologySummaryService().summarize(document: session.document)
    let edge = try #require(topology.entries.first { entry in
        entry.kind == .edge && entry.start != nil && entry.end != nil && entry.selectionTarget() != nil
    })
    let start = try #require(edge.start)
    let end = try #require(edge.end)
    let expected = Point2D(
        x: (start.y + end.y) * 0.5,
        y: (start.z + end.z) * 0.5
    )

    let result = try SnapResolver().resolve(
        point: Point2D(x: expected.x + 0.00001, y: expected.y + 0.00001),
        in: session.document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            usesConstructionPlaneProjection: true,
            constructionPlane: .yz,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.02,
            maximumCandidateCount: 64
        )
    )

    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .edgeMidpoint &&
            candidate.topologySource?.persistentName == edge.persistentName
    })
    #expect(abs(candidate.point.x - expected.x) <= 1.0e-12)
    #expect(abs(candidate.point.y - expected.y) <= 1.0e-12)
    let worldPoint = try #require(candidate.topologySource?.worldPoint)
    #expect(worldPoint.x == (start.x + end.x) * 0.5)
    #expect(worldPoint.y == (start.y + end.y) * 0.5)
    #expect(worldPoint.z == (start.z + end.z) * 0.5)
}

@MainActor
@Test func snapResolverReportsGeneratedTopologyFaceCenterCandidate() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let topology = try TopologySummaryService().summarize(document: session.document)
    let face = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.center != nil && entry.selectionTarget() != nil
    })
    let center = try #require(face.center)
    let faceTarget = try #require(face.selectionTarget())

    let result = try SnapResolver().resolve(
        point: Point2D(x: center.x + 0.00001, y: center.y + 0.00001),
        in: session.document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 32
        )
    )

    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .faceCenter &&
            candidate.topologySource?.persistentName == face.persistentName
    })
    #expect(candidate.label == "Face Center")
    #expect(candidate.source == nil)
    #expect(candidate.topologySource?.selectionTarget == faceTarget)
    #expect(abs(candidate.point.x - center.x) <= 1.0e-12)
    #expect(abs(candidate.point.y - center.y) <= 1.0e-12)
}

@MainActor
@Test func snapResolverResolvesMeasurementTopologyReferencesFromCurrentTopology() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    var document = session.document
    let topology = try TopologySummaryService().summarize(document: document)
    let edge = try #require(topology.entries.first { entry in
        entry.kind == .edge && entry.start != nil && entry.end != nil && entry.selectionTarget() != nil
    })
    let start = try #require(edge.start)
    let end = try #require(edge.end)
    let target = try #require(edge.selectionTarget())
    let measurementID = try document.addMeasurementAnnotation(
        MeasurementAnnotation(
            name: "Measured Generated Edge",
            kind: .distance,
            anchors: [
                .topologyReference(
                    sceneNodeID: target.sceneNodeID,
                    component: target.component,
                    kind: edge.kind,
                    persistentName: edge.persistentName,
                    referenceID: edge.referenceID,
                    role: .center
                ),
                .worldPoint(Point3D(x: start.x, y: start.y, z: start.z), role: .start),
            ]
        )
    )
    let midpoint = Point2D(
        x: (start.x + end.x) * 0.5,
        y: (start.y + end.y) * 0.5
    )

    let result = try SnapResolver().resolve(
        point: Point2D(x: midpoint.x + 0.00001, y: midpoint.y + 0.00001),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 32
        )
    )

    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .measurementPoint &&
            candidate.measurementSource?.measurementID == measurementID &&
            candidate.measurementSource?.anchorIndex == 0
    })
    #expect(candidate.measurementSource?.anchorKind == .topologyReference)
    #expect(candidate.measurementSource?.topologyReference?.persistentName == edge.persistentName)
    #expect(candidate.measurementSource?.topologyReference?.referenceID == edge.referenceID)
    #expect(candidate.measurementSource?.topologyReference?.component == target.component)
    #expect(abs(candidate.point.x - midpoint.x) <= 1.0e-12)
    #expect(abs(candidate.point.y - midpoint.y) <= 1.0e-12)
    #expect(abs((candidate.measurementSource?.worldPoint.x ?? 0.0) - midpoint.x) <= 1.0e-12)
    #expect(abs((candidate.measurementSource?.worldPoint.y ?? 0.0) - midpoint.y) <= 1.0e-12)
    #expect(abs((candidate.measurementSource?.worldPoint.z ?? 0.0) - ((start.z + end.z) * 0.5)) <= 1.0e-12)
}

@MainActor
@Test func snapResolverResolvesMeasurementTopologyEdgeParametersFromCurrentLineEdge() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    var document = session.document
    let topology = try TopologySummaryService().summarize(document: document)
    let edge = try #require(topology.entries.first { entry in
        entry.kind == .edge &&
            entry.curveKind == "line" &&
            entry.curveOrigin != nil &&
            entry.curveDirection != nil &&
            entry.edgeParameterRange != nil &&
            entry.selectionTarget() != nil
    })
    let origin = try #require(edge.curveOrigin)
    let direction = try #require(edge.curveDirection)
    let range = try #require(edge.edgeParameterRange)
    let target = try #require(edge.selectionTarget())
    let parameter = 0.25
    let curveParameter = range.start + (range.end - range.start) * parameter
    let expectedWorldPoint = Point3D(
        x: origin.x + direction.x * curveParameter,
        y: origin.y + direction.y * curveParameter,
        z: origin.z + direction.z * curveParameter
    )
    let measurementID = try document.addMeasurementAnnotation(
        MeasurementAnnotation(
            name: "Measured Generated Edge Parameter",
            kind: .distance,
            anchors: [
                .topologyEdgeParameter(
                    sceneNodeID: target.sceneNodeID,
                    component: target.component,
                    persistentName: edge.persistentName,
                    referenceID: edge.referenceID,
                    parameter: parameter,
                    role: .point
                ),
                .worldPoint(Point3D(x: origin.x, y: origin.y, z: origin.z), role: .start),
            ]
        )
    )

    let result = try SnapResolver().resolve(
        point: Point2D(x: expectedWorldPoint.x + 0.00001, y: expectedWorldPoint.y + 0.00001),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 32
        )
    )

    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .measurementPoint &&
            candidate.measurementSource?.measurementID == measurementID &&
            candidate.measurementSource?.anchorIndex == 0
    })
    #expect(candidate.measurementSource?.anchorKind == .topologyEdgeParameter)
    #expect(candidate.measurementSource?.topologyEdgeParameter?.persistentName == edge.persistentName)
    #expect(candidate.measurementSource?.topologyEdgeParameter?.referenceID == edge.referenceID)
    #expect(candidate.measurementSource?.topologyEdgeParameter?.component == target.component)
    #expect(candidate.measurementSource?.topologyEdgeParameter?.parameter == parameter)
    #expect(abs(candidate.point.x - expectedWorldPoint.x) <= 1.0e-12)
    #expect(abs(candidate.point.y - expectedWorldPoint.y) <= 1.0e-12)
    #expect(abs((candidate.measurementSource?.worldPoint.x ?? 0.0) - expectedWorldPoint.x) <= 1.0e-12)
    #expect(abs((candidate.measurementSource?.worldPoint.y ?? 0.0) - expectedWorldPoint.y) <= 1.0e-12)
    #expect(abs((candidate.measurementSource?.worldPoint.z ?? 0.0) - expectedWorldPoint.z) <= 1.0e-12)
}

@MainActor
@Test func snapResolverResolvesMeasurementTopologyEdgeParametersFromCurrentCircularEdge() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedCircle())
    var document = session.document
    let topology = try TopologySummaryService().summarize(document: document)
    let edge = try #require(topology.entries.first { entry in
        entry.kind == .edge &&
            entry.curveKind == "circle" &&
            entry.curveCenter != nil &&
            entry.curveParameterXAxis != nil &&
            entry.curveParameterYAxis != nil &&
            entry.curveRadius != nil &&
            entry.edgeParameterRange != nil &&
            entry.selectionTarget() != nil
    })
    let center = try #require(edge.curveCenter)
    let xAxis = try #require(edge.curveParameterXAxis)
    let yAxis = try #require(edge.curveParameterYAxis)
    let radius = try #require(edge.curveRadius)
    let range = try #require(edge.edgeParameterRange)
    let target = try #require(edge.selectionTarget())
    let parameter = 0.25
    let curveParameter = range.start + (range.end - range.start) * parameter
    let expectedWorldPoint = Point3D(
        x: center.x + (xAxis.x * cos(curveParameter) + yAxis.x * sin(curveParameter)) * radius,
        y: center.y + (xAxis.y * cos(curveParameter) + yAxis.y * sin(curveParameter)) * radius,
        z: center.z + (xAxis.z * cos(curveParameter) + yAxis.z * sin(curveParameter)) * radius
    )
    let measurementID = try document.addMeasurementAnnotation(
        MeasurementAnnotation(
            name: "Measured Generated Circular Edge Parameter",
            kind: .distance,
            anchors: [
                .topologyEdgeParameter(
                    sceneNodeID: target.sceneNodeID,
                    component: target.component,
                    persistentName: edge.persistentName,
                    referenceID: edge.referenceID,
                    parameter: parameter,
                    role: .point
                ),
                .worldPoint(Point3D(x: center.x, y: center.y, z: center.z), role: .center),
            ]
        )
    )

    let result = try SnapResolver().resolve(
        point: Point2D(x: expectedWorldPoint.x + 0.00001, y: expectedWorldPoint.y + 0.00001),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 32
        )
    )

    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .measurementPoint &&
            candidate.measurementSource?.measurementID == measurementID &&
            candidate.measurementSource?.anchorIndex == 0
    })
    #expect(candidate.measurementSource?.anchorKind == .topologyEdgeParameter)
    #expect(candidate.measurementSource?.topologyEdgeParameter?.persistentName == edge.persistentName)
    #expect(candidate.measurementSource?.topologyEdgeParameter?.referenceID == edge.referenceID)
    #expect(candidate.measurementSource?.topologyEdgeParameter?.component == target.component)
    #expect(candidate.measurementSource?.topologyEdgeParameter?.parameter == parameter)
    #expect(abs(candidate.point.x - expectedWorldPoint.x) <= 1.0e-12)
    #expect(abs(candidate.point.y - expectedWorldPoint.y) <= 1.0e-12)
    #expect(abs((candidate.measurementSource?.worldPoint.x ?? 0.0) - expectedWorldPoint.x) <= 1.0e-12)
    #expect(abs((candidate.measurementSource?.worldPoint.y ?? 0.0) - expectedWorldPoint.y) <= 1.0e-12)
    #expect(abs((candidate.measurementSource?.worldPoint.z ?? 0.0) - expectedWorldPoint.z) <= 1.0e-12)
}

@Test func snapResolverReportsGeneratedPolySplineBoundaryVertexAsSurfaceCV() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createPolySplineSurface(
        name: "Snap PolySpline",
        sourceMesh: snapResolverPolySplineQuadMesh()
    )
    let topology = try TopologySummaryService().summarize(document: document)
    let surfaceVertex = try #require(topology.entries.first { entry in
        entry.kind == .vertex
            && PolySplineSurfaceVertexTarget.canParsePersistentName(entry.persistentName)
            && entry.start != nil
            && entry.selectionTarget() != nil
    })
    let point = try #require(surfaceVertex.start)
    let target = try #require(surfaceVertex.selectionTarget())

    let result = try SnapResolver().resolve(
        point: Point2D(x: point.x + 0.00001, y: point.y + 0.00001),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 32
        )
    )

    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .surfaceControlVertex
            && candidate.topologySource?.persistentName == surfaceVertex.persistentName
    })
    #expect(result.selectedCandidate?.kind == .surfaceControlVertex)
    #expect(candidate.label == "Surface CV")
    #expect(candidate.source == nil)
    #expect(candidate.topologySource?.selectionTarget == target)
    #expect(candidate.topologySource?.kind == .vertex)
    #expect(candidate.topologySource?.worldPoint == point)
    #expect(candidate.topologySource?.referenceID.isEmpty == false)
    #expect(candidate.topologySource?.persistentName.contains(featureID.description) == true)
    #expect(abs(candidate.point.x - point.x) <= 1.0e-12)
    #expect(abs(candidate.point.y - point.y) <= 1.0e-12)
}

@Test func snapResolverReportsVisibleTrimSurfaceFrameCandidate() async throws {
    var document = DesignDocument.empty()
    _ = try document.createBSplineSurface(
        name: "Snap Trim Frame Surface",
        surface: snapResolverDirectBSplineSurface()
    )
    let initialSummary = try SurfaceSourceSummaryService().summarize(document: document)
    let faceReference = try #require(initialSummary.sources.first?.patches.first?.faceSelectionReference)
    try document.setSurfaceTrimLoops(
        target: faceReference,
        trimLoops: [snapResolverAuthoredTrimLoop()]
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let trimEdge = try #require(summary.sources.first?.patches.first?.trimLoops.first?.edges.first)
    let spanSelection = try #require(trimEdge.parameterCurve.spans.first?.selectionReference)
    let query = SurfaceFrameQuery(selectionReference: spanSelection)
    try document.setSurfaceFrameDisplay(query: query, isVisible: true)
    let displayID = try SurfaceFrameDisplayID(query: query)
    let frame = try #require(
        SurfaceFrameService()
            .resolve(document: document, queries: [query])
            .frames
            .first
    )

    let result = try SnapResolver().resolve(
        point: Point2D(x: frame.position.x + 0.00001, y: frame.position.y + 0.00001),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 32
        )
    )

    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .surfaceFrame &&
            candidate.surfaceFrameSource?.displayID == displayID
    })
    let surfaceFrameSource = try #require(candidate.surfaceFrameSource)
    #expect(result.selectedCandidate?.kind == .surfaceFrame)
    #expect(candidate.label == "Surface Frame")
    #expect(surfaceFrameSource.query == query)
    #expect(surfaceFrameSource.faceID.isEmpty == false)
    #expect(surfaceFrameSource.facePersistentNames == frame.facePersistentNames)
    #expect(surfaceFrameSource.u == frame.u)
    #expect(surfaceFrameSource.v == frame.v)
    #expect(abs(surfaceFrameSource.worldPoint.x - frame.position.x) <= 1.0e-12)
    #expect(abs(surfaceFrameSource.worldPoint.y - frame.position.y) <= 1.0e-12)
    #expect(abs(surfaceFrameSource.worldPoint.z - frame.position.z) <= 1.0e-12)
    #expect(abs(candidate.point.x - frame.position.x) <= 1.0e-12)
    #expect(abs(candidate.point.y - frame.position.y) <= 1.0e-12)
    let selectedWorldPoint = try #require(result.selectedSurfaceFrameWorldPoint)
    #expect(abs(selectedWorldPoint.x - frame.position.x) <= 1.0e-12)
    #expect(abs(selectedWorldPoint.y - frame.position.y) <= 1.0e-12)
    #expect(abs(selectedWorldPoint.z - frame.position.z) <= 1.0e-12)
}

@Test func snapResolverProjectsVisibleSurfaceFrameCandidateOntoConstructionPlane() async throws {
    var document = DesignDocument.empty()
    _ = try document.createBSplineSurface(
        name: "Snap Projected Frame Surface",
        surface: snapResolverDirectBSplineSurface(topRightZ: 0.004)
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let faceReference = try #require(summary.sources.first?.patches.first?.faceSelectionReference)
    let query = SurfaceFrameQuery(
        selectionReference: faceReference,
        u: 0.5,
        v: 0.5
    )
    try document.setSurfaceFrameDisplay(query: query, isVisible: true)
    let displayID = try SurfaceFrameDisplayID(query: query)
    let frame = try #require(
        SurfaceFrameService()
            .resolve(document: document, queries: [query])
            .frames
            .first
    )

    let result = try SnapResolver().resolve(
        point: Point2D(x: frame.position.y + 0.00001, y: frame.position.z + 0.00001),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            usesConstructionPlaneProjection: true,
            constructionPlane: .yz,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 32
        )
    )

    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .surfaceFrame &&
            candidate.surfaceFrameSource?.displayID == displayID
    })
    let surfaceFrameSource = try #require(candidate.surfaceFrameSource)
    #expect(result.selectedCandidate?.kind == .surfaceFrame)
    #expect(surfaceFrameSource.query == query)
    #expect(abs(candidate.point.x - frame.position.y) <= 1.0e-12)
    #expect(abs(candidate.point.y - frame.position.z) <= 1.0e-12)
    #expect(abs(surfaceFrameSource.worldPoint.x - frame.position.x) <= 1.0e-12)
    #expect(abs(surfaceFrameSource.worldPoint.y - frame.position.y) <= 1.0e-12)
    #expect(abs(surfaceFrameSource.worldPoint.z - frame.position.z) <= 1.0e-12)
}

@Test func snapResolverReportsSurfaceTrimEndpointCandidate() async throws {
    var document = DesignDocument.empty()
    let surface = snapResolverDirectBSplineSurface()
    let featureID = try document.createBSplineSurface(
        name: "Snap Trim Endpoint Surface",
        surface: surface
    )
    let initialSummary = try SurfaceSourceSummaryService().summarize(document: document)
    let faceReference = try #require(initialSummary.sources.first?.patches.first?.faceSelectionReference)
    try document.setSurfaceTrimLoops(
        target: faceReference,
        trimLoops: [snapResolverAuthoredTrimLoop()]
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let trimEdge = try #require(summary.sources.first?.patches.first?.trimLoops.first?.edges.first)
    let selectionReference = try #require(trimEdge.selectionReference)
    let expected = try surface.differentialGeometry(atU: 0.2, v: 0.2).position

    let result = try SnapResolver().resolve(
        point: Point2D(x: expected.x + 0.00001, y: expected.y + 0.00001),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 64
        )
    )

    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .surfaceTrimEndpoint &&
            candidate.surfaceTrimSource?.selectionReference == selectionReference &&
            candidate.surfaceTrimSource?.endpoint == .start
    })
    let source = try #require(candidate.surfaceTrimSource)
    #expect(candidate.label == "Surface Trim Start")
    #expect(source.kind == .endpoint)
    #expect(source.controlPointIndex == nil)
    #expect(source.sourceFeatureID == featureID.description)
    #expect(source.sceneNodeID != nil)
    #expect(abs(source.u - 0.2) <= 1.0e-12)
    #expect(abs(source.v - 0.2) <= 1.0e-12)
    #expect(abs(source.worldPoint.x - expected.x) <= 1.0e-12)
    #expect(abs(source.worldPoint.y - expected.y) <= 1.0e-12)
    #expect(abs(source.worldPoint.z - expected.z) <= 1.0e-12)
    #expect(abs(candidate.point.x - expected.x) <= 1.0e-12)
    #expect(abs(candidate.point.y - expected.y) <= 1.0e-12)
    #expect(abs(snapResolverVectorLength(source.normal) - 1.0) <= 1.0e-12)
}

@Test func snapResolverReportsSurfaceTrimControlPointCandidate() async throws {
    var document = DesignDocument.empty()
    let surface = snapResolverDirectBSplineSurface()
    let featureID = try document.createBSplineSurface(
        name: "Snap Trim Control Point Surface",
        surface: surface
    )
    let initialSummary = try SurfaceSourceSummaryService().summarize(document: document)
    let faceReference = try #require(initialSummary.sources.first?.patches.first?.faceSelectionReference)
    try document.setSurfaceTrimLoops(
        target: faceReference,
        trimLoops: [snapResolverAuthoredTrimLoop()]
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let trimEdge = try #require(summary.sources.first?.patches.first?.trimLoops.first?.edges.first)
    let selectionReference = try #require(trimEdge.selectionReference)
    let expected = try surface.differentialGeometry(atU: 0.52, v: 0.42).position

    let result = try SnapResolver().resolve(
        point: Point2D(x: expected.x + 0.00001, y: expected.y + 0.00001),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 64
        )
    )

    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .surfaceTrimControlPoint &&
            candidate.surfaceTrimSource?.selectionReference == selectionReference &&
            candidate.surfaceTrimSource?.controlPointIndex == 1
    })
    let source = try #require(candidate.surfaceTrimSource)
    let selectedWorldPoint = try #require(result.selectedSurfaceTrimWorldPoint)
    #expect(result.selectedCandidate?.kind == .surfaceTrimControlPoint)
    #expect(candidate.label == "Surface Trim CP")
    #expect(source.kind == .controlPoint)
    #expect(source.endpoint == nil)
    #expect(source.sourceFeatureID == featureID.description)
    #expect(source.sceneNodeID != nil)
    #expect(abs(source.u - 0.52) <= 1.0e-12)
    #expect(abs(source.v - 0.42) <= 1.0e-12)
    #expect(abs(source.worldPoint.x - expected.x) <= 1.0e-12)
    #expect(abs(source.worldPoint.y - expected.y) <= 1.0e-12)
    #expect(abs(source.worldPoint.z - expected.z) <= 1.0e-12)
    #expect(abs(selectedWorldPoint.x - expected.x) <= 1.0e-12)
    #expect(abs(selectedWorldPoint.y - expected.y) <= 1.0e-12)
    #expect(abs(selectedWorldPoint.z - expected.z) <= 1.0e-12)
    #expect(abs(snapResolverVectorLength(source.uAxis) - 1.0) <= 1.0e-12)
    #expect(abs(snapResolverVectorLength(source.vAxis) - 1.0) <= 1.0e-12)
}

@Test func snapResolverProjectsSurfaceTrimCandidateOntoConstructionPlane() async throws {
    var document = DesignDocument.empty()
    let surface = snapResolverDirectBSplineSurface(topRightZ: 0.004)
    _ = try document.createBSplineSurface(
        name: "Snap Projected Trim Surface",
        surface: surface
    )
    let initialSummary = try SurfaceSourceSummaryService().summarize(document: document)
    let faceReference = try #require(initialSummary.sources.first?.patches.first?.faceSelectionReference)
    try document.setSurfaceTrimLoops(
        target: faceReference,
        trimLoops: [snapResolverAuthoredTrimLoop()]
    )
    let expected = try surface.differentialGeometry(atU: 0.52, v: 0.42).position

    let result = try SnapResolver().resolve(
        point: Point2D(x: expected.y + 0.00001, y: expected.z + 0.00001),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            usesConstructionPlaneProjection: true,
            constructionPlane: .yz,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 64
        )
    )

    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .surfaceTrimControlPoint &&
            candidate.surfaceTrimSource?.controlPointIndex == 1
    })
    let source = try #require(candidate.surfaceTrimSource)
    #expect(result.selectedCandidate?.kind == .surfaceTrimControlPoint)
    #expect(abs(candidate.point.x - expected.y) <= 1.0e-12)
    #expect(abs(candidate.point.y - expected.z) <= 1.0e-12)
    #expect(abs(source.worldPoint.x - expected.x) <= 1.0e-12)
    #expect(abs(source.worldPoint.y - expected.y) <= 1.0e-12)
    #expect(abs(source.worldPoint.z - expected.z) <= 1.0e-12)
}

@Test func snapResolverReportsSplineControlVerticesAsCVTargets() async throws {
    var document = DesignDocument.empty()
    _ = try document.createSplineSketch(
        name: "Snap CV Spline",
        plane: .xy,
        spline: SketchSpline(controlPoints: [
            SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
            SketchPoint(x: .length(2.0, .millimeter), y: .length(3.0, .millimeter)),
            SketchPoint(x: .length(6.0, .millimeter), y: .length(3.0, .millimeter)),
            SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
        ])
    )

    let result = try SnapResolver().resolve(
        point: Point2D(x: 0.00202, y: 0.00301),
        in: document,
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 8
        )
    )

    #expect(result.selectedCandidate?.kind == .controlVertex)
    #expect(result.selectedCandidate?.label == "CV")
    #expect(result.selectedCandidate?.source?.controlPointIndex == 1)
    #expect(abs(result.resolvedPoint.x - 0.002) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - 0.003) <= 1.0e-12)
}

private func snapResolverSingleLineID(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> SketchEntityID {
    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation,
          let lineEntry = sketch.entities.first(where: { _, entity in
              if case .line = entity {
                  return true
              }
              return false
          }) else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Snap resolver test requires a line sketch."
        )
    }
    return lineEntry.key
}

private func snapResolverSketchSceneNodeID(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> SceneNodeID {
    guard let entry = document.productMetadata.sceneNodes.first(where: { _, node in
        node.reference?.kind == .sketch && node.reference?.featureID == featureID
    }) else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Snap resolver test requires a sketch scene node."
        )
    }
    return entry.key
}

private func snapResolverPolySplineQuadMesh() -> Mesh {
    Mesh(
        positions: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.02, z: 0.004),
            Point3D(x: 0.0, y: 0.02, z: 0.0),
        ],
        indices: [0, 1, 2, 0, 2, 3]
    )
}

private func snapResolverVectorLength(_ vector: SurfaceAnalysisResult.Vector) -> Double {
    sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
}

private func snapResolverDirectBSplineSurface(topRightZ: Double = 0.0) -> BSplineSurface3D {
    BSplineSurface3D.cubicBezierPatch(
        bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
        bottomRight: Point3D(x: 1.0, y: 0.0, z: 0.0),
        topRight: Point3D(x: 1.0, y: 1.0, z: topRightZ),
        topLeft: Point3D(x: 0.0, y: 1.0, z: 0.0)
    )
}

private func snapResolverAuthoredTrimLoop() -> BSplineSurfaceTrimLoop {
    BSplineSurfaceTrimLoop(
        role: .outer,
        edges: [
            BSplineSurfaceTrimEdge(parameterCurve: .bSpline(BSplineCurve2D(
                degree: 2,
                knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                controlPoints: [
                    Point2D(x: 0.2, y: 0.2),
                    Point2D(x: 0.52, y: 0.42),
                    Point2D(x: 0.8, y: 0.25),
                ]
            ))),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.8, v: 0.25),
                SurfaceParameter(u: 0.45, v: 0.8),
            ])),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.45, v: 0.8),
                SurfaceParameter(u: 0.2, v: 0.2),
            ])),
        ]
    )
}
