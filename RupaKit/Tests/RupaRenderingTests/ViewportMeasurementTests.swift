import CoreGraphics
import RupaCore
import RupaGeometry
@testable import RupaRendering
import RupaViewportScene
import SwiftCAD
import Testing

@Test
func viewportMeasurementRefusalAndResetClearPreview() {
    var session = ViewportMeasurementSession()
    session.click(measurementEndpoint(.origin))
    session.hover(measurementEndpoint(Point3D(x: 1, y: 2, z: 3)))
    #expect(session.state.distanceMeters != nil)
    session.refuse(.noConstructionPlane)
    #expect(session.state.preview == nil)
    #expect(session.state.distanceMeters == nil)
    #expect(session.state.phase == .anchored)
    session.reset()
    #expect(session.state == ViewportMeasurementState())
}

@Test
func viewportMeasurementPlaneRayRoundTripsBothLenses() throws {
    for projection in [ViewportCameraProjection.parallel, .standardPerspective] {
        let layout = ViewportLayout(
            modelBounds: CGRect(x: -2, y: -2, width: 4, height: 4),
            size: CGSize(width: 800, height: 600), camera: ViewportCamera(projection: projection),
            basis: .isometric, verticalBounds: -2...2
        )
        let world = Point3D(x: 0.5, y: -0.25, z: 0)
        let screen = try #require(layout.projectedPoint(world)).point
        let resolved = ViewportMeasurementResolver().resolve(at: screen, layout: layout, effectivePlane: .xy,
                                                            snap: nil, presentationHit: nil)
        #expect(try #require(resolved.endpoint).point.isApproximatelyEqual(to: world, tolerance: 1.0e-9))
        let failure = ViewportMeasurementResolver().resolve(at: screen, layout: layout, effectivePlane: .xy,
            snap: ViewportSnapResolution(attemptedResolution: true, result: nil, failureDescription: "Invalid plane"),
            presentationHit: nil)
        #expect(failure.endpoint != nil)
        #expect(failure.failure == nil)
        #expect(failure.warning == "Snap failed: Invalid plane")
    }
}

private func measurementEndpoint(
    _ point: Point3D,
    source: ViewportMeasurementEndpointSource = .constructionPlane(.xy)
) -> ViewportMeasurementEndpoint {
    ViewportMeasurementEndpoint(point: point, source: source)
}

@Test
func viewportMeasurementSessionRecomputesClickAndUsesWorldDistance() {
    let start = measurementEndpoint(Point3D(x: 0.0, y: 0.0, z: 0.0))
    let hover = measurementEndpoint(Point3D(x: 1.0, y: 0.0, z: 0.0))
    let click = measurementEndpoint(Point3D(x: 0.0, y: 2.0, z: 2.0))
    var session = ViewportMeasurementSession()

    session.click(start)
    session.hover(hover)
    session.click(click)

    #expect(session.state.phase == .completed)
    #expect(session.state.end == click)
    #expect(session.state.distanceMeters == 2.8284271247461903)
    #expect(session.state.preview == nil)
}

@Test
func viewportMeasurementResolverUsesPresentationBeforeConstructionPlane() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -2.0, y: -2.0, width: 4.0, height: 4.0),
        size: CGSize(width: 800.0, height: 600.0),
        basis: .isometric,
        verticalBounds: -2.0...2.0
    )
    let point = try #require(layout.projectedPoint(Point3D(x: 0.5, y: 0.4, z: -0.2))).point
    let occurrenceID = SceneOccurrenceID(rawValue: "measurement.presentation")
    let presentation = ViewportMeasurementPresentationHit(
        point: Point3D(x: 0.5, y: 0.4, z: -0.2),
        occurrenceID: occurrenceID
    )
    let resolution = ViewportMeasurementResolver().resolve(
        at: point,
        layout: layout,
        effectivePlane: nil,
        snap: nil,
        presentationHit: presentation
    )

    #expect(resolution.endpoint?.point == presentation.point)
    #expect(resolution.endpoint?.source == .presentation(occurrenceID: occurrenceID))
}

@Test
func viewportMeasurementResolverRefusesMissingPlaneInsteadOfUsingWorldOrigin() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -2.0, y: -2.0, width: 4.0, height: 4.0),
        size: CGSize(width: 800.0, height: 600.0),
        basis: .isometric,
        verticalBounds: -2.0...2.0
    )
    let resolution = ViewportMeasurementResolver().resolve(
        at: CGPoint(x: layout.fittingCenter.x + 20.0, y: layout.fittingCenter.y + 15.0),
        layout: layout,
        effectivePlane: nil,
        snap: nil,
        presentationHit: nil
    )

    #expect(resolution.endpoint == nil)
    #expect(resolution.failure == .noConstructionPlane)
}

