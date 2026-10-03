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

// MARK: - Pure rules

@Test func coincidentCandidatesTieOnlyAsNearVerticesOrEdges() {
    let edge = ViewportNativeHitCandidate(rank: .edge, metric: 2.4)
    #expect(edge.ties(with: ViewportNativeHitCandidate(rank: .edge, metric: 2.4 + 0.9)))
    #expect(edge.ties(with: ViewportNativeHitCandidate(rank: .edge, metric: 2.4 + 1.5)) == false)
    #expect(edge.ties(with: ViewportNativeHitCandidate(rank: .vertex, metric: 2.4)) == false)
    // A face's metric is a depth, never a distance to the pointer, so faces do not tie.
    let face = ViewportNativeHitCandidate(rank: .face, metric: 1.0)
    #expect(face.ties(with: ViewportNativeHitCandidate(rank: .face, metric: 1.0)) == false)
}

@Test func coincidentPickMenuNamesEachEdgeByItsObjectAndDeliversTheChosenOne() throws {
    let (first, second) = (SceneNodeID(), SceneNodeID())
    let feature = FeatureID()
    func edgeHit(_ node: SceneNodeID) -> ViewportHit {
        ViewportHit(featureID: feature, sceneNodeID: node, kind: .body,
                    selectionComponent: .edge(SelectionComponentID(rawValue: "generatedTopology:edge/0")))
    }
    let target = ViewportCanvasTarget(
        hit: edgeHit(first), modelPoint: Point2D(x: 0, y: 0), selectionIntent: .toggle,
        modifierFlags: ViewportInputModifierFlags(containsShift: true, containsControl: true)
    )
    let names = [first: "Extruded.001", second: "Sheet 7"]
    let menu = ViewportCoincidentPickMenu(point: CGPoint(x: 10, y: 20), target: target,
                                          hits: [edgeHit(first), edgeHit(second)], name: { names[$0] })
    #expect(menu.entries.map(\.title) == ["Edge - Extruded.001", "Edge - Sheet 7"])
    let chosen = menu.target(choosing: menu.entries[1])
    #expect(chosen.hit == edgeHit(second))
    #expect(chosen.selectionIntent == .toggle)
    #expect(chosen.modifierFlags.containsShift)
    #expect(chosen.modifierFlags.containsControl == false)
    let highlighted = menu.objectHit(of: menu.entries[1])
    #expect(highlighted.sceneNodeID == second)
    #expect(highlighted.selectionComponent == nil)
}

// MARK: - Mounted: two sheets sharing an edge

private let coincidentViewportSize = CGSize(width: 800.0, height: 600.0)

private struct CoincidentSheetsFixture {
    let document: DesignDocument
    let presentationScene: UniversalViewportScene
    let sceneNodeIDByOccurrenceID: [SceneOccurrenceID: SceneNodeID]
    let currentEvaluation: DocumentEvaluationContext
    let generation: DocumentGeneration
    let ruler: RulerConfiguration
    let cpuScene: ViewportScene
    let leftSheet: SceneNodeID
    let rightSheet: SceneNodeID
    let interactionSceneNodeIDs: Set<SceneNodeID>
}

private enum CoincidentFixtureError: Error {
    case missingSceneNode
}

/// Two flat sheets side by side in `z = 0`, the left over `x ∈ [-0.06, 0]`, the right over
/// `x ∈ [0, 0.06]`, sharing the edge `x = 0`; the camera looks down `-z`.
@MainActor
private func coincidentSheetsFixture() throws -> CoincidentSheetsFixture {
    let session = EditorSession()
    func sheet(_ name: String, from x0: Double, to x1: Double) throws -> FeatureID {
        _ = session.createBSplineSurface(
            name: name,
            surface: BSplineSurface3D.cubicBezierPatch(
                bottomLeft: Point3D(x: x0, y: -0.03, z: 0),
                bottomRight: Point3D(x: x1, y: -0.03, z: 0),
                topRight: Point3D(x: x1, y: 0.03, z: 0),
                topLeft: Point3D(x: x0, y: 0.03, z: 0)
            )
        )
        guard let id = session.document.cadDocument.designGraph.order.last else { throw CoincidentFixtureError.missingSceneNode }
        return id
    }
    let left = try sheet("Left Sheet", from: -0.06, to: 0)
    let right = try sheet("Right Sheet", from: 0, to: 0.06)
    let currentEvaluation = try #require(session.currentEvaluation)
    let document = session.document
    func sceneNodeID(of featureID: FeatureID) throws -> SceneNodeID {
        guard let entry = document.productMetadata.sceneNodes.first(where: { $0.value.reference == .body(featureID) }) else {
            throw CoincidentFixtureError.missingSceneNode
        }
        return entry.key
    }
    let projection = try DesignDocumentProjectBridge().projection(for: document)
    let evaluator = try DefaultDesignDocumentProjectEvaluatorFactory().makeEvaluator(for: document, reusing: currentEvaluation)
    let snapshot = try evaluator.evaluate(project: projection.source, purpose: .presentation, revision: session.transactionRevision)
    let presentationScene = try UniversalViewportSceneBuilder().build(from: snapshot, project: projection.source)
    let ruler = RulerConfiguration.standard(for: .millimeter)
    let cpuScene = ViewportSceneBuilder().build(
        document: document, ruler: ruler, currentEvaluation: currentEvaluation,
        documentGeneration: session.generation, evaluationPolicy: .suppliedOnly
    )
    return CoincidentSheetsFixture(
        document: document,
        presentationScene: presentationScene,
        sceneNodeIDByOccurrenceID: projection.sceneNodeIDByOccurrenceID,
        currentEvaluation: currentEvaluation,
        generation: session.generation,
        ruler: ruler,
        cpuScene: cpuScene,
        leftSheet: try sceneNodeID(of: left),
        rightSheet: try sceneNodeID(of: right),
        interactionSceneNodeIDs: exactPresentationCADSceneNodeIDs(
            scene: presentationScene,
            sceneNodeIDByOccurrenceID: projection.sceneNodeIDByOccurrenceID,
            document: document,
            generation: session.generation,
            cadInteraction: currentEvaluation
        )
    )
}

