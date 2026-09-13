import CoreGraphics
import RupaCore
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

// MARK: - Synthetic native frame

/// A deterministic stand-in for the mounted native camera and its surface hit.
///
/// The camera looks along +Y from `y = -10`, so camera depth is `y + 10` and
/// the reference depth 10 maps world units to 100 screen points. An
/// orthographic frame keeps that scale at every depth, giving the screen map
/// `(200 + 100x, 200 - 100z)`; a perspective frame scales it by `10 / depth`,
/// which is the pinhole projection that makes reciprocal depth — not depth —
/// linear on screen. The only surface in the frame is the unit square
/// `x, z in [0, 1]` at camera depth `surfaceDepth`, which by default is the
/// body face under test. `section` is the frame's retained half-space, the one
/// fact about visibility that neither the depth interval nor an empty pixel
/// reports. Substituting the frame keeps the projection, visibility and
/// identity contracts observable without a mounted RealityKit view.
private struct NativeCADFrame {
    static let occurrenceID = SceneOccurrenceID(rawValue: "occurrence.cad.body")

    var surfaceOccurrenceID: SceneOccurrenceID = NativeCADFrame.occurrenceID
    var projectionFailure: MeshSourcePresentationRenderError?
    var surfaceFailure: MeshSourcePresentationRenderError?
    /// Shrinks the drawn square inside the exact face so the outline pixels
    /// answer no surface, reproducing how a tessellated silhouette lands
    /// relative to the exact B-Rep boundary.
    var surfaceInset: Double = 0
    /// Camera depth of the drawn square. Placing it in front of a candidate
    /// makes the frame an occluder instead of the body's own face.
    var surfaceDepth: Double = 10
    /// The mesh face identity of the drawn triangle, which is the triangle's
    /// own index in the CAD body's emission order. It is the only thing the
    /// face branch reads, so varying it selects a different prepared face.
    var surfaceFaceID: MeshFaceID = MeshFaceID(7)
    var usesPerspectiveProjection: Bool = false
    /// The retained half-space, in the same world space as the topology:
    /// `dot(point, normal) - offset >= -tolerance`.
    var section: (normal: Vector3D, offset: Double, tolerance: Double)?

    private func screenScale(atDepth depth: Double) -> Double {
        usesPerspectiveProjection ? 10 / depth : 1
    }

    func projectedPointWithinDepthRange(
        _ point: Point3D
    ) throws -> (point: CGPoint, depth: Double)? {
        if let projectionFailure {
            throw projectionFailure
        }
        let depth = point.y + 10
        let scale = screenScale(atDepth: depth)
        return (
            point: CGPoint(x: 200 + point.x * 100 * scale, y: 200 - point.z * 100 * scale),
            depth: depth
        )
    }

    func surfaceHit(
        at point: CGPoint
    ) throws -> (triangle: MeshSourcePresentationTriangle, point: Point3D)? {
        if let surfaceFailure {
            throw surfaceFailure
        }
        let scale = screenScale(atDepth: surfaceDepth)
        let x = Double(point.x - 200) / (100 * scale)
        let z = Double(200 - point.y) / (100 * scale)
        guard x >= surfaceInset, x <= 1 - surfaceInset,
              z >= surfaceInset, z <= 1 - surfaceInset else {
            return nil
        }
        let surfacePoint = Point3D(x: x, y: surfaceDepth - 10, z: z)
        // The frame draws nothing where the section removed geometry, so a cut
        // pixel is empty in exactly the same way a silhouette pixel is.
        guard try retainsSectionedPoint(surfacePoint) else { return nil }
        return (
            triangle: frameTriangle(occurrenceID: surfaceOccurrenceID, faceID: surfaceFaceID),
            point: surfacePoint
        )
    }

    func retainsSectionedPoint(_ point: Point3D) throws -> Bool {
        guard let section else { return true }
        let distance = point.x * section.normal.x
            + point.y * section.normal.y
            + point.z * section.normal.z
        return distance - section.offset >= -section.tolerance
    }

