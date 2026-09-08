import CoreGraphics
import RupaCore
import RupaGeometry
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

/// Screen-fixed extents of the body transform affordance.
///
/// The invariant is that every transform handle is reachable at the same screen
/// size whatever the body measures, so each extent is a point length owned by
/// `ViewportSpatialOverlayProducer.BodyTransformMetrics` rather than a fraction
/// of the body span. These tests read the semantic source the producer emits,
/// which is where the lengths are decided; the mounted resolution of the two
/// placement forms is owned by `RealityViewportSpatialResourcesTests`.
@Suite
struct ViewportBodyTransformScreenExtentTests {
    private typealias Producer = ViewportSpatialOverlayProducer
    /// The point lengths the emit site is contracted to produce.
    ///
    /// They are restated here rather than read from `BodyTransformMetrics`,
    /// which is file-private to its emit site. Pinning the values makes a
    /// change to any one of them a visible contract change that has to
    /// re-derive the separation rule asserted below.
    private enum Expected {
        static let rotationRadiusPoints: CGFloat = 72
        static let centerScalePoints: CGFloat = 95
        static let axisLengthPoints: CGFloat = 132
        static let rotationSegmentCount = 12
    }
    private typealias Source = ViewportSpatialOverlayProducer.SurfaceTransformAffordanceSource

