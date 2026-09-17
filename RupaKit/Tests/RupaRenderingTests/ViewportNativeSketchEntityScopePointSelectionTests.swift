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

private enum SketchScopeFixtureError: Error {
    case missingFeature
    case missingSceneNode
    case missingBody
    case missingTopology
    case missingLineSketch
    case missingLineWorldPoints
}

/// The solid the sketch line runs behind, and the line itself.
///
/// The camera the mounted tests use looks down `-y` at the world's `zx` plane,
/// which is the plane every sketch is drawn on: the overlay producer maps a
/// sketch's two coordinates to world `x` and world `z` and leaves `y` at zero,
/// whatever plane the sketch was authored on. Looking along any other axis
/// would collapse the whole sketch onto one screen line, so this is the only
/// basis the entity families separate on.
///
/// Under that camera screen `x` follows world `x`, screen `y` follows world
/// `z`, and a larger `y` is nearer. The solid is extruded along `+z` from the
/// `xy` plane, so it covers a band of the screen `40mm` wide and `60mm` tall
/// while standing `10mm` in front of the sketch plane. The line is drawn at a
/// height that crosses that band and runs well past both of its sides, which
/// is what gives one pointer the solid in front of it and two pointers a clear
/// view of the same line.
///
/// The sizes are chosen against the layout's measured scale rather than its
/// geometry. The fitted model bounds are the ruler's own square unioned with
/// the scene, and the ruler's square is the larger of the two here, so a scene
/// of this size does not set the scale and every distance below lands at about
/// 500 pixels per metre. The separations are asserted in pixels by the fixture
/// invariants, so a layout change that moves the scale fails there instead of
/// silently weakening the rules under test.
private let sketchScopeSolidWidthMillimeters = 320.0
private let sketchScopeSolidHeightMillimeters = 160.0
private let sketchScopeSolidDepthMillimeters = 480.0
private let sketchScopeLineHalfSpanMillimeters = 480.0
private let sketchScopeLineHeightMillimeters = 320.0

/// Where along the line each pointer sits, as a fraction from its `-x` end.
///
/// The middle pointer is the one the solid covers. The other two are mirror
/// images either side of the world's `yz` plane, which is the plane the
/// section test cuts on, so one survives that cut and the other does not.
private let sketchScopeOccludedParameter = 0.5
private let sketchScopeClearParameter = 0.875
private let sketchScopeMirrorParameter = 0.125

/// A scene carrying one CAD solid and one line sketch, which is the smallest
/// scene that separates the three rules the `sketchEntity` scope owns: that the
/// polyline the frame drew is what answers, that a body drawn in front of it
/// hides it, and that the section removes it.
struct SketchScopeSelectionFixture {
    let document: DesignDocument
    let presentationScene: UniversalViewportScene
    let sceneNodeIDByOccurrenceID: [SceneOccurrenceID: SceneNodeID]
    let currentEvaluation: DocumentEvaluationContext
    let generation: DocumentGeneration
    let ruler: RulerConfiguration
    let cpuScene: ViewportScene
    let solidFeatureID: FeatureID
    let solidSceneNodeID: SceneNodeID
    let solidTopology: ViewportBodyTopology
    let solidModelTransform: Transform3D
    let lineFeatureID: FeatureID
    let lineSceneNodeID: SceneNodeID?
    let lineModelTransform: Transform3D
    let lineEntityID: SketchEntityID
    let linePrimitive: ViewportSketchPrimitive
    let interactionSceneNodeIDs: Set<SceneNodeID>
}

let sketchScopeViewportSize = CGSize(width: 800.0, height: 600.0)

