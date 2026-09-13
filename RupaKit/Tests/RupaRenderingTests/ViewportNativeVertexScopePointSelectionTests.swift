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

// MARK: - Fixture

private enum VertexScopeFixtureError: Error {
    case missingSceneNode
    case missingBody
    case missingTopology
}

/// The two B-spline sheets and the solid they are placed against.
///
/// The camera the mounted tests use looks down `-z` at the `zx` sketch plane's
/// `+y` half, so the three placements separate on both axes the rules under
/// test read: `z` decides which body the frame draws at a pixel, and `y`
/// decides which side of the section a handle is on.
///
/// - `occludedSheet` sits inside the solid's screen silhouette and strictly
///   behind it, so the frame draws the solid at its knot's pixel, and its knot
///   is on the half the `front` section removes.
/// - `freeSheet` sits clear of the solid in `y`, so nothing is drawn in front
///   of its knot, and its knot is on the half the `front` section keeps.
///
/// The sizes are chosen against the layout's measured scale rather than its
/// geometry: the model bounds are the ruler's own square unioned with the
/// scene, so a scene this small does not set the scale and every distance
/// below lands at about 800 pixels per metre. A sheet spans its knot to its
/// span handles at a fifth of its side, so the side is what keeps those two
/// families further apart on screen than the resolver's tolerance. The
/// placements are asserted in pixels by the fixture invariants, so a layout
/// change that moves the scale fails there instead of silently weakening the
/// rules under test.
///
/// The occluded knot is the sheet's centre, which is why the origins are
/// offset by half a side: it has to sit inside the solid's `xy` footprint,
/// which the extruded rectangle fixes at 40mm by 20mm.
private let vertexScopeSheetSide = 0.12
private let vertexScopeOccludedSheetOrigin = (x: -0.06, y: -0.065, z: -0.005)
private let vertexScopeFreeSheetOrigin = (x: -0.06, y: 0.01, z: 0.0)

/// A scene carrying one CAD solid and two B-spline sheets whose parametric
/// handles the `vertex` scope is answered from.
///
/// The solid supplies the prepared topology a face answer needs and the drawn
/// surface a handle can stand in front of; the sheets supply the surface handle
/// display families. All three are needed on one frame, because the rules under
/// test are about how a handle orders against the body drawn beneath it and
/// about which handles one section keeps.
struct VertexScopeSelectionFixture {
    let document: DesignDocument
    let presentationScene: UniversalViewportScene
    let sceneNodeIDByOccurrenceID: [SceneOccurrenceID: SceneNodeID]
    let currentEvaluation: DocumentEvaluationContext
    let generation: DocumentGeneration
    let ruler: RulerConfiguration
    let cpuScene: ViewportScene
    let solidSceneNodeID: SceneNodeID
    let solidTopology: ViewportBodyTopology
    let solidModelTransform: Transform3D
    let occludedSheetSceneNodeID: SceneNodeID
    let occludedSheetComponent: ViewportBodyComponent
    let occludedSheetModelTransform: Transform3D
    let freeSheetSceneNodeID: SceneNodeID
    let freeSheetComponent: ViewportBodyComponent
    let freeSheetModelTransform: Transform3D
    let interactionSceneNodeIDs: Set<SceneNodeID>
}

let vertexScopeViewportSize = CGSize(width: 800.0, height: 600.0)

/// An editable B-spline sheet placed so its handles can be positioned relative
/// to the solid the same frame draws.
///
/// The knot vector carries one interior knot in each direction, which is what
/// makes the preparation record knot and span displays at all: a single-span
/// Bezier patch has no interior knot to name.
private func vertexScopeEditableSheet(
    originX: Double,
    originY: Double,
    z: Double,
    side: Double
) -> BSplineSurface3D {
    let patch = BSplineSurface3D.cubicBezierPatch(
        bottomLeft: Point3D(x: originX, y: originY, z: z),
        bottomRight: Point3D(x: originX + side, y: originY, z: z),
        topRight: Point3D(x: originX + side, y: originY + side, z: z),
        topLeft: Point3D(x: originX, y: originY + side, z: z)
    )
    return BSplineSurface3D(
        uDegree: 2,
        vDegree: 2,
        uKnots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
        vKnots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
        controlPoints: patch.controlPoints
    )
}

