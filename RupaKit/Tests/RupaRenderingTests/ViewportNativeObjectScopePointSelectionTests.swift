import AppKit
import CoreGraphics
import RupaCore
import RupaKit
import RupaViewportScene
import SwiftCAD
import SwiftUI
import Testing

@testable import RupaRendering

// MARK: - Mounted point harness

private struct ObjectScopePickObservation {
    var point: CGPoint
    var target: ViewportCanvasTarget
}

/// Drives `onPick` on a mounted viewport and reports what each pointer resolved
/// to.
///
/// The frame is proven ready by `readyPoint` before any other pointer is asked.
/// `pick(at:size:selectionIntent:)` returns without calling `onPick` while the
/// mounted frame cannot answer, and it calls `onPick` with a `nil` hit once the
/// frame answers and nothing was drawn there, so a pointer that must select
/// something is the only safe readiness signal: retrying until the callback
/// merely fires would read a not-yet-mounted frame as an empty pixel.
///
/// `onPresentationOccurrencePick` and `onMeshElementPick` are deliberately not
/// supplied. Both short-circuit `pick` before the native CAD sub-shape query
/// runs, so passing either would test the tool-specific occurrence channel
/// instead of the scope-resolved hit this file owns.
@MainActor
private func objectScopePicks(
    fixture: RectangleSelectionFixture,
    control: ViewportControlSession,
    selectionHitPolicy: ViewportSelectionHitPolicy,
    readyPoint: CGPoint,
    points: [CGPoint]
) async throws -> [ObjectScopePickObservation] {
    let size = rectangleSelectionViewportSize
    var targets: [ViewportCanvasTarget] = []
    let selection = SelectionModel()
    let viewport = Viewport(
        document: fixture.document,
        sourceIdentity: .document(id: fixture.document.id, generation: fixture.generation),
        controlSession: control,
        presentationScene: fixture.presentationScene,
        presentationSceneNodeIDByOccurrenceID: fixture.sceneNodeIDByOccurrenceID,
        workspaceRenderState: .init(revision: WorkspaceRevision(), ruler: fixture.ruler),
        currentEvaluation: fixture.currentEvaluation,
        selection: selection,
        objectSelectionIndex: .init(document: fixture.document, selection: selection),
        selectionHitPolicy: selectionHitPolicy,
        allowsObjectAffordances: false,
        presentationCADInteractionSceneNodeIDs: fixture.interactionSceneNodeIDs,
        selectedPresentationHasExactCADContext: true,
        onPick: { targets.append($0) }
    ).frame(width: size.width, height: size.height)
    let controller = NSHostingController(rootView: viewport)
    let window = NSWindow(
        contentRect: CGRect(origin: .zero, size: size),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    window.orderFront(nil)
    defer {
        window.contentViewController = nil
        window.close()
    }
    func input(in view: NSView) -> ViewportInputSurface.InputView? {
        if let value = view as? ViewportInputSurface.InputView { return value }
        for child in view.subviews {
            if let value = input(in: child) { return value }
        }
        return nil
    }

    let deadline = ContinuousClock.now.advanced(by: .seconds(20))
    var attempts = 0
    while targets.last?.hit == nil, ContinuousClock.now < deadline {
        attempts += 1
        targets.removeAll()
        input(in: controller.view)?.onPick?(readyPoint, size, .replace)
        if targets.last?.hit == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    _ = try #require(
        targets.last?.hit,
        "The mounted \(selectionHitPolicy) frame never resolved the readiness pointer \(readyPoint)."
    )
    print("[cost] scope=\(selectionHitPolicy) ready=\(readyPoint) attempts=\(attempts)")

    var observations: [ObjectScopePickObservation] = []
    for point in points {
        targets.removeAll()
        input(in: controller.view)?.onPick?(point, size, .replace)
        let target = try #require(
            targets.first,
            "The mounted \(selectionHitPolicy) frame refused to answer the pointer \(point)."
        )
        #expect(targets.count == 1)
        observations.append(ObjectScopePickObservation(point: point, target: target))
    }
    return observations
}

@MainActor
private func objectScopeControlSession() -> ViewportControlSession {
    ViewportControlSession(camera: .init(projection: .parallel), basis: .axisFront(.z))
}

/// The pointer over the CAD body's unoccluded `-x` half, on its camera-facing
/// face.
///
/// The occluder the fixture draws covers the `+x` half only, which the vertex
/// rectangle rule already measures, so this half is where the CAD body is the
/// front-most thing the frame drew.
private func objectScopeCADPoint(
    geometry: RectangleSelectionScreenGeometry
) throws -> CGPoint {
    try #require(
        geometry.layout.projectedPoint(
            Point3D(
                x: geometry.worldBounds.minX * 0.5,
                y: (geometry.worldBounds.minY + geometry.worldBounds.maxY) * 0.5,
                z: geometry.worldBounds.maxZ
            )
        )?.point,
        "The fixture layout projects no point for the CAD body's unoccluded half."
    )
}