    /// A single selected cube whose span is the only thing the caller varies.
    private func makeSource(spanMeters: Double) throws -> Source {
        let featureID = FeatureID()
        let nodeID = SceneNodeID()
        let half = spanMeters / 2
        let item = ViewportSceneItem(
            id: "body",
            featureID: featureID,
            sceneNodeID: nodeID,
            modelBounds: CGRect(x: -half, y: -half, width: spanMeters, height: spanMeters),
            kind: .body(component: ViewportBodyComponent(
                sizeXMeters: spanMeters,
                sizeYMeters: spanMeters,
                sizeZMeters: spanMeters,
                yMinMeters: 0,
                yMaxMeters: spanMeters,
                topology: ViewportBodyTopology(
                    faces: [],
                    edges: [],
                    vertices: [
                        .init(componentID: SelectionComponentID(rawValue: "body.vertex.0"), point: .origin),
                    ]
                )
            ))
        )
        let raw = Source.RawInput(
            document: .empty(),
            scene: ViewportScene(items: [item]),
            selection: SelectionModel(selectedTargets: [SelectionTarget(sceneNodeID: nodeID)]),
            ruler: .standard(for: .meter),
            enabledRoutes: [.bodyTransform],
            interactiveRoutes: [.bodyTransform]
        )
        var interactionRecords: [ViewportSpatialInteractionRecord] = []
        return try #require(
            try Producer.makeSurfaceTransformAffordanceSource(
                from: raw,
                interactionRecords: &interactionRecords,
                checkpoint: { _, _, _ in }
            )
        )
    }

    private func action(_ identity: ViewportSpatialHandleIdentity?) -> ViewportAffordanceAction? {
        guard case .affordance(let target) = identity else { return nil }
        return target.action
    }

    /// The point distance a placement advances, for the two forms that state
    /// one. A fixed or projected offset states no fixed screen extent, so it is
    /// reported as nil rather than reduced to a number.
    private func pointLength(_ offset: RealityViewportSpatialBatch.Offset) -> CGFloat? {
        switch offset {
        case .directed(_, let parallel, let perpendicular): perpendicular == 0 ? parallel : nil
        case .worldDirected(_, let lengthPoints): lengthPoints
        case .fixed, .projected: nil
        }
    }

    private func towardPoint(_ offset: RealityViewportSpatialBatch.Offset) -> Point3D? {
        switch offset {
        case .directed(let toward, _, _), .projected(let toward, _, _, _): toward
        case .fixed, .worldDirected: nil
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [0.002, 1.0, 5_000.0])
    func bodyTransformExtentsAreScreenLengthsIndependentOfTheBodySpan(spanMeters: Double) throws {
        let source = try makeSource(spanMeters: spanMeters)
        for axis in ViewportCoordinateAxis.allCases {
            let arrow = try #require(source.cameraLines.first { action($0.identity) == .translate(axis) })
            #expect(arrow.points.count == 2)
            #expect(arrow.points[0].usesFixedOffset)
            #expect(arrow.points[1].minimumLength == nil)
            #expect(arrow.points[1].parallel == Expected.axisLengthPoints)
            #expect(arrow.hitTolerancePoints == 7.0)

            // Both axis markers share the arrow's own `toward` point, so they
            // resolve on the drawn shaft at every camera angle instead of
            // foreshortening off it.
            let tip = try #require(source.markers.first { action($0.identity) == .oneSidedScale(axis) })
            #expect(pointLength(tip.offset) == Expected.axisLengthPoints)
            #expect(towardPoint(tip.offset) == arrow.points[1].toward)
            #expect(tip.anchor == arrow.points[1].anchor)
            #expect(tip.hitTolerancePoints == 10.0)

            let centre = try #require(source.markers.first { action($0.identity) == .centerScale(axis) })
            #expect(pointLength(centre.offset) == Expected.centerScalePoints)
            #expect(towardPoint(centre.offset) == arrow.points[1].toward)
            #expect(centre.anchor == arrow.points[1].anchor)
            #expect(centre.hitTolerancePoints == 10.0)

            let ring = try #require(source.cameraLines.first { action($0.identity) == .rotate(axis) })
            #expect(ring.points.count == Expected.rotationSegmentCount + 1)
            #expect(ring.points.allSatisfy { $0.parallel == Expected.rotationRadiusPoints })
            #expect(ring.points.allSatisfy { $0.worldDirection != nil })
            #expect(ring.hitTolerancePoints == 8.0)
        }
        // The affordance is the only thing that stopped scaling: the bounds box
        // still measures the body.
        #expect(source.worldLines.count == 12)
    }

    @Test(.timeLimit(.minutes(1)))
    func bodyTransformHandleFootprintsCannotOverlapOnOneAxis() throws {
        let source = try makeSource(spanMeters: 1.0)
        let axis = ViewportCoordinateAxis.x
        let ring = try #require(source.cameraLines.first { action($0.identity) == .rotate(axis) })
        let centre = try #require(source.markers.first { action($0.identity) == .centerScale(axis) })
        let tip = try #require(source.markers.first { action($0.identity) == .oneSidedScale(axis) })
        let ringRadius = try #require(ring.points.first.map(\.parallel))
        let centreLength = try #require(pointLength(centre.offset))
        let tipLength = try #require(pointLength(tip.offset))
        let ringTolerance = try #require(ring.hitTolerancePoints)
        let centreTolerance = try #require(centre.hitTolerancePoints)
        let tipTolerance = try #require(tip.hitTolerancePoints)

        // The ordering together with the separation rule is the invariant, not
        // the three literals: adjacent footprints on one axis cannot overlap.
        #expect(ringRadius < centreLength)
        #expect(centreLength < tipLength)
        #expect(centreLength - ringRadius >= CGFloat(centreTolerance + ringTolerance))
        #expect(tipLength - centreLength >= CGFloat(tipTolerance + centreTolerance))
    }

    @Test(.timeLimit(.minutes(1)))
    func rotationRingSamplesASceneSpaceArcRatherThanACameraPlaneCircle() throws {
        let source = try makeSource(spanMeters: 1.0)
        let planes: [(ViewportCoordinateAxis, Vector3D, Vector3D)] = [
            (.x, Vector3D(x: 0, y: 1, z: 0), Vector3D(x: 0, y: 0, z: 1)),
            (.y, Vector3D(x: 0, y: 0, z: 1), Vector3D(x: 1, y: 0, z: 0)),
            (.z, Vector3D(x: 1, y: 0, z: 0), Vector3D(x: 0, y: 1, z: 0)),
        ]
        for (axis, planeStart, planeEnd) in planes {
            let ring = try #require(source.cameraLines.first { action($0.identity) == .rotate(axis) })
            let directions = ring.points.compactMap(\.worldDirection)
            #expect(directions.count == ring.points.count)
            // A quarter turn from one plane axis to the other: the samples carry
            // the plane the ring rotates about, which is what lets the mounted
            // camera foreshorten it. A camera-plane offset would normalize every
            // projected direction and draw three identical circles.
            let first = try #require(directions.first)
            let last = try #require(directions.last)
            #expect(abs(first.x - planeStart.x) < 1e-9)
            #expect(abs(first.y - planeStart.y) < 1e-9)
            #expect(abs(first.z - planeStart.z) < 1e-9)
            #expect(abs(last.x - planeEnd.x) < 1e-9)
            #expect(abs(last.y - planeEnd.y) < 1e-9)
            #expect(abs(last.z - planeEnd.z) < 1e-9)
            #expect(directions.allSatisfy { abs($0.length - 1) < 1e-9 })
            #expect(zip(directions, directions.dropFirst()).allSatisfy { ($0 - $1).length > 1e-3 })
            #expect(ring.points.allSatisfy { $0.anchor == ring.points[0].anchor })
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aDegenerateWorldDirectedPlacementIsATypedAdmissionFailure() throws {
        func batch(_ offset: RealityViewportSpatialBatch.Offset) throws -> RealityViewportSpatialBatch {
            try RealityViewportSpatialBatch(
                markers: [
                    .init(shape: .sphere, anchor: .origin, diameterPoints: 9,
                          color: [1, 1, 1, 1], offset: offset),
                ],
                renderOrigin: .origin,
                retainedSurfaceByteCount: 0
            )
        }
        // A direction and a length are source properties the camera cannot
        // repair, so they are refused at admission rather than disabling the
        // placement on every frame.
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try batch(.worldDirected(along: Vector3D(x: 0, y: 0, z: 0), lengthPoints: 72))
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try batch(.worldDirected(along: Vector3D(x: .nan, y: 0, z: 0), lengthPoints: 72))
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try batch(.worldDirected(along: Vector3D(x: 0, y: 1, z: 0), lengthPoints: -1))
        }
        // A world direction carries no second world point, so unlike a
        // direction-relative offset it charges no additional item or position.
        let admitted = try batch(.worldDirected(along: Vector3D(x: 0, y: 1, z: 0), lengthPoints: 72))
        let directed = try batch(.directed(toward: Point3D(x: 0, y: 1, z: 0), parallel: 72, perpendicular: 0))
        #expect(directed.itemCount == admitted.itemCount + 1)
        #expect(directed.positionCount == admitted.positionCount + 1)
    }
}
