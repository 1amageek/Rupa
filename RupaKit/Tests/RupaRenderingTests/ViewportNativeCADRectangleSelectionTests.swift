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

private enum RectangleSelectionFixtureError: Error {
    case missingSceneNode
    case missingTopology
    case missingModelingRepresentation
}

struct RectangleSelectionFixture {
    let document: DesignDocument
    let presentationScene: UniversalViewportScene
    let sceneNodeIDByOccurrenceID: [SceneOccurrenceID: SceneNodeID]
    let currentEvaluation: DocumentEvaluationContext
    let generation: DocumentGeneration
    let ruler: RulerConfiguration
    let cpuScene: ViewportScene
    let cadSceneNodeID: SceneNodeID
    let cadOccurrenceID: SceneOccurrenceID
    let meshSceneNodeID: SceneNodeID
    let meshOccurrenceID: SceneOccurrenceID
    let topology: ViewportBodyTopology
    let modelTransform: Transform3D
    let triangleCount: Int
    let interactionSceneNodeIDs: Set<SceneNodeID>
}

/// The screen geometry of the CAD body, measured with the same layout the
/// mounted viewport builds for the supplied scene and presentation bounds.
struct RectangleSelectionScreenGeometry {
    let layout: ViewportLayout
    let silhouette: CGRect
    let vertexPoints: [SelectionComponentID: CGPoint]
    let worldVertices: [SelectionComponentID: Point3D]
    let worldBounds: (minX: Double, maxX: Double, minY: Double, maxY: Double, minZ: Double, maxZ: Double)
}

let rectangleSelectionViewportSize = CGSize(width: 800, height: 600)
private let rectangleSelectionWorldTolerance = 1.0e-6

// MARK: - Fixture invariants

@MainActor
@Test(.timeLimit(.minutes(3)))
func viewportNativeCADRectangleFixtureNamesEveryDrawnTriangleOnce() async throws {
    _ = NSApplication.shared
    let fixture = try rectangleSelectionFixture()

    #expect(fixture.interactionSceneNodeIDs == [fixture.cadSceneNodeID])
    #expect(fixture.topology.faces.count == 6)
    #expect(fixture.topology.edges.count == 12)
    #expect(fixture.topology.vertices.count == 8)

    // Every emitted triangle is named by exactly one prepared run, so the
    // truthful miss `componentID(forTriangle:)` reports for an unnamed
    // emission index has no witness in this fixture.
    var namedTriangles: Set<Int> = []
    var runsByComponent: [SelectionComponentID: Int] = [:]
    for run in fixture.topology.meshFaceRuns {
        for index in run.triangleRange {
            #expect(namedTriangles.insert(index).inserted)
        }
        runsByComponent[run.componentID, default: 0] += 1
    }
    #expect(namedTriangles.count == fixture.triangleCount)
    #expect(runsByComponent.count == fixture.topology.meshFaceRuns.count)
    #expect(runsByComponent.values.max() == 1)
}

// MARK: - Face scope

@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeCADRectangleFaceScopeReadsPreparedFaceIdentity() async throws {
    _ = NSApplication.shared
    let fixture = try rectangleSelectionFixture()
    let control = ViewportControlSession(
        camera: .init(projection: .parallel),
        basis: .axisFront(.z)
    )
    let geometry = try rectangleSelectionScreenGeometry(fixture: fixture, control: control)
    let rect = geometry.silhouette.insetBy(dx: -4.0, dy: -4.0)

    let observations = try await rectangleSelectionDrags(
        fixture: fixture,
        control: control,
        selectionHitPolicy: .face,
        rects: [rect]
    )
    let hits = try #require(observations.first).target.hits
    #expect(hits.isEmpty == false)

    let runComponentIDs = Set(fixture.topology.meshFaceRuns.map(\.componentID))
    var targets: Set<SelectionTarget> = []
    for hit in hits {
        #expect(hit.kind == .body)
        #expect(hit.sceneNodeID == fixture.cadSceneNodeID)
        let component = try #require(hit.selectionComponent)
        guard case .face(let componentID) = component else {
            Issue.record("A face scope rectangle reported \(component).")
            continue
        }
        #expect(runComponentIDs.contains(componentID))
        #expect(targets.insert(SelectionTarget(sceneNodeID: fixture.cadSceneNodeID, component: component)).inserted)
    }
    #expect(targets.count == hits.count)

    // The face the camera looks straight at is drawn by two triangles, both
    // inside the rectangle. It is reported once.
    let frontFaceID = try #require(
        rectangleSelectionFrontFaceComponentID(fixture: fixture, geometry: geometry),
        "The fixture body prepares no face on its camera-facing plane."
    )
    #expect(hits.filter { $0.selectionComponent == .face(frontFaceID) }.count == 1)
}

