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

private enum RegionScopeFixtureError: Error {
    case missingFeature
    case missingProfileRegion
    case missingProfileSketch
    case missingSolidBody
    case missingStandaloneRegion
    case missingStandaloneSketch
}

/// The profile rectangle's side, how far it is extruded, and where the sketch
/// nothing consumes is drawn.
///
/// The profile is square and the extrusion is shallow, so on the `-y` camera
/// these tests look through, the body covers a band only as tall as the
/// extrusion while the profile's own region reaches half the square above the
/// plane it was drawn on. The standalone rectangle is placed past the profile's
/// far side and spans exactly the height of that clear band, which puts a
/// pointer at its centre on the same screen row as a pointer inside the profile
/// region that the body does not cover.
private let regionScopeProfileSideMillimeters = 320.0
private let regionScopeProfileDepthMillimeters = 40.0
private let regionScopeStandaloneNearXMillimeters = 240.0
private let regionScopeStandaloneFarXMillimeters = 400.0
private let regionScopeStandaloneNearYMillimeters = 40.0
private let regionScopeStandaloneFarYMillimeters = 160.0

/// A scene carrying a profile sketch, the body extruded from it, and a second
/// rectangle sketch nothing consumes.
///
/// The second rectangle is not decoration. The suppression rule this file owns
/// is observed by mounting the same scene twice and selecting the body on the
/// second mount, and a mounted frame is only known to answer once a pointer
/// selects something on it. Under the `region` scope nothing but a region can
/// be that pointer, so the sketch the extrude consumed cannot be the only one
/// the scene carries: the mount that suppresses it would have no way left to
/// prove it answered at all.
///
/// `createExtrudedRectangle` nests its profile under the body and hides it, so
/// a scene built that way carries no suppressible sketch. The general route —
/// `createRectangleSketch` then `extrudeProfile` — leaves the profile a visible
/// scene item that the body item names through `sourceFeatureID`, which is the
/// only shape the suppression rule applies to.
struct RegionScopeSelectionFixture {
    let mountInputs: SketchScopeMountInputs
    let document: DesignDocument
    let cpuScene: ViewportScene
    let layout: ViewportLayout
    let profileFeatureID: FeatureID
    let profileRegionComponentID: SelectionComponentID
    /// The profile region's boundary, projected through the layout the frame is
    /// fitted with, so a pointer is tested against the polygon on screen.
    let profileRegionBoundary: [CGPoint]
    let profileSilhouette: CGRect
    let standaloneFeatureID: FeatureID
    let standaloneRegionComponentID: SelectionComponentID
    let standaloneRegionBoundary: [CGPoint]
    let standaloneSilhouette: CGRect
    let solidFeatureID: FeatureID
    let solidSceneNodeID: SceneNodeID
    let solidSourceFeatureID: FeatureID?
    let solidSilhouette: CGRect
    /// The projected extent of everything the frame draws, used only to name a
    /// pixel outside all of it.
    let drawnSilhouette: CGRect
    let sketchRegionCounts: [Int]
    let sketchItemCount: Int
    let bodyItemCount: Int
    /// A pointer inside the profile's region, on the part of it the body does
    /// not cover.
    let profilePoint: CGPoint
    /// A pointer at the centre of the standalone rectangle's region.
    let readyPoint: CGPoint
    /// A pointer on the same row as the other two, left of everything drawn.
    let emptyPoint: CGPoint
}