/// The pointer over the authored-mesh occluder, taken from the CAD body's `+x`
/// half so the frame draws the mesh in front of prepared CAD topology.
private func objectScopeMeshPoint(
    geometry: RectangleSelectionScreenGeometry
) throws -> CGPoint {
    try #require(
        geometry.layout.projectedPoint(
            Point3D(
                x: geometry.worldBounds.maxX * 0.5,
                y: (geometry.worldBounds.minY + geometry.worldBounds.maxY) * 0.5,
                z: geometry.worldBounds.maxZ
            )
        )?.point,
        "The fixture layout projects no point for the occluded half of the CAD body."
    )
}

// MARK: - Fixture invariants

@MainActor
@Test(.timeLimit(.minutes(3)))
func viewportNativeObjectScopeFixtureCarriesBothOccurrencesAsSceneItems() async throws {
    _ = NSApplication.shared
    let fixture = try rectangleSelectionFixture()

    // The occurrence answer is named through a scene item, so the authored-mesh
    // body has to exist in the supplied scene for the mesh pointer to resolve at
    // all. Asserting it here separates a resolver defect from a fixture whose
    // premise moved.
    let meshItem = try #require(
        fixture.cpuScene.items.first { $0.sceneNodeID == fixture.meshSceneNodeID },
        "The supplied scene carries no item for the authored-mesh scene node."
    )
    guard case .body = meshItem.kind else {
        Issue.record("The authored-mesh scene node is carried as \(meshItem.kind).")
        return
    }
    #expect(fixture.interactionSceneNodeIDs.contains(fixture.meshSceneNodeID) == false)
    #expect(fixture.sceneNodeIDByOccurrenceID[fixture.meshOccurrenceID] == fixture.meshSceneNodeID)
    #expect(fixture.sceneNodeIDByOccurrenceID[fixture.cadOccurrenceID] == fixture.cadSceneNodeID)
}

// MARK: - Object scope

@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeObjectScopeSelectsTheOccurrenceTheFrameDrew() async throws {
    _ = NSApplication.shared
    let fixture = try rectangleSelectionFixture()
    let control = objectScopeControlSession()
    let geometry = try rectangleSelectionScreenGeometry(fixture: fixture, control: control)
    let cadPoint = try objectScopeCADPoint(geometry: geometry)
    let meshPoint = try objectScopeMeshPoint(geometry: geometry)

    let observations = try await objectScopePicks(
        fixture: fixture,
        control: control,
        selectionHitPolicy: .object,
        readyPoint: cadPoint,
        points: [cadPoint, meshPoint]
    )

    let cadHit = try #require(observations[0].target.hit)
    #expect(cadHit.sceneNodeID == fixture.cadSceneNodeID)
    #expect(cadHit.selectionComponent == .object)

    // The authored-mesh occurrence carries no prepared CAD topology, and the
    // legacy point filter answered only the exact CAD interaction node, so this
    // pointer selected nothing before the frame owned the answer. The rectangle
    // path already harvested it; the two paths now name the same occurrence set.
    let meshHit = try #require(
        observations[1].target.hit,
        "The pointer over the authored-mesh occluder selected nothing."
    )
    #expect(meshHit.sceneNodeID == fixture.meshSceneNodeID)
    #expect(meshHit.selectionComponent == .object)
    #expect(meshHit.sceneNodeID != cadHit.sceneNodeID)
}

@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeObjectScopeSelectsNothingWhereTheFrameDrewNothing() async throws {
    _ = NSApplication.shared
    let fixture = try rectangleSelectionFixture()
    let control = objectScopeControlSession()
    let geometry = try rectangleSelectionScreenGeometry(fixture: fixture, control: control)
    let cadPoint = try objectScopeCADPoint(geometry: geometry)
    let emptyPoint = CGPoint(x: 4.0, y: 4.0)
    #expect(geometry.silhouette.contains(emptyPoint) == false)

    let observations = try await objectScopePicks(
        fixture: fixture,
        control: control,
        selectionHitPolicy: .object,
        readyPoint: cadPoint,
        points: [emptyPoint]
    )

    // The readiness pointer resolved on this same mounted frame, so the frame
    // answered here too and drew nothing. The object scope reaches no second
    // hit rule past that answer, so this is the frame's own miss and not a
    // routed one: nothing the pointer could still have selected is withheld.
    #expect(observations[0].target.hit == nil)
}

// MARK: - Rank

@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeCombinedScopePrefersTheCADFaceOverItsOccurrence() async throws {
    _ = NSApplication.shared
    let fixture = try rectangleSelectionFixture()
    let control = objectScopeControlSession()
    let geometry = try rectangleSelectionScreenGeometry(fixture: fixture, control: control)
    let cadPoint = try objectScopeCADPoint(geometry: geometry)
    let frontFaceID = try #require(
        rectangleSelectionFrontFaceComponentID(fixture: fixture, geometry: geometry),
        "The fixture names no camera-facing prepared CAD face."
    )

    let observations = try await objectScopePicks(
        fixture: fixture,
        control: control,
        selectionHitPolicy: .all,
        readyPoint: cadPoint,
        points: [cadPoint]
    )

    // The combined scope admits the occurrence as well, so the drawn occurrence
    // is a live candidate at this pointer. The face outranks it, which is what
    // keeps a pointer that named a sub-shape from resolving to the whole body.
    let hit = try #require(observations[0].target.hit)
    #expect(hit.sceneNodeID == fixture.cadSceneNodeID)
    #expect(hit.selectionComponent == .face(frontFaceID))
}
