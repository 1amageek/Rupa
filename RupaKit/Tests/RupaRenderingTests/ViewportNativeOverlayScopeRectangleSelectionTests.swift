import AppKit
import CoreGraphics
import RupaCore
import RupaEvaluation
import RupaKit
import RupaViewportScene
import SwiftCAD
import SwiftUI
import Testing

@testable import RupaRendering

// MARK: - Mounted harness

private struct OverlayScopeRectangleObservation {
    var rect: CGRect
    var target: ViewportSelectionDragTarget
    var attempts: Int
    var duration: Duration
}

@MainActor
private func overlayScopeRectangleControl() -> ViewportControlSession {
    ViewportControlSession(
        camera: .init(projection: .parallel),
        basis: .axisFront(.y)
    )
}

/// A rectangle centred on one pixel, wide enough to clip a span out of a
/// polyline drawn through it and narrow enough to stay inside the band that
/// pixel was chosen for.
private func overlayScopeRectangle(around point: CGPoint) -> CGRect {
    CGRect(x: point.x - 8.0, y: point.y - 8.0, width: 16.0, height: 16.0)
}

/// The region component identities a rectangle answer names.
private func overlayScopeRegionComponentIDs(
    _ hits: [ViewportHit]
) -> Set<SelectionComponentID> {
    Set(
        hits.compactMap { hit -> SelectionComponentID? in
            guard let component = hit.selectionComponent,
                  case .region(let componentID) = component else {
                return nil
            }
            return componentID
        }
    )
}