@MainActor
private func vertexScopeBody(
    sceneNodeID: SceneNodeID,
    in scene: ViewportScene
) throws -> (component: ViewportBodyComponent, modelTransform: Transform3D) {
    guard let item = scene.items.first(where: { $0.sceneNodeID == sceneNodeID }),
          case .body(let component) = item.kind else {
        throw VertexScopeFixtureError.missingBody
    }
    return (component, item.modelTransform)
}

@MainActor
func vertexScopeSelectionFixture() throws -> VertexScopeSelectionFixture {
    let session = EditorSession()
    _ = session.createDefaultExtrudedRectangle()
    guard let solidFeatureID = session.document.cadDocument.designGraph.order.last else {
        throw VertexScopeFixtureError.missingSceneNode
    }
    _ = session.createBSplineSurface(
        name: "Vertex Scope Occluded Sheet",
        surface: vertexScopeEditableSheet(
            originX: vertexScopeOccludedSheetOrigin.x,
            originY: vertexScopeOccludedSheetOrigin.y,
            z: vertexScopeOccludedSheetOrigin.z,
            side: vertexScopeSheetSide
        )
    )
    guard let occludedFeatureID = session.document.cadDocument.designGraph.order.last,
          occludedFeatureID != solidFeatureID else {
        throw VertexScopeFixtureError.missingSceneNode
    }
    _ = session.createBSplineSurface(
        name: "Vertex Scope Free Sheet",
        surface: vertexScopeEditableSheet(
            originX: vertexScopeFreeSheetOrigin.x,
            originY: vertexScopeFreeSheetOrigin.y,
            z: vertexScopeFreeSheetOrigin.z,
            side: vertexScopeSheetSide
        )
    )
    guard let freeFeatureID = session.document.cadDocument.designGraph.order.last,
          freeFeatureID != occludedFeatureID else {
        throw VertexScopeFixtureError.missingSceneNode
    }
    let currentEvaluation = try #require(session.currentEvaluation)
    let document = session.document
    func sceneNodeID(of featureID: FeatureID) throws -> SceneNodeID {
        guard let entry = document.productMetadata.sceneNodes.first(where: {
            $0.value.reference == .body(featureID)
        }) else {
            throw VertexScopeFixtureError.missingSceneNode
        }
        return entry.key
    }
    let solidSceneNodeID = try sceneNodeID(of: solidFeatureID)
    let occludedSheetSceneNodeID = try sceneNodeID(of: occludedFeatureID)
    let freeSheetSceneNodeID = try sceneNodeID(of: freeFeatureID)

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
    let solid = try vertexScopeBody(sceneNodeID: solidSceneNodeID, in: cpuScene)
    guard let solidTopology = solid.component.topology else {
        throw VertexScopeFixtureError.missingTopology
    }
    let occludedSheet = try vertexScopeBody(sceneNodeID: occludedSheetSceneNodeID, in: cpuScene)
    let freeSheet = try vertexScopeBody(sceneNodeID: freeSheetSceneNodeID, in: cpuScene)

    return VertexScopeSelectionFixture(
        document: document,
        presentationScene: presentationScene,
        sceneNodeIDByOccurrenceID: projection.sceneNodeIDByOccurrenceID,
        currentEvaluation: currentEvaluation,
        generation: session.generation,
        ruler: ruler,
        cpuScene: cpuScene,
        solidSceneNodeID: solidSceneNodeID,
        solidTopology: solidTopology,
        solidModelTransform: solid.modelTransform,
        occludedSheetSceneNodeID: occludedSheetSceneNodeID,
        occludedSheetComponent: occludedSheet.component,
        occludedSheetModelTransform: occludedSheet.modelTransform,
        freeSheetSceneNodeID: freeSheetSceneNodeID,
        freeSheetComponent: freeSheet.component,
        freeSheetModelTransform: freeSheet.modelTransform,
        interactionSceneNodeIDs: exactPresentationCADSceneNodeIDs(
            scene: presentationScene,
            sceneNodeIDByOccurrenceID: projection.sceneNodeIDByOccurrenceID,
            document: document,
            generation: session.generation,
            cadInteraction: currentEvaluation
        )
    )
}

