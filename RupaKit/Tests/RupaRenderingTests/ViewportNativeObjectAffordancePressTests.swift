import AppKit
import CoreGraphics
import RupaCore
import RupaGeometry
import RupaKit
import RupaProject
import SwiftCAD
import RupaViewportScene
import SwiftUI
import Testing
import Synchronization
@testable import RupaRendering

private typealias BodyMetrics = ViewportSpatialOverlayProducer.BodyTransformMetrics

private struct ObjectAffordancePressFixtureError: Error {
    let message: String
}

/// One gizmo station per case. All three translate axes commit, because a
/// placement is the scene node's own frame rather than an edit of the profile
/// sketch one of them happens to lie in.
enum ViewportObjectHandlePressCase: String, CaseIterable {
    case translateX
    case translateZ
    case translateY
    case centerScaleX
    case centerScaleY
    case centerScaleZ
    case translateTipX
    case rotateX

    /// The world axis a released drag on this station must move the body
    /// along. The gizmo's arrows are the world axes, so naming one here is
    /// what separates "it moved" from "it moved where the pointer pointed".
    var committedAxis: ViewportCoordinateAxis? {
        switch self {
        case .translateX, .translateTipX: return .x
        case .translateY: return .y
        case .translateZ: return .z
        case .centerScaleX, .centerScaleY, .centerScaleZ, .rotateX: return nil
        }
    }

    var handleName: String {
        switch self {
        case .translateX: return "translate(.x)"
        case .translateZ: return "translate(.z)"
        case .translateY: return "translate(.y)"
        case .centerScaleX: return "centerScale(.x)"
        case .centerScaleY: return "centerScale(.y)"
        case .centerScaleZ: return "centerScale(.z)"
        case .translateTipX: return "translate(.x)"
        case .rotateX: return "rotate(.x)"
        }
    }
}

/// A drawn handle reduced to the screen footprint the native hit test accepts:
/// a marker collider is a sphere whose world radius is the tolerance in points,
/// and a line collider accepts a perpendicular distance within its tolerance,
/// so both reduce to a screen distance compared against the emitted tolerance.
private enum ObjectHandleShape {
    case marker(CGPoint)
    case polyline([CGPoint])
}

private struct ObjectHandleFootprint {
    let name: String
    let shape: ObjectHandleShape
    let tolerance: CGFloat

    func distance(to point: CGPoint) -> CGFloat {
        switch shape {
        case .marker(let center):
            return hypot(point.x - center.x, point.y - center.y)
        case .polyline(let points):
            guard let first = points.first else { return .greatestFiniteMagnitude }
            var best = hypot(point.x - first.x, point.y - first.y)
            for index in points.indices.dropLast() {
                best = min(best, Self.distance(from: point, to: points[index], points[index + 1]))
            }
            return best
        }
    }

    private static func distance(from point: CGPoint, to start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 1.0e-12 else {
            return hypot(point.x - start.x, point.y - start.y)
        }
        let raw = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        let clamped = min(max(raw, 0.0), 1.0)
        return hypot(point.x - (start.x + dx * clamped), point.y - (start.y + dy * clamped))
    }
}

@MainActor
private struct ObjectHandlePressFixture {
    static let canvasSketchPlane: SketchPlane = .xy
    /// Isolate markers for lifecycle checks: the shaft tolerance is 7 and the
    /// marker tolerance is 10. The overlap test removes this offset to verify
    /// native priority at the visible marker and on the shaft beneath it.
    static let markerOffsetPoints: CGFloat = 8.5
    /// Far enough from the centre decoration, which carries no collider, and
    /// short of the rotation ring's axial endpoints.
    static let translateStationPoints: CGFloat = 40.0
    static let dragPoints: CGFloat = 24.0

    let document: DesignDocument
    let ruler: RulerConfiguration
    let scene: ViewportScene
    let target: SelectionTarget
    let selection: SelectionModel
    let control: ViewportControlSession
    let size: CGSize
    let press: CGPoint
    let dragEnd: CGPoint
    let translateStation: CGPoint
    let translateStationDragEnd: CGPoint
    let emptyPoint: CGPoint
    let emptyDragEnd: CGPoint

