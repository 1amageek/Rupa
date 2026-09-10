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

/// The selected CAD face's exact world point must come from the mounted frame.
///
/// The box is viewed along its extrusion axis, so an interior pixel of its
/// projected silhouette is drawn by the near face and covers the far one. A CPU
/// ray/polygon resolver answers that pixel for either face because it never
/// consults occlusion; the mounted frame answers it only for the face it drew.
/// Selecting the far face and pressing that pixel therefore separates the two
/// suppliers on both the press and the drag routes.
///
/// The pixel is offset from the silhouette centroid. Sweeping the silhouette a
/// pixel at a time showed the centroid to be the single interior pixel the
/// mounted frame leaves unanswered; every other interior pixel answers. That
/// gap belongs to the mounted frame's raycast, not to the suppliers compared
/// here, so the fixture presses beside it.
@MainActor
@Test(.timeLimit(.minutes(2)), arguments: [ViewportCameraProjection.parallel, .standardPerspective])
func viewportSelectedCADFaceExactPointComesFromMountedFrame(
    projection: ViewportCameraProjection
) async throws {
    _ = NSApplication.shared
    let fixture = try nativeCADFaceFixture()
    let control = ViewportControlSession(camera: .init(projection: projection), basis: .axisFront(.z))
    let size = CGSize(width: 800, height: 600)
    // The layout only locates a deterministic pointer fixture; it mirrors the
    // production scene context so the pixel lands where the mounted frame draws.
    let layout = ViewportSceneContext(
        ruler: fixture.ruler,
        scene: fixture.cpuScene,
        size: size,
        camera: control.camera,
        basis: .axisFront(.z),
        geometryBoundsSource: .geometry(fixture.presentationScene.worldBounds),
        fittingInsets: ViewportCanvasChromeLayout(
            viewportSize: size,
            viewportBadgeWidth: ViewportCanvasChromeLayout.maximumViewportBadgeWidth
        ).fittingInsets
    ).layout
    var projected: [CGPoint] = []
    for face in fixture.topology.faces {
        for point in nativeCADFaceWorldPolygon(face, transform: fixture.modelTransform) {
            if let screen = layout.projectedPoint(point)?.point {
                projected.append(screen)
            }
        }
    }
    let minX = try #require(projected.map(\.x).min())
    let maxX = try #require(projected.map(\.x).max())
    let minY = try #require(projected.map(\.y).min())
    let maxY = try #require(projected.map(\.y).max())
    let press = CGPoint(
        x: minX + (maxX - minX) * 0.37,
        y: minY + (maxY - minY) * 0.29
    )
    let span = min(maxX - minX, maxY - minY)
    #expect(span > 0)
    let dragEnd = CGPoint(x: press.x + span * 0.1, y: press.y + span * 0.1)

    let unselected = try await probeNativeCADFace(
        fixture: fixture, control: control, size: size,
        selection: .empty, press: press, dragEnd: dragEnd
    )
    #expect(unselected.target.modelWorldPoint == nil)
    let nearHit = try #require(
        unselected.target.hit,
        """
        The mounted frame named no element at \(press). \
        Projected silhouette x \(minX)...\(maxX), y \(minY)...\(maxY), span \(span).
        """
    )
    let nearComponent = try #require(nearHit.selectionComponent)
    guard case .face(let nearComponentID) = nearComponent else {
        Issue.record("The mounted frame named \(nearComponent) at \(press) instead of a face.")
        return
    }
    #expect(nearComponentID.generatedTopologySubshapeID != nil)

    let nearFace = try #require(fixture.topology.faces.first { $0.componentID == nearComponentID })
    let nearPolygon = nativeCADFaceWorldPolygon(nearFace, transform: fixture.modelTransform)
    let nearNormal = try #require(nativeCADFacePolygonNormal(nearPolygon))
    let opposites = fixture.topology.faces.filter { face in
        guard face.componentID != nearComponentID,
              let normal = nativeCADFacePolygonNormal(
                  nativeCADFaceWorldPolygon(face, transform: fixture.modelTransform)
              ) else { return false }
        let alignment = normal.x * nearNormal.x + normal.y * nearNormal.y + normal.z * nearNormal.z
        return abs(alignment) > 0.99
    }
    #expect(opposites.count == 1)
    let farFace = try #require(opposites.first, "The body has no face parallel to the drawn one.")
    let farPolygon = nativeCADFaceWorldPolygon(farFace, transform: fixture.modelTransform)
    let nearOrigin = try #require(nearPolygon.first)
    let farOrigin = try #require(farPolygon.first)
    let separation = abs(
        (farOrigin.x - nearOrigin.x) * nearNormal.x
            + (farOrigin.y - nearOrigin.y) * nearNormal.y
            + (farOrigin.z - nearOrigin.z) * nearNormal.z
    )
    #expect(separation > 0)

    let far = try await probeNativeCADFace(
        fixture: fixture, control: control, size: size,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: fixture.bodySceneNodeID, component: .face(farFace.componentID))
        ]),
        press: press, dragEnd: dragEnd
    )
    #expect(
        far.target.modelWorldPoint == nil,
        "An occluded selected face must have no exact point: \(String(describing: far.target.modelWorldPoint))"
    )
    #expect(far.drag.startWorldPoint == nil)
    #expect(far.drag.endWorldPoint == nil)

    let near = try await probeNativeCADFace(
        fixture: fixture, control: control, size: size,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: fixture.bodySceneNodeID, component: .face(nearComponentID))
        ]),
        press: press, dragEnd: dragEnd
    )
    let exact = try #require(near.target.modelWorldPoint, "The drawn selected face must answer with its surface point.")
    let offset = abs(
        (exact.x - nearOrigin.x) * nearNormal.x
            + (exact.y - nearOrigin.y) * nearNormal.y
            + (exact.z - nearOrigin.z) * nearNormal.z
    )
    #expect(offset < separation * 0.05)
    #expect(near.drag.startWorldPoint != nil)
    #expect(near.drag.endWorldPoint != nil)
}