// MARK: - Object scope

@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeCADRectangleObjectScopeReportsAuthoredMeshOccurrence() async throws {
    _ = NSApplication.shared
    let fixture = try rectangleSelectionFixture()
    let control = ViewportControlSession(
        camera: .init(projection: .parallel),
        basis: .axisFront(.z)
    )
    let geometry = try rectangleSelectionScreenGeometry(fixture: fixture, control: control)
    let rect = geometry.silhouette.insetBy(dx: -4.0, dy: -4.0)

    let observations = try await rectangleSelectionDrags(
        fixture: fixture,
        control: control,
        selectionHitPolicy: .object,
        rects: [rect]
    )
    let target = try #require(observations.first).target
    let occurrenceIDs = Set(target.presentationOccurrenceIDs)

    // Both placements are drawn inside the same rectangle the face scope
    // harvested, so the `.cad` filter that scope applies to a drawn triangle
    // rejected real authored-mesh triangles rather than an empty set.
    #expect(occurrenceIDs.contains(fixture.cadOccurrenceID))
    #expect(occurrenceIDs.contains(fixture.meshOccurrenceID))
}

// MARK: - Vertex scope

@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeCADRectangleVertexScopeAdmitsOwnPixelAndRefusesOccluded() async throws {
    _ = NSApplication.shared
    let fixture = try rectangleSelectionFixture()
    let control = ViewportControlSession(
        camera: .init(projection: .parallel),
        basis: .axisFront(.z)
    )
    let geometry = try rectangleSelectionScreenGeometry(fixture: fixture, control: control)
    let unoccluded = rectangleSelectionVertexIDs(geometry: geometry) { $0.x < 0.0 }
    let occluded = rectangleSelectionVertexIDs(geometry: geometry) { $0.x > 0.0 }
    let cameraFacingUnoccluded = rectangleSelectionVertexIDs(geometry: geometry) {
        $0.x < 0.0 && abs($0.z - geometry.worldBounds.maxZ) <= rectangleSelectionWorldTolerance
    }
    #expect(unoccluded.count == 4)
    #expect(occluded.count == 4)
    #expect(cameraFacingUnoccluded.count == 2)

    // The rectangles are the screen bounds of each group, so neither depends
    // on which screen direction the camera maps world `+x` to.
    let unoccludedRect = try rectangleSelectionBounds(of: unoccluded, geometry: geometry)
    let occludedRect = try rectangleSelectionBounds(of: occluded, geometry: geometry)
    // The occluded rectangle is not vacuous: it contains every occluded
    // vertex's own pixel, so an empty answer there is the occlusion rule
    // rather than a rectangle that named none of them.
    for componentID in occluded {
        let point = try #require(geometry.vertexPoints[componentID])
        #expect(occludedRect.contains(point))
        #expect(unoccludedRect.contains(point) == false)
    }
    for componentID in unoccluded {
        let point = try #require(geometry.vertexPoints[componentID])
        #expect(unoccludedRect.contains(point))
        #expect(occludedRect.contains(point) == false)
    }

    let observations = try await rectangleSelectionDrags(
        fixture: fixture,
        control: control,
        selectionHitPolicy: .vertex,
        rects: [unoccludedRect, occludedRect]
    )
    let admitted = try rectangleSelectionVertexComponentIDs(
        in: observations[0].target.hits, sceneNodeID: fixture.cadSceneNodeID
    )
    let refused = try rectangleSelectionVertexComponentIDs(
        in: observations[1].target.hits, sceneNodeID: fixture.cadSceneNodeID
    )
    #expect(admitted.isSubset(of: unoccluded))
    #expect(cameraFacingUnoccluded.isSubset(of: admitted))
    #expect(refused.isEmpty)
}