/// Drives the production rectangle path over a scene mounted from
/// `SketchScopeMountInputs`: the mounted `ViewportInputSurface` canvas drag
/// reaches `handleSelectionDrag`, which asks `selectionDragTarget` for the
/// answer the frame just drew.
///
/// The overlay families this file covers are drawn for sketch items and named
/// by whole occurrences, which the CAD body fixtures carry none of, so the
/// scene comes from the two sketch fixtures rather than from
/// `RectangleSelectionFixture`.
///
/// No separate readiness rectangle is needed here, unlike the point harnesses
/// in the same suite. `handleSelectionDrag` publishes nothing at all while the
/// frame cannot answer, and publishes a target once it can, so a published
/// target is itself the proof that the frame answered — including the target
/// carrying no hit, which a rectangle enclosing nothing has to produce.
@MainActor
private func overlayScopeRectangleDrags(
    mount: SketchScopeMountInputs,
    control: ViewportControlSession,
    selectionHitPolicy: ViewportSelectionHitPolicy,
    rects: [CGRect]
) async throws -> [OverlayScopeRectangleObservation] {
    let size = sketchScopeViewportSize
    var targets: [ViewportSelectionDragTarget] = []
    let selection = SelectionModel()
    let viewport = Viewport(
        document: mount.document,
        sourceIdentity: .document(
            id: mount.document.id, generation: mount.generation
        ),
        controlSession: control,
        presentationScene: mount.presentationScene,
        presentationSceneNodeIDByOccurrenceID: mount.sceneNodeIDByOccurrenceID,
        workspaceRenderState: .init(
            revision: WorkspaceRevision(), ruler: mount.ruler
        ),
        currentEvaluation: mount.currentEvaluation,
        selection: selection,
        objectSelectionIndex: .init(
            document: mount.document, selection: selection
        ),
        sectionAnalysis: nil,
        sectionClippingPlan: nil,
        selectionHitPolicy: selectionHitPolicy,
        allowsSelectionRectangle: true,
        allowsObjectAffordances: false,
        presentationCADInteractionSceneNodeIDs: mount.interactionSceneNodeIDs,
        selectedPresentationHasExactCADContext: true,
        onSelectionDrag: { targets.append($0) }
    ).frame(width: size.width, height: size.height)
    let controller = NSHostingController(rootView: viewport)
    let window = NSWindow(
        contentRect: CGRect(origin: .zero, size: size),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    controller.view.frame = CGRect(origin: .zero, size: window.contentLayoutRect.size)
    window.contentViewController = controller
    window.contentView?.layoutSubtreeIfNeeded()
    #expect(!window.isVisible && !window.isKeyWindow)
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

    var observations: [OverlayScopeRectangleObservation] = []
    for rect in rects {
        let start = CGPoint(x: rect.minX, y: rect.minY)
        let end = CGPoint(x: rect.maxX, y: rect.maxY)
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        var attempts = 0
        var duration = Duration.zero
        while targets.isEmpty, ContinuousClock.now < deadline {
            attempts += 1
            let clock = ContinuousClock()
            duration = clock.measure {
                input(in: controller.view)?.onCanvasDrag?(
                    start, end, size, .replace
                )
            }
            if targets.isEmpty {
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        let target = try #require(
            targets.first,
            """
            The mounted \(selectionHitPolicy) frame never answered the \
            rectangle \(rect).
            """
        )
        targets.removeAll()
        print(
            "[cost] scope=\(selectionHitPolicy) rect=\(rect)"
                + " attempts=\(attempts) answer=\(duration)"
                + " hits=\(target.hits.count)"
                + " occurrences=\(target.presentationOccurrenceIDs.count)"
        )
        observations.append(
            OverlayScopeRectangleObservation(
                rect: rect, target: target, attempts: attempts,
                duration: duration
            )
        )
    }
    return observations
}

// MARK: - Region scope

/// The rectangle answers the sketch regions it meets by area, names each one
/// once, and reports neither a body sub-shape nor an occurrence under this
/// scope.
///
/// Three rectangles separate the three statements: one that reaches a single
/// region, one that encloses everything the frame drew, and one clear of all
/// of it. The last is why this harness does not prove readiness with a
/// separate rectangle: an answer carrying no hit is an answer here, and the
/// frame not having answered at all is not.
@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeRegionScopeRectangleSelectsTheRegionsItMeets() async throws {
    _ = NSApplication.shared
    let control = overlayScopeRectangleControl()
    let fixture = try regionScopeSelectionFixture(control: control)

    let standaloneRect = fixture.standaloneSilhouette
        .insetBy(dx: -4.0, dy: -4.0)
    let wholeRect = fixture.drawnSilhouette.insetBy(dx: -4.0, dy: -4.0)
    let emptyRect = overlayScopeRectangle(around: fixture.emptyPoint)
    // The premises the three answers are read against: the rectangle that
    // names one region reaches only that one, and the rectangle that must
    // answer nothing is clear of everything the frame drew.
    #expect(standaloneRect.intersects(fixture.profileSilhouette) == false)
    #expect(emptyRect.maxX < fixture.drawnSilhouette.minX)

    let observations = try await overlayScopeRectangleDrags(
        mount: fixture.mountInputs,
        control: control,
        selectionHitPolicy: .region,
        rects: [standaloneRect, wholeRect, emptyRect]
    )

    let standalone = observations[0].target
    #expect(
        overlayScopeRegionComponentIDs(standalone.hits)
            == [fixture.standaloneRegionComponentID]
    )
    #expect(standalone.hits.count == 1)
    let hit = try #require(standalone.hits.first)
    #expect(hit.kind == .sketch)
    #expect(hit.featureID == fixture.standaloneFeatureID)
    // A region names the drawn area. No entity and no sub-shape reference
    // stands in for it.
    #expect(hit.sketchEntityID == nil)
    #expect(hit.selectionReference == nil)
    #expect(standalone.presentationOccurrenceIDs.isEmpty)

    // The wider rectangle covers the drawn body as well, and under this scope
    // no body family answers: the face harvest, the surface handle displays
    // and the prepared edge and vertex families are all gated off.
    let whole = observations[1].target
    #expect(
        overlayScopeRegionComponentIDs(whole.hits) == [
            fixture.profileRegionComponentID,
            fixture.standaloneRegionComponentID
        ]
    )
    #expect(whole.hits.count == 2)
    #expect(whole.hits.contains { $0.kind == .body } == false)
    #expect(whole.presentationOccurrenceIDs.isEmpty)

    #expect(observations[2].target.hits.isEmpty)
    #expect(observations[2].target.presentationOccurrenceIDs.isEmpty)
}

// MARK: - Sketch entity scope

