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

/// The cameras a mounted profile gesture has to commit under.
///
/// The parallel isometric case is the routing baseline. The perspective case
/// covers the measurement that probed a model axis one metre from the handle:
/// at CAD scale that probe fell behind the standard perspective camera and
/// every profile commit was refused. The axis-front case covers the measurement
/// that required all three model axes to resolve, which refused a face solvable
/// along its own axis whenever a different axis was the degenerate one. The
/// left face is solved along world `x`, and `axisFront(.z)` collapses `z`.
enum ViewportProfileHandlePressCamera: String, CaseIterable {
    case isometricParallel
    case isometricPerspective
    case axisFrontParallel

    var basis: ViewportProjectionBasis {
        switch self {
        case .isometricParallel, .isometricPerspective:
            return .isometric
        case .axisFrontParallel:
            return .axisFront(.z)
        }
    }

    var projection: ViewportCameraProjection {
        switch self {
        case .isometricParallel, .axisFrontParallel:
            return .parallel
        case .isometricPerspective:
            return .standardPerspective
        }
    }
}

/// The four profile handles, each naming the commit route it owns.
enum ViewportProfileHandleKind: String {
    case face
    case corner
    case fillet
    case chamfer
}

/// The handle and camera pairs the mounted gesture is proven on.
///
/// The list is explicit rather than a product of handles and cameras. The face
/// is the one handle whose distance is solved on a single world axis, so it is
/// the only one an axis-front camera can answer: the other three sample the
/// profile sketch plane, whose normal is world `y`, and `axisFront(.z)` looks
/// along world `z`, which leaves that plane edge-on and is a typed refusal
/// rather than a routing failure.
enum ViewportProfileHandlePressCase: String, CaseIterable {
    case faceIsometricParallel
    case faceIsometricPerspective
    case faceAxisFrontParallel
    case cornerIsometricParallel
    case cornerIsometricPerspective
    case filletIsometricParallel
    case filletIsometricPerspective
    case chamferIsometricParallel
    case chamferIsometricPerspective

    var handle: ViewportProfileHandleKind {
        switch self {
        case .faceIsometricParallel, .faceIsometricPerspective, .faceAxisFrontParallel:
            return .face
        case .cornerIsometricParallel, .cornerIsometricPerspective:
            return .corner
        case .filletIsometricParallel, .filletIsometricPerspective:
            return .fillet
        case .chamferIsometricParallel, .chamferIsometricPerspective:
            return .chamfer
        }
    }

    var camera: ViewportProfileHandlePressCamera {
        switch self {
        case .faceIsometricParallel, .cornerIsometricParallel,
             .filletIsometricParallel, .chamferIsometricParallel:
            return .isometricParallel
        case .faceIsometricPerspective, .cornerIsometricPerspective,
             .filletIsometricPerspective, .chamferIsometricPerspective:
            return .isometricPerspective
        case .faceAxisFrontParallel:
            return .axisFrontParallel
        }
    }
}

/// The press point and the drag the mounted viewport has to resolve.
///
/// Every quantity here is derived the way the overlay producer derives it: the
/// selection component comes from the generated topology resolver production
/// prefers, the handle's world anchor comes from the same sub-shape production
/// resolves that component back to, and the screen offset repeats the directed
/// placement formula the spatial resources apply. A press that misses is then a
/// routing failure rather than a placement guess.
@MainActor
private struct ProfileHandlePressFixture {
    /// The world displacement a drag asks for. One millimetre on a ten
    /// millimetre body is large enough to clear the four point press slop and
    /// small enough to stay a valid edge treatment on that body.
    static let dragMeters = 0.001

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
    /// The release point of a gesture on empty space. It lies on the same
    /// construction plane as the empty press, one step further out, so the whole
    /// gesture resolves through the plane the canvas drag mapper uses.
    let emptyDragEnd: CGPoint
    /// Every handle this selection draws, not only the pressed one, so the
    /// empty point can be proven clear of all of them.
    let handlePoints: [CGPoint]