// MARK: - Screen geometry

/// Where the fixture's handles and its whole drawn scene land on the mounted
/// viewport's pixels, projected through the same layout the frame is fitted
/// with.
struct VertexScopeScreenGeometry {
    let layout: ViewportLayout
    /// The projected extent of everything the scene draws, used only to name a
    /// pixel that is outside all of it.
    let sceneSilhouette: CGRect
    let solidSilhouette: CGRect
    let occludedKnot: (reference: SelectionReference, world: Point3D, point: CGPoint)
    let freeKnot: (reference: SelectionReference, world: Point3D, point: CGPoint)
}

@MainActor
private func vertexScopeKnot(
    component: ViewportBodyComponent,
    modelTransform: Transform3D,
    layout: ViewportLayout,
    name: String
) throws -> (reference: SelectionReference, world: Point3D, point: CGPoint) {
    // The recorded order is the resolver's own tie-break, and both directions
    // record a knot at the patch centre, so the first display is the one a
    // pointer at that centre resolves to.
    let display = try #require(
        component.surfaceKnotDisplays.first,
        "The \(name) sheet records no surface knot display."
    )
    let world = ViewportLayout.transformedPoint(display.point, by: modelTransform)
    let point = try #require(
        layout.projectedPoint(world)?.point,
        "The fixture layout projects no point for the \(name) sheet's knot."
    )
    return (display.selectionReference, world, point)
}

@MainActor
func vertexScopeScreenGeometry(
    fixture: VertexScopeSelectionFixture,
    control: ViewportControlSession
) throws -> VertexScopeScreenGeometry {
    let size = vertexScopeViewportSize
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

    func silhouette(of points: [Point3D], name: String) throws -> CGRect {
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for world in points {
            let projected = try #require(
                layout.projectedPoint(world)?.point,
                "The fixture layout projects no point for a \(name) corner."
            )
            minX = min(minX, projected.x)
            maxX = max(maxX, projected.x)
            minY = min(minY, projected.y)
            maxY = max(maxY, projected.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    let bounds = try #require(
        fixture.presentationScene.worldBounds,
        "The presentation scene reports no world bounds."
    )
    var sceneCorners: [Point3D] = []
    for corner in 0..<8 {
        sceneCorners.append(Point3D(
            x: corner & 1 == 0 ? bounds.minimum.x : bounds.maximum.x,
            y: corner & 2 == 0 ? bounds.minimum.y : bounds.maximum.y,
            z: corner & 4 == 0 ? bounds.minimum.z : bounds.maximum.z
        ))
    }
    let solidPoints = fixture.solidTopology.vertices.map {
        ViewportLayout.transformedPoint($0.point, by: fixture.solidModelTransform)
    }

    return VertexScopeScreenGeometry(
        layout: layout,
        sceneSilhouette: try silhouette(of: sceneCorners, name: "scene bounds"),
        solidSilhouette: try silhouette(of: solidPoints, name: "solid vertex"),
        occludedKnot: try vertexScopeKnot(
            component: fixture.occludedSheetComponent,
            modelTransform: fixture.occludedSheetModelTransform,
            layout: layout,
            name: "occluded"
        ),
        freeKnot: try vertexScopeKnot(
            component: fixture.freeSheetComponent,
            modelTransform: fixture.freeSheetModelTransform,
            layout: layout,
            name: "free"
        )
    )
}

@MainActor
private func vertexScopeControlSession() -> ViewportControlSession {
    ViewportControlSession(camera: .init(projection: .parallel), basis: .axisFront(.z))
}

/// The `zx` plane section the handle rules are measured against, keeping the
/// `+y` half.
///
/// The plane's normal is `+y` and `front` keeps the half the normal points to,
/// so the free sheet's knot survives the cut and the occluded sheet's knot does
/// not. The two halves are asserted from the analysis itself in the fixture
/// invariants rather than assumed here.
@MainActor
private func vertexScopeSection(
    fixture: VertexScopeSelectionFixture
) throws -> (analysis: SectionAnalysisResult, plan: SectionAnalysisClippingPlan) {
    let analysis = try SectionAnalysisService().analyze(
        document: fixture.document,
        query: SectionAnalysisQuery(source: .sketchPlane(.zx), toleranceMeters: 1.0e-8),
        activeConstructionPlaneID: nil,
        displayUnit: .millimeter,
        currentEvaluation: fixture.currentEvaluation,
        currentGeneration: fixture.generation
    )
    return (analysis, SectionAnalysisClippingPlan(result: analysis, retaining: .front))
}

// MARK: - Mounted point harness

private struct VertexScopePickObservation {
    var point: CGPoint
    var target: ViewportCanvasTarget
}

/// Drives `onPick` on a mounted viewport and reports what each pointer resolved
/// to.
///
/// The frame is proven ready by `readyPoint` before any other pointer is asked,
/// for the same reason the object scope harness does it: `pick` returns without
/// calling `onPick` while the mounted frame cannot answer, and calls it with a
/// `nil` hit once the frame answers and nothing was drawn there, so only a
/// pointer that must select something separates the two.
///
/// `onPresentationOccurrencePick` and `onMeshElementPick` are deliberately not
/// supplied: both short-circuit `pick` before the native CAD sub-shape query
/// runs.
@MainActor
private func vertexScopePicks(
    fixture: VertexScopeSelectionFixture,
    control: ViewportControlSession,
    selectionHitPolicy: ViewportSelectionHitPolicy,
    sectionAnalysis: SectionAnalysisResult? = nil,
    sectionClippingPlan: SectionAnalysisClippingPlan? = nil,
    readyPoint: CGPoint,
    points: [CGPoint]
) async throws -> [VertexScopePickObservation] {
    let size = vertexScopeViewportSize
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
        sectionAnalysis: sectionAnalysis,
        sectionClippingPlan: sectionClippingPlan,
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

    var observations: [VertexScopePickObservation] = []
    for point in points {
        targets.removeAll()
        input(in: controller.view)?.onPick?(point, size, .replace)
        let target = try #require(
            targets.first,
            "The mounted \(selectionHitPolicy) frame refused to answer the pointer \(point)."
        )
        #expect(targets.count == 1)
        observations.append(VertexScopePickObservation(point: point, target: target))
    }
    return observations
}