private struct NativeCADFaceFixture {
    let document: DesignDocument
    let presentationScene: UniversalViewportScene
    let sceneNodeIDByOccurrenceID: [SceneOccurrenceID: SceneNodeID]
    let currentEvaluation: DocumentEvaluationContext
    let generation: DocumentGeneration
    let ruler: RulerConfiguration
    let cpuScene: ViewportScene
    let bodySceneNodeID: SceneNodeID
    let topology: ViewportBodyTopology
    let modelTransform: Transform3D
}

private enum NativeCADFaceFixtureError: Error {
    case missingTopology
}

/// The production pairing: a document-identified viewport supplied with the
/// bridge's presentation scene and the same evaluation `MainView` hands it.
@MainActor
private func nativeCADFaceFixture() throws -> NativeCADFaceFixture {
    let session = EditorSession()
    _ = session.createDefaultExtrudedRectangle()
    let currentEvaluation = try #require(session.currentEvaluation)
    let document = session.document
    let projection = try DesignDocumentProjectBridge().projection(for: document)
    let evaluator = try DefaultDesignDocumentProjectEvaluatorFactory().makeEvaluator(
        for: document,
        reusing: currentEvaluation
    )
    let snapshot = try evaluator.evaluate(
        project: projection.source,
        purpose: .presentation,
        revision: session.transactionRevision
    )
    let presentationScene = try UniversalViewportSceneBuilder().build(
        from: snapshot,
        project: projection.source
    )
    let ruler = RulerConfiguration.standard(for: .millimeter)
    let cpuScene = ViewportSceneBuilder().build(
        document: document,
        ruler: ruler,
        currentEvaluation: currentEvaluation,
        documentGeneration: session.generation,
        evaluationPolicy: .suppliedOnly
    )
    let bodyItem = try #require(
        cpuScene.items.first { item in
            guard case .body(let component) = item.kind else { return false }
            return component.topology?.meshFaceRuns.isEmpty == false
        },
        "The supplied scene carries no CAD body with prepared mesh face runs."
    )
    guard case .body(let component) = bodyItem.kind, let topology = component.topology else {
        throw NativeCADFaceFixtureError.missingTopology
    }
    let bodySceneNodeID = try #require(bodyItem.sceneNodeID)
    #expect(projection.sceneNodeIDByOccurrenceID.values.contains(bodySceneNodeID))
    return NativeCADFaceFixture(
        document: document,
        presentationScene: presentationScene,
        sceneNodeIDByOccurrenceID: projection.sceneNodeIDByOccurrenceID,
        currentEvaluation: currentEvaluation,
        generation: session.generation,
        ruler: ruler,
        cpuScene: cpuScene,
        bodySceneNodeID: bodySceneNodeID,
        topology: topology,
        modelTransform: bodyItem.modelTransform
    )
}