    init(pressCase: ViewportProfileHandlePressCase) throws {
        let camera = pressCase.camera
        let basis = camera.basis
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
        // identifier for a body sub-shape and only falls back to the legacy
        // identifier when the document cannot name it. This fixture must select
        // what production selects, because the overlay producer resolves the
        // handle from the body topology that carries the generated identifiers.
        let resolver = GeneratedTopologySelectionResolver()
        let componentID: SelectionComponentID
        switch pressCase.handle {
        case .face:
            guard let resolved = try resolver.componentID(
                for: sceneNodeID, bodyFace: .left, in: document
            ) else {
                throw ProfileAffordancePressFixtureError(
                    message: "The fixture body names no generated topology left face."
                )
            }
            componentID = resolved
            target = SelectionTarget(sceneNodeID: sceneNodeID, component: .face(resolved))
        case .corner:
            guard let resolved = try resolver.componentID(
                for: sceneNodeID, cornerVertex: .frontBottomLeft, in: document
            ) else {
                throw ProfileAffordancePressFixtureError(
                    message: "The fixture body names no generated topology front bottom left vertex."
                )
            }
            componentID = resolved
            target = SelectionTarget(sceneNodeID: sceneNodeID, component: .vertex(resolved))
        case .fillet, .chamfer:
            guard let resolved = try resolver.componentID(
                for: sceneNodeID, cornerEdge: .leftBottom, in: document
            ) else {
                throw ProfileAffordancePressFixtureError(
                    message: "The fixture body names no generated topology left bottom edge."
                )
            }
            componentID = resolved
            target = SelectionTarget(sceneNodeID: sceneNodeID, component: .edge(resolved))
        }
        selection = SelectionModel(selectedTargets: [target])
        size = CGSize(width: 900.0, height: 700.0)
        control = ViewportControlSession(
            camera: .init(projection: camera.projection), basis: basis
        )
        let layout = ViewportSceneContext(
            ruler: ruler,
            scene: scene,
            size: size,
            camera: control.camera,
            basis: basis,
            fittingInsets: ViewportCanvasChromeLayout(
                viewportSize: size
            ).fittingInsets
        ).layout
        let edit = ViewportObjectEditState(item: bodyItem)

        // The anchor and the drag direction both come from the sub-shape the
        // producer resolves this component back to, so a resolver that answers a
        // different sub-shape is reported here rather than read as a miss.
        let anchor: Point3D
        let dragDirection: Vector3D
        switch pressCase.handle {
        case .face:
            let resolvedFace = try resolver.bodyFace(
                for: target,
                in: document,
                objectRegistry: .builtIn,
                operationName: "Viewport generated topology selection"
            )
            let face: ViewportBodyFace
            switch resolvedFace {
            case .front: face = .front
            case .back: face = .back
            case .top: face = .top
            case .bottom: face = .bottom
            case .left: face = .left
            case .right: face = .right
            case .side: face = .side
            }
            anchor = edit.worldPoint(edit.position(for: face))
            // The face distance reads exactly one model axis, and the mapping
            // names which one, so the drag travels along that axis alone.
            dragDirection = edit.worldAxis(ViewportProfileFaceDragMapping.axis(for: face))
        case .corner:
            let resolvedVertex = try resolver.cornerVertex(
                for: target,
                in: document,
                objectRegistry: .builtIn,
                operationName: "Viewport generated topology selection"
            )
            let vertex: ViewportBodyVertex
            switch resolvedVertex {
            case .frontBottomLeft: vertex = .frontBottomLeft
            case .frontBottomRight: vertex = .frontBottomRight
            case .frontTopRight: vertex = .frontTopRight
            case .frontTopLeft: vertex = .frontTopLeft
            case .backBottomLeft: vertex = .backBottomLeft
            case .backBottomRight: vertex = .backBottomRight
            case .backTopRight: vertex = .backTopRight
            case .backTopLeft: vertex = .backTopLeft
            }
            anchor = edit.worldPoint(edit.position(for: vertex))
            dragDirection = edit.worldAxis(.x) + edit.worldAxis(.z)
        case .fillet, .chamfer:
            let resolvedEdge = try resolver.cornerEdge(
                for: target,
                in: document,
                objectRegistry: .builtIn,
                operationName: "Viewport generated topology selection"
            )
            // The inward direction below is the left bottom corner's, so a
            // resolver that answers a different edge is reported rather than
            // silently dragged outward, where every treatment is a valid
            // nothing-to-commit answer.
            guard resolvedEdge == .leftBottom else {
                throw ProfileAffordancePressFixtureError(
                    message: "The selected edge resolves to \(resolvedEdge) rather than the left bottom edge."
                )
            }
            // The edge handles anchor on the topology edge itself rather than on
            // the edit box, and the producer throws when the topology does not
            // carry the selected edge, which would remove the handle entirely.
            guard case .body(let component) = bodyItem.kind,
                  let topology = component.topology else {
                throw ProfileAffordancePressFixtureError(
                    message: "The fixture body item carries no topology for its edge handles."
                )
            }
            guard let sourceEdge = topology.edges.first(where: { $0.componentID == componentID })
            else {
                throw ProfileAffordancePressFixtureError(
                    message: "The fixture body topology does not carry the selected edge."
                )
            }
            let start = bodyItem.modelTransform.viewportTransformedPoint(sourceEdge.start)
            let end = bodyItem.modelTransform.viewportTransformedPoint(sourceEdge.end)
            anchor = Point3D(
                x: (start.x + end.x) / 2.0,
                y: (start.y + end.y) / 2.0,
                z: (start.z + end.z) / 2.0
            )
            // Both edge treatments read the inward corner displacement, and the
            // left bottom corner is inward along positive world x and z.
            dragDirection = edit.worldAxis(.x) + edit.worldAxis(.z)
        }

        guard let projectedAnchor = layout.projectedPoint(anchor)?.point else {
            throw ProfileAffordancePressFixtureError(
                message: "The handle anchor does not project into the fixture viewport."
            )
        }
        guard let projectedCenter = layout.projectedPoint(edit.worldPoint(edit.centerPoint))?.point
        else {
            throw ProfileAffordancePressFixtureError(
                message: "The body centre does not project into the fixture viewport."
            )
        }
        switch pressCase.handle {
        case .face, .corner:
            press = projectedAnchor
            handlePoints = [projectedAnchor]
        case .fillet, .chamfer:
            let filletPoint = try Self.directedPoint(
                anchor: projectedAnchor,
                toward: projectedCenter,
                points: ProfileMetrics.filletOffsetPoints
            )
            let chamferPoint = try Self.directedPoint(
                anchor: projectedAnchor,
                toward: projectedCenter,
                points: ProfileMetrics.chamferOffsetPoints
            )
            press = pressCase.handle == .fillet ? filletPoint : chamferPoint
            handlePoints = [filletPoint, chamferPoint]
        }
        guard let projectedDragEnd = layout.projectedPoint(
            anchor + dragDirection * Self.dragMeters
        )?.point else {
            throw ProfileAffordancePressFixtureError(
                message: "The drag destination does not project into the fixture viewport."
            )
        }
        // The drag is stated as a world displacement and then expressed on
        // screen, so the sample the frame resolves is the displacement the
        // mapping needs rather than an arbitrary screen travel.
        dragEnd = CGPoint(
            x: press.x + projectedDragEnd.x - projectedAnchor.x,
            y: press.y + projectedDragEnd.y - projectedAnchor.y
        )
        // A gesture on empty space has to resolve against the construction
        // plane production resolves a canvas drag on, so the empty point is
        // chosen as a point on that plane rather than as a viewport corner. A
        // corner is only a screen position: under a perspective camera the ray
        // through it can meet the plane behind the camera, which the frame
        // refuses, and the gesture then reaches no owner at all. Every candidate
        // below starts as a world point on the plane, so the camera sees it by
        // construction. The layout projection stands in for the mounted camera
        // here on the same assumption the press and the drag already make.
        let canvasPlane = try SketchPlaneCoordinateSystem(plane: Self.canvasSketchPlane)
        let centerLocal = canvasPlane.project(edit.worldPoint(edit.centerPoint)).point
        var span = 0.0
        var bodyScreenRadius: CGFloat = 0.0
        for corner in edit.worldBoxCorners {
            let local = canvasPlane.project(corner).point
            span = max(span, hypot(local.x - centerLocal.x, local.y - centerLocal.y))
            guard let projected = layout.projectedPoint(corner)?.point else {
                throw ProfileAffordancePressFixtureError(
                    message: "A body corner does not project into the fixture viewport."
                )
            }
            bodyScreenRadius = max(
                bodyScreenRadius,
                hypot(projected.x - projectedCenter.x, projected.y - projectedCenter.y)
            )
        }
        guard span > 0.0 else {
            throw ProfileAffordancePressFixtureError(
                message: "The fixture body collapses to one point on the construction plane."
            )
        }
        // The loops below read local copies so nothing captures `self` before
        // every stored property is initialized.
        let marks = handlePoints
        let viewportSize = size
        let clearance = ProfileMetrics.hitTolerancePoints + ProfileMetrics.markRadiusPoints
        var chosenPress: CGPoint?
        var chosenEnd: CGPoint?
        for step in 0...Self.emptyPointRadiusSteps {
            let radius = Self.emptyPointFirstRadius
                + Self.emptyPointRadiusStride * Double(step)
            for direction in Self.planeDirections {
                let startLocal = Point2D(
                    x: centerLocal.x + direction.x * radius * span,
                    y: centerLocal.y + direction.y * radius * span
                )
                guard let start = layout.projectedPoint(
                    canvasPlane.point(from: startLocal)
                )?.point else { continue }
                guard Self.isInside(start, size: viewportSize) else { continue }
                guard hypot(start.x - projectedCenter.x, start.y - projectedCenter.y)
                    > bodyScreenRadius + clearance else { continue }
                var clearsMarks = true
                for mark in marks {
                    if hypot(start.x - mark.x, start.y - mark.y) <= clearance {
                        clearsMarks = false
                    }
                }
                guard clearsMarks else { continue }
                // The release has to travel far enough on screen for the
                // viewport to read the gesture as a drag rather than as press
                // slop. How far one body span carries on screen is a property of
                // the camera, not of the body, so the release is searched
                // outward along the same direction until the travel itself is
                // long enough, rather than fixed as a fraction of the span.
                var chosenTravel: CGPoint?
                for travelStep in 1...Self.emptyDragSteps {
                    let reach = radius + Self.emptyDragStride * Double(travelStep)
                    let endLocal = Point2D(
                        x: centerLocal.x + direction.x * reach * span,
                        y: centerLocal.y + direction.y * reach * span
                    )
                    guard let end = layout.projectedPoint(
                        canvasPlane.point(from: endLocal)
                    )?.point else { continue }
                    guard Self.isInside(end, size: viewportSize) else { continue }
                    guard hypot(end.x - start.x, end.y - start.y)
                        > Self.emptyDragMinimumPoints else { continue }
                    chosenTravel = end
                    break
                }
                guard let end = chosenTravel else { continue }
                chosenPress = start
                chosenEnd = end
                break
            }
            if chosenPress != nil { break }
        }
        guard let chosenPress, let chosenEnd else {
            throw ProfileAffordancePressFixtureError(
                message: """
                    No point on the construction plane clears the body by \
                    \(bodyScreenRadius + clearance) points, travels more than \
                    \(Self.emptyDragMinimumPoints) points outward, and still \
                    projects inside the fixture viewport.
                    """
            )
        }
        emptyPoint = chosenPress
        emptyDragEnd = chosenEnd
    }