// MARK: - Edge scope

@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeCADRectangleEdgeScopeAdmitsFirstDrawnPixel() async throws {
    _ = NSApplication.shared
    let fixture = try rectangleSelectionFixture()
    let control = ViewportControlSession(
        camera: .init(projection: .parallel),
        basis: .axisFront(.z)
    )
    let geometry = try rectangleSelectionScreenGeometry(fixture: fixture, control: control)
    let bounds = geometry.worldBounds
    let unoccludedEdge = try #require(rectangleSelectionEdgeID(fixture: fixture) { start, end in
        rectangleSelectionNear(start.x, bounds.minX) && rectangleSelectionNear(end.x, bounds.minX)
            && rectangleSelectionNear(start.z, bounds.maxZ) && rectangleSelectionNear(end.z, bounds.maxZ)
    }, "The fixture body prepares no camera-facing edge on its unoccluded side.")
    let occludedEdge = try #require(rectangleSelectionEdgeID(fixture: fixture) { start, end in
        rectangleSelectionNear(start.x, bounds.maxX) && rectangleSelectionNear(end.x, bounds.maxX)
            && rectangleSelectionNear(start.z, bounds.maxZ) && rectangleSelectionNear(end.z, bounds.maxZ)
    }, "The fixture body prepares no camera-facing edge on its occluded side.")
    let straddlingEdge = try #require(rectangleSelectionEdgeID(fixture: fixture) { start, end in
        rectangleSelectionNear(start.y, bounds.maxY) && rectangleSelectionNear(end.y, bounds.maxY)
            && rectangleSelectionNear(start.z, bounds.maxZ) && rectangleSelectionNear(end.z, bounds.maxZ)
    }, "The fixture body prepares no camera-facing edge crossing the occluder.")
    #expect(unoccludedEdge != occludedEdge)
    #expect(straddlingEdge != occludedEdge)

    let rect = geometry.silhouette.insetBy(dx: -4.0, dy: -4.0)
    let observations = try await rectangleSelectionDrags(
        fixture: fixture,
        control: control,
        selectionHitPolicy: .edge,
        rects: [rect]
    )
    let hits = observations[0].target.hits
    var admitted: Set<SelectionComponentID> = []
    for hit in hits {
        #expect(hit.sceneNodeID == fixture.cadSceneNodeID)
        let component = try #require(hit.selectionComponent)
        guard case .edge(let componentID) = component else {
            Issue.record("An edge scope rectangle reported \(component).")
            continue
        }
        #expect(admitted.insert(componentID).inserted)
    }
    #expect(admitted.contains(unoccludedEdge))
    #expect(admitted.contains(straddlingEdge))
    #expect(admitted.contains(occludedEdge) == false)
}

// MARK: - Section