    init(pressCase: ViewportObjectHandlePressCase) throws {
        let session = EditorSession()
        guard session.createDefaultExtrudedRectangle() != nil else {
            throw ObjectAffordancePressFixtureError(
                message: "The fixture document did not create the default body."
            )
        }
        guard let bodyFeatureID = session.document.cadDocument.designGraph.order.last else {
            throw ObjectAffordancePressFixtureError(
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
            throw ObjectAffordancePressFixtureError(
                message: "The fixture scene has no body item for the created feature."
            )
        }
        guard let sceneNodeID = bodyItem.sceneNodeID else {
            throw ObjectAffordancePressFixtureError(
                message: "The fixture body item carries no scene node identity."
            )
        }
        // The transform gizmo is the occurrence-scope affordance, so the
        // fixture selects the occurrence itself rather than a sub-shape.
        target = SelectionTarget(sceneNodeID: sceneNodeID, component: .object)
        selection = SelectionModel(selectedTargets: [target])
        size = CGSize(width: 900.0, height: 700.0)
        // Isometric keeps all three axes non-degenerate, so one camera carries
        // every station this suite presses.
        let basis = ViewportProjectionBasis.isometric
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
        let centerWorld = edit.worldPoint(edit.centerPoint)
        guard let projectedCenter = layout.projectedPoint(centerWorld)?.point else {
            throw ObjectAffordancePressFixtureError(
                message: "The fixture camera does not project the body centre."
            )
        }
        let scale = layout.scale
        guard scale.isFinite, scale > 0 else {
            throw ObjectAffordancePressFixtureError(
                message: "The fixture layout reports no usable scale."
            )
        }

        // The loops below read local copies so nothing captures `self` before
        // every stored property is initialized.
        func project(_ point: Point3D) throws -> CGPoint {
            guard let value = layout.projectedPoint(point)?.point else {
                throw ObjectAffordancePressFixtureError(
                    message: "The fixture camera does not project a handle anchor."
                )
            }
            return value
        }
        /// A `.directed` offset is resolved in screen points, so the arrow and
        /// the two axis markers only need the axis direction on screen.
        func screenDirection(_ vector: Vector3D) throws -> CGPoint {
            let probe = try project(centerWorld + vector * (1.0 / scale))
            let dx = probe.x - projectedCenter.x
            let dy = probe.y - projectedCenter.y
            let length = hypot(dx, dy)
            guard length > 1.0e-9 else {
                throw ObjectAffordancePressFixtureError(
                    message: "A gizmo axis projects to a degenerate screen direction."
                )
            }
            return CGPoint(x: dx / length, y: dy / length)
        }
        /// A `.worldDirected` offset is resolved in scene space, so the ring is
        /// a foreshortened arc rather than a screen circle. Its screen offset is
        /// the projection of a world step of `points * metresPerPoint`.
        func worldDirectedOffset(_ vector: Vector3D, points: CGFloat) throws -> CGPoint {
            let probe = try project(centerWorld + vector * (Double(points) / scale))
            return CGPoint(x: probe.x - projectedCenter.x, y: probe.y - projectedCenter.y)
        }
        func station(_ direction: CGPoint, _ points: CGFloat, perpendicular: CGFloat = 0.0) -> CGPoint {
            CGPoint(
                x: projectedCenter.x + direction.x * points - direction.y * perpendicular,
                y: projectedCenter.y + direction.y * points + direction.x * perpendicular
            )
        }

        let axes: [ViewportCoordinateAxis] = [.x, .y, .z]
        let worldAxes = axes.map { edit.worldAxis($0) }
        let directions = try worldAxes.map { try screenDirection($0) }
        var footprints: [ObjectHandleFootprint] = []
        for (index, axis) in axes.enumerated() {
            let direction = directions[index]
            let tip = station(direction, BodyMetrics.axisLengthPoints)
            footprints.append(
                ObjectHandleFootprint(
                    name: "translate(.\(axis))",
                    shape: .polyline([projectedCenter, tip]),
                    tolerance: 7.0
                )
            )
            footprints.append(
                ObjectHandleFootprint(
                    name: "translate(.\(axis))", shape: .marker(tip), tolerance: 10.0
                )
            )
            footprints.append(
                ObjectHandleFootprint(
                    name: "centerScale(.\(axis))",
                    shape: .marker(station(direction, BodyMetrics.centerScalePoints)),
                    tolerance: 10.0
                )
            )
        }
        let rotationPlanes: [(ViewportCoordinateAxis, Vector3D, Vector3D)] = [
            (.x, worldAxes[1], worldAxes[2]),
            (.y, worldAxes[2], worldAxes[0]),
            (.z, worldAxes[0], worldAxes[1]),
        ]
        func rotationSample(_ start: Vector3D, _ end: Vector3D, _ index: Int) throws -> CGPoint {
            let radians = Double(index) / Double(BodyMetrics.rotationSegmentCount) * .pi / 2.0
            let direction = try (start * cos(radians) + end * sin(radians))
                .normalized(tolerance: 1.0e-12)
            let offset = try worldDirectedOffset(direction, points: BodyMetrics.rotationRadiusPoints)
            return CGPoint(x: projectedCenter.x + offset.x, y: projectedCenter.y + offset.y)
        }
        for (axis, planeStart, planeEnd) in rotationPlanes {
            var arc: [CGPoint] = []
            for index in 0 ... BodyMetrics.rotationSegmentCount {
                arc.append(try rotationSample(planeStart, planeEnd, index))
            }
            footprints.append(
                ObjectHandleFootprint(
                    name: "rotate(.\(axis))", shape: .polyline(arc), tolerance: 8.0
                )
            )
        }
        for face in ViewportBodyFace.editableCases {
            footprints.append(
                ObjectHandleFootprint(
                    name: "faceMove(\(face))",
                    shape: .marker(try project(edit.worldPoint(edit.position(for: face)))),
                    tolerance: 10.0
                )
            )
        }
        for (index, corner) in edit.worldBoxCorners.enumerated() {
            footprints.append(
                ObjectHandleFootprint(
                    name: "vertexMove(corner \(index))",
                    shape: .marker(try project(corner)),
                    tolerance: 10.0
                )
            )
        }

        func claimants(of point: CGPoint) -> [String] {
            footprints.filter { $0.distance(to: point) <= $0.tolerance }.map(\.name)
        }
        func requireSoleClaimant(_ point: CGPoint, _ name: String) throws {
            let claimed = claimants(of: point)
            guard claimed == [name] else {
                throw ObjectAffordancePressFixtureError(
                    message: "The \(name) station is claimed by \(claimed) instead of \(name) alone."
                )
            }
        }

        let axisIndex: Int
        let pressPoint: CGPoint
        switch pressCase {
        case .translateX, .centerScaleX, .translateTipX, .rotateX:
            axisIndex = 0
        case .translateY, .centerScaleY:
            axisIndex = 1
        case .translateZ, .centerScaleZ:
            axisIndex = 2
        }
        switch pressCase {
        case .translateX, .translateY, .translateZ:
            pressPoint = station(directions[axisIndex], Self.translateStationPoints)
        case .centerScaleX, .centerScaleY, .centerScaleZ:
            pressPoint = station(
                directions[axisIndex],
                BodyMetrics.centerScalePoints,
                perpendicular: Self.markerOffsetPoints
            )
        case .translateTipX:
            pressPoint = station(
                directions[axisIndex],
                BodyMetrics.axisLengthPoints,
                perpendicular: Self.markerOffsetPoints
            )
        case .rotateX:
            pressPoint = try rotationSample(
                worldAxes[1], worldAxes[2], BodyMetrics.rotationSegmentCount / 2
            )
        }
        try requireSoleClaimant(pressPoint, pressCase.handleName)
        press = pressPoint
        let dragDirection = directions[axisIndex]
        dragEnd = CGPoint(
            x: pressPoint.x + dragDirection.x * Self.dragPoints,
            y: pressPoint.y + dragDirection.y * Self.dragPoints
        )

        // The positive control for the mounted frame is the in-plane translate
        // the same round must commit, so a silent target cannot be confused
        // with a frame that answers no affordance at all.
        let controlStation = station(directions[0], Self.translateStationPoints)
        try requireSoleClaimant(controlStation, "translate(.x)")
        translateStation = controlStation
        translateStationDragEnd = CGPoint(
            x: controlStation.x + directions[0].x * Self.dragPoints,
            y: controlStation.y + directions[0].y * Self.dragPoints
        )

        // An empty point has to clear every drawn handle and stay inside the
        // canvas, and its drag has to exceed the canvas drag threshold.
        let inset: CGFloat = 40.0
        let viewportSize = size
        var resolvedEmptyPoint: CGPoint?
        search: for step in 0 ..< 10 {
            let radius = 170.0 + CGFloat(step) * 20.0
            for angleStep in 0 ..< 8 {
                let angle = Double(angleStep) / 8.0 * 2.0 * .pi
                let candidate = CGPoint(
                    x: projectedCenter.x + radius * CGFloat(cos(angle)),
                    y: projectedCenter.y + radius * CGFloat(sin(angle))
                )
                let end = CGPoint(x: candidate.x + Self.dragPoints, y: candidate.y)
                guard candidate.x >= inset, candidate.y >= inset,
                      candidate.x <= viewportSize.width - inset,
                      candidate.y <= viewportSize.height - inset,
                      end.x <= viewportSize.width - inset,
                      claimants(of: candidate).isEmpty, claimants(of: end).isEmpty else {
                    continue
                }
                resolvedEmptyPoint = candidate
                break search
            }
        }
        guard let resolvedEmptyPoint else {
            throw ObjectAffordancePressFixtureError(
                message: "The fixture found no canvas point clear of every gizmo handle."
            )
        }
        emptyPoint = resolvedEmptyPoint
        emptyDragEnd = CGPoint(x: resolvedEmptyPoint.x + Self.dragPoints, y: resolvedEmptyPoint.y)
    }
}

@MainActor
private struct MountedObjectHandleViewport {
    enum Invalidation: CaseIterable { case source, selection, route }
    let window: NSWindow
    let controller: NSViewController
    let invalidate: (Invalidation) -> Void