@MainActor
private func probeNativeCADFace(
    fixture: NativeCADFaceFixture,
    control: ViewportControlSession,
    size: CGSize,
    selection: SelectionModel,
    press: CGPoint,
    dragEnd: CGPoint
) async throws -> (target: ViewportCanvasTarget, drag: ViewportModelDrag) {
    var picks: [ViewportCanvasTarget] = []
    var drags: [ViewportModelDrag] = []
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
        selectionHitPolicy: .face,
        allowsObjectAffordances: false,
        presentationCADInteractionSceneNodeIDs: [fixture.bodySceneNodeID],
        selectedPresentationHasExactCADContext: true,
        onPick: { picks.append($0) },
        onCanvasDrag: { drags.append($0) }
    ).frame(width: size.width, height: size.height)
    let controller = NSHostingController(rootView: viewport)
    let window = NSWindow(
        contentRect: CGRect(origin: .zero, size: size),
        styleMask: [.titled], backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    window.orderFront(nil)
    defer { window.contentViewController = nil; window.close() }
    func input(in view: NSView) -> ViewportInputSurface.InputView? {
        if let value = view as? ViewportInputSurface.InputView { return value }
        for child in view.subviews {
            if let value = input(in: child) { return value }
        }
        return nil
    }
    let pickDeadline = ContinuousClock.now.advanced(by: .seconds(10))
    while picks.isEmpty, ContinuousClock.now < pickDeadline {
        input(in: controller.view)?.onPick?(press, size, .replace)
        try await Task.sleep(for: .milliseconds(20))
    }
    let target = try #require(picks.first, "The mounted frame never answered the press at \(press).")
    let dragDeadline = ContinuousClock.now.advanced(by: .seconds(10))
    while drags.isEmpty, ContinuousClock.now < dragDeadline {
        input(in: controller.view)?.onCanvasDrag?(press, dragEnd, size, .replace)
        try await Task.sleep(for: .milliseconds(20))
    }
    let drag = try #require(drags.first, "The mounted frame never answered the drag to \(dragEnd).")
    return (target, drag)
}

private func nativeCADFaceWorldPolygon(
    _ face: ViewportBodyTopology.Face,
    transform: Transform3D
) -> [Point3D] {
    face.points.map { ViewportLayout.transformedPoint($0, by: transform) }
}

/// Newell's method, so a non-planar or reversed loop still yields a usable normal.
private func nativeCADFacePolygonNormal(_ points: [Point3D]) -> (x: Double, y: Double, z: Double)? {
    guard points.count >= 3 else { return nil }
    var x = 0.0
    var y = 0.0
    var z = 0.0
    for index in points.indices {
        let current = points[index]
        let next = points[(index + 1) % points.count]
        x += (current.y - next.y) * (current.z + next.z)
        y += (current.z - next.z) * (current.x + next.x)
        z += (current.x - next.x) * (current.y + next.y)
    }
    let length = (x * x + y * y + z * z).squareRoot()
    guard length.isFinite, length > 1.0e-12 else { return nil }
    return (x / length, y / length, z / length)
}
