import AppKit
import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD
import SwiftUI
import Testing
@testable import RupaRendering

/// Owns the sketch transform route: what the producer registers and draws, what
/// the input owner computes and refuses, and what a mounted viewport commits.
///
/// The mounted cases drive the production press, drag, cancel and release
/// callbacks against a real window, so the handle they press is the one the
/// native frame mounted rather than one this test projected for itself. The
/// layout below only locates a deterministic pointer fixture.
@Suite(.serialized)
struct ViewportSketchTransformLifecycleTests {
    private typealias Producer = ViewportSpatialOverlayProducer
    private typealias Source = ViewportSpatialOverlayProducer.SurfaceTransformAffordanceSource
    private typealias Route = ViewportSpatialOverlayProducer.SurfaceTransformAffordanceRoute
    private typealias Algebra = ViewportWorldTransformAlgebra
    private typealias Identity = ViewportSketchTransformHandleIdentity

    private enum Expected {
        static let rotationRadiusPoints: CGFloat = 72
        static let axisLengthPoints: CGFloat = 132
        static let rotationSegmentCount = 12
    }

    /// Binary-exact coordinates, so an expectation never fails on a rounding
    /// difference the owner under test did not introduce.
    private static let pivot = Point3D(x: 0.5, y: 0.25, z: -0.75)
    private static let probe = Point3D(x: 0.125, y: -0.25, z: 0.375)
    private static let tolerance = 1.0e-9

    // MARK: - Fixture

    private struct Fixture {
        let document: DesignDocument
        let ruler: RulerConfiguration
        let scene: ViewportScene
        let item: ViewportSceneItem
        let sceneNodeID: SceneNodeID
        let selection: SelectionModel
    }

    private func makeFixture() throws -> Fixture {
        var document = DesignDocument.empty()
        // The gizmo's ring, arrows and markers are sized in points against a
        // ruler-fitted camera, so the sketch is authored large enough for a
        // corner marker to clear them at the default zoom.
        let feature = try document.createRectangleSketch(
            name: "Sketch transform",
            plane: .xy,
            width: .length(400, .millimeter),
            height: .length(240, .millimeter)
        )
        let ruler = RulerConfiguration.standard(for: .millimeter)
        let scene = ViewportSceneBuilder().build(document: document, ruler: ruler)
        let item = try #require(scene.items.first { $0.featureID == feature })
        let sceneNodeID = try #require(item.sceneNodeID)
        return Fixture(
            document: document,
            ruler: ruler,
            scene: scene,
            item: item,
            sceneNodeID: sceneNodeID,
            selection: SelectionModel(selectedTargets: [SelectionTarget(sceneNodeID: sceneNodeID)])
        )
    }

    private func makeRawInput(
        _ fixture: Fixture,
        interactiveRoutes: Set<Route> = [.sketchTransform],
        activeValues: [Producer.SurfaceTransformActiveValue] = []
    ) -> Source.RawInput {
        Source.RawInput(
            document: fixture.document,
            scene: fixture.scene,
            selection: fixture.selection,
            ruler: fixture.ruler,
            enabledRoutes: [.sketchTransform],
            interactiveRoutes: interactiveRoutes,
            activeValues: activeValues
        )
    }