@MainActor
func regionScopeSelectionFixture(
    control: ViewportControlSession
) throws -> RegionScopeSelectionFixture {
    let session = EditorSession()
    _ = try session.execute(.createRectangleSketch(
        name: "Region Scope Profile",
        plane: .xy,
        width: .length(regionScopeProfileSideMillimeters, .millimeter),
        height: .length(regionScopeProfileSideMillimeters, .millimeter)
    ))
    guard let profileFeatureID = session.document.cadDocument.designGraph.order.last else {
        throw RegionScopeFixtureError.missingFeature
    }
    _ = try session.execute(.extrudeProfile(
        name: "Region Scope Consuming Body",
        profile: ProfileReference(featureID: profileFeatureID),
        distance: .length(regionScopeProfileDepthMillimeters, .millimeter),
        direction: .normal
    ))
    guard let solidFeatureID = session.document.cadDocument.designGraph.order.last,
          solidFeatureID != profileFeatureID else {
        throw RegionScopeFixtureError.missingFeature
    }
    _ = try session.execute(.createRectangleSketchFromCorners(
        name: "Region Scope Standalone Profile",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(regionScopeStandaloneNearXMillimeters, .millimeter),
            y: .length(regionScopeStandaloneNearYMillimeters, .millimeter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(regionScopeStandaloneFarXMillimeters, .millimeter),
            y: .length(regionScopeStandaloneFarYMillimeters, .millimeter)
        )
    ))
    guard let standaloneFeatureID = session.document.cadDocument.designGraph.order.last,
          standaloneFeatureID != solidFeatureID else {
        throw RegionScopeFixtureError.missingFeature
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

    func projected(_ world: Point3D, name: String) throws -> CGPoint {
        try #require(
            layout.projectedPoint(world)?.point,
            "The fixture layout projects no point for \(name)."
        )
    }
    func silhouette(of points: [CGPoint]) -> CGRect {
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    guard let solidItem = cpuScene.items.first(where: { $0.featureID == solidFeatureID }),
          case .body(let solidComponent) = solidItem.kind,
          let solidTopology = solidComponent.topology,
          let solidSceneNodeID = solidItem.sceneNodeID else {
        throw RegionScopeFixtureError.missingSolidBody
    }
    guard let profileItem = cpuScene.items.first(where: { $0.featureID == profileFeatureID }),
          case .sketch = profileItem.kind else {
        throw RegionScopeFixtureError.missingProfileSketch
    }
    guard let profileRegion = profileItem.sketchRegions.first else {
        throw RegionScopeFixtureError.missingProfileRegion
    }
    guard let standaloneItem = cpuScene.items.first(where: {
        $0.featureID == standaloneFeatureID
    }), case .sketch = standaloneItem.kind else {
        throw RegionScopeFixtureError.missingStandaloneSketch
    }
    guard let standaloneRegion = standaloneItem.sketchRegions.first else {
        throw RegionScopeFixtureError.missingStandaloneRegion
    }

    // Both regions are read through the mapping the overlay producer drew them
    // with, which is the mapping the query reads, so the pointers below sit on
    // the polygons the frame answers about rather than on a second reading of
    // the authored coordinates. Their extents in that sketch space are what
    // places the pointers, so no assumption about the authored unit enters.
    func boundary(of region: ViewportSketchRegion, name: String) throws -> [CGPoint] {
        try region.points.map {
            try projected(ViewportSpatialOverlayProducer.point($0), name: "a \(name) corner")
        }
    }
    func sketchBounds(of region: ViewportSketchRegion) -> CGRect {
        silhouette(of: region.points)
    }
    let profileRegionBoundary = try boundary(of: profileRegion, name: "profile region")
    let standaloneRegionBoundary = try boundary(of: standaloneRegion, name: "standalone region")
    let standaloneSketchBounds = sketchBounds(of: standaloneRegion)
    let profileSketchBounds = sketchBounds(of: profileRegion)
    // The standalone rectangle spans exactly the band of the profile the body
    // leaves clear, so its centre row is a row on which the profile region is
    // drawn and the body is not.
    let readySketchPoint = CGPoint(
        x: standaloneSketchBounds.midX,
        y: standaloneSketchBounds.midY
    )
    let profileSketchPoint = CGPoint(
        x: profileSketchBounds.midX,
        y: standaloneSketchBounds.midY
    )

    let solidSilhouette = silhouette(
        of: try solidTopology.vertices.map {
            try projected(
                ViewportLayout.transformedPoint($0.point, by: solidItem.modelTransform),
                name: "a solid vertex"
            )
        }
    )
    let profileSilhouette = silhouette(of: profileRegionBoundary)
    let standaloneSilhouette = silhouette(of: standaloneRegionBoundary)
    let drawnSilhouette = profileSilhouette
        .union(standaloneSilhouette)
        .union(solidSilhouette)
    let readyPoint = try projected(
        ViewportSpatialOverlayProducer.point(readySketchPoint),
        name: "the readiness pointer"
    )
    let profilePoint = try projected(
        ViewportSpatialOverlayProducer.point(profileSketchPoint),
        name: "the profile pointer"
    )
    // Containment under this scope is exact, so the pixel below is outside
    // every region by construction. The tolerance-wide margin keeps it outside
    // anything else the frame draws as well, which is what makes the empty
    // answer a statement about the region family rather than about a near miss.
    let emptyPoint = CGPoint(
        x: drawnSilhouette.minX - ViewportNativeCADTopologyResolver.pointTolerance * 4.0,
        y: readyPoint.y
    )

    return RegionScopeSelectionFixture(
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
        profileRegionComponentID: profileRegion.componentID,
        profileRegionBoundary: profileRegionBoundary,
        profileSilhouette: profileSilhouette,
        standaloneFeatureID: standaloneFeatureID,
        standaloneRegionComponentID: standaloneRegion.componentID,
        standaloneRegionBoundary: standaloneRegionBoundary,
        standaloneSilhouette: standaloneSilhouette,
        solidFeatureID: solidFeatureID,
        solidSceneNodeID: solidSceneNodeID,
        solidSourceFeatureID: solidItem.sourceFeatureID,
        solidSilhouette: solidSilhouette,
        drawnSilhouette: drawnSilhouette,
        sketchRegionCounts: cpuScene.items.compactMap {
            guard case .sketch = $0.kind else { return nil }
            return $0.sketchRegions.count
        },
        sketchItemCount: cpuScene.items.filter {
            if case .sketch = $0.kind { return true }
            return false
        }.count,
        bodyItemCount: cpuScene.items.filter {
            if case .body = $0.kind { return true }
            return false
        }.count,
        profilePoint: profilePoint,
        readyPoint: readyPoint,
        emptyPoint: emptyPoint
    )
}

// MARK: - Mounted point harness

@MainActor
private func regionScopeControlSession() -> ViewportControlSession {
    ViewportControlSession(camera: .init(projection: .parallel), basis: .axisFront(.y))
}

private struct RegionScopePickObservation {
    var point: CGPoint
    var target: ViewportCanvasTarget
}

/// Drives `onPick` on a mounted viewport under the `region` scope and reports
/// what each pointer resolved to.
///
/// The frame is proven ready by `readyPoint` before any other pointer is asked:
/// `pick` returns without calling `onPick` while the mounted frame cannot
/// answer, and calls it with a `nil` hit once the frame answers and nothing was
/// drawn there, so only a pointer that must select something separates the two.
/// `pick` is also silent where it cannot map the pointer onto the construction
/// plane, so every pointer passed here is on a row the readiness pointer has
/// shown that mapping to be defined on.
@MainActor
private func regionScopePicks(
    mount: SketchScopeMountInputs,
    control: ViewportControlSession,
    selection: SelectionModel = SelectionModel(),
    readyPoint: CGPoint,
    points: [CGPoint]
) async throws -> [RegionScopePickObservation] {
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
        sectionAnalysis: nil,
        sectionClippingPlan: nil,
        selectionHitPolicy: .region,
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
        "The mounted region frame never resolved the readiness pointer \(readyPoint)."
    )
    print("[cost] scope=region ready=\(readyPoint) attempts=\(attempts)")

    var observations: [RegionScopePickObservation] = []
    for point in points {
        targets.removeAll()
        input(in: controller.view)?.onPick?(point, size, .replace)
        let target = try #require(
            targets.first,
            "The mounted region frame refused to answer the pointer \(point)."
        )
        #expect(targets.count == 1)
        observations.append(RegionScopePickObservation(point: point, target: target))
    }
    return observations
}