@MainActor
@Test(.timeLimit(.minutes(5)))
func viewportNativeCADRectangleVertexScopeRefusesSectionedVertices() async throws {
    _ = NSApplication.shared
    let fixture = try rectangleSelectionFixture()
    let control = ViewportControlSession(
        camera: .init(projection: .parallel),
        basis: .axisFront(.z)
    )
    let geometry = try rectangleSelectionScreenGeometry(fixture: fixture, control: control)
    let rect = geometry.silhouette.insetBy(dx: -4.0, dy: -4.0)

    let analysis = try SectionAnalysisService().analyze(
        document: fixture.document,
        query: SectionAnalysisQuery(source: .sketchPlane(.zx), toleranceMeters: 1.0e-8),
        activeConstructionPlaneID: nil,
        displayUnit: .millimeter,
        currentEvaluation: fixture.currentEvaluation,
        currentGeneration: fixture.generation
    )
    let plan = SectionAnalysisClippingPlan(result: analysis, retaining: .front)

    let open = try await rectangleSelectionDrags(
        fixture: fixture,
        control: control,
        selectionHitPolicy: .vertex,
        rects: [rect]
    )
    let sectioned = try await rectangleSelectionDrags(
        fixture: fixture,
        control: control,
        selectionHitPolicy: .vertex,
        sectionAnalysis: analysis,
        sectionClippingPlan: plan,
        rects: [rect]
    )
    let openIDs = try rectangleSelectionVertexComponentIDs(
        in: open[0].target.hits, sceneNodeID: fixture.cadSceneNodeID
    )
    let sectionedIDs = try rectangleSelectionVertexComponentIDs(
        in: sectioned[0].target.hits, sceneNodeID: fixture.cadSceneNodeID
    )
    #expect(openIDs.isEmpty == false)
    #expect(sectionedIDs.isEmpty == false)
    #expect(sectionedIDs.isStrictSubset(of: openIDs))

    // Every surviving vertex is on one side of the same plane the frame cut
    // with, so the refusal is the section rule rather than a dropped query.
    let normal = analysis.plane.normal
    let origin = analysis.plane.origin
    var signs: Set<Int> = []
    for componentID in sectionedIDs {
        let point = try #require(geometry.worldVertices[componentID])
        let distance = (point.x - origin.x) * normal.x
            + (point.y - origin.y) * normal.y
            + (point.z - origin.z) * normal.z
        #expect(abs(distance) > analysis.toleranceMeters)
        signs.insert(distance > 0 ? 1 : -1)
    }
    #expect(signs.count == 1)
}

// MARK: - Mounted harness

private struct RectangleDragObservation {
    var rect: CGRect
    var target: ViewportSelectionDragTarget
    var attempts: Int
    var duration: Duration
}

/// Drives the production rectangle path: the mounted `ViewportInputSurface`
/// canvas drag reaches `handleSelectionDrag`, which asks
/// `selectionDragTarget(from:to:size:)` for the answer the frame just drew.
@MainActor
private func rectangleSelectionDrags(
    fixture: RectangleSelectionFixture,
    control: ViewportControlSession,
    selectionHitPolicy: ViewportSelectionHitPolicy,
    sectionAnalysis: SectionAnalysisResult? = nil,
    sectionClippingPlan: SectionAnalysisClippingPlan? = nil,
    rects: [CGRect]
) async throws -> [RectangleDragObservation] {
    let size = rectangleSelectionViewportSize
    var targets: [ViewportSelectionDragTarget] = []
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
        allowsSelectionRectangle: true,
        allowsObjectAffordances: false,
        presentationCADInteractionSceneNodeIDs: fixture.interactionSceneNodeIDs,
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

    var observations: [RectangleDragObservation] = []
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
                input(in: controller.view)?.onCanvasDrag?(start, end, size, .replace)
            }
            if targets.isEmpty {
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        let target = try #require(
            targets.first,
            "The mounted \(selectionHitPolicy) frame never answered the rectangle \(rect)."
        )
        targets.removeAll()
        print(
            "[cost] scope=\(selectionHitPolicy) rect=\(rect) attempts=\(attempts)"
                + " answer=\(duration) hits=\(target.hits.count)"
                + " occurrences=\(target.presentationOccurrenceIDs.count)"
        )
        observations.append(
            RectangleDragObservation(
                rect: rect, target: target, attempts: attempts, duration: duration
            )
        )
    }
    return observations
}

// MARK: - Screen geometry