    /// The construction plane a canvas drag resolves on. The fixture states it
    /// and hands the same value to the viewport, so the empty point and the
    /// viewport cannot disagree about which plane the gesture lands on.
    static let canvasSketchPlane: SketchPlane = .xy

    /// The outward directions the empty point search walks, as unit vectors in
    /// the construction plane's own `u`/`v` basis.
    static let planeDirections: [(x: Double, y: Double)] = [
        (x: 1.0, y: 0.0),
        (x: -1.0, y: 0.0),
        (x: 0.0, y: 1.0),
        (x: 0.0, y: -1.0),
        (x: 0.7071067811865476, y: 0.7071067811865476),
        (x: 0.7071067811865476, y: -0.7071067811865476),
        (x: -0.7071067811865476, y: 0.7071067811865476),
        (x: -0.7071067811865476, y: -0.7071067811865476),
    ]

    /// The search walks outward from just past the body and stops once a
    /// candidate clears every handle and still projects inside the viewport.
    static let emptyPointFirstRadius = 1.25
    static let emptyPointRadiusStride = 0.25
    static let emptyPointRadiusSteps = 19
    /// The empty gesture's release is searched outward in these steps, measured
    /// in body spans, until its screen travel clears the viewport's threshold.
    static let emptyDragStride = 0.25
    static let emptyDragSteps = 24
    /// The screen travel the viewport needs before it reads a drag at all.
    static let emptyDragMinimumPoints: CGFloat = 8.0
    /// The margin a candidate keeps from the viewport edge, so a one point
    /// camera change cannot move it out of the drawn surface.
    static let emptyPointInsetPoints: CGFloat = 40.0