/// Even-odd containment against a projected boundary, which is the rule the
/// resolver applies to the same polygon.
private func regionScopeContains(_ point: CGPoint, in boundary: [CGPoint]) -> Bool {
    guard boundary.count >= 3 else { return false }
    var inside = false
    var previous = boundary.count - 1
    for current in boundary.indices {
        let a = boundary[current]
        let b = boundary[previous]
        if (a.y > point.y) != (b.y > point.y) {
            let crossing = a.x + (point.y - a.y) / (b.y - a.y) * (b.x - a.x)
            if point.x < crossing {
                inside.toggle()
            }
        }
        previous = current
    }
    return inside
}

private func regionScopeClearance(_ point: CGPoint, of rect: CGRect) -> Double {
    let dx = max(rect.minX - point.x, point.x - rect.maxX)
    let dy = max(rect.minY - point.y, point.y - rect.maxY)
    return Double(max(dx, dy))
}

// MARK: - Fixture invariants

/// The premises every rule below reads: that the scene carries two sketches
/// with one region each and a body naming the profile, that each pointer is
/// inside exactly the region it is named for, and that all three share a screen
/// row inside the mounted viewport.
///
/// Without the first of these a later change to profile extraction could leave
/// the scene with no region under a pointer and turn every case below into a
/// statement about an empty scene.
@MainActor
@Test(.timeLimit(.minutes(3)))
func viewportNativeRegionScopeFixtureCarriesTwoRegionsOnOneRow() async throws {
    _ = NSApplication.shared
    let control = regionScopeControlSession()
    let fixture = try regionScopeSelectionFixture(control: control)

    // The general extrude route leaves the profile a scene item of its own, so
    // the frame draws two sketches and one body, and the body names the profile
    // it consumed.
    #expect(fixture.sketchItemCount == 2)
    #expect(fixture.bodyItemCount == 1)
    #expect(fixture.sketchRegionCounts == [1, 1])
    #expect(fixture.solidSourceFeatureID == fixture.profileFeatureID)
    #expect(fixture.profileRegionComponentID != fixture.standaloneRegionComponentID)
    // The rule the native query reads resolves suppression by scene node, so
    // the body has to carry one.
    #expect(
        fixture.cpuScene.items.contains {
            $0.featureID == fixture.solidFeatureID && $0.sceneNodeID == fixture.solidSceneNodeID
        }
    )

    // Each pointer is inside exactly the region it is named for, measured
    // against the projected boundary the query is asked about.
    #expect(regionScopeContains(fixture.readyPoint, in: fixture.standaloneRegionBoundary))
    #expect(regionScopeContains(fixture.readyPoint, in: fixture.profileRegionBoundary) == false)
    #expect(regionScopeContains(fixture.profilePoint, in: fixture.profileRegionBoundary))
    #expect(
        regionScopeContains(fixture.profilePoint, in: fixture.standaloneRegionBoundary) == false
    )
    #expect(regionScopeContains(fixture.emptyPoint, in: fixture.profileRegionBoundary) == false)
    #expect(
        regionScopeContains(fixture.emptyPoint, in: fixture.standaloneRegionBoundary) == false
    )

    let tolerance = Double(ViewportNativeCADTopologyResolver.pointTolerance)
    // The body does not cover the profile pointer, so the only thing that can
    // change its answer between two mounts is the selection.
    #expect(fixture.solidSilhouette.contains(fixture.profilePoint) == false)
    #expect(regionScopeClearance(fixture.profilePoint, of: fixture.solidSilhouette) > tolerance)
    // The empty pointer is outside everything the frame draws by more than the
    // hit tolerance, and inside the mounted viewport.
    #expect(Double(fixture.drawnSilhouette.minX - fixture.emptyPoint.x) > tolerance * 2.0)
    #expect(fixture.emptyPoint.x > 0.0)
    #expect(fixture.readyPoint.x < sketchScopeViewportSize.width)
    #expect(fixture.readyPoint.y > 0.0)
    #expect(fixture.readyPoint.y < sketchScopeViewportSize.height)
    // All three pointers share a screen row, so the row each is asked on is the
    // row a resolved pointer has already proven `pick` maps onto the
    // construction plane.
    #expect(abs(fixture.readyPoint.y - fixture.profilePoint.y) < 0.5)
    #expect(abs(fixture.readyPoint.y - fixture.emptyPoint.y) < 0.5)
}