    // The point query asks none of the rectangle's frame questions. Answering
    // them would let this frame stand in for a region raster it does not model,
    // so each one refuses instead of returning a value the resolver could read
    // as an empty region.

    func projectedPointWithDepth(
        _ point: Point3D
    ) throws -> (point: CGPoint?, depth: Double) {
        throw UnqueriedRegionFrameQuery()
    }

    func regionFragment(
        at point: CGPoint
    ) throws -> (triangle: MeshSourcePresentationTriangle, depth: Double)? {
        throw UnqueriedRegionFrameQuery()
    }

    func cameraDepthInterval() throws -> ClosedRange<Double> {
        throw UnqueriedRegionFrameQuery()
    }

    func sectionParameterBound(
        from start: Point3D,
        to end: Point3D
    ) throws -> ViewportCameraDepthClip.AffineScalarBound? {
        throw UnqueriedRegionFrameQuery()
    }

    func regionSegmentProbe(
        from start: CGPoint,
        to end: CGPoint,
        within rect: CGRect,
        startingAt step: Int
    ) throws -> RealityViewportRegionSegmentProbe {
        throw UnqueriedRegionFrameQuery()
    }
}

extension NativeCADFrame: ViewportNativeFrameProbe {}

/// Raised when the point query reaches a frame question only the rectangle
/// query asks.
private struct UnqueriedRegionFrameQuery: Error {}

private func frameTriangle(
    occurrenceID: SceneOccurrenceID,
    faceID: MeshFaceID
) -> MeshSourcePresentationTriangle {
    MeshSourcePresentationTriangle(
        occurrenceID: occurrenceID,
        definitionID: ObjectDefinitionID(rawValue: "definition.cad"),
        representationID: GeometryRepresentationID(rawValue: "representation.cad"),
        sourceReference: .cad(sourceID: "cad.source", outputID: "cad.output"),
        faceID: faceID,
        firstVertexID: MeshVertexID(0),
        secondVertexID: MeshVertexID(1),
        thirdVertexID: MeshVertexID(2),
        firstPosition: GeometryPoint3D(x: 0, y: 0, z: 0),
        secondPosition: GeometryPoint3D(x: 1, y: 0, z: 0),
        thirdPosition: GeometryPoint3D(x: 1, y: 0, z: 1)
    )
}

// MARK: - Prepared CAD identity

private let topologyFeatureID = FeatureID()

private func preparedComponentID(role: String, ordinal: Int) -> SelectionComponentID {
    .generatedTopology(SubshapeID(featureID: topologyFeatureID, role: role, ordinal: ordinal))
}

private let frontFaceComponentID = preparedComponentID(role: "face", ordinal: 3)
private let sideFaceComponentID = preparedComponentID(role: "face", ordinal: 4)
private let bottomEdgeComponentID = preparedComponentID(role: "edge", ordinal: 11)
private let originVertexComponentID = preparedComponentID(role: "vertex", ordinal: 5)
private let hiddenVertexComponentID = preparedComponentID(role: "vertex", ordinal: 6)

/// The face is the unit square at `y = 0`; the edge is its `z = 0` side; the
/// vertices are the visible origin corner and one corner hidden behind the
/// face at the same pixel as the face centre.
///
/// Two prepared runs partition the drawn triangles: the front face generated
/// triangles 0..<10 and a second face generated 10..<20. The frame's default
/// triangle, 7, therefore belongs to the front face, and triangle 20 and above
/// belongs to no prepared face at all.
private func bodyTopology(includingHiddenVertex hidden: Bool = true) -> ViewportBodyTopology {
    ViewportBodyTopology(
        faces: [
            .init(
                componentID: frontFaceComponentID,
                points: [
                    Point3D(x: 0, y: 0, z: 0),
                    Point3D(x: 1, y: 0, z: 0),
                    Point3D(x: 1, y: 0, z: 1),
                    Point3D(x: 0, y: 0, z: 1),
                ]
            )
        ],
        edges: [
            .init(
                componentID: bottomEdgeComponentID,
                start: Point3D(x: 0, y: 0, z: 0),
                end: Point3D(x: 1, y: 0, z: 0)
            )
        ],
        vertices: hidden
            ? [
                .init(componentID: originVertexComponentID, point: Point3D(x: 0, y: 0, z: 0)),
                .init(componentID: hiddenVertexComponentID, point: Point3D(x: 0.5, y: 0.5, z: 0.5)),
            ]
            : [
                .init(componentID: originVertexComponentID, point: Point3D(x: 0, y: 0, z: 0))
            ],
        meshFaceRuns: [
            .init(componentID: frontFaceComponentID, triangleRange: 0 ..< 10),
            .init(componentID: sideFaceComponentID, triangleRange: 10 ..< 20),
        ]
    )
}

