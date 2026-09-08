import CoreGraphics
import RupaCore
import RupaGeometry
@testable import RupaRendering
import RupaViewportScene
import SwiftCAD
import Testing

#if canImport(AppKit)
import AppKit
import SwiftUI

@MainActor
@Test(.timeLimit(.minutes(1)), arguments: [ViewportCameraProjection.parallel, .standardPerspective], [false, true])
func viewportSurfaceInputUsesNativeFrame(projection: ViewportCameraProjection, measuring: Bool) async throws {
    _ = NSApplication.shared
    let document = DesignDocument.empty()
    let scene = try planCacheScene(suffix: "surface-input", projectID: document.projectID)
    let occurrence = try #require(scene.items.first?.occurrenceID)
    let control = ViewportControlSession(camera: .init(projection: projection), basis: .axisFront(.z))
    let size = CGSize(width: 800, height: 600)
    var state = ViewportMeasurementState()
    var picked: [SceneOccurrenceID] = []
    var hovered: SceneOccurrenceID?
    var legacyPicks = 0
    var legacyHoverHits = 0
    let viewport = Viewport(
        document: document,
        sourceIdentity: .presentation(scene.snapshotID),
        controlSession: control,
        presentationScene: scene,
        workspaceRenderState: .init(revision: WorkspaceRevision(), ruler: .standard(for: .millimeter)),
        objectSelectionIndex: .init(document: document, selection: .empty),
        measurementToolActive: measuring,
        measurementConstructionPlane: .xy,
        allowsObjectAffordances: false,
        selectedPresentationHasExactCADContext: false,
        onPresentationOccurrencePick: { id, _ in picked.append(id) },
        onPresentationOccurrenceHover: { hovered = $0 },
        onPick: { _ in legacyPicks += 1 },
        onHover: { if $0 != nil { legacyHoverHits += 1 } },
        onMeasurementStateChange: { state = $0 }
    ).frame(width: size.width, height: size.height)
    let controller = NSHostingController(rootView: viewport)
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    window.orderFront(nil)
    defer { window.contentViewController = nil; window.close() }
    let start = CGPoint(x: 390, y: 280)
    let end = CGPoint(x: 430, y: 300)
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while (measuring ? state.start == nil : picked.isEmpty), ContinuousClock.now < deadline {
        measurementInput(in: controller.view)?.onPick?(start, size, .replace)
        try await Task.sleep(for: .milliseconds(20))
    }
    let input = try #require(measurementInput(in: controller.view))
    if measuring {
        let accepted = try #require(state.start)
        #expect(accepted.source == .presentation(occurrenceID: occurrence))
        #expect(abs(accepted.point.z) < 1e-6)
        let endDeadline = ContinuousClock.now.advanced(by: .seconds(10))
        while state.end == nil, ContinuousClock.now < endDeadline {
            input.onPick?(end, size, .replace)
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(try #require(state.end).source == .presentation(occurrenceID: occurrence))
        #expect(try #require(state.distanceMeters) > 0)
    } else {
        #expect(picked == [occurrence])
        let hoverDeadline = ContinuousClock.now.advanced(by: .seconds(10))
        while hovered == nil, ContinuousClock.now < hoverDeadline {
            input.onHover?(start, size)
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(hovered == occurrence)
        _ = try control.perform(.pan(deltaXPoints: 17, deltaYPoints: 9))
        input.onPick?(start, size, .replace)
        input.onHover?(start, size)
        #expect(picked == [occurrence])
        #expect(hovered == nil)
    }
    #expect(legacyPicks == 0)
    #expect(legacyHoverHits == 0)
}

@MainActor
@Test(.timeLimit(.minutes(1)), arguments: [ViewportCameraProjection.parallel, .standardPerspective])
func viewportMeshInputRejectsUnappliedNativeFrame(projection: ViewportCameraProjection) async throws {
    _ = NSApplication.shared
    let document = DesignDocument.empty()
    let scene = try planCacheScene(suffix: "mesh-input", projectID: document.projectID)
    let occurrence = try #require(scene.items.first?.occurrenceID)
    let control = ViewportControlSession(camera: .init(projection: projection), basis: .axisFront(.z))
    let size = CGSize(width: 800, height: 600)
    var hits: [ViewportMeshElementHit] = []
    var meshCallbackCount = 0
    var legacyPicks = 0
    let viewport = Viewport(
        document: document, sourceIdentity: .presentation(scene.snapshotID),
        controlSession: control, presentationScene: scene,
        workspaceRenderState: .init(revision: WorkspaceRevision(), ruler: .standard(for: .millimeter)),
        objectSelectionIndex: .init(document: document, selection: .empty),
        allowsObjectAffordances: false,
        meshSelectionDomain: .face,
        onMeshElementPick: { hit, _ in
            meshCallbackCount += 1
            if let hit { hits.append(hit) }
        },
        selectedPresentationHasExactCADContext: false,
        onPick: { _ in legacyPicks += 1 }
    ).frame(width: size.width, height: size.height)
    let controller = NSHostingController(rootView: viewport)
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    window.orderFront(nil)
    defer { window.contentViewController = nil; window.close() }
    let point = CGPoint(x: 390, y: 280)
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while hits.isEmpty, ContinuousClock.now < deadline {
        measurementInput(in: controller.view)?.onPick?(point, size, .replace)
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(try #require(hits.first).occurrenceID == occurrence)
    guard case .face = try #require(hits.first).element else {
        Issue.record("The production Mesh callback did not select a source face."); return
    }
    let input = try #require(measurementInput(in: controller.view))
    let acceptedCount = hits.count
    let acceptedCallbackCount = meshCallbackCount
    _ = try control.perform(.pan(deltaXPoints: 17, deltaYPoints: 9))
    input.onPick?(point, size, .replace)
    #expect(hits.count == acceptedCount)
    #expect(meshCallbackCount == acceptedCallbackCount)
    #expect(legacyPicks == 0)
}

@MainActor
@Test(.timeLimit(.minutes(1)), arguments: [ViewportCameraProjection.parallel, .standardPerspective])
func viewportCanvasPlaneInputRejectsUnappliedNativeFrame(projection: ViewportCameraProjection) async throws {
    _ = NSApplication.shared
    let document = DesignDocument.empty()
    let control = ViewportControlSession(camera: .init(projection: projection), basis: .axisFront(.z))
    let size = CGSize(width: 800, height: 600)
    var picks: [ViewportCanvasTarget] = []
    let viewport = Viewport(
        document: document,
        sourceIdentity: .document(id: document.id, generation: DocumentGeneration(1)),
        controlSession: control,
        workspaceRenderState: .init(revision: WorkspaceRevision(), ruler: .standard(for: .millimeter)),
        objectSelectionIndex: .init(document: document, selection: .empty),
        allowsObjectAffordances: false,
        selectedPresentationHasExactCADContext: false,
        onPick: { picks.append($0) }
    ).frame(width: size.width, height: size.height)
    let controller = NSHostingController(rootView: viewport)
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    window.orderFront(nil)
    defer { window.contentViewController = nil; window.close() }
    let point = CGPoint(x: 450, y: 310)
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while picks.isEmpty, ContinuousClock.now < deadline {
        measurementInput(in: controller.view)?.onPick?(point, size, .replace)
        try await Task.sleep(for: .milliseconds(20))
    }
    let accepted = try #require(picks.first)
    #expect(accepted.sketchPlane == .xy)
    let input = try #require(measurementInput(in: controller.view))
    let count = picks.count
    _ = try control.perform(.pan(deltaXPoints: 17, deltaYPoints: 9))
    input.onPick?(point, size, .replace)
    #expect(picks.count == count)
    let resumedDeadline = ContinuousClock.now.advanced(by: .seconds(10))
    while picks.count == count, ContinuousClock.now < resumedDeadline {
        try await Task.sleep(for: .milliseconds(20))
        measurementInput(in: controller.view)?.onPick?(point, size, .replace)
    }
    #expect(picks.count == count + 1)
    #expect(try #require(picks.last).modelPoint != accepted.modelPoint)
}

@MainActor
private func measurementInput(in view: NSView) -> ViewportInputSurface.InputView? {
    if let input = view as? ViewportInputSurface.InputView { return input }
    for child in view.subviews {
        if let result = measurementInput(in: child) { return result }
    }
    return nil
}

@MainActor
@Test(.timeLimit(.minutes(1)), arguments: [ViewportCameraProjection.parallel, .standardPerspective])
func viewportMeasurementInputRequiresMatchingNativeFrame(projection: ViewportCameraProjection) async throws {
    _ = NSApplication.shared
    let document = DesignDocument.empty()
    let control = ViewportControlSession(camera: .init(projection: projection), basis: .isometric)
    let size = CGSize(width: 800, height: 600)
    var state = ViewportMeasurementState()
    var canvasPoint: Point2D?
    func viewport(measuring: Bool) -> some View { Viewport(
        document: document,
        sourceIdentity: .document(id: document.id, generation: DocumentGeneration(1)),
        controlSession: control,
        workspaceRenderState: .init(revision: WorkspaceRevision(), ruler: .standard(for: .millimeter)),
        objectSelectionIndex: .init(document: document, selection: .empty),
        measurementToolActive: measuring,
        measurementConstructionPlane: .xy,
        selectedPresentationHasExactCADContext: false,
        onPick: { canvasPoint = $0.modelPoint },
        onMeasurementStateChange: { state = $0 }
    ).frame(width: size.width, height: size.height) }
    let controller = NSHostingController(rootView: viewport(measuring: false))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    window.orderFront(nil)
    defer { window.contentViewController = nil; window.close() }
    let start = CGPoint(x: 390, y: 280)
    let end = CGPoint(x: 450, y: 300)
    let canvasDeadline = ContinuousClock.now.advanced(by: .seconds(10))
    while canvasPoint == nil, ContinuousClock.now < canvasDeadline {
        measurementInput(in: controller.view)?.onPick?(start, size, .replace)
        try await Task.sleep(for: .milliseconds(20))
    }
    let nativeStart = try #require(canvasPoint)
    controller.rootView = viewport(measuring: true)
    let readyDeadline = ContinuousClock.now.advanced(by: .seconds(10))
    while state.start == nil, ContinuousClock.now < readyDeadline {
        measurementInput(in: controller.view)?.onPick?(start, size, .replace)
        try await Task.sleep(for: .milliseconds(20))
    }
    let inputView = try #require(measurementInput(in: controller.view))
    let acceptedStart = try #require(state.start)
    #expect(acceptedStart.source == .constructionPlane(.xy))
    #expect(acceptedStart.point.isApproximatelyEqual(
        to: Point3D(x: nativeStart.x, y: nativeStart.y, z: 0), tolerance: 1e-6
    ))

    // Mutate the camera and invoke the production input callback before the
    // native host can apply the new revision on its next update.
    _ = try control.perform(.pan(deltaXPoints: 17, deltaYPoints: 9))
    inputView.onPick?(end, size, .replace)
    #expect(state.phase == .anchored)
    #expect(state.start == acceptedStart)
    #expect(state.end == nil)
    #expect(state.status?.contains("displayed surface is unavailable") == true)

    let resumedDeadline = ContinuousClock.now.advanced(by: .seconds(10))
    while state.end == nil, ContinuousClock.now < resumedDeadline {
        try await Task.sleep(for: .milliseconds(20))
        measurementInput(in: controller.view)?.onPick?(end, size, .replace)
    }
    let acceptedEnd = try #require(state.end)
    #expect(state.phase == .completed)
    #expect(acceptedEnd.source == .constructionPlane(.xy))
    #expect(try #require(state.distanceMeters) > 0)
    canvasPoint = nil
    controller.rootView = viewport(measuring: false)
    let endCanvasDeadline = ContinuousClock.now.advanced(by: .seconds(10))
    while canvasPoint == nil, ContinuousClock.now < endCanvasDeadline {
        measurementInput(in: controller.view)?.onPick?(end, size, .replace)
        try await Task.sleep(for: .milliseconds(20))
    }
    let nativeEnd = try #require(canvasPoint)
    #expect(acceptedEnd.point.isApproximatelyEqual(
        to: Point3D(x: nativeEnd.x, y: nativeEnd.y, z: 0), tolerance: 1e-6
    ))
}
#endif

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
func viewportMeasurementResolverPreservesPlanePointAndSnapFailureWarning() throws {
    let world = Point3D(x: 0.5, y: -0.25, z: 0)
    let resolved = ViewportMeasurementResolver().resolve(
        effectivePlane: .xy,
        snap: nil,
        presentationHit: nil,
        planeIntersection: { _ in world },
        validateWorldPoint: { _ in }
    )
    #expect(try #require(resolved.endpoint).point.isApproximatelyEqual(to: world, tolerance: 1.0e-9))
    let failure = ViewportMeasurementResolver().resolve(
        effectivePlane: .xy,
        snap: ViewportSnapResolution(
            attemptedResolution: true,
            result: nil,
            failureDescription: "Invalid plane"
        ),
        presentationHit: nil,
        planeIntersection: { _ in world },
        validateWorldPoint: { _ in }
    )
    #expect(failure.endpoint != nil)
    #expect(failure.failure == nil)
    #expect(failure.warning == "Snap failed: Invalid plane")
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
    let occurrenceID = SceneOccurrenceID(rawValue: "measurement.presentation")
    let presentation = ViewportMeasurementPresentationHit(
        point: Point3D(x: 0.5, y: 0.4, z: -0.2),
        occurrenceID: occurrenceID
    )
    let resolution = ViewportMeasurementResolver().resolve(
        effectivePlane: nil,
        snap: nil,
        presentationHit: presentation,
        planeIntersection: { _ in presentation.point },
        validateWorldPoint: { _ in }
    )

    #expect(resolution.endpoint?.point == presentation.point)
    #expect(resolution.endpoint?.source == .presentation(occurrenceID: occurrenceID))
}