    private static func isInside(_ point: CGPoint, size: CGSize) -> Bool {
        point.x >= Self.emptyPointInsetPoints
            && point.x <= size.width - Self.emptyPointInsetPoints
            && point.y >= Self.emptyPointInsetPoints
            && point.y <= size.height - Self.emptyPointInsetPoints
    }

    /// The screen point a directed handle placement lands on: the anchor moved
    /// `points` along the screen direction toward the body centre, which is the
    /// offset the spatial resources resolve for a directed placement with no
    /// perpendicular component.
    private static func directedPoint(
        anchor: CGPoint, toward center: CGPoint, points: CGFloat
    ) throws -> CGPoint {
        let dx = center.x - anchor.x
        let dy = center.y - anchor.y
        let length = hypot(dx, dy)
        guard length > 0.0 else {
            throw ProfileAffordancePressFixtureError(
                message: "The handle anchor and the body centre project to one point."
            )
        }
        return CGPoint(x: anchor.x + dx * points / length, y: anchor.y + dy * points / length)
    }

    /// The distance from the empty point to the nearest drawn handle.
    var emptyPointDistance: CGFloat {
        handlePoints.map { hypot(emptyPoint.x - $0.x, emptyPoint.y - $0.y) }.min() ?? 0.0
    }
}