    /// `onBodyPlacementCommit` is the only commit callback the transform gizmo
    /// has, and `allowsObjectAffordances` is what makes the gizmo interactive
    /// at all. The
    /// profile callbacks stay unset so the profile routes are not interactive
    /// and cannot claim a press this suite attributes to the gizmo.
    init(
        fixture: ObjectHandlePressFixture,
        presentation: ProjectViewSnapshot? = nil,
        allowsObjectAffordances: Bool = true,
        onSelectionDrag: ((ViewportSelectionDragTarget) -> Void)? = nil,
        onPick: @escaping (ViewportCanvasTarget) -> Void,
        onCanvasDrag: @escaping (ViewportModelDrag) -> Void,
        onBodyPlacementCommit: @escaping ([ViewportBodyPlacementDragTarget]) -> Void,
        commitCompletion: (@MainActor () async throws -> ViewportSourceIdentity)? = nil,
        onBodyResizeCommit: ((ViewportBodyResizeDragTarget) -> Void)? = nil
    ) async throws {
        _ = NSApplication.shared
        func viewport(invalidation: Invalidation? = nil) -> AnyView {
        let selection = invalidation == .selection ? SelectionModel() : fixture.selection
        let resizeCommit: ((ViewportBodyResizeDragTarget) async throws -> ViewportSourceIdentity)?
        if let onBodyResizeCommit, invalidation != .route {
            resizeCommit = { target in
                onBodyResizeCommit(target)
                return .document(id: fixture.document.id, generation: DocumentGeneration(1))
            }
        } else { resizeCommit = nil }
        return AnyView(Viewport(
            document: presentation?.document.document ?? fixture.document,
            sourceIdentity: .document(id: fixture.document.id, generation: DocumentGeneration(invalidation == .source ? 2 : 1)),
            controlSession: fixture.control,
            presentationScene: presentation?.viewport,
            presentationSceneNodeIDByOccurrenceID: presentation?.sceneNodeIDByOccurrenceID ?? [:],
            workspaceRenderState: .init(revision: WorkspaceRevision(), ruler: fixture.ruler),
            selection: selection,
            objectSelectionIndex: .init(document: fixture.document, selection: selection),
            canvasDragSketchPlaneOverride: ObjectHandlePressFixture.canvasSketchPlane,
            allowsSelectionRectangle: onSelectionDrag != nil,
            allowsObjectAffordances: allowsObjectAffordances && invalidation != .route,
            selectedPresentationHasExactCADContext: true,
            onPick: onPick,
            onCanvasDrag: onCanvasDrag,
            onSelectionDrag: onSelectionDrag,
            onBodyPlacementCommit: invalidation == .route ? nil : { targets in
                onBodyPlacementCommit(targets)
                if let commitCompletion { return try await commitCompletion() }
                return .document(id: fixture.document.id, generation: DocumentGeneration(1))
            },
            onBodyResizeCommit: resizeCommit
        ).frame(width: fixture.size.width, height: fixture.size.height))
        }
        let controller = NSHostingController(rootView: viewport())
        self.invalidate = { controller.rootView = viewport(invalidation: $0) }
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: fixture.size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        controller.view.frame = CGRect(origin: .zero, size: fixture.size)
        window.contentViewController = controller
        window.setContentSize(fixture.size)
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(!window.isVisible && !window.isKeyWindow)
        self.controller = controller
        self.window = window

        var mounted = false
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !mounted, ContinuousClock.now < deadline {
            controller.view.layoutSubtreeIfNeeded()
            mounted = Self.inputView(in: controller.view)?.bounds.size == fixture.size
            if !mounted {
                try await Task.sleep(for: .milliseconds(30))
            }
        }
        guard mounted else {
            window.contentViewController = nil
            window.close()
            throw ObjectAffordancePressFixtureError(
                message: "The mounted viewport never installed an input surface."
            )
        }
    }

