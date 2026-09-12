import AppKit
import CoreGraphics
import RupaCore
import SwiftCAD
import RupaViewportScene
import SwiftUI
import Testing
@testable import RupaRendering

private typealias ProfileMetrics = ViewportSpatialOverlayProducer.ProfileAffordanceMetrics

private struct ProfileAffordancePressFixtureError: Error {
    let message: String
}

/// The profile face handle is drawn with no offset, so the mark sits on the
/// projected face anchor and that projection is the point a press has to land
/// on. The fixture resolves the same anchor the overlay producer emits, so a
/// press that misses is a routing failure rather than a placement guess.
@MainActor
private struct ProfileFacePressFixture {
    let document: DesignDocument
    let ruler: RulerConfiguration
    let scene: ViewportScene
    let target: SelectionTarget
    let selection: SelectionModel
    let control: ViewportControlSession
    let size: CGSize
    let press: CGPoint
    let dragEnd: CGPoint
    let emptyPoint: CGPoint

    init() throws {
        let basis = ViewportProjectionBasis.isometric
        let session = EditorSession()
        guard session.createDefaultExtrudedRectangle() != nil else {
            throw ProfileAffordancePressFixtureError(
                message: "The fixture document did not create the default body."
            )
        }
        guard let bodyFeatureID = session.document.cadDocument.designGraph.order.last else {
            throw ProfileAffordancePressFixtureError(
                message: "The fixture document has no feature to select."
            )
        }
        document = session.document
        ruler = session.workspaceState.ruler
        scene = ViewportSceneBuilder().build(document: document, ruler: ruler)
        guard let bodyItem = scene.items.first(where: { item in
            guard case .body = item.kind else { return false }
            return item.featureID == bodyFeatureID
        }) else {
            throw ProfileAffordancePressFixtureError(
                message: "The fixture scene has no body item for the created feature."
            )
        }
        guard let sceneNodeID = bodyItem.sceneNodeID else {
            throw ProfileAffordancePressFixtureError(
                message: "The fixture body item carries no scene node identity."
            )
        }
        // The production selection resolver prefers the generated topology
        // identifier for a body face and only falls back to the legacy
        // identifier when the document cannot name the face. This fixture must
        // select what production selects, because the overlay producer resolves
        // the handle from the body topology that carries the generated
        // identifiers.
        guard let faceComponentID = try GeneratedTopologySelectionResolver().componentID(
            for: sceneNodeID,
            bodyFace: .left,
            in: document
        ) else {
            throw ProfileAffordancePressFixtureError(
                message: "The fixture body exposes no generated topology identifier for its left face."
            )
        }
        target = SelectionTarget(sceneNodeID: sceneNodeID, component: .face(faceComponentID))
        selection = SelectionModel(selectedTargets: [target])
        size = CGSize(width: 900.0, height: 700.0)
        // The committed face distance is solved against all three projected model
        // axes, so the fixture keeps the default isometric basis where every axis
        // has a non-degenerate screen direction. An axis-front basis collapses one
        // of them and the commit would be refused for a reason unrelated to
        // routing.
        //
        // The projection stays parallel for the same reason. The perspective
        // measurement path probes each model axis one meter away from the handle
        // centre, and at CAD scale that probe falls behind the perspective camera,
        // so the distance is refused before routing is exercised. Moving that
        // measurement onto the mounted camera is owned by the follow-up item that
        // replaces the legacy projection, not by this routing proof.
        control = ViewportControlSession(camera: .init(projection: .parallel), basis: basis)
        let layout = ViewportSceneContext(
            ruler: ruler,
            scene: scene,
            size: size,
            camera: control.camera,
            basis: basis,
            fittingInsets: ViewportCanvasChromeLayout(
                viewportSize: size,
                viewportBadgeWidth: ViewportCanvasChromeLayout.maximumViewportBadgeWidth
            ).fittingInsets
        ).layout
        let edit = ViewportObjectEditState(item: bodyItem)
        guard let anchor = layout.projectedPoint(edit.worldPoint(edit.position(for: .left)))?.point else {
            throw ProfileAffordancePressFixtureError(
                message: "The left face anchor does not project into the fixture viewport."
            )
        }
        press = anchor
        dragEnd = CGPoint(x: anchor.x + 40.0, y: anchor.y)
        let corners = [
            CGPoint(x: 20.0, y: 20.0),
            CGPoint(x: size.width - 20.0, y: 20.0),
            CGPoint(x: 20.0, y: size.height - 20.0),
            CGPoint(x: size.width - 20.0, y: size.height - 20.0),
        ]
        guard let farthest = corners.max(by: { first, second in
            hypot(first.x - anchor.x, first.y - anchor.y)
                < hypot(second.x - anchor.x, second.y - anchor.y)
        }) else {
            throw ProfileAffordancePressFixtureError(
                message: "The fixture viewport has no candidate empty point."
            )
        }
        emptyPoint = farthest
    }