@MainActor
func rectangleSelectionScreenGeometry(
    fixture: RectangleSelectionFixture,
    control: ViewportControlSession
) throws -> RectangleSelectionScreenGeometry {
    let size = rectangleSelectionViewportSize
    let layout = ViewportSceneContext(
        ruler: fixture.ruler,
        scene: fixture.cpuScene,
        size: size,
        camera: control.camera,
        basis: .axisFront(.z),
        geometryBoundsSource: .geometry(fixture.presentationScene.worldBounds),
        fittingInsets: ViewportCanvasChromeLayout(
            viewportSize: size
        ).fittingInsets
    ).layout

    var vertexPoints: [SelectionComponentID: CGPoint] = [:]
    var worldVertices: [SelectionComponentID: Point3D] = [:]
    var minScreenX = Double.greatestFiniteMagnitude
    var maxScreenX = -Double.greatestFiniteMagnitude
    var minScreenY = Double.greatestFiniteMagnitude
    var maxScreenY = -Double.greatestFiniteMagnitude
    var minX = Double.greatestFiniteMagnitude
    var maxX = -Double.greatestFiniteMagnitude
    var minY = Double.greatestFiniteMagnitude
    var maxY = -Double.greatestFiniteMagnitude
    var minZ = Double.greatestFiniteMagnitude
    var maxZ = -Double.greatestFiniteMagnitude
    for vertex in fixture.topology.vertices {
        let world = ViewportLayout.transformedPoint(vertex.point, by: fixture.modelTransform)
        let projected = try #require(
            layout.projectedPoint(world)?.point,
            "The fixture layout projects no point for a prepared CAD vertex."
        )
        vertexPoints[vertex.componentID] = projected
        worldVertices[vertex.componentID] = world
        minScreenX = min(minScreenX, projected.x)
        maxScreenX = max(maxScreenX, projected.x)
        minScreenY = min(minScreenY, projected.y)
        maxScreenY = max(maxScreenY, projected.y)
        minX = min(minX, world.x)
        maxX = max(maxX, world.x)
        minY = min(minY, world.y)
        maxY = max(maxY, world.y)
        minZ = min(minZ, world.z)
        maxZ = max(maxZ, world.z)
    }
    return RectangleSelectionScreenGeometry(
        layout: layout,
        silhouette: CGRect(
            x: minScreenX, y: minScreenY,
            width: maxScreenX - minScreenX, height: maxScreenY - minScreenY
        ),
        vertexPoints: vertexPoints,
        worldVertices: worldVertices,
        worldBounds: (minX, maxX, minY, maxY, minZ, maxZ)
    )
}

/// The screen bounds of the named vertices, outset so the half-open
/// `CGRect.contains` still admits a point that projects onto an edge.
private func rectangleSelectionBounds(
    of componentIDs: Set<SelectionComponentID>,
    geometry: RectangleSelectionScreenGeometry
) throws -> CGRect {
    var minX = Double.greatestFiniteMagnitude
    var maxX = -Double.greatestFiniteMagnitude
    var minY = Double.greatestFiniteMagnitude
    var maxY = -Double.greatestFiniteMagnitude
    for componentID in componentIDs {
        let point = try #require(geometry.vertexPoints[componentID])
        minX = min(minX, point.x)
        maxX = max(maxX, point.x)
        minY = min(minY, point.y)
        maxY = max(maxY, point.y)
    }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        .insetBy(dx: -4.0, dy: -4.0)
}

private func rectangleSelectionNear(_ lhs: Double, _ rhs: Double) -> Bool {
    abs(lhs - rhs) <= rectangleSelectionWorldTolerance
}

private func rectangleSelectionVertexIDs(
    geometry: RectangleSelectionScreenGeometry,
    where predicate: (Point3D) -> Bool
) -> Set<SelectionComponentID> {
    Set(geometry.worldVertices.compactMap { componentID, point in
        predicate(point) ? componentID : nil
    })
}

private func rectangleSelectionEdgeID(
    fixture: RectangleSelectionFixture,
    where predicate: (Point3D, Point3D) -> Bool
) -> SelectionComponentID? {
    for edge in fixture.topology.edges {
        let start = ViewportLayout.transformedPoint(edge.start, by: fixture.modelTransform)
        let end = ViewportLayout.transformedPoint(edge.end, by: fixture.modelTransform)
        if predicate(start, end) { return edge.componentID }
    }
    return nil
}

func rectangleSelectionFrontFaceComponentID(
    fixture: RectangleSelectionFixture,
    geometry: RectangleSelectionScreenGeometry
) -> SelectionComponentID? {
    let runComponentIDs = Set(fixture.topology.meshFaceRuns.map(\.componentID))
    for face in fixture.topology.faces where runComponentIDs.contains(face.componentID) {
        let world = face.points.map {
            ViewportLayout.transformedPoint($0, by: fixture.modelTransform)
        }
        guard world.isEmpty == false,
              world.allSatisfy({ rectangleSelectionNear($0.z, geometry.worldBounds.maxZ) }) else {
            continue
        }
        return face.componentID
    }
    return nil
}