// MARK: - Fixture invariants

/// The premises every rule below reads: which knot the solid stands in front
/// of, which knot nothing covers, and which side of the section each is on.
///
/// Asserting them here separates a resolver defect from a fixture whose
/// geometry moved.
@MainActor
@Test(.timeLimit(.minutes(3)))
func viewportNativeVertexScopeFixtureSeparatesItsTwoSurfaceKnots() async throws {
    _ = NSApplication.shared
    let fixture = try vertexScopeSelectionFixture()
    let control = vertexScopeControlSession()
    let geometry = try vertexScopeScreenGeometry(fixture: fixture, control: control)

    // The face answer is gated on exact CAD affordance context, so the solid
    // has to carry it for the occlusion premise to be measurable at all.
    #expect(fixture.interactionSceneNodeIDs.contains(fixture.solidSceneNodeID))
    #expect(fixture.occludedSheetComponent.surfaceKnotDisplays.count == 2)
    #expect(fixture.freeSheetComponent.surfaceKnotDisplays.count == 2)

    var solidBounds = (
        minX: Double.greatestFiniteMagnitude, maxX: -Double.greatestFiniteMagnitude,
        minY: Double.greatestFiniteMagnitude, maxY: -Double.greatestFiniteMagnitude,
        minZ: Double.greatestFiniteMagnitude, maxZ: -Double.greatestFiniteMagnitude
    )
    for vertex in fixture.solidTopology.vertices {
        let point = ViewportLayout.transformedPoint(vertex.point, by: fixture.solidModelTransform)
        solidBounds.minX = min(solidBounds.minX, point.x)
        solidBounds.maxX = max(solidBounds.maxX, point.x)
        solidBounds.minY = min(solidBounds.minY, point.y)
        solidBounds.maxY = max(solidBounds.maxY, point.y)
        solidBounds.minZ = min(solidBounds.minZ, point.z)
        solidBounds.maxZ = max(solidBounds.maxZ, point.z)
    }

    // The camera looks down `-z`, so a point inside the solid's `xy` footprint
    // and below its minimum `z` is drawn over by the solid.
    let occluded = geometry.occludedKnot.world
    #expect(occluded.x > solidBounds.minX && occluded.x < solidBounds.maxX)
    #expect(occluded.y > solidBounds.minY && occluded.y < solidBounds.maxY)
    #expect(occluded.z < solidBounds.minZ)
    #expect(geometry.solidSilhouette.contains(geometry.occludedKnot.point))

    // The free knot leaves the solid's footprint in `y`, so nothing the scene
    // draws stands in front of it.
    let free = geometry.freeKnot.world
    #expect(free.y > solidBounds.maxY)
    #expect(geometry.solidSilhouette.contains(geometry.freeKnot.point) == false)

    // Each knot is far enough from the other, and from its own span handles,
    // that the resolver's tolerance cannot confuse them.
    let tolerance = Double(ViewportNativeCADTopologyResolver.pointTolerance)
    #expect(
        hypot(
            geometry.occludedKnot.point.x - geometry.freeKnot.point.x,
            geometry.occludedKnot.point.y - geometry.freeKnot.point.y
        ) > tolerance * 4.0
    )
    for display in fixture.freeSheetComponent.surfaceSpanDisplays {
        let world = ViewportLayout.transformedPoint(
            display.point, by: fixture.freeSheetModelTransform
        )
        let projected = try #require(geometry.layout.projectedPoint(world)?.point)
        #expect(
            hypot(
                projected.x - geometry.freeKnot.point.x,
                projected.y - geometry.freeKnot.point.y
            ) > tolerance
        )
    }

    // The section keeps exactly one of the two knots, measured from the plane
    // the analysis resolved rather than from an assumed orientation.
    let section = try vertexScopeSection(fixture: fixture)
    #expect(section.plan.retainedSide == .front)
    let normal = section.analysis.plane.normal
    let origin = section.analysis.plane.origin
    func signedDistance(_ point: Point3D) -> Double {
        (point.x - origin.x) * normal.x
            + (point.y - origin.y) * normal.y
            + (point.z - origin.z) * normal.z
    }
    #expect(signedDistance(free) > section.analysis.toleranceMeters)
    #expect(signedDistance(occluded) < -section.analysis.toleranceMeters)
}