private let slantedEdgeComponentID = preparedComponentID(role: "edge", ordinal: 21)

/// A single edge whose endpoints lie at camera depths 1 and 3. Its projected
/// midpoint is depth 2 under an orthographic camera and depth 1.5 under a
/// perspective camera, so a drawn surface at depth 1.6 hides it under exactly
/// one of the two rules.
private func slantedEdgeTopology() -> ViewportBodyTopology {
    ViewportBodyTopology(
        faces: [],
        edges: [
            .init(
                componentID: slantedEdgeComponentID,
                start: Point3D(x: 0, y: -9, z: 0),
                end: Point3D(x: 1, y: -7, z: 0)
            )
        ],
        vertices: []
    )
}

/// The render provenance of the native surface the body under test draws at
/// `point`, which is what the viewport resolves before it asks each body. It is
/// nil when the frame draws nothing there, and nil when the drawn surface
/// belongs to another occurrence, so an empty pixel and an occluding body reach
/// the resolver the same way they do in production.
private func visibleSurface(
    at point: CGPoint,
    frame: NativeCADFrame
) throws -> (faceID: MeshFaceID, depth: Double)? {
    guard let hit = try frame.surfaceHit(at: point),
          hit.triangle.occurrenceID == NativeCADFrame.occurrenceID,
          let depth = try frame.projectedPointWithinDepthRange(hit.point)?.depth else {
        return nil
    }
    return (faceID: hit.triangle.faceID, depth: depth)
}

private func resolve(
    at point: CGPoint,
    frame: NativeCADFrame = NativeCADFrame(),
    topology: ViewportBodyTopology = bodyTopology(),
    modelTransform: Transform3D = .identity,
    policy: ViewportSelectionHitPolicy = .all
) throws -> SelectionComponent? {
    try ViewportNativeCADTopologyResolver.resolve(
        at: point,
        topology: topology,
        modelTransform: modelTransform,
        selectionHitPolicy: policy,
        visibleSurface: try visibleSurface(at: point, frame: frame),
        probe: frame
    )?.component
}

// MARK: - Tests

@Suite struct ViewportNativeCADTopologyResolverTests {
    @Test(.timeLimit(.minutes(1)))
    func nativeCADTopologyResolverReturnsPreparedFaceIdentityAtTheSurfacePoint() throws {
        let component = try #require(try resolve(at: CGPoint(x: 250, y: 150)))
        #expect(component == .face(frontFaceComponentID))
    }

    @Test(.timeLimit(.minutes(1)))
    func nativeCADTopologyResolverNamesTheRunThatContainsTheDrawnTriangle() throws {
        // The drawn pixel does not move; only the triangle the frame reports
        // there does. The answer follows the triangle, which is what makes this
        // the frame's own face decision rather than a second one.
        var frame = NativeCADFrame()
        frame.surfaceFaceID = MeshFaceID(9)
        #expect(try resolve(at: CGPoint(x: 250, y: 150), frame: frame) == .face(frontFaceComponentID))
        frame.surfaceFaceID = MeshFaceID(10)
        #expect(try resolve(at: CGPoint(x: 250, y: 150), frame: frame) == .face(sideFaceComponentID))
        frame.surfaceFaceID = MeshFaceID(19)
        #expect(try resolve(at: CGPoint(x: 250, y: 150), frame: frame) == .face(sideFaceComponentID))
    }