@MainActor
func sketchScopeSelectionFixture() throws -> SketchScopeSelectionFixture {
    let session = EditorSession()
    // `execute` rather than `perform`: a rejected command has to fail here,
    // not leave the graph one feature short and fail as a geometry premise.
    _ = try session.execute(.createExtrudedRectangle(
        name: "Sketch Scope Solid",
        plane: .xy,
        width: .length(sketchScopeSolidWidthMillimeters, .millimeter),
        height: .length(sketchScopeSolidHeightMillimeters, .millimeter),
        depth: .length(sketchScopeSolidDepthMillimeters, .millimeter),
        direction: .normal
    ))
    guard let solidFeatureID = session.document.cadDocument.designGraph.order.last else {
        throw SketchScopeFixtureError.missingFeature
    }
    _ = try session.execute(.createLineSketch(
        name: "Sketch Scope Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(-sketchScopeLineHalfSpanMillimeters, .millimeter),
            y: .length(sketchScopeLineHeightMillimeters, .millimeter)
        ),
        end: SketchPoint(
            x: .length(sketchScopeLineHalfSpanMillimeters, .millimeter),
            y: .length(sketchScopeLineHeightMillimeters, .millimeter)
        )
    ))
    guard let lineFeatureID = session.document.cadDocument.designGraph.order.last,
          lineFeatureID != solidFeatureID else {
        throw SketchScopeFixtureError.missingFeature
    }
    let currentEvaluation = try #require(session.currentEvaluation)
    let document = session.document
    guard let sceneNodeEntry = document.productMetadata.sceneNodes.first(where: {
        $0.value.reference == .body(solidFeatureID)
    }) else {
        throw SketchScopeFixtureError.missingSceneNode
    }
    let solidSceneNodeID = sceneNodeEntry.key

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
    guard let solidItem = cpuScene.items.first(where: { $0.sceneNodeID == solidSceneNodeID }),
          case .body(let solidComponent) = solidItem.kind else {
        throw SketchScopeFixtureError.missingBody
    }
    guard let solidTopology = solidComponent.topology else {
        throw SketchScopeFixtureError.missingTopology
    }
    guard let lineItem = cpuScene.items.first(where: { $0.featureID == lineFeatureID }),
          case .sketch(let primitives) = lineItem.kind,
          primitives.count == 1,
          case .line = primitives[0] else {
        throw SketchScopeFixtureError.missingLineSketch
    }

    return SketchScopeSelectionFixture(
        document: document,
        presentationScene: presentationScene,
        sceneNodeIDByOccurrenceID: projection.sceneNodeIDByOccurrenceID,
        currentEvaluation: currentEvaluation,
        generation: session.generation,
        ruler: ruler,
        cpuScene: cpuScene,
        solidFeatureID: solidFeatureID,
        solidSceneNodeID: solidSceneNodeID,
        solidTopology: solidTopology,
        solidModelTransform: solidItem.modelTransform,
        lineFeatureID: lineFeatureID,
        lineSceneNodeID: lineItem.sceneNodeID,
        lineModelTransform: lineItem.modelTransform,
        lineEntityID: primitives[0].entityID,
        linePrimitive: primitives[0],
        interactionSceneNodeIDs: exactPresentationCADSceneNodeIDs(
            scene: presentationScene,
            sceneNodeIDByOccurrenceID: projection.sceneNodeIDByOccurrenceID,
            document: document,
            generation: session.generation,
            cadInteraction: currentEvaluation
        )
    )
}

/// The inputs a mounted `Viewport` needs, which every fixture in this file
/// supplies and the pick harness reads.
///
/// Two fixtures mount the same viewport to ask different questions — one about
/// which sketch a pointer lands on, one about whether a suppressed sketch is
/// answered at all — so the harness reads this rather than either fixture's
/// own geometry.
struct SketchScopeMountInputs {
    let document: DesignDocument
    let presentationScene: UniversalViewportScene
    let sceneNodeIDByOccurrenceID: [SceneOccurrenceID: SceneNodeID]
    let currentEvaluation: DocumentEvaluationContext
    let generation: DocumentGeneration
    let ruler: RulerConfiguration
    let interactionSceneNodeIDs: Set<SceneNodeID>
}

extension SketchScopeSelectionFixture {
    var mountInputs: SketchScopeMountInputs {
        SketchScopeMountInputs(
            document: document,
            presentationScene: presentationScene,
            sceneNodeIDByOccurrenceID: sceneNodeIDByOccurrenceID,
            currentEvaluation: currentEvaluation,
            generation: generation,
            ruler: ruler,
            interactionSceneNodeIDs: interactionSceneNodeIDs
        )
    }
}

// MARK: - Screen geometry

/// The layout the mounted viewport is fitted with, which is what a fixture
/// projects its pointers through so that a pixel it names is the pixel the
/// frame answers at.
@MainActor
func sketchScopeLayout(
    ruler: RulerConfiguration,
    cpuScene: ViewportScene,
    presentationScene: UniversalViewportScene,
    control: ViewportControlSession
) -> ViewportLayout {
    let size = sketchScopeViewportSize
    return ViewportSceneContext(
        ruler: ruler,
        scene: cpuScene,
        size: size,
        camera: control.camera,
        basis: .axisFront(.y),
        geometryBoundsSource: .geometry(presentationScene.worldBounds),
        fittingInsets: ViewportCanvasChromeLayout(
            viewportSize: size,
            viewportBadgeWidth: ViewportCanvasChromeLayout.maximumViewportBadgeWidth
        ).fittingInsets
    ).layout
}

/// Where the fixture's line, its three pointers and the solid's silhouette land
/// on the mounted viewport's pixels, projected through the same layout the
/// frame is fitted with.
struct SketchScopeScreenGeometry {
    let layout: ViewportLayout
    /// The projected extent of every family this frame draws — the solid, the
    /// profile sketch and the test line — used only to name a pixel outside all
    /// of them.
    let drawnSilhouette: CGRect
    let solidSilhouette: CGRect
    let lineStart: Point3D
    let lineEnd: Point3D
    let occluded: (world: Point3D, point: CGPoint)
    let clear: (world: Point3D, point: CGPoint)
    let mirror: (world: Point3D, point: CGPoint)
}