/// Where a world point of the fixture lands on the mounted viewport.
@MainActor
private func coincidentScreenPoint(_ world: Point3D, fixture: CoincidentSheetsFixture, control: ViewportControlSession) throws -> CGPoint {
    let size = coincidentViewportSize
    let layout = ViewportSceneContext(
        ruler: fixture.ruler,
        scene: fixture.cpuScene,
        size: size,
        camera: control.camera,
        basis: .axisFront(.z),
        geometryBoundsSource: .geometry(fixture.presentationScene.worldBounds),
        fittingInsets: ViewportCanvasChromeLayout(viewportSize: size).fittingInsets
    ).layout
    return try #require(layout.projectedPoint(world)?.point, "The fixture layout projects no point for \(world).")
}

@MainActor
@Test(.timeLimit(.minutes(5)))
func coincidentSheetEdgesArePickedByTheSheetHoveredByTheMenuAndByTheHeldWheel() async throws {
    _ = NSApplication.shared
    let fixture = try coincidentSheetsFixture()
    let control = ViewportControlSession(camera: .init(projection: .parallel), basis: .axisFront(.z))
    // Points a few pixels to each side of the shared edge, inside each sheet.
    let onLeft = try coincidentScreenPoint(Point3D(x: -0.003, y: 0.01, z: 0), fixture: fixture, control: control)
    let onRight = try coincidentScreenPoint(Point3D(x: 0.003, y: 0.01, z: 0), fixture: fixture, control: control)
    let onEdge = try coincidentScreenPoint(Point3D(x: 0, y: 0.01, z: 0), fixture: fixture, control: control)
    // The premise: both sides lie within the tie tolerance of the edge's distance on screen.
    #expect(abs(abs(onLeft.x - onEdge.x) - abs(onRight.x - onEdge.x)) < ViewportNativeHitCandidate.coincidentMetricTolerance)
    #expect(abs(onLeft.x - onEdge.x) > 1.0)

    let size = coincidentViewportSize
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
        selectionHitPolicy: .edge,
        allowsObjectAffordances: false,
        presentationCADInteractionSceneNodeIDs: fixture.interactionSceneNodeIDs,
        selectedPresentationHasExactCADContext: true,
        onPick: { targets.append($0) }
    ).frame(width: size.width, height: size.height)
    let controller = NSHostingController(rootView: viewport)
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    controller.view.frame = CGRect(origin: .zero, size: window.contentLayoutRect.size)
    window.contentViewController = controller
    window.contentView?.layoutSubtreeIfNeeded()
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
    func surface() throws -> ViewportInputSurface.InputView {
        try #require(input(in: controller.view), "The mounted viewport has no input surface.")
    }
    func pick(_ point: CGPoint) throws -> ViewportCanvasTarget? {
        targets.removeAll()
        try surface().onPick?(point, size, .replace)
        return targets.first
    }
    func edgeOwner(_ target: ViewportCanvasTarget?) -> SceneNodeID? {
        guard case .edge? = target?.hit?.selectionComponent else { return nil }
        return target?.hit?.sceneNodeID
    }

    // The frame is ready once a pointer beside the edge resolves an edge.
    let deadline = ContinuousClock.now.advanced(by: .seconds(20))
    while try edgeOwner(pick(onLeft)) == nil, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }

    // Hovering a sheet near the shared edge picks that sheet's edge.
    #expect(try edgeOwner(pick(onLeft)) == fixture.leftSheet)
    #expect(try edgeOwner(pick(onRight)) == fixture.rightSheet)

    // Control-Shift-click lists the two edges instead of picking one; the next click closes the
    // list without picking.
    try surface().onModifierFlagsChange?(ViewportInputModifierFlags(containsShift: true, containsControl: true), size)
    try await Task.sleep(for: .milliseconds(50))
    #expect(try pick(onLeft) == nil)
    #expect(try pick(onLeft) == nil)
    try surface().onModifierFlagsChange?(ViewportInputModifierFlags(), size)
    try await Task.sleep(for: .milliseconds(50))

    // The wheel turned with the button held over the edge steps to the other sheet's edge, which
    // the release picks; elsewhere the wheel stays the camera's.
    try surface().onPress?(onLeft, size, .replace)
    let stepped = try #require(try surface().onHeldScroll?(onLeft, size, .up))
    #expect(stepped)
    #expect(try edgeOwner(pick(onLeft)) == fixture.rightSheet)
    let farAway = CGPoint(x: 4, y: 4)
    try surface().onPress?(farAway, size, .replace)
    #expect(try surface().onHeldScroll?(farAway, size, .up) == false)
}