// MARK: - Region scope

/// A pointer inside a region the frame drew selects that region, named by the
/// `SelectionComponent` the scene prepared for it.
@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeRegionScopeSelectsTheRegionUnderThePointer() async throws {
    _ = NSApplication.shared
    let control = regionScopeControlSession()
    let fixture = try regionScopeSelectionFixture(control: control)

    let observations = try await regionScopePicks(
        mount: fixture.mountInputs,
        control: control,
        readyPoint: fixture.readyPoint,
        points: [fixture.readyPoint]
    )

    let hit = try #require(
        observations[0].target.hit,
        "The region scope answers nothing inside the standalone region."
    )
    #expect(hit.pickingBackend == .native)
    #expect(hit.kind == .sketch)
    #expect(hit.featureID == fixture.standaloneFeatureID)
    #expect(hit.selectionComponent == .region(fixture.standaloneRegionComponentID))
}

/// The profile sketch the extrude consumed is still drawn, so the region inside
/// it answers the same way — which is the premise the suppression rule below
/// removes.
@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeRegionScopeSelectsTheProfileRegionTheFrameDraws() async throws {
    _ = NSApplication.shared
    let control = regionScopeControlSession()
    let fixture = try regionScopeSelectionFixture(control: control)

    let observations = try await regionScopePicks(
        mount: fixture.mountInputs,
        control: control,
        readyPoint: fixture.readyPoint,
        points: [fixture.profilePoint]
    )

    let hit = try #require(
        observations[0].target.hit,
        "The region scope answers nothing inside the drawn profile region."
    )
    #expect(hit.pickingBackend == .native)
    #expect(hit.kind == .sketch)
    #expect(hit.featureID == fixture.profileFeatureID)
    #expect(hit.selectionComponent == .region(fixture.profileRegionComponentID))
}