private func rectangleSelectionVertexComponentIDs(
    in hits: [ViewportHit],
    sceneNodeID: SceneNodeID
) throws -> Set<SelectionComponentID> {
    var componentIDs: Set<SelectionComponentID> = []
    for hit in hits {
        #expect(hit.sceneNodeID == sceneNodeID)
        let component = try #require(hit.selectionComponent)
        guard case .vertex(let componentID) = component else {
            Issue.record("A vertex scope rectangle reported \(component).")
            continue
        }
        #expect(componentIDs.insert(componentID).inserted)
    }
    return componentIDs
}

// MARK: - Fixture construction

@MainActor
func rectangleSelectionFixture() throws -> RectangleSelectionFixture {
    let session = EditorSession()
    _ = session.createDefaultExtrudedRectangle()
    guard let cadFeatureID = session.document.cadDocument.designGraph.order.last else {
        throw RectangleSelectionFixtureError.missingSceneNode
    }
    _ = session.createDefaultExtrudedRectangle()
    guard let meshFeatureID = session.document.cadDocument.designGraph.order.last,
          meshFeatureID != cadFeatureID else {
        throw RectangleSelectionFixtureError.missingSceneNode
    }
    let currentEvaluation = try #require(session.currentEvaluation)
    var document = session.document
    guard let meshEntry = document.productMetadata.sceneNodes.first(where: {
        $0.value.reference == .body(meshFeatureID)
    }),
        let cadEntry = document.productMetadata.sceneNodes.first(where: {
            $0.value.reference == .body(cadFeatureID)
        }) else {
        throw RectangleSelectionFixtureError.missingSceneNode
    }

    let source = try rectangleSelectionMeshSource()
    guard var meshObject = meshEntry.value.object,
          let modeling = meshObject.geometryRepresentations.representation(for: .modeling) else {
        throw RectangleSelectionFixtureError.missingModelingRepresentation
    }
    let presentationID = GeometryRepresentationID(rawValue: "rectangle.presentation.mesh")
    var representations = meshObject.geometryRepresentations
    representations.representations[presentationID] = GeometryRepresentation(
        id: presentationID,
        source: .authoredMesh(source.identity)
    )
    representations.selection = GeometryRepresentationSelection(
        modeling: modeling.id,
        presentation: presentationID
    )
    meshObject.geometryRepresentations = representations
    var meshNode = meshEntry.value
    meshNode.object = meshObject
    document.authoredMeshAssets[source.identity] = try AuthoredMeshAsset(
        source: source,
        provenance: .created
    )
    document.productMetadata.sceneNodes[meshEntry.key] = meshNode

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
    let cadItem = try #require(cpuScene.items.first { item in
        guard item.sceneNodeID == cadEntry.key, case .body = item.kind else { return false }
        return true
    }, "The supplied scene carries no CAD body for the interaction scene node.")
    guard case .body(let component) = cadItem.kind, let topology = component.topology else {
        throw RectangleSelectionFixtureError.missingTopology
    }

    var cadOccurrenceID: SceneOccurrenceID?
    var meshOccurrenceID: SceneOccurrenceID?
    for (occurrenceID, sceneNodeID) in projection.sceneNodeIDByOccurrenceID {
        if sceneNodeID == cadEntry.key { cadOccurrenceID = occurrenceID }
        if sceneNodeID == meshEntry.key { meshOccurrenceID = occurrenceID }
    }

    return RectangleSelectionFixture(
        document: document,
        presentationScene: presentationScene,
        sceneNodeIDByOccurrenceID: projection.sceneNodeIDByOccurrenceID,
        currentEvaluation: currentEvaluation,
        generation: session.generation,
        ruler: ruler,
        cpuScene: cpuScene,
        cadSceneNodeID: cadEntry.key,
        cadOccurrenceID: try #require(cadOccurrenceID),
        meshSceneNodeID: meshEntry.key,
        meshOccurrenceID: try #require(meshOccurrenceID),
        topology: topology,
        modelTransform: cadItem.modelTransform,
        triangleCount: (component.mesh?.indices.count ?? 0) / 3,
        interactionSceneNodeIDs: exactPresentationCADSceneNodeIDs(
            scene: presentationScene,
            sceneNodeIDByOccurrenceID: projection.sceneNodeIDByOccurrenceID,
            document: document,
            generation: session.generation,
            cadInteraction: currentEvaluation
        )
    )
}