@MainActor
func sketchScopeScreenGeometry(
    fixture: SketchScopeSelectionFixture,
    control: ViewportControlSession
) throws -> SketchScopeScreenGeometry {
    let layout = sketchScopeLayout(
        ruler: fixture.ruler,
        cpuScene: fixture.cpuScene,
        presentationScene: fixture.presentationScene,
        control: control
    )

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

    let solidPoints = fixture.solidTopology.vertices.map {
        ViewportLayout.transformedPoint($0.point, by: fixture.solidModelTransform)
    }

    // The line's world points come from the overlay producer that drew it, so
    // the pointers are placed on the polyline the query reads and not on a
    // second mapping of the authored coordinates.
    let linePoints = try ViewportSpatialOverlayProducer.sketchPrimitiveWorldPoints(
        fixture.linePrimitive
    )
    guard linePoints.count == 2 else {
        throw SketchScopeFixtureError.missingLineWorldPoints
    }
    let ordered = linePoints.sorted { $0.x < $1.x }
    func onLine(_ parameter: Double) -> Point3D {
        Point3D(
            x: ordered[0].x + (ordered[1].x - ordered[0].x) * parameter,
            y: ordered[0].y + (ordered[1].y - ordered[0].y) * parameter,
            z: ordered[0].z + (ordered[1].z - ordered[0].z) * parameter
        )
    }
    func pointer(_ parameter: Double, name: String) throws -> (world: Point3D, point: CGPoint) {
        let world = onLine(parameter)
        let point = try #require(
            layout.projectedPoint(world)?.point,
            "The fixture layout projects no point for the \(name) pointer."
        )
        return (world, point)
    }

    return SketchScopeScreenGeometry(
        layout: layout,
        drawnSilhouette: try silhouette(
            of: solidPoints + linePoints,
            name: "drawn geometry"
        ),
        solidSilhouette: try silhouette(of: solidPoints, name: "solid vertex"),
        lineStart: ordered[0],
        lineEnd: ordered[1],
        occluded: try pointer(sketchScopeOccludedParameter, name: "occluded"),
        clear: try pointer(sketchScopeClearParameter, name: "clear"),
        mirror: try pointer(sketchScopeMirrorParameter, name: "mirror")
    )
}

@MainActor
private func sketchScopeControlSession() -> ViewportControlSession {
    ViewportControlSession(camera: .init(projection: .parallel), basis: .axisFront(.y))
}

/// The `yz` plane section the sketch rules are measured against, keeping the
/// `front` half.
///
/// The two clear pointers are mirror images across this plane, so exactly one
/// of them survives whichever half `front` names. Which one is asserted from
/// the analysis itself in the fixture invariants rather than assumed here.
@MainActor
private func sketchScopeSection(
    fixture: SketchScopeSelectionFixture
) throws -> (analysis: SectionAnalysisResult, plan: SectionAnalysisClippingPlan) {
    let analysis = try SectionAnalysisService().analyze(
        document: fixture.document,
        query: SectionAnalysisQuery(source: .sketchPlane(.yz), toleranceMeters: 1.0e-8),
        activeConstructionPlaneID: nil,
        displayUnit: .millimeter,
        currentEvaluation: fixture.currentEvaluation,
        currentGeneration: fixture.generation
    )
    return (analysis, SectionAnalysisClippingPlan(result: analysis, retaining: .front))
}

// MARK: - Mounted point harness

private struct SketchScopePickObservation {
    var point: CGPoint
    var target: ViewportCanvasTarget
}

/// Drives `onPick` on a mounted viewport and reports what each pointer resolved
/// to.
///
/// The frame is proven ready by `readyPoint` before any other pointer is asked,
/// for the same reason the vertex scope harness does it: `pick` returns without
/// calling `onPick` while the mounted frame cannot answer, and calls it with a
/// `nil` hit once the frame answers and nothing was drawn there, so only a
/// pointer that must select something separates the two. `pick` is also silent
/// where it cannot map the pointer onto the construction plane, so every
/// pointer passed here is chosen on a row the readiness pointer has shown that
/// mapping to be defined on.
@MainActor
private func sketchScopePicks(
    mount: SketchScopeMountInputs,
    control: ViewportControlSession,
    selection: SelectionModel = SelectionModel(),
    selectionHitPolicy: ViewportSelectionHitPolicy,
    sectionAnalysis: SectionAnalysisResult? = nil,
    sectionClippingPlan: SectionAnalysisClippingPlan? = nil,
    readyPoint: CGPoint,
    points: [CGPoint]
) async throws -> [SketchScopePickObservation] {
    let size = sketchScopeViewportSize
    var targets: [ViewportCanvasTarget] = []
    let viewport = Viewport(
        document: mount.document,
        sourceIdentity: .document(id: mount.document.id, generation: mount.generation),
        controlSession: control,
        presentationScene: mount.presentationScene,
        presentationSceneNodeIDByOccurrenceID: mount.sceneNodeIDByOccurrenceID,
        workspaceRenderState: .init(revision: WorkspaceRevision(), ruler: mount.ruler),
        currentEvaluation: mount.currentEvaluation,
        selection: selection,
        objectSelectionIndex: .init(document: mount.document, selection: selection),
        sectionAnalysis: sectionAnalysis,
        sectionClippingPlan: sectionClippingPlan,
        selectionHitPolicy: selectionHitPolicy,
        allowsObjectAffordances: false,
        presentationCADInteractionSceneNodeIDs: mount.interactionSceneNodeIDs,
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

    var observations: [SketchScopePickObservation] = []
    for point in points {
        targets.removeAll()
        input(in: controller.view)?.onPick?(point, size, .replace)
        let target = try #require(
            targets.first,
            "The mounted \(selectionHitPolicy) frame refused to answer the pointer \(point)."
        )
        #expect(targets.count == 1)
        observations.append(SketchScopePickObservation(point: point, target: target))
    }
    return observations
}