    func close() {
        window.contentViewController = nil
        window.close()
    }

    private static func inputView(in view: NSView) -> ViewportInputSurface.InputView? {
        if let value = view as? ViewportInputSurface.InputView { return value }
        for child in view.subviews {
            if let value = inputView(in: child) { return value }
        }
        return nil
    }

    private func resolvedInput() throws -> ViewportInputSurface.InputView {
        guard let input = Self.inputView(in: controller.view) else {
            throw ObjectAffordancePressFixtureError(
                message: "The mounted viewport lost its input surface mid-gesture."
            )
        }
        return input
    }

    private func receiver(at point: CGPoint) throws -> ViewportInputSurface.InputView {
        let input = try resolvedInput()
        let root = controller.view
        let hitPoint = input.convert(point, to: root.superview)
        let hit = try #require(root.hitTest(hitPoint),
            "Hosted hit failed: input point \(point), input frame \(input.frame), root frame \(root.frame), root bounds \(root.bounds), parent \(String(describing: root.superview)), hidden \(root.isHiddenOrHasHiddenAncestor)")
        try #require(hit === input, "Another hosted view intercepted the canvas pointer.")
        return input
    }

    func click(at point: CGPoint, size: CGSize) throws {
        let input = try receiver(at: point)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type,
                location: input.convert(point, to: nil), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
            if type == .leftMouseDown { input.mouseDown(with: event) }
            else { input.mouseUp(with: event) }
        }
    }

    func gesture(from start: CGPoint, to end: CGPoint, size: CGSize,
                 preview: CGPoint? = nil, sendsPreview: Bool = true,
                 cancel: Bool = false, beforeRelease: (() -> Void)? = nil) async throws {
        let input = try receiver(at: start)
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type,
                location: input.convert(point, to: nil), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
        }
        input.mouseDown(with: try event(.leftMouseDown, start))
        try await Task.sleep(for: .milliseconds(500))
        if sendsPreview { input.mouseDragged(with: try event(.leftMouseDragged, preview ?? end)) }
        if cancel { input.cancelOperation(nil) }
        if let beforeRelease {
            beforeRelease()
            try await Task.sleep(for: .milliseconds(200))
        }
        input.mouseUp(with: try event(.leftMouseUp, end))
        try await Task.sleep(for: .milliseconds(500))
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)), arguments: ViewportObjectHandlePressCase.allCases, [false, true])
func authoredMeshHandlesCommitThroughNativeInput(pressCase: ViewportObjectHandlePressCase, keepsCADModeling: Bool) async throws {
    let fixture = try ObjectHandlePressFixture(pressCase: pressCase)
    let item = try #require(fixture.scene.items.first { $0.sceneNodeID == fixture.target.sceneNodeID })
    guard case .body(let component) = item.kind else { Issue.record("Expected fixture body."); return }
    let bodyMesh = try #require(component.mesh)
    var builder = MeshSourceBuilder()
    let vertices = try bodyMesh.positions.map {
        try builder.addVertex(GeometryPoint3D(x: $0.x, y: $0.y, z: $0.z))
    }
    for offset in stride(from: 0, to: bodyMesh.indices.count, by: 3) {
        _ = try builder.addFace(vertexIDs: (0..<3).map { vertices[Int(bodyMesh.indices[offset + $0])] })
    }
    let mesh = try builder.build()
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    var document = fixture.document
    document.authoredMeshAssets[asset.id] = asset
    if keepsCADModeling {
        var object = try #require(document.productMetadata.sceneNodes[fixture.target.sceneNodeID]?.object)
        object.geometryRepresentations.representations["mesh"] = .init(id: "mesh", source: .authoredMesh(asset.id))
        object.geometryRepresentations.selection?.presentation = "mesh"
        document.productMetadata.sceneNodes[fixture.target.sceneNodeID]?.object = object
    } else {
        document.productMetadata.sceneNodes[fixture.target.sceneNodeID]?.reference = .authoredMesh(asset.id)
        document.productMetadata.sceneNodes[fixture.target.sceneNodeID]?.object = ObjectDescriptor(
            category: .body, geometryRole: .mesh, geometryRepresentations: .init(
                representations: ["mesh": .init(id: "mesh", source: .authoredMesh(asset.id))],
                selection: .init(modeling: "mesh", presentation: "mesh")))
    }
    let copyID = try document.productMetadata.appendSceneNodeToFirstRoot(name: "Unselected Mesh Copy",
        reference: .authoredMesh(asset.id), object: ObjectDescriptor(
            category: .body, geometryRole: .mesh, geometryRepresentations: .init(
                representations: ["mesh": .init(id: "mesh", source: .authoredMesh(asset.id))],
                selection: .init(modeling: "mesh", presentation: "mesh"))))
    let controller = try ProjectController(document: document,
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(), projector: DesignDocumentProjectBridge())
    let workspace = ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()
    if pressCase == .translateX, !keepsCADModeling {
        var raw = ViewportSpatialOverlayProducer.SurfaceTransformAffordanceSource.RawInput(
            document: document, scene: .init(items: []), selection: fixture.selection,
            ruler: fixture.ruler, enabledRoutes: [.bodyTransform])
        raw.presentationScene = snapshot.viewport
        raw.presentationNodeIDs = snapshot.sceneNodeIDByOccurrenceID
        let selected = try #require(snapshot.viewport.items.first {
            snapshot.sceneNodeID(for: $0.occurrenceID) == fixture.target.sceneNodeID
        })
        let mutation = try ViewportWorldTransformAlgebra.translation(Vector3D(x: 0.25, y: 0, z: 0))
        raw.bodyPreviewTransforms[selected.occurrenceID.rawValue] = mutation
        var records: [ViewportSpatialInteractionRecord] = []
        let source = try #require(try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: raw, interactionRecords: &records, checkpoint: { _, _, _ in }))
        // The mounted surface owns solid previews; affordances must not
        // duplicate the object as a wire mesh.
        #expect(source.meshes.isEmpty)
        #expect(source.worldLines.filter { $0.route == .bodyTransform }.isEmpty)
        #expect(source.cameraLines.filter { $0.route == .bodyTransform }.allSatisfy {
            $0.objectPreviewOccurrenceID == selected.occurrenceID.rawValue
        })
        #expect(source.markers.filter { $0.route == .bodyTransform }.allSatisfy {
            $0.objectPreviewOccurrenceID == selected.occurrenceID.rawValue
        })
        #expect(!records.isEmpty)
    }
    var commits: [ViewportBodyPlacementDragTarget] = []
    var canvasDrags = 0
    let mounted = try await MountedObjectHandleViewport(fixture: fixture, presentation: snapshot,
        allowsObjectAffordances: false, onPick: { _ in }, onCanvasDrag: { _ in canvasDrags += 1 },
        onBodyPlacementCommit: { commits.append(contentsOf: $0) })
    defer { mounted.close() }
    let deadline = ContinuousClock.now.advanced(by: .seconds(20))
    while commits.isEmpty, ContinuousClock.now < deadline {
        try await mounted.gesture(from: fixture.press, to: fixture.dragEnd, size: fixture.size)
    }
    let target = try #require(commits.last, "Mesh handle must commit without exact CAD affordance permission.")
    #expect(target.reference == document.productMetadata.sceneNodes[fixture.target.sceneNodeID]?.reference)
    #expect((target.featureID != nil) == keepsCADModeling)
    #expect(target.localTransform != target.baseLocalTransform)
    if let axis = pressCase.committedAxis {
        let delta = try translationDelta(of: target)
        for other in ViewportCoordinateAxis.allCases {
            if other == axis { #expect(abs(delta[other] ?? 0) > 1e-9) }
            else { #expect(abs(delta[other] ?? 0) < 1e-9) }
        }
    }
    commits.removeAll(); canvasDrags = 0
    try await mounted.gesture(from: fixture.press, to: fixture.dragEnd, size: fixture.size, cancel: true)
    #expect(commits.isEmpty && canvasDrags == 0)
    try target.validate(in: snapshot.document.document)
    let action = try DefaultProjectWorkspaceActionPlanner().source(name: "Mesh Placement", commands: [
        .setSceneNodeTransform(id: target.sceneNodeID, localTransform: target.localTransform)
    ], from: snapshot)
    _ = try await workspace.perform(action)
    let changed = try #require(workspace.view)
    #expect(changed.document.document.authoredMeshAssets[asset.id] == asset)
    #expect(changed.document.document.productMetadata.sceneNodes[target.sceneNodeID]?.localTransform == target.localTransform)
    #expect(changed.document.document.productMetadata.sceneNodes[copyID] == document.productMetadata.sceneNodes[copyID])
    #expect(throws: EditorError.self) { try target.validate(in: changed.document.document) }
    let undone = try await workspace.undo()
    #expect(undone.document.document.productMetadata == document.productMetadata)
    let redone = try await workspace.redo()
    #expect(redone.document.document.productMetadata == changed.document.document.productMetadata)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func boxFaceAndCornerHandlesReachSourceResizeWithoutPlacementFallback() async throws {
    let fixture = try ObjectHandlePressFixture(pressCase: .translateX)
    let workspace = ProjectWorkspace(project: try ProjectController(document: fixture.document,
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(), projector: DesignDocumentProjectBridge()))
    let snapshot = try await workspace.evaluate()
    var raw = ViewportSpatialOverlayProducer.SurfaceTransformAffordanceSource.RawInput(
        document: fixture.document, scene: .init(items: []), selection: fixture.selection,
        ruler: fixture.ruler, enabledRoutes: [.bodyTransform], interactiveRoutes: [.bodyTransform])
    raw.presentationScene = snapshot.viewport
    raw.presentationNodeIDs = snapshot.sceneNodeIDByOccurrenceID
    raw.allowsBodyResize = true
    var records: [ViewportSpatialInteractionRecord] = []
    let source = try #require(try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
        from: raw, interactionRecords: &records, checkpoint: { _, _, _ in }))
    let resizeRecords = records.filter {
        guard case .objectTransform(let action, _, _) = $0.target else { return false }
        switch action { case .faceMove, .vertexMove: return true; default: return false }
    }
    #expect(resizeRecords.count == 14)
    #expect(source.markers.filter { if case .cone = $0.shape { true } else { false } }.count == 3)
    var resizes: [ViewportBodyResizeDragTarget] = []
    var placements = 0
    var canvas = 0
    let mounted = try await MountedObjectHandleViewport(fixture: fixture, presentation: snapshot,
        onPick: { _ in }, onCanvasDrag: { _ in canvas += 1 }, onBodyPlacementCommit: { _ in placements += 1 },
        onBodyResizeCommit: { resizes.append($0) })
    defer { mounted.close() }
    let layout = ViewportSceneContext(ruler: fixture.ruler, scene: fixture.scene, size: fixture.size,
        camera: fixture.control.camera, basis: fixture.control.basis,
        fittingInsets: ViewportCanvasChromeLayout(viewportSize: fixture.size,
            viewportBadgeWidth: ViewportCanvasChromeLayout.maximumViewportBadgeWidth).fittingInsets).layout
    for action: ViewportAffordanceAction in [.faceMove(.right), .vertexMove(.frontBottomRight)] {
        let marker = try #require(source.markers.first {
            guard case .objectTransform(_, let value) = $0.identity else { return false }
            return value == action
        })
        let start = try #require(layout.projectedPoint(marker.anchor)?.point)
        let end = CGPoint(x: start.x + 12, y: start.y + 8)
        let count = resizes.count
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while resizes.count == count, ContinuousClock.now < deadline {
            try await mounted.gesture(from: start, to: end, size: fixture.size)
        }
        #expect(resizes.count > count, "The actual mounted face/corner must reach the source resize callback.")
        let after = resizes.count
        try await mounted.gesture(from: start, to: end, size: fixture.size, cancel: true)
        #expect(resizes.count == after)
    }
    #expect(placements == 0 && canvas == 0)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func cadPresentationPlacementUsesNativeInputAndRejectsIncompleteSelections() async throws {
    let fixture = try ObjectHandlePressFixture(pressCase: .translateY)
    let controller = try ProjectController(document: fixture.document,
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(), projector: DesignDocumentProjectBridge())
    let workspace = ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()
    func source(document: DesignDocument, selection: SelectionModel) -> ViewportSpatialOverlayProducer.SurfaceTransformAffordanceSource.RawInput {
        var input = ViewportSpatialOverlayProducer.SurfaceTransformAffordanceSource.RawInput(
            document: document, scene: .init(items: []), selection: selection,
            ruler: fixture.ruler, enabledRoutes: [.bodyTransform])
        input.presentationScene = snapshot.viewport
        input.presentationNodeIDs = snapshot.sceneNodeIDByOccurrenceID
        return input
    }
    let valid = source(document: fixture.document, selection: fixture.selection)
    #expect(try ViewportSpatialOverlayProducer.presentationTransformMembers(input: valid)?.count == 1)
    var missing = valid
    missing.presentationNodeIDs = [:]
    #expect(try ViewportSpatialOverlayProducer.presentationTransformMembers(input: missing) == nil)
    var lockedDocument = fixture.document
    lockedDocument.productMetadata.sceneNodes[fixture.target.sceneNodeID]?.isLocked = true
    #expect(try ViewportSpatialOverlayProducer.presentationTransformMembers(
        input: source(document: lockedDocument, selection: fixture.selection)) == nil)
    let incomplete = SelectionModel(selectedTargets: [fixture.target, .init(sceneNodeID: SceneNodeID(), component: .object)])
    #expect(try ViewportSpatialOverlayProducer.presentationTransformMembers(
        input: source(document: fixture.document, selection: incomplete)) == nil)
    var commits: [ViewportBodyPlacementDragTarget] = []
    let mounted = try await MountedObjectHandleViewport(fixture: fixture, presentation: snapshot,
        onPick: { _ in }, onCanvasDrag: { _ in }, onBodyPlacementCommit: { commits.append(contentsOf: $0) })
    defer { mounted.close() }
    let deadline = ContinuousClock.now.advanced(by: .seconds(20))
    while commits.isEmpty, ContinuousClock.now < deadline {
        try await mounted.gesture(from: fixture.press, to: fixture.dragEnd, size: fixture.size)
    }
    let committed = try #require(commits.last)
    let delta = try translationDelta(of: committed)
    #expect(abs(delta[.y] ?? 0) > 1e-9)
    #expect(abs(delta[.x] ?? 0) < 1e-9)
    #expect(abs(delta[.z] ?? 0) < 1e-9)
    try committed.validate(in: fixture.document)
}