/// The rectangle answers the sketch entity whose drawn polyline it clips a
/// span out of, and names the authored entity rather than a handle the
/// rectangle invented.
@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeSketchEntityScopeRectangleSelectsTheLineItMeets() async throws {
    _ = NSApplication.shared
    let fixture = try sketchScopeSelectionFixture()
    let control = overlayScopeRectangleControl()
    let geometry = try sketchScopeScreenGeometry(
        fixture: fixture, control: control
    )
    let rect = overlayScopeRectangle(around: geometry.clear.point)
    // The premise: this rectangle is clear of the solid, so nothing the frame
    // draws stands in front of the polyline inside it.
    #expect(rect.intersects(geometry.solidSilhouette) == false)

    let observations = try await overlayScopeRectangleDrags(
        mount: fixture.mountInputs,
        control: control,
        selectionHitPolicy: .sketchEntity,
        rects: [rect]
    )

    let target = observations[0].target
    #expect(target.hits.count == 1)
    let hit = try #require(target.hits.first)
    #expect(hit.featureID == fixture.lineFeatureID)
    #expect(hit.kind == .sketch)
    #expect(hit.sceneNodeID == fixture.lineSceneNodeID)
    // The identity is the authored sketch entity the frame drew the polyline
    // for: no endpoint handle is invented for it, no control point index is
    // claimed, and no `SelectionComponent` stands in for the entity.
    #expect(hit.sketchEntityID == fixture.lineEntityID)
    #expect(hit.sketchPointHandle == nil)
    #expect(hit.sketchControlPointIndex == nil)
    #expect(hit.selectionComponent == nil)
    #expect(hit.selectionReference == nil)
    #expect(target.presentationOccurrenceIDs.isEmpty)
}

/// A polyline the drawn body covers over every step of the span the rectangle
/// clips is not answered, and the scope no longer routes that miss to the
/// replaced backend.
@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeSketchEntityScopeRectangleRefusesACoveredLine() async throws {
    _ = NSApplication.shared
    let fixture = try sketchScopeSelectionFixture()
    let control = overlayScopeRectangleControl()
    let geometry = try sketchScopeScreenGeometry(
        fixture: fixture, control: control
    )
    let rect = overlayScopeRectangle(around: geometry.occluded.point)
    // The first premise: this rectangle lies inside the solid's drawn extent.
    #expect(geometry.solidSilhouette.contains(rect))

    // The second premise, measured rather than assumed: inside this rectangle
    // the frame draws the solid. The face scope reads the drawn surface
    // directly, so its answer is what covers the line.
    let covering = try await overlayScopeRectangleDrags(
        mount: fixture.mountInputs,
        control: control,
        selectionHitPolicy: .face,
        rects: [rect]
    )
    #expect(
        covering[0].target.hits.contains {
            $0.sceneNodeID == fixture.solidSceneNodeID && $0.kind == .body
        }
    )

    // The rule: the frame draws the polyline at scene depth, so the body in
    // front of it hides every step the rectangle walks, and the scope reports
    // no entity there.
    let observations = try await overlayScopeRectangleDrags(
        mount: fixture.mountInputs,
        control: control,
        selectionHitPolicy: .sketchEntity,
        rects: [rect]
    )
    #expect(observations[0].target.hits.isEmpty)
}

// MARK: - Combined scope

/// A scope admitting whole objects answers occurrences for the bodies the
/// rectangle covers and sub-shapes for none of them, while the sketch families
/// it also admits still answer.
///
/// The rule lives in the dispatcher rather than in any one family: the body
/// families are asked only where the scope does not admit whole objects, so a
/// scope admitting both reports the occurrence and leaves the face, edge,
/// vertex and surface handle families unasked. No family can be asked this on
/// its own, which is why it is measured on the mounted frame.
@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeCombinedScopeRectangleNamesOccurrencesNotSubshapes() async throws {
    _ = NSApplication.shared
    let control = overlayScopeRectangleControl()
    let fixture = try regionScopeSelectionFixture(control: control)
    let rect = fixture.drawnSilhouette.insetBy(dx: -4.0, dy: -4.0)

    let observations = try await overlayScopeRectangleDrags(
        mount: fixture.mountInputs,
        control: control,
        selectionHitPolicy: .all,
        rects: [rect]
    )

    let target = observations[0].target
    #expect(target.hits.contains { $0.kind == .body } == false)
    let occurrenceSceneNodeIDs = Set(
        target.presentationOccurrenceIDs.compactMap {
            fixture.mountInputs.sceneNodeIDByOccurrenceID[$0]
        }
    )
    #expect(occurrenceSceneNodeIDs.contains(fixture.solidSceneNodeID))
    // The region family is admitted by the same scope, so both regions are
    // still named alongside the occurrence.
    #expect(
        overlayScopeRegionComponentIDs(target.hits) == [
            fixture.profileRegionComponentID,
            fixture.standaloneRegionComponentID
        ]
    )
}