    private func makeSource(
        _ raw: Source.RawInput
    ) throws -> (source: Source, records: [ViewportSpatialInteractionRecord]) {
        var records: [ViewportSpatialInteractionRecord] = []
        let source = try #require(
            try Producer.makeSurfaceTransformAffordanceSource(
                from: raw, interactionRecords: &records, checkpoint: { _, _, _ in }
            )
        )
        return (source, records)
    }

    private func expectClose(
        _ value: Point3D,
        _ expected: Point3D,
        _ subject: Comment,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(abs(value.x - expected.x) <= Self.tolerance, subject, sourceLocation: sourceLocation)
        #expect(abs(value.y - expected.y) <= Self.tolerance, subject, sourceLocation: sourceLocation)
        #expect(abs(value.z - expected.z) <= Self.tolerance, subject, sourceLocation: sourceLocation)
    }

    private func expectClose(
        _ value: Vector3D,
        _ expected: Vector3D,
        _ subject: Comment,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(abs(value.x - expected.x) <= Self.tolerance, subject, sourceLocation: sourceLocation)
        #expect(abs(value.y - expected.y) <= Self.tolerance, subject, sourceLocation: sourceLocation)
        #expect(abs(value.z - expected.z) <= Self.tolerance, subject, sourceLocation: sourceLocation)
    }

    private func distance(_ lhs: Point3D, _ rhs: Point3D) -> Double {
        let dx = lhs.x - rhs.x, dy = lhs.y - rhs.y, dz = lhs.z - rhs.z
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    // MARK: - Producer

    @Test
    func sketchTransformRegistersOneRecordPerHandleWhileInteractive() throws {
        let fixture = try makeFixture()
        let (source, records) = try makeSource(makeRawInput(fixture))

        let identities = records.compactMap { record -> Identity? in
            guard case .sketchTransform(let baseline) = record.target else { return nil }
            return baseline.identity
        }
        #expect(records.count == 7)
        #expect(identities.count == 7)
        #expect(identities.allSatisfy { $0.featureID == fixture.item.featureID })
        #expect(identities.allSatisfy { $0.sceneNodeID == fixture.sceneNodeID })
        let roles = identities.map(\.role)
        #expect(roles.contains(.translate(.x)))
        #expect(roles.contains(.translate(.z)))
        #expect(roles.contains(.rotate(.y)))
        #expect(roles.contains(.scale(.minXMinY)))
        #expect(roles.contains(.scale(.maxXMinY)))
        #expect(roles.contains(.scale(.maxXMaxY)))
        #expect(roles.contains(.scale(.minXMaxY)))
        // A sketch never borrows the body affordance identity, whose press route
        // resolves a body edit baseline and would move it as if it were a body.
        #expect(!records.contains { record in
            if case .affordance = record.target { return true }
            return false
        })

        let outlines = source.cameraLines.filter { $0.route == .sketchTransform && $0.identity == nil }
        #expect(outlines.count == 1)
        let outline = try #require(outlines.first)
        #expect(outline.identity == nil)
        #expect(outline.hitTolerancePoints == nil)
        #expect(outline.points.count == 5)
        #expect(outline.points.first?.anchor == outline.points.last?.anchor)

        let sketchCameraLines = source.cameraLines.filter { $0.route == .sketchTransform }
        #expect(sketchCameraLines.count == 4)
        let arrows = sketchCameraLines.filter { $0.points.count == 2 }
        #expect(arrows.count == 2)
        for arrow in arrows {
            // Both ends are screen lengths owned by `BodyTransformMetrics`, so
            // the arm keeps its reach whatever the sketch measures.
            #expect(arrow.points[0].usesFixedOffset)
            #expect(arrow.points[0].worldDirection == nil)
            #expect(arrow.points[1].parallel == Expected.axisLengthPoints)
            #expect(arrow.points[1].minimumLength == nil)
            #expect(arrow.hitTolerancePoints == 7.0)
            #expect(arrow.occurrenceID == fixture.item.id)
        }
        let rings = sketchCameraLines.filter { $0.points.count != 2 && $0.identity != nil }
        #expect(rings.count == 1)
        let ring = try #require(rings.first)
        #expect(ring.points.count == Expected.rotationSegmentCount + 1)
        #expect(ring.points.allSatisfy { $0.parallel == Expected.rotationRadiusPoints })
        #expect(ring.points.allSatisfy { $0.worldDirection != nil })
        #expect(ring.points.allSatisfy { $0.anchor == ring.points[0].anchor })
        #expect(ring.hitTolerancePoints == 8.0)
        #expect(ring.occurrenceID == fixture.item.id)

        let sketchMarkers = source.markers.filter { $0.route == .sketchTransform }
        #expect(sketchMarkers.count == 4)
        let centres = sketchMarkers.filter { $0.identity == nil }
        #expect(centres.isEmpty)
        let cornerMarkers = sketchMarkers.filter { $0.identity != nil }
        #expect(cornerMarkers.count == 4)
        #expect(cornerMarkers.allSatisfy { $0.diameterPoints == 9 })
        #expect(cornerMarkers.allSatisfy { $0.hitTolerancePoints == 10.0 })
        #expect(cornerMarkers.allSatisfy { $0.occurrenceID == fixture.item.id })

        var meshes: [ViewportSpatialOverlayInput.Mesh] = []
        var paths: [ViewportSpatialOverlayInput.Path] = []
        var labels: [ViewportSpatialOverlayInput.Label] = []
        var nativeMarkers: [ViewportSpatialOverlayInput.Marker] = []
        var nativeCameraLines: [ViewportSpatialOverlayInput.CameraLine] = []
        var nativeCameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
        var families: Set<ViewportSpatialOverlayFamily> = []
        var materialized = records
        try Producer.appendSurfaceTransformAffordances(
            from: source,
            checkpoint: { _, _, _ in },
            meshes: &meshes,
            paths: &paths,
            labels: &labels,
            markers: &nativeMarkers,
            cameraLines: &nativeCameraLines,
            cameraPaths: &nativeCameraPaths,
            interactionRecords: &materialized,
            activeFamilies: &families
        )
        // Materialization resolves the handles the emit step registered; it
        // never registers one of its own.
        #expect(materialized.count == 7)
        #expect(meshes.isEmpty)
        #expect(nativeCameraLines.count == 4)
        #expect(nativeMarkers.count == 4)
        #expect(nativeCameraPaths.isEmpty)
        #expect(labels.isEmpty)
        #expect(families.contains(.transform))
    }

    @Test
    func sketchTransformDrawsWithoutRegisteringWhenTheRouteIsNotInteractive() throws {
        let fixture = try makeFixture()
        let (source, records) = try makeSource(makeRawInput(fixture, interactiveRoutes: []))
        // `Viewport` enables and enters this route under one predicate, so
        // production never separates the two sets. The producer's own contract
        // still does: a drawn handle is not by itself a registered one.
        #expect(records.isEmpty)
        #expect(source.worldLines.filter { $0.route == .sketchTransform }.isEmpty)
        #expect(source.cameraLines.filter { $0.route == .sketchTransform }.count == 4)
        #expect(source.markers.filter { $0.route == .sketchTransform }.count == 4)
    }

    @Test
    func pendingSketchMutationRetainsOneNativeBaselineForGeometryAndHandles() throws {
        let fixture = try makeFixture()
        let shift = Vector3D(x: 0.25, y: 0, z: -0.125)
        let mutation = try Algebra.translation(shift)
        let identity = Identity(
            featureID: fixture.item.featureID, sceneNodeID: fixture.sceneNodeID, role: .translate(.x)
        )
        let (base, _) = try makeSource(makeRawInput(fixture))
        let (moved, _) = try makeSource(
            makeRawInput(
                fixture,
                activeValues: [.init(identity: .sketchTransform(identity), transform: mutation)]
            )
        )
        #expect(base.worldLines.isEmpty && moved.worldLines.isEmpty)
        #expect(base.cameraLines.count == moved.cameraLines.count)
        for (before, after) in zip(base.cameraLines, moved.cameraLines) {
            #expect(before.points.count == after.points.count)
            for (from, to) in zip(before.points, after.points) {
                expectClose(to.anchor, from.anchor, "The native frame owns the preview transform, applied exactly once.")
                expectClose(to.toward, from.toward, "Worker output retains the immutable source baseline.")
            }
            #expect(after.objectPreviewOccurrenceID == fixture.item.id)
        }
        #expect(base.markers.count == moved.markers.count)
        for (before, after) in zip(base.markers, moved.markers) {
            expectClose(after.anchor, before.anchor, "Handle and outline retain the same baseline.")
            #expect(after.objectPreviewOccurrenceID == fixture.item.id)
        }
        // The preview is drawn from the drag value alone: the document the route
        // reads still holds the frame the gesture has not committed.
        #expect(base.scene == moved.scene)
        #expect(
            base.document.productMetadata.sceneNodes[fixture.sceneNodeID]?.localTransform
                == moved.document.productMetadata.sceneNodes[fixture.sceneNodeID]?.localTransform
        )
    }

    @Test
    func activeSketchTransformMutationRefusesValuesItCannotDraw() throws {
        let fixture = try makeFixture()
        let identity = Identity(
            featureID: fixture.item.featureID, sceneNodeID: fixture.sceneNodeID, role: .translate(.x)
        )
        let wrongKind = makeRawInput(
            fixture, activeValues: [.init(identity: .sketchTransform(identity), distance: 0.25)]
        )
        #expect(throws: MeshSourcePresentationRenderError.self) {
            var records: [ViewportSpatialInteractionRecord] = []
            _ = try Producer.makeSurfaceTransformAffordanceSource(
                from: wrongKind, interactionRecords: &records, checkpoint: { _, _, _ in }
            )
        }
        let mutation = try Algebra.translation(Vector3D(x: 0.25, y: 0, z: 0))
        let rotateIdentity = Identity(
            featureID: fixture.item.featureID, sceneNodeID: fixture.sceneNodeID, role: .rotate(.y)
        )
        let doubled = makeRawInput(
            fixture,
            activeValues: [
                .init(identity: .sketchTransform(identity), transform: mutation),
                .init(identity: .sketchTransform(rotateIdentity), transform: mutation),
            ]
        )
        #expect(throws: MeshSourcePresentationRenderError.self) {
            var records: [ViewportSpatialInteractionRecord] = []
            _ = try Producer.makeSurfaceTransformAffordanceSource(
                from: doubled, interactionRecords: &records, checkpoint: { _, _, _ in }
            )
        }
    }

    // MARK: - Input owner

    private func makeInput(
        role: Identity.Role,
        geometry: ViewportSketchTransformBaseline.Geometry,
        parentWorldTransform: Transform3D,
        baseLocalTransform: Transform3D
    ) throws -> ViewportSketchTransformInput {
        let baseline = ViewportSketchTransformBaseline(
            identity: Identity(featureID: FeatureID(), sceneNodeID: SceneNodeID(), role: role),
            baseLocalTransform: baseLocalTransform,
            parentWorldTransform: parentWorldTransform,
            pivot: Self.pivot,
            geometry: geometry
        )
        let record = try ViewportSpatialInteractionRecord(target: .sketchTransform(baseline))
        return try #require(try ViewportSketchTransformInput(record: record))
    }

    /// Applies the commit and proves the world invariant the conversion owns:
    /// the committed local frame, seen through the same parent frame, places
    /// every point exactly where the world mutation placed it.
    ///
    /// Both sides are evaluated with `ViewportLayout.transformedPoint`, the
    /// public projection oracle, so no algebra from the owner under test
    /// appears in the expectation.
    @discardableResult
    private func commitPreservesWorldMutation(
        input: ViewportSketchTransformInput,
        sample: ViewportSketchTransformInput.Sample,
        parent: Transform3D,
        local: Transform3D
    ) throws -> Transform3D {
        let mutation = try input.worldMutation(for: sample)
        let target = try #require(try input.commit(worldMutation: mutation))
        #expect(target.baseLocalTransform == local)
        let placed = ViewportLayout.transformedPoint(
            ViewportLayout.transformedPoint(Self.probe, by: local), by: parent
        )
        let expected = ViewportLayout.transformedPoint(placed, by: mutation)
        let committed = ViewportLayout.transformedPoint(
            ViewportLayout.transformedPoint(Self.probe, by: target.localTransform), by: parent
        )
        expectClose(committed, expected, "The commit reproduces the world mutation.")
        return mutation
    }

    @Test
    func translateHandleMovesAlongItsAxisAndCommitsThroughTheParentFrame() throws {
        let parent = try Algebra.translation(Vector3D(x: 0.25, y: -0.5, z: 0.75))
        let local = try Algebra.translation(Vector3D(x: 0.125, y: 0, z: -0.375))
        let axis = Vector3D(x: 1, y: 0, z: 0)
        let input = try makeInput(
            role: .translate(.x),
            geometry: .translate(direction: axis),
            parentWorldTransform: parent,
            baseLocalTransform: local
        )
        let query = try input.query
        #expect(query == .worldAxisDelta(origin: Self.pivot, direction: axis))
        let mutation = try commitPreservesWorldMutation(
            input: input, sample: .worldAxisDelta(0.25), parent: parent, local: local
        )
        // The mutation is the axial offset itself, so a sign or basis error in
        // the owner shows here rather than cancelling inside the invariant.
        expectClose(
            ViewportLayout.transformedPoint(Self.probe, by: mutation),
            Point3D(x: Self.probe.x + 0.25, y: Self.probe.y, z: Self.probe.z),
            "The translation mutation is the axial offset."
        )
    }

    @Test
    func scaleHandleGrowsAboutThePivotAndCommitsThroughTheParentFrame() throws {
        let parent = try Algebra.translation(Vector3D(x: 0.25, y: -0.5, z: 0.75))
        let local = try Algebra.translation(Vector3D(x: 0.125, y: 0, z: -0.375))
        let root = 0.5.squareRoot()
        let direction = Vector3D(x: root, y: 0, z: root)
        let input = try makeInput(
            role: .scale(.maxXMaxY),
            geometry: .scale(direction: direction, baseDistance: 0.5),
            parentWorldTransform: parent,
            baseLocalTransform: local
        )
        guard case .worldAxisDelta(let origin, let queryDirection) = try input.query else {
            Issue.record("A sketch scale handle must ask the frame for an axial delta.")
            return
        }
        #expect(origin == Self.pivot)
        expectClose(queryDirection, direction, "The scale query names the pivot-to-corner axis.")
        let mutation = try commitPreservesWorldMutation(
            input: input, sample: .worldAxisDelta(0.25), parent: parent, local: local
        )
        // A quarter of the base radius added to a half-metre radius is a factor
        // of 1.5 about a fixed pivot.
        expectClose(
            ViewportLayout.transformedPoint(Self.pivot, by: mutation),
            Self.pivot,
            "The scale pivot does not move."
        )
        let offsetPoint = Point3D(
            x: Self.pivot.x + 0.25, y: Self.pivot.y - 0.5, z: Self.pivot.z + 0.125
        )
        expectClose(
            ViewportLayout.transformedPoint(offsetPoint, by: mutation),
            Point3D(
                x: Self.pivot.x + 1.5 * 0.25,
                y: Self.pivot.y + 1.5 * -0.5,
                z: Self.pivot.z + 1.5 * 0.125
            ),
            "The scale factor is the measured radius ratio."
        )
    }

    @Test
    func rotateHandleTurnsInItsPlaneAndCommitsThroughTheParentFrame() throws {
        let parent = try Algebra.translation(Vector3D(x: 0.25, y: -0.5, z: 0.75))
        let local = try Algebra.translation(Vector3D(x: 0.125, y: 0, z: -0.375))
        let planeStart = Vector3D(x: 1, y: 0, z: 0)
        let planeEnd = Vector3D(x: 0, y: 0, z: 1)
        let input = try makeInput(
            role: .rotate(.y),
            geometry: .rotate(planeStart: planeStart, planeEnd: planeEnd),
            parentWorldTransform: parent,
            baseLocalTransform: local
        )
        let query = try input.query
        #expect(query == .worldPlanePoint(origin: Self.pivot, normal: Vector3D(x: 0, y: -1, z: 0)))
        let radius = 0.5
        let start = Point3D(x: Self.pivot.x + radius, y: Self.pivot.y, z: Self.pivot.z)
        let current = Point3D(x: Self.pivot.x, y: Self.pivot.y, z: Self.pivot.z + radius)
        let mutation = try commitPreservesWorldMutation(
            input: input,
            sample: .worldPlanePoints(start: start, current: current),
            parent: parent,
            local: local
        )
        // The turn carries the pressed point onto the released one. A flipped
        // axis or ordinate would turn the other way and fail here even though
        // the commit invariant above would still hold.
        expectClose(
            ViewportLayout.transformedPoint(start, by: mutation),
            current,
            "The rotation carries the press point onto the release point."
        )
        expectClose(
            ViewportLayout.transformedPoint(Self.pivot, by: mutation),
            Self.pivot,
            "The rotation pivot does not move."
        )
    }

    @Test
    func sketchTransformInputRefusesSamplesItCannotMeasure() throws {
        let identity = Transform3D.identity
        let translate = try makeInput(
            role: .translate(.x),
            geometry: .translate(direction: Vector3D(x: 1, y: 0, z: 0)),
            parentWorldTransform: identity,
            baseLocalTransform: identity
        )
        #expect(throws: MeshSourcePresentationRenderError.self) {
            _ = try translate.worldMutation(for: .worldAxisDelta(Double.nan))
        }
        // A sample that answers another role's query is refused rather than
        // reinterpreted, because the two carry different world meanings.
        #expect(throws: MeshSourcePresentationRenderError.self) {
            _ = try translate.worldMutation(
                for: .worldPlanePoints(start: Self.pivot, current: Self.probe)
            )
        }
        let scale = try makeInput(
            role: .scale(.minXMinY),
            geometry: .scale(direction: Vector3D(x: 0, y: 0, z: 1), baseDistance: 0.5),
            parentWorldTransform: identity,
            baseLocalTransform: identity
        )
        #expect(throws: MeshSourcePresentationRenderError.self) {
            _ = try scale.worldMutation(for: .worldAxisDelta(-0.5))
        }
        let rotate = try makeInput(
            role: .rotate(.y),
            geometry: .rotate(planeStart: Vector3D(x: 1, y: 0, z: 0), planeEnd: Vector3D(x: 0, y: 0, z: 1)),
            parentWorldTransform: identity,
            baseLocalTransform: identity
        )
        #expect(throws: MeshSourcePresentationRenderError.self) {
            _ = try rotate.worldMutation(
                for: .worldPlanePoints(
                    start: Self.pivot,
                    current: Point3D(x: Self.pivot.x, y: Self.pivot.y, z: Self.pivot.z + 0.5)
                )
            )
        }
        // A released gesture that moved nothing writes no undo step.
        let unchanged = try translate.commit(
            worldMutation: try translate.worldMutation(for: .worldAxisDelta(0))
        )
        #expect(unchanged == nil)
    }

    @Test
    func sketchTransformInputRefusesASingularParentFrame() throws {
        let baseline = ViewportSketchTransformBaseline(
            identity: Identity(featureID: FeatureID(), sceneNodeID: SceneNodeID(), role: .translate(.x)),
            baseLocalTransform: .identity,
            parentWorldTransform: try Algebra.scale(0, about: Point3D(x: 0, y: 0, z: 0)),
            pivot: Self.pivot,
            geometry: .translate(direction: Vector3D(x: 1, y: 0, z: 0))
        )
        let record = try ViewportSpatialInteractionRecord(target: .sketchTransform(baseline))
        // The parent frame must invert for the commit to reach the local frame,
        // so the refusal lands at press rather than at release.
        #expect(throws: MeshSourcePresentationRenderError.self) {
            _ = try ViewportSketchTransformInput(record: record)
        }
    }

    // MARK: - Mounted lifecycle

    /// Screen fixture for the mounted cases.
    @MainActor
    private struct Pointer {
        let start: CGPoint
        let end: CGPoint
        let cornerWorld: Point3D
        let pivotWorld: Point3D
    }

    @MainActor
    private func makePointer(
        _ fixture: Fixture, control: ViewportControlSession, size: CGSize
    ) throws -> Pointer {
        let layout = ViewportSceneContext(
            ruler: fixture.ruler,
            scene: fixture.scene,
            size: size,
            camera: control.camera,
            basis: .axisFront(.y),
            fittingInsets: ViewportCanvasChromeLayout(
                viewportSize: size,
                viewportBadgeWidth: ViewportCanvasChromeLayout.maximumViewportBadgeWidth
            ).fittingInsets
        ).layout
        let bounds = fixture.item.modelBounds
        // The viewport draws every sketch flattened into world XZ, so the
        // rectangle's second axis is world z and `minXMinY` is the corner at the
        // smaller x and z.
        let cornerWorld = ViewportLayout.transformedPoint(
            Point3D(x: bounds.minX, y: 0, z: bounds.minY), by: fixture.item.modelTransform
        )
        let pivotWorld = ViewportLayout.transformedPoint(
            Point3D(x: bounds.midX, y: 0, z: bounds.midY), by: fixture.item.modelTransform
        )
        let projectedCorner = try #require(layout.projectedPoint(cornerWorld)?.point)
        let projectedPivot = try #require(layout.projectedPoint(pivotWorld)?.point)
        let dx = projectedCorner.x - projectedPivot.x
        let dy = projectedCorner.y - projectedPivot.y
        let radius = hypot(dx, dy)
        // Under `.axisFront(.y)` the arrows run toward screen right and down and
        // the arc spans that quadrant, so this corner is clear of both. The
        // radius still has to clear the ring for the press to be unambiguous.
        try #require(radius > Expected.rotationRadiusPoints)
        let unit = CGVector(dx: dx / radius, dy: dy / radius)
        return Pointer(
            start: projectedCorner,
            end: CGPoint(x: projectedCorner.x + unit.dx * 24, y: projectedCorner.y + unit.dy * 24),
            cornerWorld: cornerWorld,
            pivotWorld: pivotWorld
        )
    }

    @MainActor
    private func inputView(in view: NSView) -> ViewportInputSurface.InputView? {
        if let value = view as? ViewportInputSurface.InputView { return value }
        for child in view.subviews {
            if let value = inputView(in: child) { return value }
        }
        return nil
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)), arguments: [ViewportCameraProjection.parallel, .standardPerspective])
    func mountedSketchTransformCommitsAndCancels(projection: ViewportCameraProjection) async throws {
        _ = NSApplication.shared
        let fixture = try makeFixture()
        let control = ViewportControlSession(camera: .init(projection: projection), basis: .axisFront(.y))
        let size = CGSize(width: 800, height: 600)
        var commits: [ViewportSketchTransformDragTarget] = []
        var canvasDrags = 0
        var bodyPlacementCommits = 0
        let viewport = Viewport(
            document: fixture.document,
            sourceIdentity: .document(id: fixture.document.id, generation: DocumentGeneration(1)),
            controlSession: control,
            workspaceRenderState: .init(revision: WorkspaceRevision(), ruler: fixture.ruler),
            selection: fixture.selection,
            objectSelectionIndex: .init(document: fixture.document, selection: fixture.selection),
            allowsObjectAffordances: false,
            selectedPresentationHasExactCADContext: true,
            onCanvasDrag: { _ in canvasDrags += 1 },
            onBodyPlacementCommit: { _ in
                bodyPlacementCommits += 1
                return .document(id: fixture.document.id, generation: DocumentGeneration(1))
            },
            onSketchTransformCommit: {
                commits.append($0)
                return .document(id: fixture.document.id, generation: DocumentGeneration(1))
            }
        ).frame(width: size.width, height: size.height)
        let controller = NSHostingController(rootView: viewport)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        controller.view.frame = CGRect(origin: .zero, size: window.contentLayoutRect.size)
        window.contentViewController = controller
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(!window.isVisible && !window.isKeyWindow)
        defer { window.contentViewController = nil; window.close() }

        let pointer = try makePointer(fixture, control: control, size: size)
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while commits.isEmpty, ContinuousClock.now < deadline {
            if let surface = inputView(in: controller.view) {
                surface.onPress?(pointer.start, size, .replace)
                try await Task.sleep(for: .milliseconds(500))
                surface.onCanvasDrag?(pointer.start, pointer.end, size, .replace)
            }
            try await Task.sleep(for: .milliseconds(30))
        }
        let commit = try #require(
            commits.first,
            """
            Sketch transform did not commit: start=\(pointer.start), end=\(pointer.end), \
            corner=\(pointer.cornerWorld), canvasDrags=\(canvasDrags)
            """
        )
        #expect(commit.featureID == fixture.item.featureID)
        #expect(commit.sceneNodeID == fixture.sceneNodeID)
        #expect(commit.localTransform != commit.baseLocalTransform)
        // The sketch is a root scene node holding an identity frame, so the
        // committed local frame is the world mutation itself and an outward
        // drag on the corner must move that corner away from the pivot.
        try #require(commit.baseLocalTransform == .identity)
        let moved = ViewportLayout.transformedPoint(pointer.cornerWorld, by: commit.localTransform)
        #expect(
            distance(moved, pointer.pivotWorld) > distance(pointer.cornerWorld, pointer.pivotWorld)
        )
        // The press claimed the sketch handle, so neither the body-move route
        // nor the canvas fallback ever saw this gesture.
        #expect(bodyPlacementCommits == 0)
        #expect(canvasDrags == 0)

        let surface = try #require(inputView(in: controller.view))
        func event(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
            try #require(
                NSEvent.mouseEvent(
                    with: type, location: surface.convert(point, to: nil), modifierFlags: [],
                    timestamp: 0, windowNumber: window.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1
                )
            )
        }
        // A cancel withdraws the gesture while the press still owns it, driving
        // the real event routing rather than the callback surface.
        try await Task.sleep(for: .milliseconds(800))
        let count = commits.count
        surface.mouseDown(with: try event(.leftMouseDown, at: pointer.start))
        try await Task.sleep(for: .milliseconds(800))
        surface.mouseDragged(with: try event(.leftMouseDragged, at: pointer.end))
        surface.cancelOperation(nil)
        surface.mouseUp(with: try event(.leftMouseUp, at: pointer.end))
        try await Task.sleep(for: .milliseconds(800))
        #expect(commits.count == count)
        #expect(bodyPlacementCommits == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func mountedSketchTransformWithdrawsWhenTheRouteLosesItsCallback() async throws {
        _ = NSApplication.shared
        let fixture = try makeFixture()
        let control = ViewportControlSession(camera: .init(projection: .parallel), basis: .axisFront(.y))
        let size = CGSize(width: 800, height: 600)
        var commits: [ViewportSketchTransformDragTarget] = []
        // The concrete view type is named rather than opaque so the same
        // structural identity can be remounted with a different callback.
        func makeViewport(
            onCommit: ((ViewportSketchTransformDragTarget) async throws -> ViewportSourceIdentity)?
        ) -> Viewport {
            Viewport(
                document: fixture.document,
                sourceIdentity: .document(id: fixture.document.id, generation: DocumentGeneration(1)),
                controlSession: control,
                workspaceRenderState: .init(revision: WorkspaceRevision(), ruler: fixture.ruler),
                selection: fixture.selection,
                objectSelectionIndex: .init(document: fixture.document, selection: fixture.selection),
                allowsObjectAffordances: false,
                selectedPresentationHasExactCADContext: true,
                onSketchTransformCommit: onCommit
            )
        }
        let controller = NSHostingController(rootView: makeViewport(onCommit: {
            commits.append($0)
            return .document(id: fixture.document.id, generation: DocumentGeneration(1))
        }))
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        controller.view.frame = CGRect(origin: .zero, size: window.contentLayoutRect.size)
        window.contentViewController = controller
        controller.view.frame = CGRect(origin: .zero, size: size)
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(!window.isVisible && !window.isKeyWindow)
        defer { window.contentViewController = nil; window.close() }

        let pointer = try makePointer(fixture, control: control, size: size)
        // The first gesture proves this press point is live on this mount, so
        // the absence below is the gate's doing and not a missed handle.
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while commits.isEmpty, ContinuousClock.now < deadline {
            if let surface = inputView(in: controller.view) {
                surface.onPress?(pointer.start, size, .replace)
                try await Task.sleep(for: .milliseconds(500))
                surface.onCanvasDrag?(pointer.start, pointer.end, size, .replace)
            }
            try await Task.sleep(for: .milliseconds(30))
        }
        try #require(commits.count == 1)

        try await Task.sleep(for: .milliseconds(800))
        let pressed = try #require(inputView(in: controller.view))
        pressed.onPress?(pointer.start, size, .replace)
        try await Task.sleep(for: .milliseconds(500))
        // The route is gated by this callback alone. Losing it mid-drag retires
        // the press instead of committing a frame nothing is bound to apply.
        controller.rootView = makeViewport(onCommit: nil)
        try await Task.sleep(for: .milliseconds(500))
        let released = try #require(inputView(in: controller.view))
        released.onCanvasDrag?(pointer.start, pointer.end, size, .replace)
        try await Task.sleep(for: .milliseconds(1500))
        #expect(commits.count == 1)
    }
}