// MARK: - Fixture invariants

/// The premises every rule below reads: which pointer the solid stands in front
/// of, which two pointers nothing covers, how far each is from the other sketch
/// the same frame draws, and which side of the section each is on.
///
/// Asserting them here separates a resolver defect from a fixture whose
/// geometry moved.
@MainActor
@Test(.timeLimit(.minutes(3)))
func viewportNativeSketchEntityScopeFixtureSeparatesItsThreePointers() async throws {
    _ = NSApplication.shared
    let fixture = try sketchScopeSelectionFixture()
    let control = sketchScopeControlSession()
    let geometry = try sketchScopeScreenGeometry(fixture: fixture, control: control)

    // The face answer the occlusion premise is measured with is gated on exact
    // CAD affordance context, so the solid has to carry it.
    #expect(fixture.interactionSceneNodeIDs.contains(fixture.solidSceneNodeID))
    // The frame draws exactly two things: the solid and the line. The extrude's
    // own profile is consumed by the feature and is not a scene item, so no
    // second sketch competes for any pointer below.
    #expect(fixture.cpuScene.items.count == 2)
    // Both the producer that draws the polyline and the query that measures it
    // map a sketch point to world without the item's model transform, so the
    // pointers below are on the drawn curve whatever that transform is. The
    // fixture states it so a transform appearing here is visible rather than
    // silently relied upon.
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

    // The whole line lies on the world plane `y == 0`, which is the plane the
    // overlay producer draws every sketch on.
    #expect(geometry.lineStart.y == 0.0)
    #expect(geometry.lineEnd.y == 0.0)
    // The solid stands in front of that plane, so a pointer inside its
    // silhouette has it drawn over the line. The camera looks down `-y`.
    #expect(solidBounds.maxY > 0.0)
    // The line crosses the solid's `z` band and runs past both of its sides.
    #expect(geometry.occluded.world.z > solidBounds.minZ)
    #expect(geometry.occluded.world.z < solidBounds.maxZ)
    #expect(geometry.lineStart.x < solidBounds.minX)
    #expect(geometry.lineEnd.x > solidBounds.maxX)

    #expect(geometry.solidSilhouette.contains(geometry.occluded.point))
    #expect(geometry.solidSilhouette.contains(geometry.clear.point) == false)
    #expect(geometry.solidSilhouette.contains(geometry.mirror.point) == false)

    // Every pointer is far enough in pixels from the solid's silhouette, from
    // the profile sketch the same frame draws, and from the line's own ends,
    // that the resolver's tolerance cannot confuse the answer.
    let tolerance = Double(ViewportNativeCADTopologyResolver.pointTolerance)
    func clearance(_ point: CGPoint, of rect: CGRect) -> Double {
        let dx = max(rect.minX - point.x, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, point.y - rect.maxY)
        return Double(max(dx, dy))
    }
    for pointer in [geometry.clear, geometry.mirror] {
        #expect(clearance(pointer.point, of: geometry.solidSilhouette) > tolerance * 2.0)
    }
    for pointer in [geometry.occluded, geometry.clear, geometry.mirror] {
        for end in [geometry.lineStart, geometry.lineEnd] {
            let projected = try #require(geometry.layout.projectedPoint(end)?.point)
            #expect(
                hypot(pointer.point.x - projected.x, pointer.point.y - projected.y)
                    > tolerance * 2.0
            )
        }
    }

    // The section keeps exactly one of the two clear pointers, measured from
    // the plane the analysis resolved rather than from an assumed orientation.
    // The occluded pointer sits on that plane and is never combined with it.
    let section = try sketchScopeSection(fixture: fixture)
    #expect(section.plan.retainedSide == .front)
    let normal = section.analysis.plane.normal
    let origin = section.analysis.plane.origin
    func signedDistance(_ point: Point3D) -> Double {
        (point.x - origin.x) * normal.x
            + (point.y - origin.y) * normal.y
            + (point.z - origin.z) * normal.z
    }
    #expect(signedDistance(geometry.clear.world) > section.analysis.toleranceMeters)
    #expect(signedDistance(geometry.mirror.world) < -section.analysis.toleranceMeters)
    #expect(abs(signedDistance(geometry.occluded.world)) <= section.analysis.toleranceMeters)
}

// MARK: - Sketch entity scope