    var emptyPointDistance: CGFloat {
        hypot(emptyPoint.x - press.x, emptyPoint.y - press.y)
    }

    var emptyDragEnd: CGPoint {
        CGPoint(x: emptyPoint.x + 40.0, y: emptyPoint.y)
    }
}

/// Mounts the viewport the same way the input owner does, so a press resolves
/// against a real prepared frame rather than a rebuilt projection.
@MainActor
private struct MountedProfileFaceViewport {
    let window: NSWindow
    let controller: NSViewController

    init(
        fixture: ProfileFacePressFixture,
        onPick: @escaping (ViewportCanvasTarget) -> Void,
        onCanvasDrag: @escaping (ViewportModelDrag) -> Void,
        onFaceDrag: @escaping (ViewportFaceDragTarget) -> Void
    ) async throws {
        _ = NSApplication.shared
        let viewport = Viewport(
            document: fixture.document,
            sourceIdentity: .document(id: fixture.document.id, generation: DocumentGeneration(1)),
            controlSession: fixture.control,
            workspaceRenderState: .init(revision: WorkspaceRevision(), ruler: fixture.ruler),
            selection: fixture.selection,
            objectSelectionIndex: .init(document: fixture.document, selection: fixture.selection),
            allowsObjectAffordances: false,
            selectedPresentationHasExactCADContext: true,
            onPick: onPick,
            onCanvasDrag: onCanvasDrag,
            onFaceDrag: onFaceDrag
        ).frame(width: fixture.size.width, height: fixture.size.height)
        let controller = NSHostingController(rootView: viewport)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: fixture.size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.orderFront(nil)
        self.controller = controller
        self.window = window

        var mounted = false
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !mounted, ContinuousClock.now < deadline {
            mounted = Self.inputView(in: controller.view) != nil
            if !mounted {
                try await Task.sleep(for: .milliseconds(30))
            }
        }
        guard mounted else {
            window.contentViewController = nil
            window.close()
            throw ProfileAffordancePressFixtureError(
                message: "The mounted viewport never installed an input surface."
            )
        }
    }

    func close() {
        window.contentViewController = nil
        window.close()
    }

    /// SwiftUI rebuilds the representable while the frame is preparing, so the
    /// surface that carried the callbacks at mount time can be replaced by a
    /// later one. Every gesture resolves the surface again rather than holding
    /// the first one it saw.
    private static func inputView(in view: NSView) -> ViewportInputSurface.InputView? {
        if let value = view as? ViewportInputSurface.InputView { return value }
        for child in view.subviews {
            if let value = inputView(in: child) { return value }
        }
        return nil
    }

    private func resolvedInput() throws -> ViewportInputSurface.InputView {
        guard let input = Self.inputView(in: controller.view) else {
            throw ProfileAffordancePressFixtureError(
                message: "The mounted viewport lost its input surface mid-gesture."
            )
        }
        return input
    }

    /// A click with no press before it. It reaches the canvas owner whenever the
    /// viewport can answer a point at all, so it separates a viewport that never
    /// resolves anything from one that resolves points but refuses the press.
    func click(at point: CGPoint, size: CGSize) throws {
        try resolvedInput().onPick?(point, size, .replace)
    }

    /// One whole gesture: the press that claims a handle, the mid-drag preview
    /// that gives the claimed drag its baseline, and the release that commits.
    func gesture(from start: CGPoint, to end: CGPoint, size: CGSize) async throws {
        let input = try resolvedInput()
        input.onPress?(start, size, .replace)
        try await Task.sleep(for: .milliseconds(500))
        input.onDragPreview?(start, end, size)
        input.onCanvasDrag?(start, end, size, .replace)
        try await Task.sleep(for: .milliseconds(30))
    }
}