@Test
func viewportMeasurementResolverRetainsSnapProvenanceAndReconstructsPlanePoint() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -2.0, y: -2.0, width: 4.0, height: 4.0),
        size: CGSize(width: 800.0, height: 600.0),
        basis: .isometric,
        verticalBounds: -2.0...2.0
    )
    let candidate = SnapCandidate(
        kind: .grid,
        point: Point2D(x: 1.25, y: -0.5),
        distanceMeters: 0.0,
        label: "Grid"
    )
    let snapResult = SnapResolutionResult(
        originalPoint: candidate.point,
        resolvedPoint: candidate.point,
        selectedCandidate: candidate,
        candidates: [candidate]
    )
    let snap = ViewportSnapResolution(
        attemptedResolution: true,
        result: snapResult,
        failureDescription: nil
    )
    let resolution = ViewportMeasurementResolver().resolve(
        at: layout.fittingCenter,
        layout: layout,
        effectivePlane: .xy,
        snap: snap,
        presentationHit: nil
    )

    #expect(resolution.endpoint?.point == Point3D(x: 1.25, y: -0.5, z: 0.0))
    #expect(resolution.endpoint?.source == .snap(candidate))
}

@Test
func viewportMeasurementBoundsRulersAreWorldLabeledAndBounded() throws {
    let bounds = try GeometryBounds3D(
        minimum: GeometryPoint3D(x: -1.0, y: -0.5, z: -0.75),
        maximum: GeometryPoint3D(x: 2.0, y: 1.5, z: 1.25)
    )
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -2.0, y: -2.0, width: 4.0, height: 4.0),
        size: CGSize(width: 1600.0, height: 1200.0),
        basis: .isometric,
        verticalBounds: -2.0...2.0
    )
    let rulers = ViewportMeasurementBoundsRulerLayout().rulers(
        for: bounds,
        layout: layout,
        displayUnit: .meter,
        safeRect: CGRect(origin: .zero, size: layout.viewportSize),
        excludedRects: []
    )

    #expect(!rulers.isEmpty)
    #expect(rulers.count <= 3)
    #expect(rulers.allSatisfy { $0.label.hasPrefix("World bounds") })
    #expect(Set(rulers.map(\.axis)).count == rulers.count)
    #expect(rulers.allSatisfy { $0.labelRect.hasFiniteComponents })
    let blocked = ViewportMeasurementBoundsRulerLayout().rulers(
        for: bounds, layout: layout, displayUnit: .meter,
        safeRect: CGRect(origin: .zero, size: layout.viewportSize),
        excludedRects: [CGRect(origin: .zero, size: layout.viewportSize)]
    )
    #expect(blocked.isEmpty)
    let leaderBlockers = rulers.map { ruler in
        CGRect(x: (ruler.extensionStart.x + ruler.dimensionStart.x) / 2 - 2,
               y: (ruler.extensionStart.y + ruler.dimensionStart.y) / 2 - 2, width: 4, height: 4)
    }
    let avoiding = ViewportMeasurementBoundsRulerLayout().rulers(
        for: bounds, layout: layout, displayUnit: .meter,
        safeRect: CGRect(origin: .zero, size: layout.viewportSize), excludedRects: leaderBlockers
    )
    for ruler in avoiding {
        for blocker in leaderBlockers {
            #expect(!MeshSourcePresentationScreenHitTester().segmentIntersectsRect(
                ruler.extensionStart, ruler.dimensionStart, rect: blocker))
            #expect(!MeshSourcePresentationScreenHitTester().segmentIntersectsRect(
                ruler.extensionEnd, ruler.dimensionEnd, rect: blocker))
        }
    }
    for ruler in rulers {
        #expect(ruler.label.contains("\(ruler.axis.title):"))
        #expect(ruler.valueMeters == (ruler.axis == .x ? 3.0 : 2.0))
    }
}

@Test
func viewportMeasurementNativePlacementUsesRetainedLabelsAndDisablesUnavailableAxes() throws {
    let bounds = try GeometryBounds3D(
        minimum: GeometryPoint3D(x: -1.0, y: 0.0, z: -0.5),
        maximum: GeometryPoint3D(x: 1.0, y: 0.0, z: 0.5)
    )
    let layout = ViewportMeasurementBoundsRulerLayout()
    let labels = layout.preformattedLabels(for: bounds, displayUnit: .meter)
    var projectionCalls = 0
    let placement = layout.placement(
        for: bounds,
        labels: labels,
        project: { point in
            projectionCalls += 1
            return CGPoint(x: point.x * 160.0 + 800.0, y: point.z * 160.0 + 600.0)
        },
        safeRect: CGRect(x: 0.0, y: 0.0, width: 1600.0, height: 1200.0),
        excludedRects: []
    )

    #expect(placement.disabledAxes.contains(.y))
    #expect(placement.rulers.allSatisfy { $0.label.hasPrefix("World bounds") })
    #expect(placement.rulers.allSatisfy { $0.dimensionOffset.x.isFinite && $0.dimensionOffset.y.isFinite })
    #expect(projectionCalls <= 32)

    let shifted = layout.placement(
        for: bounds,
        labels: labels,
        project: { point in
            CGPoint(x: point.x * 160.0 + 920.0, y: point.z * 160.0 + 600.0)
        },
        safeRect: CGRect(x: 0.0, y: 0.0, width: 1600.0, height: 1200.0),
        excludedRects: []
    )
    #expect(shifted.rulers.count == placement.rulers.count)
    #expect(shifted.disabledAxes == placement.disabledAxes)
}