@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeSketchEntityScopeSelectsTheSketchLineUnderThePointer() async throws {
    _ = NSApplication.shared
    let fixture = try sketchScopeSelectionFixture()
    let control = sketchScopeControlSession()
    let geometry = try sketchScopeScreenGeometry(fixture: fixture, control: control)

    let observations = try await sketchScopePicks(
        mount: fixture.mountInputs,
        control: control,
        selectionHitPolicy: .sketchEntity,
        readyPoint: geometry.clear.point,
        points: [geometry.clear.point]
    )

    let hit = try #require(observations[0].target.hit)
    #expect(hit.featureID == fixture.lineFeatureID)
    #expect(hit.kind == .sketch)
    #expect(hit.sceneNodeID == fixture.lineSceneNodeID)

    // The identity is the authored sketch entity the frame drew the polyline
    // for. No endpoint handle is invented for it, no control point index is
    // claimed, and no `SelectionComponent` stands in for the entity.
    #expect(hit.sketchEntityID == fixture.lineEntityID)
    #expect(hit.sketchPointHandle == nil)
    #expect(hit.sketchControlPointIndex == nil)
    #expect(hit.selectionComponent == nil)
    #expect(hit.selectionReference == nil)
}

@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeSketchEntityScopeRefusesALineTheDrawnBodyCovers() async throws {
    _ = NSApplication.shared
    let fixture = try sketchScopeSelectionFixture()
    let control = sketchScopeControlSession()
    let geometry = try sketchScopeScreenGeometry(fixture: fixture, control: control)
    let point = geometry.occluded.point

    // The first premise: at this pixel the frame draws the solid, not the line
    // beneath it. The face scope reads the drawn surface directly, so its
    // answer is the measurement of what covers the line.
    let covering = try await sketchScopePicks(
        mount: fixture.mountInputs,
        control: control,
        selectionHitPolicy: .face,
        readyPoint: point,
        points: [point]
    )
    let faceHit = try #require(
        covering[0].target.hit,
        "The frame drew no prepared CAD face over the occluded pointer."
    )
    #expect(faceHit.sceneNodeID == fixture.solidSceneNodeID)
    guard case .face = try #require(faceHit.selectionComponent) else {
        Issue.record("The covering pointer resolved \(String(describing: faceHit.selectionComponent)).")
        return
    }

    // The second premise: the line is drawn at this same pixel.
    // `viewportNativeSketchEntityScopeFixtureSeparatesItsThreePointers` states
    // it, by placing the whole line on the world plane the overlay producer
    // draws sketches on, putting the solid in front of that plane, and holding
    // this pointer inside the solid's silhouette and clear of both line ends.
    // Without depth the pointer would therefore answer the line.

    // The rule: the frame draws the polyline at scene depth, so the body in
    // front of it hides it, and nothing behind that body answers instead.
    let observations = try await sketchScopePicks(
        mount: fixture.mountInputs,
        control: control,
        selectionHitPolicy: .sketchEntity,
        readyPoint: geometry.clear.point,
        points: [point]
    )
    #expect(observations[0].target.hit == nil)
}

@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeSketchEntityScopeSelectsNothingWhereTheFrameDrewNothing() async throws {
    _ = NSApplication.shared
    let fixture = try sketchScopeSelectionFixture()
    let control = sketchScopeControlSession()
    let geometry = try sketchScopeScreenGeometry(fixture: fixture, control: control)
    // A pixel on the same screen row as the pointers that do select, left of
    // everything the frame draws by more than the hit tolerance rather than
    // assumed to be outside it.
    //
    // The row is part of the premise, not a convenience. `pick` maps the
    // pointer onto the construction plane before it publishes anything, and
    // `showsConstructionPlaneHover` defaults to false, so that plane is `.xy`
    // for every pointer here. This fixture looks along the y axis, which sees
    // `.xy` edge-on, so the mapping is defined on only one side of the row
    // where that plane crosses the screen. The readiness pointer proves this
    // row is the defined side, which keeps the pixel below a question about
    // what the frame drew rather than about where the construction plane lies.
    let tolerance = Double(ViewportNativeCADTopologyResolver.pointTolerance)
    let drawn = geometry.drawnSilhouette
    let emptyPoint = CGPoint(
        x: drawn.minX - ViewportNativeCADTopologyResolver.pointTolerance * 4.0,
        y: geometry.clear.point.y
    )
    #expect(emptyPoint.x > 0.0)
    #expect(Double(drawn.minX - emptyPoint.x) > tolerance * 2.0)

    let observations = try await sketchScopePicks(
        mount: fixture.mountInputs,
        control: control,
        selectionHitPolicy: .sketchEntity,
        readyPoint: geometry.clear.point,
        points: [emptyPoint]
    )

    // The readiness pointer resolved on this same mounted frame, so the frame
    // answered here too and drew nothing. The scene carries sketch entities, so
    // the native query is supported and reports the empty pixel as the miss it
    // is rather than as an unanswerable scope.
    #expect(observations[0].target.hit == nil)
}

// MARK: - Combined scope