/// Mirrors the production admission rule that `MainView` applies before it
/// hands a scene node to the viewport as an exact CAD interaction target.
@MainActor
func exactPresentationCADSceneNodeIDs(
    scene: UniversalViewportScene,
    sceneNodeIDByOccurrenceID: [SceneOccurrenceID: SceneNodeID],
    document: DesignDocument,
    generation: DocumentGeneration,
    cadInteraction: DocumentEvaluationContext?
) -> Set<SceneNodeID> {
    let resolver = MeshSourcePresentationCADAffordanceResolver()
    var availableCounts: [SceneNodeID: Int] = [:]
    var unavailableSceneNodeIDs: Set<SceneNodeID> = []
    for item in scene.items {
        guard let sceneNodeID = sceneNodeIDByOccurrenceID[item.occurrenceID] else { continue }
        guard case .available = resolver.resolve(
            item: item,
            sceneNodeID: sceneNodeID,
            document: document,
            generation: generation,
            cadInteraction: cadInteraction
        ) else {
            unavailableSceneNodeIDs.insert(sceneNodeID)
            continue
        }
        availableCounts[sceneNodeID, default: 0] += 1
    }
    return Set(availableCounts.compactMap { sceneNodeID, count in
        count == 1 && unavailableSceneNodeIDs.contains(sceneNodeID) == false ? sceneNodeID : nil
    })
}

/// A closed box the presentation draws in front of the CAD body's `+x` half.
///
/// It is the occluder the vertex and edge rules are asked about, and the
/// authored-mesh source whose drawn triangles the face harvest must refuse.
private func rectangleSelectionMeshSource() throws -> MeshSource {
    var builder = MeshSourceBuilder(
        identity: GeometrySourceID(rawValue: "rectangle.presentation.mesh")
    )
    try builder.reserveCapacity(vertexCount: 8, faceCount: 6, cornerCount: 24)
    let minX = 0.0
    let maxX = 0.05
    let minY = -0.02
    let maxY = 0.02
    let minZ = 0.02
    let maxZ = 0.04
    let backBottomLeft = try builder.addVertex(GeometryPoint3D(x: minX, y: minY, z: minZ))
    let backBottomRight = try builder.addVertex(GeometryPoint3D(x: maxX, y: minY, z: minZ))
    let backTopRight = try builder.addVertex(GeometryPoint3D(x: maxX, y: maxY, z: minZ))
    let backTopLeft = try builder.addVertex(GeometryPoint3D(x: minX, y: maxY, z: minZ))
    let frontBottomLeft = try builder.addVertex(GeometryPoint3D(x: minX, y: minY, z: maxZ))
    let frontBottomRight = try builder.addVertex(GeometryPoint3D(x: maxX, y: minY, z: maxZ))
    let frontTopRight = try builder.addVertex(GeometryPoint3D(x: maxX, y: maxY, z: maxZ))
    let frontTopLeft = try builder.addVertex(GeometryPoint3D(x: minX, y: maxY, z: maxZ))
    _ = try builder.addFace(
        vertexIDs: [frontBottomLeft, frontBottomRight, frontTopRight, frontTopLeft]
    )
    _ = try builder.addFace(
        vertexIDs: [backBottomLeft, backTopLeft, backTopRight, backBottomRight]
    )
    _ = try builder.addFace(
        vertexIDs: [backBottomLeft, frontBottomLeft, frontTopLeft, backTopLeft]
    )
    _ = try builder.addFace(
        vertexIDs: [backBottomRight, backTopRight, frontTopRight, frontBottomRight]
    )
    _ = try builder.addFace(
        vertexIDs: [backBottomLeft, backBottomRight, frontBottomRight, frontBottomLeft]
    )
    _ = try builder.addFace(
        vertexIDs: [backTopLeft, frontTopLeft, frontTopRight, backTopRight]
    )
    return try builder.build()
}