/// The mounted tests drive a shared `NSApplication` and an ordered window, so
/// the suite is serialized rather than sharing that state across cases.
@Suite(.serialized)
@MainActor
struct ViewportNativeProfileAffordancePressTests {
    @Test(.timeLimit(.minutes(2)))
    func profileFaceHandleGestureCommitsAndAnEmptyPointDoesNot() async throws {
        let fixture = try ProfileFacePressFixture()
        #expect(
            fixture.emptyPointDistance
                > ProfileMetrics.hitTolerancePoints + ProfileMetrics.markRadiusPoints,
            "The empty point is inside the drawn handle, so a miss would prove nothing."
        )
        var picks = 0
        var canvasDrags = 0
        var faceDrags: [ViewportFaceDragTarget] = []
        let mounted = try await MountedProfileFaceViewport(
            fixture: fixture,
            onPick: { _ in picks += 1 },
            onCanvasDrag: { _ in canvasDrags += 1 },
            onFaceDrag: { faceDrags.append($0) }
        )
        defer { mounted.close() }

        // A gesture on empty space is the readiness signal the handle gesture
        // needs. A press whose frame cannot answer a native record cancels the
        // gesture, so the canvas owner hears nothing at all; once the canvas
        // owner does hear the drag, the press reached a live frame and found no
        // handle there.
        let readyDeadline = ContinuousClock.now.advanced(by: .seconds(20))
        while canvasDrags == 0, ContinuousClock.now < readyDeadline {
            try mounted.click(at: fixture.emptyPoint, size: fixture.size)
            try await mounted.gesture(
                from: fixture.emptyPoint, to: fixture.emptyDragEnd, size: fixture.size
            )
        }
        try #require(
            canvasDrags > 0,
            """
            The mounted viewport never routed a gesture on empty space to the \
            canvas owner: picks=\(picks), empty=\(fixture.emptyPoint)
            """
        )
        #expect(
            faceDrags.isEmpty,
            "A gesture on empty space committed a face distance before the handle was pressed."
        )

        // A committed face distance is the whole routing proof in one step: the
        // press was claimed by a native record, the claimed drag kept its
        // baseline, and the release resolved the claim into the face callback.
        // The canvas count taken across the same round says which half failed
        // when it does not commit: a canvas drag means the press was never
        // claimed, and no canvas drag means the claim never resolved.
        var canvasDragsDuringRound = 0
        let commitDeadline = ContinuousClock.now.advanced(by: .seconds(20))
        while faceDrags.isEmpty, ContinuousClock.now < commitDeadline {
            let before = canvasDrags
            try await mounted.gesture(from: fixture.press, to: fixture.dragEnd, size: fixture.size)
            canvasDragsDuringRound = canvasDrags - before
        }
        let commit = try #require(
            faceDrags.first,
            """
            The profile face handle gesture never committed: \
            press=\(fixture.press), end=\(fixture.dragEnd), \
            canvasDragsInLastRound=\(canvasDragsDuringRound), picks=\(picks)
            """
        )
        #expect(commit.target == fixture.target)
        #expect(abs(commit.distance) > 1.0e-12)
        #expect(
            canvasDragsDuringRound == 0,
            "A claimed handle gesture must not also reach the canvas owner."
        )

        // The same live frame now answers a press that no handle covers. It must
        // not produce a second face commit, which is what separates a routed
        // claim from a handle that answers every press in the viewport.
        let committedCount = faceDrags.count
        let canvasCount = canvasDrags
        try await mounted.gesture(
            from: fixture.emptyPoint, to: fixture.emptyDragEnd, size: fixture.size
        )
        #expect(
            faceDrags.count == committedCount,
            """
            A gesture on empty space committed a face distance: \
            empty=\(fixture.emptyPoint), faceDrags=\(faceDrags.count)
            """
        )
        #expect(
            canvasDrags > canvasCount,
            "The gesture on empty space must still reach the canvas owner."
        )
    }
}