@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeCombinedScopeSelectsTheSketchLineThroughTheNativeFrame() async throws {
    _ = NSApplication.shared
    let fixture = try sketchScopeSelectionFixture()
    let control = sketchScopeControlSession()
    let geometry = try sketchScopeScreenGeometry(fixture: fixture, control: control)

    let observations = try await sketchScopePicks(
        mount: fixture.mountInputs,
        control: control,
        selectionHitPolicy: .all,
        readyPoint: geometry.clear.point,
        points: [geometry.clear.point]
    )

    // The combined scope admits the occurrence family too, so the sketch entity
    // has to be produced as a candidate this query orders itself rather than
    // won by default because nothing else competed for the pixel.
    let hit = try #require(observations[0].target.hit)
    #expect(hit.featureID == fixture.lineFeatureID)
    #expect(hit.kind == .sketch)
    #expect(hit.sketchEntityID == fixture.lineEntityID)
    #expect(hit.selectionComponent == nil)
}

// MARK: - Section

@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeCombinedScopeRefusesASketchLineTheSectionRemoved() async throws {
    _ = NSApplication.shared
    let fixture = try sketchScopeSelectionFixture()
    let control = sketchScopeControlSession()
    let geometry = try sketchScopeScreenGeometry(fixture: fixture, control: control)
    let section = try sketchScopeSection(fixture: fixture)

    // The premise: the removed pointer lies on the drawn line and outside the
    // solid, so only the section can refuse it.
    // `viewportNativeSketchEntityScopeFixtureSeparatesItsThreePointers` states
    // it, by holding this pointer clear of the solid's silhouette and of both
    // line ends while placing it on the discarded side of the resolved plane.

    let observations = try await sketchScopePicks(
        mount: fixture.mountInputs,
        control: control,
        selectionHitPolicy: .all,
        sectionAnalysis: section.analysis,
        sectionClippingPlan: section.plan,
        readyPoint: geometry.clear.point,
        points: [geometry.clear.point, geometry.mirror.point]
    )

    // The kept half is answered on the same frame, which is what separates the
    // section rule from a query that stopped answering. The removed half is
    // refused by the same frame rather than by a scope that declined to ask.
    let kept = try #require(observations[0].target.hit)
    #expect(kept.sketchEntityID == fixture.lineEntityID)
    #expect(observations[1].target.hit == nil)
}

// MARK: - Suppressed profile sketch

private enum SketchScopeSuppressionFixtureError: Error {
    case missingFeature
    case missingProfileSketch
    case missingProfileTopEdge
    case missingReadinessSketch
    case missingSolidBody
}

/// The profile rectangle's side, the distance it is extruded, and where the
/// second sketch runs.
///
/// The profile is square and the extrusion is shallow, so on the `-y` camera
/// the other fixture uses the body covers a band only as tall as the extrusion
/// while the profile's own top edge stands half the square above the plane it
/// was drawn on. That gap is what leaves one edge of a consumed profile drawn
/// in the clear, which is the only place a suppression rule can be observed:
/// an edge the body covers would be refused whether the rule ran or not.
///
/// The second sketch is placed on the same height and past the profile's far
/// side, so the readiness pointer shares the suppression pointer's screen row
/// without sharing anything else on the frame.
private let sketchScopeProfileSideMillimeters = 320.0
private let sketchScopeProfileDepthMillimeters = 40.0
private let sketchScopeReadinessNearXMillimeters = 300.0
private let sketchScopeReadinessFarXMillimeters = 480.0

/// A scene carrying a profile sketch, the body extruded from it, and a second
/// sketch nothing consumes.
///
/// `createExtrudedRectangle` nests its profile under the body and hides it, so
/// a scene built that way carries no suppressible sketch at all. The general
/// route — `createRectangleSketch` then `extrudeProfile` — leaves the profile a
/// visible scene item that the body item names through `sourceFeatureID`, which
/// is the shape `viewportHitTesterSelectsBodyInteriorAndSketchEdges` already
/// builds and the only shape the suppression rule applies to.
struct SketchScopeSuppressionFixture {
    let mountInputs: SketchScopeMountInputs
    let document: DesignDocument
    let cpuScene: ViewportScene
    let layout: ViewportLayout
    let profileFeatureID: FeatureID
    let profileTopEdgeEntityID: SketchEntityID
    let profileSilhouette: CGRect
    let solidFeatureID: FeatureID
    let solidSceneNodeID: SceneNodeID
    let solidSourceFeatureID: FeatureID?
    let solidSilhouette: CGRect
    let readinessFeatureID: FeatureID
    let readinessSilhouette: CGRect
    /// A pointer on the midpoint of the profile's top edge.
    let profilePoint: CGPoint
    /// A pointer on the midpoint of the second sketch's line.
    let readyPoint: CGPoint
}