/// Mounts the viewport the same way the input owner does, so a press resolves
/// against a real prepared frame rather than a rebuilt projection.
@MainActor
private struct MountedProfileHandleViewport {
    let window: NSWindow
    let controller: NSViewController

    /// Every profile commit callback is supplied, whichever handle the case
    /// presses. The interactive routes are derived from which callbacks exist,
    /// so withholding one would remove the handle instead of testing it, and
    /// supplying all of them reproduces the production case where an edge
    /// selection draws the fillet and the chamfer handle at once.
    init(
        fixture: ProfileHandlePressFixture,
        onPick: @escaping (ViewportCanvasTarget) -> Void,
        onCanvasDrag: @escaping (ViewportModelDrag) -> Void,
        onVertexDrag: @escaping (ViewportVertexDragTarget) -> Void,
        onFaceDrag: @escaping (ViewportFaceDragTarget) -> Void,
        onEdgeChamferDrag: @escaping (ViewportEdgeChamferDragTarget) -> Void,
        onEdgeFilletDrag: @escaping (ViewportEdgeFilletDragTarget) -> Void
    ) async throws {
        _ = NSApplication.shared
        let viewport = Viewport(
            document: fixture.document,
            sourceIdentity: .document(id: fixture.document.id, generation: DocumentGeneration(1)),
            controlSession: fixture.control,
            workspaceRenderState: .init(revision: WorkspaceRevision(), ruler: fixture.ruler),
            selection: fixture.selection,
            objectSelectionIndex: .init(document: fixture.document, selection: fixture.selection),
            canvasDragSketchPlaneOverride: ProfileHandlePressFixture.canvasSketchPlane,
            allowsObjectAffordances: false,
            selectedPresentationHasExactCADContext: true,
            onPick: onPick,
            onCanvasDrag: onCanvasDrag,
            onVertexDrag: onVertexDrag,
            onFaceDrag: onFaceDrag,
            onEdgeChamferDrag: onEdgeChamferDrag,
            onEdgeFilletDrag: onEdgeFilletDrag
        ).frame(width: fixture.size.width, height: fixture.size.height)
        let controller = NSHostingController(rootView: viewport)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: fixture.size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        controller.view.frame = CGRect(origin: .zero, size: window.contentLayoutRect.size)
        window.contentViewController = controller
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(!window.isVisible && !window.isKeyWindow)
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
    ///
    /// `beforeRelease` runs after the preview and before the release with no
    /// suspension in between, so a camera change it makes cannot be applied by
    /// the mounted frame before the commit measures. Running it any earlier
    /// would make the preview refuse first and drop the claim, which would
    /// prove nothing about the commit.
    func gesture(
        from start: CGPoint,
        to end: CGPoint,
        size: CGSize,
        beforeRelease: () throws -> Void = {}
    ) async throws {
        let input = try resolvedInput()
        input.onPress?(start, size, .replace)
        try await Task.sleep(for: .milliseconds(500))
        input.onDragPreview?(start, end, size)
        try beforeRelease()
        input.onCanvasDrag?(start, end, size, .replace)
        try await Task.sleep(for: .milliseconds(30))
    }
}

/// The mounted tests drive a shared `NSApplication` and an ordered window, so
/// the suite is serialized rather than sharing that state across cases.
@Suite(.serialized)
@MainActor
struct ViewportNativeProfileAffordancePressTests {
    @Test(.timeLimit(.minutes(2)), arguments: ViewportProfileHandlePressCase.allCases)
    func profileHandleGestureCommitsAndAnEmptyPointDoesNot(
        pressCase: ViewportProfileHandlePressCase
    ) async throws {
        let fixture = try ProfileHandlePressFixture(pressCase: pressCase)
        #expect(
            fixture.emptyPointDistance
                > ProfileMetrics.hitTolerancePoints + ProfileMetrics.markRadiusPoints,
            "The empty point is inside a drawn handle, so a miss would prove nothing."
        )
        if fixture.handlePoints.count > 1 {
            // The fillet and the chamfer mark are drawn on the same anchor at
            // different offsets. Their separation is what lets one press claim
            // one of them, so it is stated here rather than assumed.
            #expect(
                abs(ProfileMetrics.chamferOffsetPoints - ProfileMetrics.filletOffsetPoints)
                    > ProfileMetrics.hitTolerancePoints + ProfileMetrics.markRadiusPoints,
                "The edge treatment marks overlap, so a press cannot claim one of them."
            )
        }