/// A pointer outside every region selects nothing, and that empty answer is the
/// native frame's own miss.
///
/// The `region` scope routes no miss into the replaced identity resolver, so
/// nothing downstream can reinstate a region the frame did not draw here. The
/// readiness pointer resolved on this same mounted frame, so the frame answered
/// at this pixel too and drew no region there.
@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeRegionScopeSelectsNothingWhereTheFrameDrewNoRegion() async throws {
    _ = NSApplication.shared
    let control = regionScopeControlSession()
    let fixture = try regionScopeSelectionFixture(control: control)

    let observations = try await regionScopePicks(
        mount: fixture.mountInputs,
        control: control,
        readyPoint: fixture.readyPoint,
        points: [fixture.emptyPoint]
    )

    #expect(observations[0].target.hit == nil)
}

// MARK: - Suppressed profile sketch

/// A region the frame stopped drawing is not answered.
///
/// `ViewportSpatialOverlayProducer` stops drawing a sketch once the body it
/// feeds is selected, because the body replaced it on screen, and it applies
/// that rule to the sketch's regions exactly as it does to its entities. The
/// two mounts below differ only in that selection, so the pointer that selects
/// the profile's region on the first mount is asking, on the second, for
/// something the frame is not drawing.
///
/// The standalone region is asked on the suppressed mount as well. It is the
/// evidence that the frame answered there at all, and that what it suppressed
/// is the consumed profile rather than the region family.
@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeRegionScopeRefusesTheProfileRegionTheFrameSuppressed() async throws {
    _ = NSApplication.shared
    let control = regionScopeControlSession()
    let fixture = try regionScopeSelectionFixture(control: control)
    var selectingTheBody = SelectionModel()
    try selectingTheBody.selectSceneNode(fixture.solidSceneNodeID, in: fixture.document)
    #expect(selectingTheBody.containsSceneNode(fixture.solidSceneNodeID))

    let suppressed = try await regionScopePicks(
        mount: fixture.mountInputs,
        control: control,
        selection: selectingTheBody,
        readyPoint: fixture.readyPoint,
        points: [fixture.readyPoint, fixture.profilePoint]
    )

    let standalone = try #require(
        suppressed[0].target.hit,
        "The suppressed mount answers nothing inside the standalone region."
    )
    #expect(standalone.pickingBackend == .native)
    #expect(standalone.featureID == fixture.standaloneFeatureID)
    #expect(standalone.selectionComponent == .region(fixture.standaloneRegionComponentID))
    #expect(suppressed[1].target.hit == nil)
}