// MARK: - Vertex scope

@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeVertexScopeSelectsTheSurfaceKnotUnderThePointer() async throws {
    _ = NSApplication.shared
    let fixture = try vertexScopeSelectionFixture()
    let control = vertexScopeControlSession()
    let geometry = try vertexScopeScreenGeometry(fixture: fixture, control: control)

    let observations = try await vertexScopePicks(
        fixture: fixture,
        control: control,
        selectionHitPolicy: .vertex,
        readyPoint: geometry.freeKnot.point,
        points: [geometry.freeKnot.point]
    )

    let hit = try #require(observations[0].target.hit)
    #expect(hit.pickingBackend == .native)
    #expect(hit.sceneNodeID == fixture.freeSheetSceneNodeID)
    #expect(hit.kind == .body)

    // The identity is the `SelectionReference` the preparation assigned to the
    // knot, never a `SelectionComponent` and never a render-mesh element.
    #expect(hit.selectionReference == geometry.freeKnot.reference)
    #expect(hit.selectionComponent == nil)
}

@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeVertexScopeSelectsAKnotTheDrawnBodyCovers() async throws {
    _ = NSApplication.shared
    let fixture = try vertexScopeSelectionFixture()
    let control = vertexScopeControlSession()
    let geometry = try vertexScopeScreenGeometry(fixture: fixture, control: control)
    let point = geometry.occludedKnot.point

    // The premise: at this pixel the frame draws the solid, not the sheet the
    // knot belongs to. The face scope reads the drawn surface directly, so its
    // answer is the measurement of what covers the knot.
    let covering = try await vertexScopePicks(
        fixture: fixture,
        control: control,
        selectionHitPolicy: .face,
        readyPoint: point,
        points: [point]
    )
    let faceHit = try #require(
        covering[0].target.hit,
        "The frame drew no prepared CAD face over the occluded knot."
    )
    #expect(faceHit.sceneNodeID == fixture.solidSceneNodeID)
    guard case .face = try #require(faceHit.selectionComponent) else {
        Issue.record("The covering pointer resolved \(String(describing: faceHit.selectionComponent)).")
        return
    }

    // The rule: the frame draws these displays at annotation depth, which reads
    // no depth buffer, so the knot is visible on screen and stays selectable.
    // Testing it against the drawn surface would refuse a handle the user sees.
    let observations = try await vertexScopePicks(
        fixture: fixture,
        control: control,
        selectionHitPolicy: .vertex,
        readyPoint: point,
        points: [point]
    )
    let hit = try #require(
        observations[0].target.hit,
        "The vertex scope refused a knot the body is drawn in front of."
    )
    #expect(hit.pickingBackend == .native)
    #expect(hit.sceneNodeID == fixture.occludedSheetSceneNodeID)
    #expect(hit.selectionReference == geometry.occludedKnot.reference)
    #expect(hit.selectionComponent == nil)
}