@MainActor
func sketchScopeSuppressionFixture(
    control: ViewportControlSession
) throws -> SketchScopeSuppressionFixture {
    let session = EditorSession()
    _ = try session.execute(.createRectangleSketch(
        name: "Sketch Scope Profile",
        plane: .xy,
        width: .length(sketchScopeProfileSideMillimeters, .millimeter),
        height: .length(sketchScopeProfileSideMillimeters, .millimeter)
    ))
    guard let profileFeatureID = session.document.cadDocument.designGraph.order.last else {
        throw SketchScopeSuppressionFixtureError.missingFeature
    }
    _ = try session.execute(.extrudeProfile(
        name: "Sketch Scope Consuming Body",
        profile: ProfileReference(featureID: profileFeatureID),
        distance: .length(sketchScopeProfileDepthMillimeters, .millimeter),
        direction: .normal
    ))
    guard let solidFeatureID = session.document.cadDocument.designGraph.order.last,
          solidFeatureID != profileFeatureID else {
        throw SketchScopeSuppressionFixtureError.missingFeature
    }
    _ = try session.execute(.createLineSketch(
        name: "Sketch Scope Readiness Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(sketchScopeReadinessNearXMillimeters, .millimeter),
            y: .length(sketchScopeProfileSideMillimeters / 2.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(sketchScopeReadinessFarXMillimeters, .millimeter),
            y: .length(sketchScopeProfileSideMillimeters / 2.0, .millimeter)
        )
    ))
    guard let readinessFeatureID = session.document.cadDocument.designGraph.order.last,
          readinessFeatureID != solidFeatureID else {
        throw SketchScopeSuppressionFixtureError.missingFeature
    }
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
    let layout = sketchScopeLayout(
        ruler: ruler,
        cpuScene: cpuScene,
        presentationScene: presentationScene,
        control: control
    )

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

    guard let solidItem = cpuScene.items.first(where: { $0.featureID == solidFeatureID }),
          case .body(let solidComponent) = solidItem.kind,
          let solidTopology = solidComponent.topology,
          let solidSceneNodeID = solidItem.sceneNodeID else {
        throw SketchScopeSuppressionFixtureError.missingSolidBody
    }
    guard let profileItem = cpuScene.items.first(where: { $0.featureID == profileFeatureID }),
          case .sketch(let profilePrimitives) = profileItem.kind else {
        throw SketchScopeSuppressionFixtureError.missingProfileSketch
    }
    guard let readinessItem = cpuScene.items.first(where: {
        $0.featureID == readinessFeatureID
    }), case .sketch(let readinessPrimitives) = readinessItem.kind,
          readinessPrimitives.count == 1 else {
        throw SketchScopeSuppressionFixtureError.missingReadinessSketch
    }

    // Both pointers are taken from the polylines the overlay producer emitted,
    // so they sit on the curves the query measures rather than on a second
    // mapping of the authored coordinates. The profile's top edge is found by
    // height rather than by index, so a builder that orders the rectangle's
    // four lines differently moves the pointer with it.
    var profileWorldPoints: [Point3D] = []
    var topEdge: (entityID: SketchEntityID, start: Point3D, end: Point3D)?
    for primitive in profilePrimitives {
        let points = try ViewportSpatialOverlayProducer.sketchPrimitiveWorldPoints(primitive)
        profileWorldPoints.append(contentsOf: points)
        guard points.count == 2, abs(points[0].z - points[1].z) < 1.0e-9 else { continue }
        guard topEdge.map({ points[0].z > $0.start.z }) ?? true else { continue }
        topEdge = (primitive.entityID, points[0], points[1])
    }
    guard let topEdge else {
        throw SketchScopeSuppressionFixtureError.missingProfileTopEdge
    }
    let readinessWorldPoints = try ViewportSpatialOverlayProducer.sketchPrimitiveWorldPoints(
        readinessPrimitives[0]
    )
    guard readinessWorldPoints.count == 2 else {
        throw SketchScopeSuppressionFixtureError.missingReadinessSketch
    }
    func midpoint(_ start: Point3D, _ end: Point3D) -> Point3D {
        Point3D(
            x: (start.x + end.x) / 2.0,
            y: (start.y + end.y) / 2.0,
            z: (start.z + end.z) / 2.0
        )
    }
    let profileWorld = midpoint(topEdge.start, topEdge.end)
    let readyWorld = midpoint(readinessWorldPoints[0], readinessWorldPoints[1])

    return SketchScopeSuppressionFixture(
        mountInputs: SketchScopeMountInputs(
            document: document,
            presentationScene: presentationScene,
            sceneNodeIDByOccurrenceID: projection.sceneNodeIDByOccurrenceID,
            currentEvaluation: currentEvaluation,
            generation: session.generation,
            ruler: ruler,
            interactionSceneNodeIDs: exactPresentationCADSceneNodeIDs(
                scene: presentationScene,
                sceneNodeIDByOccurrenceID: projection.sceneNodeIDByOccurrenceID,
                document: document,
                generation: session.generation,
                cadInteraction: currentEvaluation
            )
        ),
        document: document,
        cpuScene: cpuScene,
        layout: layout,
        profileFeatureID: profileFeatureID,
        profileTopEdgeEntityID: topEdge.entityID,
        profileSilhouette: try silhouette(of: profileWorldPoints, name: "profile"),
        solidFeatureID: solidFeatureID,
        solidSceneNodeID: solidSceneNodeID,
        solidSourceFeatureID: solidItem.sourceFeatureID,
        solidSilhouette: try silhouette(
            of: solidTopology.vertices.map {
                ViewportLayout.transformedPoint($0.point, by: solidItem.modelTransform)
            },
            name: "solid vertex"
        ),
        readinessFeatureID: readinessFeatureID,
        readinessSilhouette: try silhouette(of: readinessWorldPoints, name: "readiness"),
        profilePoint: try #require(
            layout.projectedPoint(profileWorld)?.point,
            "The fixture layout projects no point for the profile pointer."
        ),
        readyPoint: try #require(
            layout.projectedPoint(readyWorld)?.point,
            "The fixture layout projects no point for the readiness pointer."
        )
    )
}