    @Test(.timeLimit(.minutes(1)))
    func nativeCADTopologyResolverReadsRunsInTheOrderTheyAreRecorded() throws {
        // A run list carries no ordering guarantee across the value boundary,
        // so the lookup scans it. Descending runs resolve to the same faces an
        // ascending list would, which a search that assumed sorted order would
        // not.
        var topology = bodyTopology()
        topology.meshFaceRuns.reverse()
        var frame = NativeCADFrame()
        frame.surfaceFaceID = MeshFaceID(3)
        #expect(
            try resolve(at: CGPoint(x: 250, y: 150), frame: frame, topology: topology)
                == .face(frontFaceComponentID)
        )
        frame.surfaceFaceID = MeshFaceID(13)
        #expect(
            try resolve(at: CGPoint(x: 250, y: 150), frame: frame, topology: topology)
                == .face(sideFaceComponentID)
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func nativeCADTopologyResolverReportsAMissForATriangleNoPreparedRunNames() throws {
        // Evaluation gave this triangle's face no stable sub-shape identity, so
        // there is no CAD name to select. The miss is reported rather than
        // answered with the nearest run, which would select a face the frame
        // never drew.
        var frame = NativeCADFrame()
        frame.surfaceFaceID = MeshFaceID(20)
        #expect(try resolve(at: CGPoint(x: 250, y: 150), frame: frame) == nil)
        // The same pixel with an unprepared body answers nothing at all, so the
        // miss is the run lookup and not a projection or visibility failure.
        #expect(
            try resolve(
                at: CGPoint(x: 250, y: 150),
                frame: frame,
                topology: slantedEdgeTopology(),
                policy: .face
            ) == nil
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func nativeCADTopologyResolverRejectsAnUnrepresentableMeshFaceIdentity() throws {
        // A raw value no triangle index can hold is malformed provenance. It is
        // reported as a typed failure, because answering "nothing was hit"
        // would hand the query on as if the frame had decided.
        var frame = NativeCADFrame()
        frame.surfaceFaceID = MeshFaceID(UInt64.max)
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try resolve(at: CGPoint(x: 250, y: 150), frame: frame)
        }
        // The scope still gates the branch: a query that asks for no face never
        // reads the identity and so never fails on it.
        #expect(try resolve(at: CGPoint(x: 250, y: 150), frame: frame, policy: .vertex) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func nativeCADTopologyResolverPrefersEdgeThenVertexOverTheContainingFace() throws {
        let edge = try #require(try resolve(at: CGPoint(x: 250, y: 197)))
        #expect(edge == .edge(bottomEdgeComponentID))
        let vertex = try #require(try resolve(at: CGPoint(x: 203, y: 197)))
        #expect(vertex == .vertex(originVertexComponentID))
    }

    @Test(.timeLimit(.minutes(1)))
    func nativeCADTopologyResolverRejectsEdgeCandidatesOutsideTheScreenTolerance() throws {
        let inside = try #require(try resolve(at: CGPoint(x: 250, y: 193)))
        #expect(inside == .edge(bottomEdgeComponentID))
        let outside = try #require(try resolve(at: CGPoint(x: 250, y: 191)))
        #expect(outside == .face(frontFaceComponentID))
    }