@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeVertexScopeSelectsNothingWhereTheFrameDrewNothing() async throws {
    _ = NSApplication.shared
    let fixture = try vertexScopeSelectionFixture()
    let control = vertexScopeControlSession()
    let geometry = try vertexScopeScreenGeometry(fixture: fixture, control: control)
    let emptyPoint = CGPoint(x: 4.0, y: 4.0)
    #expect(geometry.sceneSilhouette.contains(emptyPoint) == false)

    let observations = try await vertexScopePicks(
        fixture: fixture,
        control: control,
        selectionHitPolicy: .vertex,
        readyPoint: geometry.freeKnot.point,
        points: [emptyPoint]
    )

    // The readiness pointer resolved on this same mounted frame, so the frame
    // answered here too and drew nothing. The scene carries surface handle
    // displays, so the native query is supported and reports the empty pixel as
    // the miss it is; the vertex scope no longer routes that miss to the legacy
    // resolver, so this nil is the native frame's own answer.
    #expect(observations[0].target.hit == nil)
}

// MARK: - Rank

@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeCombinedScopePrefersTheSurfaceKnotOverTheFaceBeneathIt() async throws {
    _ = NSApplication.shared
    let fixture = try vertexScopeSelectionFixture()
    let control = vertexScopeControlSession()
    let geometry = try vertexScopeScreenGeometry(fixture: fixture, control: control)
    let point = geometry.occludedKnot.point

    let observations = try await vertexScopePicks(
        fixture: fixture,
        control: control,
        selectionHitPolicy: .all,
        readyPoint: point,
        points: [point]
    )

    // The combined scope admits the solid's face and its occurrence at this
    // same pixel, so both are live candidates. The handle enters at vertex
    // rank, which is what keeps a pointer that named a handle from resolving to
    // the body drawn behind it.
    let hit = try #require(observations[0].target.hit)
    #expect(hit.pickingBackend == .native)
    #expect(hit.sceneNodeID == fixture.occludedSheetSceneNodeID)
    #expect(hit.selectionReference == geometry.occludedKnot.reference)
    #expect(hit.selectionComponent == nil)
}

// MARK: - Section

@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeVertexScopeRefusesAKnotTheSectionRemoved() async throws {
    _ = NSApplication.shared
    let fixture = try vertexScopeSelectionFixture()
    let control = vertexScopeControlSession()
    let geometry = try vertexScopeScreenGeometry(fixture: fixture, control: control)
    let section = try vertexScopeSection(fixture: fixture)

    let observations = try await vertexScopePicks(
        fixture: fixture,
        control: control,
        selectionHitPolicy: .vertex,
        sectionAnalysis: section.analysis,
        sectionClippingPlan: section.plan,
        readyPoint: geometry.freeKnot.point,
        points: [geometry.freeKnot.point, geometry.occludedKnot.point]
    )

    // The section is attached to the same sectioned root the displays hang
    // from, so a handle the cut removed is not drawn and is not admitted. The
    // kept handle is answered on the same frame, which is what separates the
    // section rule from a query that stopped answering.
    let kept = try #require(observations[0].target.hit)
    #expect(kept.sceneNodeID == fixture.freeSheetSceneNodeID)
    #expect(kept.selectionReference == geometry.freeKnot.reference)
    #expect(observations[1].target.hit == nil)
}