        var picks = 0
        var canvasDrags = 0
        var vertexDrags: [ViewportVertexDragTarget] = []
        var faceDrags: [ViewportFaceDragTarget] = []
        var chamferDrags: [ViewportEdgeChamferDragTarget] = []
        var filletDrags: [ViewportEdgeFilletDragTarget] = []
        func pressedCount() -> Int {
            switch pressCase.handle {
            case .face: faceDrags.count
            case .corner: vertexDrags.count
            case .fillet: filletDrags.count
            case .chamfer: chamferDrags.count
            }
        }
        func otherCount() -> Int {
            faceDrags.count + vertexDrags.count + filletDrags.count + chamferDrags.count
                - pressedCount()
        }
        let mounted = try await MountedProfileHandleViewport(
            fixture: fixture,
            onPick: { _ in picks += 1 },
            onCanvasDrag: { _ in canvasDrags += 1 },
            onVertexDrag: { vertexDrags.append($0) },
            onFaceDrag: { faceDrags.append($0) },
            onEdgeChamferDrag: { chamferDrags.append($0) },
            onEdgeFilletDrag: { filletDrags.append($0) }
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
            pressedCount() + otherCount() == 0,
            "A gesture on empty space committed a profile edit before the handle was pressed."
        )

        // A committed profile edit is the whole routing proof in one step: the
        // press was claimed by a native record, the claimed drag kept its
        // baseline, and the release resolved the claim into this handle's
        // callback. The canvas count taken across the same round says which half
        // failed when it does not commit: a canvas drag means the press was
        // never claimed, and no canvas drag means the claim never resolved.
        var canvasDragsDuringRound = 0
        let commitDeadline = ContinuousClock.now.advanced(by: .seconds(20))
        while pressedCount() == 0, ContinuousClock.now < commitDeadline {
            let before = canvasDrags
            try await mounted.gesture(from: fixture.press, to: fixture.dragEnd, size: fixture.size)
            canvasDragsDuringRound = canvasDrags - before
        }
        let failure = Comment(rawValue: """
            The \(pressCase.handle.rawValue) handle gesture never committed: \
            press=\(fixture.press), end=\(fixture.dragEnd), \
            canvasDragsInLastRound=\(canvasDragsDuringRound), picks=\(picks)
            """)
        switch pressCase.handle {
        case .face:
            let commit = try #require(faceDrags.first, failure)
            #expect(commit.target == fixture.target)
            #expect(abs(commit.distance) > 1.0e-12)
        case .corner:
            let commit = try #require(vertexDrags.first, failure)
            #expect(commit.target == fixture.target)
            #expect(abs(commit.deltaX) > 1.0e-12 || abs(commit.deltaY) > 1.0e-12)
        case .fillet:
            let commit = try #require(filletDrags.first, failure)
            #expect(commit.target == fixture.target)
            #expect(commit.radius > 1.0e-12)
        case .chamfer:
            let commit = try #require(chamferDrags.first, failure)
            #expect(commit.target == fixture.target)
            #expect(commit.distance > 1.0e-12)
        }
        #expect(
            otherCount() == 0,
            """
            The press committed a different profile route: vertex=\(vertexDrags.count), \
            face=\(faceDrags.count), fillet=\(filletDrags.count), chamfer=\(chamferDrags.count)
            """
        )
        #expect(
            canvasDragsDuringRound == 0,
            "A claimed handle gesture must not also reach the canvas owner."
        )

        // The same live frame now answers a press that no handle covers. It must
        // not produce a second commit, which is what separates a routed claim
        // from a handle that answers every press in the viewport.
        let committedCount = pressedCount()
        let canvasCount = canvasDrags
        try await mounted.gesture(
            from: fixture.emptyPoint, to: fixture.emptyDragEnd, size: fixture.size
        )
        #expect(
            pressedCount() == committedCount,
            """
            A gesture on empty space committed a profile edit: \
            empty=\(fixture.emptyPoint), committed=\(pressedCount())
            """
        )
        #expect(
            canvasDrags > canvasCount,
            "The gesture on empty space must still reach the canvas owner."
        )
    }

    /// A commit measures against the camera revision it names, and the mounted
    /// frame answers only for the revision it actually applied. A camera change
    /// between the claimed drag's baseline and its release therefore makes the
    /// frame stale, which is a refusal rather than a not-ready wait.
    ///
    /// The parallel isometric face case is the one this suite already proves
    /// commits, so the moved camera is the only difference between that case and
    /// this one. The refusal itself is reported on the viewport's own gesture
    /// failure channel, which a mounted host does not expose here, so it is
    /// proven by the callbacks that must stay silent and by the viewport
    /// dropping the claim rather than holding it.
    @Test(.timeLimit(.minutes(2)))
    func profileHandleCommitRefusesAStaleCameraRevision() async throws {
        let fixture = try ProfileHandlePressFixture(pressCase: .faceIsometricParallel)
        var picks = 0
        var canvasDrags = 0
        var vertexDrags: [ViewportVertexDragTarget] = []
        var faceDrags: [ViewportFaceDragTarget] = []
        var chamferDrags: [ViewportEdgeChamferDragTarget] = []
        var filletDrags: [ViewportEdgeFilletDragTarget] = []
        let mounted = try await MountedProfileHandleViewport(
            fixture: fixture,
            onPick: { _ in picks += 1 },
            onCanvasDrag: { _ in canvasDrags += 1 },
            onVertexDrag: { vertexDrags.append($0) },
            onFaceDrag: { faceDrags.append($0) },
            onEdgeChamferDrag: { chamferDrags.append($0) },
            onEdgeFilletDrag: { filletDrags.append($0) }
        )
        defer { mounted.close() }

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
        try #require(
            fixture.control.isMounted,
            "The control session never mounted, so a camera change cannot be applied at all."
        )

        // The camera moves after the claimed drag has its baseline and before
        // the release. The mounted frame cannot have applied the new revision
        // yet, because nothing suspends between the two.
        let canvasBefore = canvasDrags
        try await mounted.gesture(
            from: fixture.press,
            to: fixture.dragEnd,
            size: fixture.size,
            beforeRelease: {
                try fixture.control.perform(.pan(deltaXPoints: 1.0, deltaYPoints: 0.0))
            }
        )
        #expect(
            faceDrags.isEmpty,
            "A stale camera revision committed a face edit: \(faceDrags.count)"
        )
        #expect(
            vertexDrags.count + filletDrags.count + chamferDrags.count == 0,
            """
            A stale camera revision committed a different profile route: \
            vertex=\(vertexDrags.count), fillet=\(filletDrags.count), \
            chamfer=\(chamferDrags.count)
            """
        )
        #expect(
            canvasDrags == canvasBefore,
            "The refused handle gesture also reached the canvas owner."
        )

        // A refused commit clears the pending interaction targets, so the
        // viewport routes the next gesture instead of holding the dropped claim.
        // The frame needs the moved camera applied first, which is why this
        // waits rather than asserting on the first attempt.
        let canvasAfterRefusal = canvasDrags
        let freshDeadline = ContinuousClock.now.advanced(by: .seconds(20))
        while canvasDrags == canvasAfterRefusal, ContinuousClock.now < freshDeadline {
            try await mounted.gesture(
                from: fixture.emptyPoint, to: fixture.emptyDragEnd, size: fixture.size
            )
        }
        #expect(
            canvasDrags > canvasAfterRefusal,
            "The viewport never routed a gesture again after the refused commit."
        )
        #expect(
            faceDrags.isEmpty,
            "A gesture after the refusal committed the claim the refusal dropped."
        )
    }
}