@Test
func viewportMeasurementResolverRefusesMissingPlaneInsteadOfUsingWorldOrigin() throws {
    let resolution = ViewportMeasurementResolver().resolve(
        effectivePlane: nil,
        snap: nil,
        presentationHit: nil,
        planeIntersection: { _ in Point3D.origin },
        validateWorldPoint: { _ in }
    )

    #expect(resolution.endpoint == nil)
    #expect(resolution.failure == .noConstructionPlane)
}

@Test
func viewportMeasurementResolverRetainsSnapProvenanceAndReconstructsPlanePoint() throws {
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
        effectivePlane: .xy,
        snap: snap,
        presentationHit: nil,
        planeIntersection: { _ in Point3D.origin },
        validateWorldPoint: { _ in }
    )

    #expect(resolution.endpoint?.point == Point3D(x: 1.25, y: -0.5, z: 0.0))
    #expect(resolution.endpoint?.source == .snap(candidate))
}

@Test
func viewportMeasurementResolverRefusesNativeSnapDepthFailureWithoutFallback() {
    let candidate = SnapCandidate(
        kind: .grid,
        point: Point2D(x: 1.0, y: 2.0),
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
    let fallbackPresentation = ViewportMeasurementPresentationHit(
        point: Point3D(x: 8.0, y: 9.0, z: 10.0),
        occurrenceID: SceneOccurrenceID(rawValue: "measurement.depth-fallback")
    )
    let resolution = ViewportMeasurementResolver().resolve(
        effectivePlane: .xy,
        snap: snap,
        presentationHit: fallbackPresentation,
        planeIntersection: { _ in Point3D(x: -1.0, y: -1.0, z: 0.0) },
        validateWorldPoint: { _ in
            throw ViewportMeasurementResolutionFailure.pointBehindPerspectiveCamera
        }
    )

    #expect(resolution.endpoint == nil)
    #expect(resolution.failure == .pointBehindPerspectiveCamera)
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