    @Test(.timeLimit(.minutes(1)))
    func nativeCADTopologyResolverReportsAMissWhereNoSurfaceAndNoSubshapeProject() throws {
        #expect(try resolve(at: CGPoint(x: 150, y: 150)) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func nativeCADTopologyResolverReportsAMissWhenAnotherOccurrenceOccludesTheBody() throws {
        var frame = NativeCADFrame()
        frame.surfaceOccurrenceID = SceneOccurrenceID(rawValue: "occurrence.other")
        #expect(try resolve(at: CGPoint(x: 250, y: 150), frame: frame) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func nativeCADTopologyResolverDoesNotSelectAVertexHiddenBehindTheVisibleSurface() throws {
        let component = try #require(try resolve(at: CGPoint(x: 250, y: 150)))
        #expect(component == .face(frontFaceComponentID))
        let withoutHidden = try #require(
            try resolve(at: CGPoint(x: 250, y: 150), topology: bodyTopology(includingHiddenVertex: false))
        )
        #expect(withoutHidden == .face(frontFaceComponentID))
    }

    @Test(.timeLimit(.minutes(1)))
    func nativeCADTopologyResolverHonoursTheSelectionHitPolicyScope() throws {
        let corner = CGPoint(x: 203, y: 197)
        #expect(try resolve(at: corner, policy: .face) == .face(frontFaceComponentID))
        #expect(try resolve(at: corner, policy: .edge) == .edge(bottomEdgeComponentID))
        #expect(try resolve(at: corner, policy: .vertex) == .vertex(originVertexComponentID))
        #expect(try resolve(at: CGPoint(x: 250, y: 150), policy: .vertex) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func nativeCADTopologyResolverAppliesTheItemModelTransformBeforeProjecting() throws {
        let shifted = Transform3D(matrix: try Matrix4x4(values: [
            1, 0, 0, 0.5,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        ]))
        // The origin vertex now projects to x = 250; the untransformed pixel misses it.
        #expect(
            try resolve(at: CGPoint(x: 250, y: 197), modelTransform: shifted, policy: .vertex)
                == .vertex(originVertexComponentID)
        )
        #expect(try resolve(at: CGPoint(x: 203, y: 197), modelTransform: shifted, policy: .vertex) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func nativeCADTopologyResolverPropagatesNativeFrameFailuresInsteadOfReportingAMiss() throws {
        var projectionFailure = NativeCADFrame()
        projectionFailure.projectionFailure = MeshSourcePresentationRenderError(
            code: .invalidSceneItem,
            message: "projection unavailable"
        )
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try resolve(at: CGPoint(x: 250, y: 150), frame: projectionFailure)
        }
        var surfaceFailure = NativeCADFrame()
        surfaceFailure.surfaceFailure = MeshSourcePresentationRenderError(
            code: .invalidSceneItem,
            message: "surface query unavailable"
        )
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try resolve(at: CGPoint(x: 250, y: 150), frame: surfaceFailure)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nativeCADTopologyResolverRejectsInvalidQueryCoordinates() throws {
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try resolve(at: CGPoint(x: CGFloat.nan, y: 150))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nativeCADTopologyResolverAdmitsSilhouetteCandidatesTheDrawnSurfaceMisses() throws {
        // The drawn square stops just inside the exact loop, so the outline
        // pixels answer no surface at all. A pixel that draws nothing hides
        // nothing, so the corner and the outline edge stay selectable.
        var frame = NativeCADFrame()
        frame.surfaceInset = 0.005
        #expect(
            try resolve(at: CGPoint(x: 203, y: 197), frame: frame, policy: .vertex)
                == .vertex(originVertexComponentID)
        )
        #expect(
            try resolve(at: CGPoint(x: 250, y: 197), frame: frame, policy: .edge)
                == .edge(bottomEdgeComponentID)
        )
        // Occlusion still applies wherever the frame does draw a nearer surface.
        #expect(try resolve(at: CGPoint(x: 250, y: 150), frame: frame, policy: .vertex) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func nativeCADTopologyResolverAnswersVertexAndEdgeWherePointerDrawsNoSurface() throws {
        // Hovering just off the body is the common case. The native frame still
        // answers it, so the query never has to reach the legacy identity
        // resolver merely because nothing is drawn under the pointer.
        var frame = NativeCADFrame()
        frame.surfaceInset = 0.1
        #expect(try visibleSurface(at: CGPoint(x: 198, y: 202), frame: frame) == nil)
        #expect(
            try resolve(at: CGPoint(x: 198, y: 202), frame: frame)
                == .vertex(originVertexComponentID)
        )
        #expect(
            try resolve(at: CGPoint(x: 250, y: 203), frame: frame)
                == .edge(bottomEdgeComponentID)
        )
        // A face cannot exist where the frame draws nothing.
        #expect(try resolve(at: CGPoint(x: 250, y: 203), frame: frame, policy: .face) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func nativeCADTopologyResolverInterpolatesEdgeDepthLinearlyUnderAnOrthographicFrame() throws {
        // The edge runs from depth 1 to depth 3, so its projected midpoint is
        // at depth 2 under this frame's orthographic camera. A surface drawn at
        // depth 1.6 is in front of it and the edge is not selectable there.
        // Reciprocal interpolation would report depth 1.5 and admit an edge the
        // frame does not show.
        var frame = NativeCADFrame()
        frame.surfaceDepth = 1.6
        #expect(
            try resolve(
                at: CGPoint(x: 250, y: 200),
                frame: frame,
                topology: slantedEdgeTopology(),
                policy: .edge
            ) == nil
        )
        // Moving the drawn surface behind the midpoint admits the same edge, so
        // the miss above is occlusion and not a projection or tolerance miss.
        frame.surfaceDepth = 2.4
        #expect(
            try resolve(
                at: CGPoint(x: 250, y: 200),
                frame: frame,
                topology: slantedEdgeTopology(),
                policy: .edge
            ) == .edge(slantedEdgeComponentID)
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func nativeCADTopologyResolverInterpolatesEdgeDepthReciprocallyUnderAPerspectiveFrame() throws {
        // The same edge under a perspective camera. Its endpoints now project
        // to 200 and 533.33, and the midpoint pixel is depth 1.5, in front of
        // the surface drawn at 1.6. Linear interpolation would report depth 2
        // and reject an edge the frame does show.
        var frame = NativeCADFrame()
        frame.usesPerspectiveProjection = true
        frame.surfaceDepth = 1.6
        let midpoint = CGPoint(x: 200 + 500.0 / 3.0, y: 200)
        #expect(
            try resolve(
                at: midpoint,
                frame: frame,
                topology: slantedEdgeTopology(),
                policy: .edge
            ) == .edge(slantedEdgeComponentID)
        )
        frame.surfaceDepth = 1.4
        #expect(
            try resolve(
                at: midpoint,
                frame: frame,
                topology: slantedEdgeTopology(),
                policy: .edge
            ) == nil
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func nativeCADTopologyResolverRejectsEdgeCandidatesTheSectionRemoved() throws {
        // The frame retains only x >= 0.5, so it draws nothing over the cut
        // half of the edge. That empty pixel is indistinguishable from the
        // silhouette pixel the retained half produces, and only the frame's own
        // section answer separates the two.
        var frame = NativeCADFrame()
        frame.section = (normal: Vector3D(x: 1, y: 0, z: 0), offset: 0.5, tolerance: 0)
        #expect(try frame.surfaceHit(at: CGPoint(x: 220, y: 200)) == nil)
        #expect(
            try resolve(at: CGPoint(x: 280, y: 203), frame: frame, policy: .edge)
                == .edge(bottomEdgeComponentID)
        )
        #expect(try resolve(at: CGPoint(x: 220, y: 203), frame: frame, policy: .edge) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func nativeCADTopologyResolverRejectsVerticesTheSectionRemoved() throws {
        // The pixel just off the body draws nothing, which is the silhouette
        // case that admits the origin vertex. The section still removes that
        // vertex, so a frame that cut it away answers no candidate there.
        var frame = NativeCADFrame()
        frame.surfaceInset = 0.1
        #expect(
            try resolve(at: CGPoint(x: 198, y: 202), frame: frame, policy: .vertex)
                == .vertex(originVertexComponentID)
        )
        frame.section = (normal: Vector3D(x: 1, y: 0, z: 0), offset: 0.5, tolerance: 0)
        #expect(try resolve(at: CGPoint(x: 198, y: 202), frame: frame, policy: .vertex) == nil)
    }
}