/// The world translation a committed placement adds, read out of the two
/// frames the gesture handed over. The fixture body's scene node sits at the
/// document root, so its local frame is its world frame and the difference of
/// the two translation columns is the world motion the pointer described.
@MainActor
private func translationDelta(
    of target: ViewportBodyPlacementDragTarget
) throws -> [ViewportCoordinateAxis: Double] {
    let base = target.baseLocalTransform.matrix.values
    let next = target.localTransform.matrix.values
    guard base.count == 16, next.count == 16 else {
        throw ObjectAffordancePressFixtureError(
            message: "A committed placement frame is not a 4x4 matrix."
        )
    }
    return [.x: next[3] - base[3], .y: next[7] - base[7], .z: next[11] - base[11]]
}

/// The mounted tests retain a hidden native hierarchy and deliver events to
/// its hit-tested receiver; they never post input to the user's desktop.
@Suite(.serialized)
@MainActor
struct ViewportNativeObjectAffordancePressTests {
    @Test(.timeLimit(.minutes(1)), arguments: [ViewportObjectHandlePressCase.centerScaleX, .centerScaleY, .centerScaleZ])
    func innerMarkerOverlappingShaftKeepsCenterAndMovesBothSurfaces(
        pressCase: ViewportObjectHandlePressCase
    ) async throws {
        let fixture = try ObjectHandlePressFixture(pressCase: pressCase)
        let item = try #require(fixture.scene.items.first { $0.sceneNodeID == fixture.target.sceneNodeID })
        let edit = ViewportObjectEditState(item: item)
        let center = edit.worldPoint(edit.centerPoint)
        let axis: Vector3D = switch pressCase {
        case .centerScaleY: .init(x: 0, y: 1, z: 0)
        case .centerScaleZ: .init(x: 0, y: 0, z: 1)
        default: .init(x: 1, y: 0, z: 0)
        }
        var commits: [ViewportBodyPlacementDragTarget] = []
        let mounted = try await MountedObjectHandleViewport(fixture: fixture,
            onPick: { _ in }, onCanvasDrag: { _ in },
            onBodyPlacementCommit: { commits.append(contentsOf: $0) })
        defer { mounted.close() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while commits.isEmpty, ContinuousClock.now < deadline {
            try await mounted.gesture(from: fixture.translateStation,
                to: fixture.translateStationDragEnd, size: fixture.size)
        }
        try #require(!commits.isEmpty, "The translation control must establish native input readiness.")
        let dx = (fixture.dragEnd.x - fixture.press.x) / ObjectHandlePressFixture.dragPoints
        let dy = (fixture.dragEnd.y - fixture.press.y) / ObjectHandlePressFixture.dragPoints
        // Undo the fixture's off-shaft offset: these presses deliberately hit
        // both the marker and its translation shaft, including the visible center.
        for offset: CGFloat in [0, -3, 3] {
            commits.removeAll()
            let start = CGPoint(x: fixture.press.x + dy * ObjectHandlePressFixture.markerOffsetPoints + dx * offset,
                                y: fixture.press.y - dx * ObjectHandlePressFixture.markerOffsetPoints + dy * offset)
            let end = CGPoint(x: start.x + dx * 24, y: start.y + dy * 24)
            try await mounted.gesture(from: start, to: end, size: fixture.size)
            try #require(commits.count == 1)
            let target = try #require(commits.first)
            let baseWorld = try ViewportWorldTransformAlgebra.multiplied(target.baseParentWorldTransform, target.baseLocalTransform)
            let nextWorld = try ViewportWorldTransformAlgebra.multiplied(target.baseParentWorldTransform, target.localTransform)
            let mutation = try ViewportWorldTransformAlgebra.multiplied(nextWorld, ViewportWorldTransformAlgebra.inverted(baseWorld))
            #expect(try (ViewportWorldTransformAlgebra.transformedPoint(center, by: mutation) - center).length < 1e-7)
            let low = center + axis * -1
            let high = center + axis
            let lowDelta = try ViewportWorldTransformAlgebra.transformedPoint(low, by: mutation) - low
            let highDelta = try ViewportWorldTransformAlgebra.transformedPoint(high, by: mutation) - high
            #expect(highDelta.dot(axis) > 1e-7)
            #expect((lowDelta + highDelta).length < 1e-7)
            #expect(highDelta.cross(axis).length < 1e-7)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func releasedHandleWaitsForPublicationAndRecovers(fails: Bool) async throws {
        let fixture = try ObjectHandlePressFixture(pressCase: .translateY)
        let released = Mutex(false)
        var commits = 0
        let mounted = try await MountedObjectHandleViewport(
            fixture: fixture, onPick: { _ in }, onCanvasDrag: { _ in },
            onBodyPlacementCommit: { _ in commits += 1 }, commitCompletion: {
                let deadline = ContinuousClock.now.advanced(by: .seconds(5))
                while !released.withLock({ $0 }), ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(1))
                }
                try #require(released.withLock { $0 })
                if fails { throw ObjectAffordancePressFixtureError(message: "Rejected placement.") }
                return .document(id: fixture.document.id, generation: DocumentGeneration(1))
            })
        defer { released.withLock { $0 = true }; mounted.close() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while commits == 0, ContinuousClock.now < deadline {
            try await mounted.gesture(from: fixture.press, to: fixture.dragEnd, size: fixture.size)
        }
        try #require(commits == 1)
        // Release has returned, but the source owner has not acknowledged it.
        try await mounted.gesture(from: fixture.press, to: fixture.dragEnd, size: fixture.size)
        #expect(commits == 1)
        released.withLock { $0 = true }
        try await Task.sleep(for: .milliseconds(200))
        try await mounted.gesture(from: fixture.press, to: fixture.dragEnd, size: fixture.size)
        #expect(commits == 2)
        #expect(!mounted.window.isVisible && !mounted.window.isKeyWindow)
    }

    @Test(.timeLimit(.minutes(1)))
    func escapeConsumesSelectionRectangleAndNextRectangleStillCommits() async throws {
        let fixture = try ObjectHandlePressFixture(pressCase: .translateY)
        var selections = 0
        let mounted = try await MountedObjectHandleViewport(fixture: fixture,
            onSelectionDrag: { _ in selections += 1 }, onPick: { _ in },
            onCanvasDrag: { _ in Issue.record("Selection rectangle escaped to canvas creation.") },
            onBodyPlacementCommit: { _ in Issue.record("Selection rectangle changed a body.") })
        defer { mounted.close() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while selections == 0, ContinuousClock.now < deadline {
            try await mounted.gesture(from: fixture.emptyPoint, to: fixture.emptyDragEnd, size: fixture.size)
        }
        try #require(selections > 0)
        selections = 0
        try await mounted.gesture(from: fixture.emptyPoint, to: fixture.emptyDragEnd, size: fixture.size, cancel: true)
        #expect(selections == 0)
        try await mounted.gesture(from: fixture.emptyPoint, to: fixture.emptyDragEnd, size: fixture.size)
        #expect(selections == 1)
    }

    @Test(.timeLimit(.minutes(1)), arguments: MountedObjectHandleViewport.Invalidation.allCases)
    private func invalidatedGestureCannotCommit(reason: MountedObjectHandleViewport.Invalidation) async throws {
        let fixture = try ObjectHandlePressFixture(pressCase: .translateY)
        var moves = 0
        var canvasDrags = 0
        let mounted = try await MountedObjectHandleViewport(fixture: fixture, onPick: { _ in },
            onCanvasDrag: { _ in canvasDrags += 1 }, onBodyPlacementCommit: { _ in moves += 1 })
        defer { mounted.close() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while moves == 0, ContinuousClock.now < deadline {
            try await mounted.gesture(from: fixture.press, to: fixture.dragEnd, size: fixture.size)
        }
        try #require(moves > 0)
        moves = 0
        canvasDrags = 0
        try await mounted.gesture(from: fixture.press, to: fixture.dragEnd, size: fixture.size,
                                  beforeRelease: { mounted.invalidate(reason) })
        #expect(moves == 0)
        #expect(canvasDrags == 0)
        try await mounted.gesture(from: fixture.emptyPoint, to: fixture.emptyDragEnd, size: fixture.size)
        #expect(canvasDrags == 1, "Cancellation must release ownership for the next gesture.")
    }

    /// Every drawn transform station commits through real AppKit input.
    @Test(.timeLimit(.minutes(3)), arguments: ViewportObjectHandlePressCase.allCases)
    func objectHandleGestureFollowsItsCommitContract(
        pressCase: ViewportObjectHandlePressCase
    ) async throws {
        let fixture = try ObjectHandlePressFixture(pressCase: pressCase)
        var canvasDrags = 0
        var bodyMoves: [ViewportBodyPlacementDragTarget] = []
        let mounted = try await MountedObjectHandleViewport(
            fixture: fixture,
            onPick: { _ in },
            onCanvasDrag: { _ in canvasDrags += 1 },
            onBodyPlacementCommit: { bodyMoves.append(contentsOf: $0) }
        )
        // Closing an already closed window is a no-op, so the explicit close
        // before the gate control coexists with the throw-path cleanup.
        defer { mounted.close() }

        let readinessDeadline = ContinuousClock.now.advanced(by: .seconds(20))
        while canvasDrags == 0, ContinuousClock.now < readinessDeadline {
            try mounted.click(at: fixture.emptyPoint, size: fixture.size)
            try await mounted.gesture(
                from: fixture.emptyPoint, to: fixture.emptyDragEnd, size: fixture.size
            )
        }
        try #require(canvasDrags > 0, "The mounted viewport never answered an empty canvas drag.")

        canvasDrags = 0
        bodyMoves.removeAll()
        let controlDeadline = ContinuousClock.now.advanced(by: .seconds(20))
        while bodyMoves.isEmpty, ContinuousClock.now < controlDeadline {
            try await mounted.gesture(
                from: fixture.translateStation,
                to: fixture.translateStationDragEnd,
                size: fixture.size
            )
        }
        try #require(
            !bodyMoves.isEmpty,
            "The mounted frame never committed the translate(.x) control station."
        )
        #expect(canvasDrags == 0, "The translate(.x) control station reached the canvas owner.")

        canvasDrags = 0
        bodyMoves.removeAll()
        try await mounted.gesture(from: fixture.press, to: fixture.dragEnd, size: fixture.size)
        let report = Comment(
            rawValue: "\(pressCase.handleName) at \(fixture.press) produced "
                + "\(canvasDrags) canvas drags and \(bodyMoves.count) body moves."
        )
            try #require(bodyMoves.count == 1, report)
            let committed = try #require(bodyMoves.first, report)
            #expect(committed.localTransform != committed.baseLocalTransform, report)
            if let axis = pressCase.committedAxis {
            let moved = try translationDelta(of: committed)
            // The drag moves along one arrow, so the committed frame has to
            // move the body along that world axis and leave the other two
            // where they were. A frame that moved on a different axis is the
            // defect this case exists to catch.
            for candidate in ViewportCoordinateAxis.allCases {
                let component = moved[candidate] ?? 0
                if candidate == axis {
                    #expect(abs(component) > 1.0e-9, report)
                } else {
                    #expect(abs(component) <= 1.0e-9, report)
                }
            }
            }
            #expect(committed.sceneNodeID == fixture.target.sceneNodeID, report)
        #expect(canvasDrags == 0, report)

        let expected = try #require(bodyMoves.first).localTransform
        bodyMoves.removeAll()
        try await mounted.gesture(from: fixture.press, to: fixture.dragEnd, size: fixture.size,
                                  sendsPreview: false)
        #expect(bodyMoves.count == 1)
        #expect(bodyMoves.first?.localTransform == expected)

        bodyMoves.removeAll()
        let halfway = CGPoint(x: (fixture.press.x + fixture.dragEnd.x) / 2,
                              y: (fixture.press.y + fixture.dragEnd.y) / 2)
        try await mounted.gesture(from: fixture.press, to: fixture.dragEnd, size: fixture.size,
                                  preview: halfway)
        #expect(bodyMoves.count == 1)
        #expect(bodyMoves.first?.localTransform == expected,
                "Release must be measured independently of the last preview.")

        bodyMoves.removeAll()
        try await mounted.gesture(from: fixture.press, to: fixture.dragEnd, size: fixture.size,
                                  cancel: true)
        #expect(bodyMoves.isEmpty, "Escape must consume the body release.")
        #expect(canvasDrags == 0)
        try await mounted.gesture(from: fixture.emptyPoint, to: fixture.emptyDragEnd,
                                  size: fixture.size, cancel: true)
        #expect(canvasDrags == 0, "Escape must consume an ordinary canvas release.")

        // The fixture is still live, so the silence above is the affordance
        // route claiming the press rather than a viewport that stopped
        // answering.
        canvasDrags = 0
        let closingMoves = bodyMoves.count
        try await mounted.gesture(
            from: fixture.emptyPoint, to: fixture.emptyDragEnd, size: fixture.size
        )
        #expect(canvasDrags == 1, "The closing empty drag did not reach the canvas owner.")
        #expect(bodyMoves.count == closingMoves, "The closing empty drag committed a body move.")

        // The silence above has to be the gizmo claiming the press rather than a
        // point the canvas owner could not solve anyway. `allowsObjectAffordances`
        // is the one gate that makes the body transform route interactive, so the
        // same document, camera, selection, and point with the gate closed must
        // reach the canvas owner instead.
        mounted.close()
        var ungatedCanvasDrags = 0
        let ungated = try await MountedObjectHandleViewport(
            fixture: fixture,
            allowsObjectAffordances: false,
            onPick: { _ in },
            onCanvasDrag: { _ in ungatedCanvasDrags += 1 },
            onBodyPlacementCommit: { _ in Issue.record("A closed gate committed a body move.") }
        )
        defer { ungated.close() }
        let ungatedDeadline = ContinuousClock.now.advanced(by: .seconds(20))
        while ungatedCanvasDrags == 0, ContinuousClock.now < ungatedDeadline {
            try await ungated.gesture(
                from: fixture.press, to: fixture.dragEnd, size: fixture.size
            )
        }
        #expect(
            ungatedCanvasDrags > 0,
            Comment(
                rawValue: "With the object-affordance gate closed, \(pressCase.handleName)'s "
                    + "station never reached the canvas owner, so its silence under the open "
                    + "gate is not attributable to the gizmo."
            )
        )
    }
}