/// The premises the suppression rule is measured against: that the frame draws
/// a profile sketch beside the body that consumes it, that the body names that
/// profile, that the pointer on the profile is clear of everything else the
/// frame draws, and that the readiness pointer shares its screen row.
@MainActor
@Test(.timeLimit(.minutes(3)))
func viewportNativeSketchEntityScopeSuppressionFixtureDrawsAProfileClearOfItsBody() async throws {
    _ = NSApplication.shared
    let control = sketchScopeControlSession()
    let fixture = try sketchScopeSuppressionFixture(control: control)

    // The general extrude route leaves the profile a scene item of its own, so
    // the frame draws three things and the body names the profile it consumed.
    #expect(fixture.cpuScene.items.count == 3)
    #expect(fixture.solidSourceFeatureID == fixture.profileFeatureID)
    // The rule the native query reads resolves the selection by scene node
    // where an item has one, so the body has to carry one.
    #expect(
        fixture.cpuScene.items.contains {
            $0.featureID == fixture.solidFeatureID && $0.sceneNodeID == fixture.solidSceneNodeID
        }
    )

    let tolerance = Double(ViewportNativeCADTopologyResolver.pointTolerance)
    func clearance(_ point: CGPoint, of rect: CGRect) -> Double {
        let dx = max(rect.minX - point.x, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, point.y - rect.maxY)
        return Double(max(dx, dy))
    }
    // Nothing the frame draws in front of the profile pointer, and nothing
    // within the hit tolerance of it, so the only thing that can change its
    // answer between two mounts is the selection.
    #expect(fixture.solidSilhouette.contains(fixture.profilePoint) == false)
    #expect(clearance(fixture.profilePoint, of: fixture.solidSilhouette) > tolerance * 2.0)
    #expect(clearance(fixture.profilePoint, of: fixture.readinessSilhouette) > tolerance * 2.0)
    // The readiness pointer is on the second sketch, clear of the profile and
    // of the body, so a mount that suppresses the profile still resolves it.
    #expect(clearance(fixture.readyPoint, of: fixture.profileSilhouette) > tolerance * 2.0)
    #expect(clearance(fixture.readyPoint, of: fixture.solidSilhouette) > tolerance * 2.0)
    // Both pointers share a screen row, so the row the suppression pointer is
    // asked on is the row a resolved pointer has already proven `pick` maps.
    #expect(abs(fixture.readyPoint.y - fixture.profilePoint.y) < 0.5)
}

/// A sketch the frame stopped drawing is not answered, in either scope that
/// reaches the sketch families and in the combined scope.
///
/// `ViewportSpatialOverlayProducer` stops drawing a sketch once the body it
/// feeds is selected, because the body replaced it on screen. The two mounts
/// below differ only in that selection, so the pointer that selects the
/// profile's top edge on the first mount is asking, on the second, for
/// something the frame is not drawing.
///
/// `.object` and `.all` reach the sketch families through the same gate, so
/// they are asked here too. No resolver stands behind the mounted frame to
/// reinstate what it stopped drawing, so the same pointer has to come back
/// empty in all three scopes.
@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeSketchEntityScopeRefusesTheProfileSketchTheFrameSuppressed() async throws {
    _ = NSApplication.shared
    let control = sketchScopeControlSession()
    let fixture = try sketchScopeSuppressionFixture(control: control)
    var selectingTheBody = SelectionModel()
    try selectingTheBody.selectSceneNode(fixture.solidSceneNodeID, in: fixture.document)
    #expect(selectingTheBody.containsSceneNode(fixture.solidSceneNodeID))

    for policy in [ViewportSelectionHitPolicy.sketchEntity, .object, .all] {
        let drawn = try await sketchScopePicks(
            mount: fixture.mountInputs,
            control: control,
            selectionHitPolicy: policy,
            readyPoint: fixture.readyPoint,
            points: [fixture.profilePoint]
        )
        let hit = try #require(
            drawn[0].target.hit,
            "The \(policy) scope answers nothing on the drawn profile edge."
        )
        #expect(hit.featureID == fixture.profileFeatureID)
        #expect(hit.sketchEntityID == fixture.profileTopEdgeEntityID)

        let suppressed = try await sketchScopePicks(
            mount: fixture.mountInputs,
            control: control,
            selection: selectingTheBody,
            selectionHitPolicy: policy,
            readyPoint: fixture.readyPoint,
            points: [fixture.profilePoint]
        )
        #expect(suppressed[0].target.hit == nil)
    }
}
