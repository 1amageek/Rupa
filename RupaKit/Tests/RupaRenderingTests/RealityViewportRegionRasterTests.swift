import CoreGraphics
import Foundation
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaGeometry
import RupaProjectModel
import RupaViewportScene
import Testing
import simd
@testable import RupaRendering

/// The mounted frame's region visibility rule, exercised without a mounted
/// frame.
///
/// Everything the raster reads arrives in a `RealityViewportRegionFrame`
/// value, so the projection, the near clip, the back-face sign, the depth
/// interval, the section half-space, the two region ceilings and the lazy
/// tiling are all decidable here. What needs a display — that a live frame
/// derives the same value, and that the plan cache gates these queries the way
/// it gates `surfaceHit` — is not this suite's to prove.
///
/// The fixtures use an identity view matrix, a zero render origin and a unit
/// camera-plane map, so a CAD world position `(x, y, z)` lands on device pixel
/// `(x, y)` under the orthographic frame and its linear view-space depth is
/// `-z`. The perspective frame adds only the half-viewport translation its
/// affine map needs to keep projected points positive.
@Suite struct RealityViewportRegionRasterTests {

    // MARK: - Retained cost

    @Test(.timeLimit(.minutes(1)))
    func projectedTriangleStrideMatchesAdmittedCost() {
        // `maxRegionRetainedByteCount` is stated at this stride. If the layout
        // grows, the admission is charging less than the raster retains.
        #expect(MemoryLayout<RealityViewportProjectedTriangle>.stride == 112)
    }

    // MARK: - Frame key

    @Test(.timeLimit(.minutes(1)))
    func regionFrameKeyDistinguishesEveryMember() {
        let base = regionFrameKey()
        #expect(base == regionFrameKey())

        #expect(base != regionFrameKey(appliedViewportRevision: 8))
        var movedLayout = regionLayout()
        movedLayout.scale += 1
        #expect(base != regionFrameKey(appliedLayout: movedLayout))
        #expect(base != regionFrameKey(appliedDisplayScale: 2))
        #expect(base != regionFrameKey(calibrationGeneration: 1))
        #expect(base != regionFrameKey(
            section: RealityViewportSectionHalfSpace(
                normal: SIMD3<Double>(1, 0, 0), offset: 0, tolerance: 0
            )
        ))
        #expect(base != regionFrameKey(cullsBackfaces: false))
        #expect(base != regionFrameKey(geometryRootEnabled: false))
    }

    // MARK: - Near clip

    @Test(.timeLimit(.minutes(1)))
    func perspectiveNearClipEmitsOneSplitTriangle() throws {
        // One vertex sits behind the eye, so the frame draws the part of the
        // triangle in front of its near plane and nothing else. The clipped
        // polygon is a quadrilateral and reaches the raster as two fans, but
        // it is one CAD triangle and has to be reported once.
        let source = try regionSource(
            identity: "mesh.region.near-clip",
            points: [
                GeometryPoint3D(x: -20, y: -20, z: -10),
                GeometryPoint3D(x: 20, y: -20, z: -10),
                GeometryPoint3D(x: 0, y: 20, z: 5),
            ]
        )
        let plan = try regionPlan([(source, try regionTransform())])
        let raster = try RealityViewportRegionRaster(
            frame: regionPerspectiveFrame(), plan: plan
        )

        var emitted: [MeshSourcePresentationTriangle] = []
        try raster.forEachRegionTriangle(
            intersecting: CGRect(x: 0, y: 0, width: 32, height: 32)
        ) { emitted.append($0) }
        #expect(emitted.count == 1)

        // A pixel each fan owns. The second lies past where the unclipped
        // triangle's projection would be defined at all.
        let firstFan = try raster.regionFragment(
            at: CGPoint(x: 16.5, y: 14.5)
        )
        #expect(firstFan != nil)
        let secondFan = try raster.regionFragment(
            at: CGPoint(x: 22.5, y: 19.5)
        )
        #expect(secondFan != nil)
        // The clip put its new vertices exactly on the near plane, so no
        // fragment of either fan may fall in front of it.
        #expect((secondFan?.depth ?? 0) >= 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func perspectiveFrameDrawsNothingBehindTheEye() throws {
        // Wound so the back-face rule keeps it: what removes it is the near
        // clip, not the cull.
        let source = try regionSource(
            identity: "mesh.region.behind-eye",
            points: [
                GeometryPoint3D(x: 0, y: 0, z: 5),
                GeometryPoint3D(x: 0, y: 40, z: 5),
                GeometryPoint3D(x: 40, y: 0, z: 5),
            ]
        )
        let plan = try regionPlan([(source, try regionTransform())])
        let raster = try RealityViewportRegionRaster(
            frame: regionPerspectiveFrame(), plan: plan
        )

        var emitted = 0
        try raster.forEachRegionTriangle(
            intersecting: CGRect(x: 0, y: 0, width: 32, height: 32)
        ) { _ in emitted += 1 }
        #expect(emitted == 0)
        #expect(try raster.regionFragment(
            at: CGPoint(x: 16.5, y: 16.5)
        ) == nil)
    }

    // MARK: - Back-face sign

    @Test(.timeLimit(.minutes(1)))
    func backFaceSignAgreesAcrossProjections() throws {
        // The orthographic rule reads the camera forward and the perspective
        // one reads the eye, so they are different expressions. A quad wound
        // towards the camera has to survive both, and its reverse has to be
        // removed by both.
        let facing = try regionQuad(
            identity: "mesh.region.facing", side: 4, z: -5, reversed: false
        )
        let away = try regionQuad(
            identity: "mesh.region.away", side: 4, z: -5, reversed: true
        )
        let orthographic = regionOrthographicFrame()
        let facingRaster = try RealityViewportRegionRaster(
            frame: orthographic,
            plan: try regionPlan([(facing, try regionTransform())])
        )
        let awayRaster = try RealityViewportRegionRaster(
            frame: orthographic,
            plan: try regionPlan([(away, try regionTransform())])
        )
        #expect(try facingRaster.regionFragment(
            at: CGPoint(x: 2.5, y: 1.5)
        ) != nil)
        #expect(try awayRaster.regionFragment(
            at: CGPoint(x: 2.5, y: 1.5)
        ) == nil)

        let farFacing = try regionQuad(
            identity: "mesh.region.facing-far", side: 40, z: -10,
            reversed: false
        )
        let farAway = try regionQuad(
            identity: "mesh.region.away-far", side: 40, z: -10, reversed: true
        )
        let perspective = regionPerspectiveFrame()
        let farFacingRaster = try RealityViewportRegionRaster(
            frame: perspective,
            plan: try regionPlan([(farFacing, try regionTransform())])
        )
        let farAwayRaster = try RealityViewportRegionRaster(
            frame: perspective,
            plan: try regionPlan([(farAway, try regionTransform())])
        )
        #expect(try farFacingRaster.regionFragment(
            at: CGPoint(x: 18.5, y: 17.5)
        ) != nil)
        #expect(try farAwayRaster.regionFragment(
            at: CGPoint(x: 18.5, y: 17.5)
        ) == nil)
    }

    // MARK: - Depth interpolation

    @Test(.timeLimit(.minutes(1)))
    func orthographicDepthMatchesRayPlaneIntersection() throws {
        // Depth is stored in the form that is linear in screen space and read
        // back through barycentric weights. The reference here intersects the
        // pixel's ray with the triangle's plane instead, so agreement is not
        // the raster confirming its own interpolation.
        let points = [
            SIMD3<Double>(0, 0, -5),
            SIMD3<Double>(8, 0, -9),
            SIMD3<Double>(0, 8, -5),
        ]
        let source = try regionSource(
            identity: "mesh.region.ortho-depth", points: points.map {
                GeometryPoint3D(x: $0.x, y: $0.y, z: $0.z)
            }
        )
        let frame = regionOrthographicFrame()
        let raster = try RealityViewportRegionRaster(
            frame: frame,
            plan: try regionPlan([(source, try regionTransform())])
        )
        for pixel in [SIMD2<Double>(2.5, 1.5), SIMD2<Double>(1.5, 4.5)] {
            let fragment = try raster.regionFragment(
                at: CGPoint(x: pixel.x, y: pixel.y)
            )
            let expected = rayPlaneDepth(
                points: points, devicePixel: pixel, frame: frame
            )
            #expect(fragment != nil)
            #expect(abs((fragment?.depth ?? 0) - expected) <= 1e-9 * expected)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func perspectiveDepthMatchesRayPlaneIntersection() throws {
        let points = [
            SIMD3<Double>(-40, -40, -10),
            SIMD3<Double>(40, -40, -10),
            SIMD3<Double>(0, 40, -20),
        ]
        let source = try regionSource(
            identity: "mesh.region.perspective-depth", points: points.map {
                GeometryPoint3D(x: $0.x, y: $0.y, z: $0.z)
            }
        )
        let frame = regionPerspectiveFrame()
        let raster = try RealityViewportRegionRaster(
            frame: frame,
            plan: try regionPlan([(source, try regionTransform())])
        )
        for pixel in [SIMD2<Double>(16.5, 13.5), SIMD2<Double>(16.5, 15.5)] {
            let fragment = try raster.regionFragment(
                at: CGPoint(x: pixel.x, y: pixel.y)
            )
            let expected = rayPlaneDepth(
                points: points, devicePixel: pixel, frame: frame
            )
            #expect(fragment != nil)
            #expect(abs((fragment?.depth ?? 0) - expected) <= 1e-9 * expected)
        }
    }

    // MARK: - Section half-space

    @Test(.timeLimit(.minutes(1)))
    func sectionHalfSpaceCutsWithinOneTriangle() throws {
        // The cut runs through the interior of a single triangle, so a
        // per-triangle test would keep or drop both pixels together.
        let source = try regionSource(
            identity: "mesh.region.section",
            points: [
                GeometryPoint3D(x: 0, y: 0, z: -5),
                GeometryPoint3D(x: 8, y: 0, z: -5),
                GeometryPoint3D(x: 0, y: 8, z: -5),
            ]
        )
        let plan = try regionPlan([(source, try regionTransform())])
        let removed = CGPoint(x: 1.5, y: 1.5)
        let retained = CGPoint(x: 5.5, y: 1.5)

        let uncut = try RealityViewportRegionRaster(
            frame: regionOrthographicFrame(), plan: plan
        )
        #expect(try uncut.regionFragment(at: removed) != nil)
        #expect(try uncut.regionFragment(at: retained) != nil)

        let cut = try RealityViewportRegionRaster(
            frame: regionOrthographicFrame(
                section: RealityViewportSectionHalfSpace(
                    normal: SIMD3<Double>(1, 0, 0), offset: 4, tolerance: 0
                )
            ),
            plan: plan
        )
        #expect(try cut.regionFragment(at: removed) == nil)
        #expect(try cut.regionFragment(at: retained) != nil)
    }

    // MARK: - Rectangle bounds

    @Test(.timeLimit(.minutes(1)))
    func abuttingRectanglesDoNotShareADevicePixel() throws {
        // Two rectangles meeting at x = 1 must not both answer with the pixel
        // on that edge, or a drag releasing on a boundary picks up whatever
        // the neighbouring column draws.
        let source = try regionQuad(
            identity: "mesh.region.column", width: 1, height: 4, z: -5
        )
        let plan = try regionPlan([
            (source, try regionTransform()),
            (source, try regionTransform(x: 1)),
        ])
        let raster = try RealityViewportRegionRaster(
            frame: regionOrthographicFrame(), plan: plan
        )

        var leading: Set<SceneOccurrenceID> = []
        try raster.forEachRegionTriangle(
            intersecting: CGRect(x: 0, y: 0, width: 1, height: 4)
        ) { leading.insert($0.occurrenceID) }
        var trailing: Set<SceneOccurrenceID> = []
        try raster.forEachRegionTriangle(
            intersecting: CGRect(x: 1, y: 0, width: 1, height: 4)
        ) { trailing.insert($0.occurrenceID) }

        #expect(leading.count == 1)
        #expect(trailing.count == 1)
        #expect(leading.isDisjoint(with: trailing))
    }

    // MARK: - Admission

    @Test(.timeLimit(.minutes(1)))
    func regionFragmentCeilingRefusesTheFrame() throws {
        // 12000 x 11104 device pixels under one triangle covering all of them
        // is 133,248,000 fragments, just past the admitted count. A refused
        // frame answers no rectangle rather than part of one.
        let source = try regionSource(
            identity: "mesh.region.fragment-ceiling",
            points: [
                GeometryPoint3D(x: -10, y: -10, z: -5),
                GeometryPoint3D(x: 20000, y: -10, z: -5),
                GeometryPoint3D(x: -10, y: 20000, z: -5),
            ]
        )
        let plan = try regionPlan([(source, try regionTransform())])
        #expect(throws: MeshSourcePresentationRenderError.self) {
            _ = try RealityViewportRegionRaster(
                frame: regionOrthographicFrame(width: 12000, height: 11104),
                plan: plan
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func regionByteCeilingRefusesTheFrame() throws {
        // 8100 x 6000 is 48,600,000 fragments, well inside the fragment
        // ceiling, but its identity buffer alone is 194,400,000 bytes and the
        // retained total clears the admitted byte count. The two ceilings are
        // therefore independent.
        let source = try regionSource(
            identity: "mesh.region.byte-ceiling",
            points: [
                GeometryPoint3D(x: -10, y: -10, z: -5),
                GeometryPoint3D(x: 20000, y: -10, z: -5),
                GeometryPoint3D(x: -10, y: 20000, z: -5),
            ]
        )
        let plan = try regionPlan([(source, try regionTransform())])
        #expect(throws: MeshSourcePresentationRenderError.self) {
            _ = try RealityViewportRegionRaster(
                frame: regionOrthographicFrame(width: 8100, height: 6000),
                plan: plan
            )
        }
    }

    // MARK: - Lazy tiling

    @Test(.timeLimit(.minutes(1)))
    func tilesRasterizeOnlyWhereQueried() throws {
        // A 1024-pixel frame is sixteen tiles. Paying for all of them on a
        // one-pixel query would make a hover cost a full-frame rasterization.
        let source = try regionQuad(
            identity: "mesh.region.tiles", side: 1024, z: -5
        )
        let raster = try RealityViewportRegionRaster(
            frame: regionOrthographicFrame(width: 1024, height: 1024),
            plan: try regionPlan([(source, try regionTransform())])
        )
        #expect(raster.rasterizedTileCount == 0)

        _ = try raster.regionFragment(at: CGPoint(x: 10, y: 10))
        #expect(raster.rasterizedTileCount == 1)

        try raster.forEachRegionTriangle(
            intersecting: CGRect(x: 0, y: 0, width: 300, height: 300)
        ) { _ in }
        #expect(raster.rasterizedTileCount == 4)
    }

    // MARK: - Emission order

    @Test(.timeLimit(.minutes(1)))
    func regionTrianglesArriveInPlanOrder() throws {
        // The plan's order is what resolves a depth tie, so a region answer
        // that reordered its triangles would disagree with the frame about
        // which one is in front.
        let source = try regionQuad(
            identity: "mesh.region.order", side: 4, z: -5
        )
        let plan = try regionPlan([
            (source, try regionTransform()),
            (source, try regionTransform(x: 6)),
            (source, try regionTransform(x: 12)),
        ])
        var planOrder: [MeshSourcePresentationTriangle] = []
        plan.forEachTriangle { planOrder.append($0) }

        let raster = try RealityViewportRegionRaster(
            frame: regionOrthographicFrame(), plan: plan
        )
        var emitted: [MeshSourcePresentationTriangle] = []
        try raster.forEachRegionTriangle(
            intersecting: CGRect(x: 0, y: 0, width: 32, height: 32)
        ) { emitted.append($0) }

        #expect(planOrder.count == 6)
        #expect(emitted == planOrder)
    }

    // MARK: - Segment probe

    @Test(.timeLimit(.minutes(1)))
    func segmentProbeWalksAOnePixelTallRectangle() throws {
        // The rectangle is one pixel tall and the segment crosses it without
        // ever meeting the centre line of that row. Clipping the walk to the
        // box of admissible pixel centres would collapse it to a single
        // sample and miss the drawn column the frame plainly shows.
        let source = try regionQuad(
            identity: "mesh.region.probe", width: 1, height: 2, z: -5
        )
        let raster = try RealityViewportRegionRaster(
            frame: regionOrthographicFrame(),
            plan: try regionPlan([(source, try regionTransform(x: 4))])
        )
        let probe = try raster.regionSegmentProbe(
            from: CGPoint(x: 0.1, y: 0.1),
            to: CGPoint(x: 5.9, y: 0.9),
            within: CGRect(x: 0, y: 0, width: 32, height: 1),
            startingAt: 0
        )
        #expect(probe.stepCount == 6)
        #expect(probe.drawn?.step == 4)
        #expect(abs((probe.drawn?.fraction ?? 0) - 4.5 / 6) <= 1e-12)
        #expect(abs((probe.drawn?.depth ?? 0) - 5) <= 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func segmentProbeResumesPastARejectedStep() throws {
        // A consumer that rejects the reported pixel continues the same walk
        // rather than restarting it, so the step count it sees must not move.
        let source = try regionQuad(
            identity: "mesh.region.probe-resume", width: 1, height: 2, z: -5
        )
        let raster = try RealityViewportRegionRaster(
            frame: regionOrthographicFrame(),
            plan: try regionPlan([(source, try regionTransform(x: 4))])
        )
        let rect = CGRect(x: 0, y: 0, width: 32, height: 1)
        let resumed = try raster.regionSegmentProbe(
            from: CGPoint(x: 0.1, y: 0.1),
            to: CGPoint(x: 5.9, y: 0.9),
            within: rect,
            startingAt: 5
        )
        #expect(resumed.stepCount == 6)
        #expect(resumed.drawn == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func segmentProbeRefusesANegativeStep() throws {
        let source = try regionQuad(
            identity: "mesh.region.probe-refusal", width: 1, height: 2, z: -5
        )
        let raster = try RealityViewportRegionRaster(
            frame: regionOrthographicFrame(),
            plan: try regionPlan([(source, try regionTransform(x: 4))])
        )
        #expect(throws: MeshSourcePresentationRenderError.self) {
            _ = try raster.regionSegmentProbe(
                from: CGPoint(x: 0.1, y: 0.1),
                to: CGPoint(x: 5.9, y: 0.9),
                within: CGRect(x: 0, y: 0, width: 32, height: 1),
                startingAt: -1
            )
        }
    }
}

// MARK: - Frames

private func regionOrthographicFrame(
    width: Int = 32,
    height: Int = 32,
    section: RealityViewportSectionHalfSpace? = nil,
    cullsBackfaces: Bool = true
) -> RealityViewportRegionFrame {
    RealityViewportRegionFrame(
        viewMatrix: matrix_identity_double4x4,
        renderOrigin: .zero,
        eye: .zero,
        forward: SIMD3<Double>(0, 0, -1),
        step: 1,
        sampleDepth: 1,
        usesPerspectiveProjection: false,
        planeToPoints: (a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0),
        displayScale: 1,
        pixelWidth: width,
        pixelHeight: height,
        nearDepth: 0.1,
        farDepth: 1000,
        section: section,
        cullsBackfaces: cullsBackfaces
    )
}

private func regionPerspectiveFrame(
    width: Int = 32,
    height: Int = 32,
    section: RealityViewportSectionHalfSpace? = nil,
    cullsBackfaces: Bool = true
) -> RealityViewportRegionFrame {
    RealityViewportRegionFrame(
        viewMatrix: matrix_identity_double4x4,
        renderOrigin: .zero,
        eye: .zero,
        forward: SIMD3<Double>(0, 0, -1),
        step: 1,
        sampleDepth: 1,
        usesPerspectiveProjection: true,
        // Without the half-viewport translation a centred model projects onto
        // negative device pixels and the frame draws none of it.
        planeToPoints: (
            a: 1, b: 0, c: 0, d: 1,
            tx: Double(width) / 2, ty: Double(height) / 2
        ),
        displayScale: 1,
        pixelWidth: width,
        pixelHeight: height,
        nearDepth: 1,
        farDepth: 1000,
        section: section,
        cullsBackfaces: cullsBackfaces
    )
}

private func regionLayout() -> ViewportLayout {
    ViewportLayout(
        modelBounds: CGRect(x: 0, y: 0, width: 1, height: 1),
        size: CGSize(width: 32, height: 32)
    )
}

private func regionFrameKey(
    appliedViewportRevision: UInt64 = 4,
    appliedLayout: ViewportLayout? = nil,
    appliedDisplayScale: CGFloat = 1,
    calibrationGeneration: UInt64 = 0,
    section: RealityViewportSectionHalfSpace? = nil,
    cullsBackfaces: Bool = true,
    geometryRootEnabled: Bool = true
) -> RealityViewportRegionFrameKey {
    RealityViewportRegionFrameKey(
        appliedViewportRevision: appliedViewportRevision,
        appliedLayout: appliedLayout ?? regionLayout(),
        appliedDisplayScale: appliedDisplayScale,
        calibrationGeneration: calibrationGeneration,
        section: section,
        cullsBackfaces: cullsBackfaces,
        geometryRootEnabled: geometryRootEnabled
    )
}

// MARK: - Independent depth reference

/// The linear view-space depth at which the ray through one device pixel meets
/// the plane of a triangle.
///
/// This reconstructs the ray from the frame's own camera-plane map and then
/// intersects it analytically, so it shares no code with the barycentric
/// interpolation it is checking. The fixtures place the camera at the native
/// scene origin with an identity view matrix, so the triangle's positions are
/// already camera-local here.
private func rayPlaneDepth(
    points: [SIMD3<Double>],
    devicePixel: SIMD2<Double>,
    frame: RealityViewportRegionFrame
) -> Double {
    let normal = simd_cross(points[1] - points[0], points[2] - points[0])
    let plane = SIMD2<Double>(
        devicePixel.x / frame.displayScale - frame.planeToPoints.tx,
        devicePixel.y / frame.displayScale - frame.planeToPoints.ty
    )
    if frame.usesPerspectiveProjection {
        let direction = SIMD3<Double>(
            plane.x * frame.step / frame.sampleDepth,
            plane.y * frame.step / frame.sampleDepth,
            -1
        )
        return simd_dot(normal, points[0]) / simd_dot(normal, direction)
    }
    return (normal.x * plane.x * frame.step
        + normal.y * plane.y * frame.step
        - simd_dot(normal, points[0])) / normal.z
}

// MARK: - Sources

private func regionSource(
    identity: String, points: [GeometryPoint3D]
) throws -> MeshSource {
    var builder = MeshSourceBuilder(
        identity: GeometrySourceID(rawValue: identity)
    )
    try builder.reserveCapacity(
        vertexCount: points.count, faceCount: 1, cornerCount: points.count
    )
    let vertices = try points.map { try builder.addVertex($0) }
    _ = try builder.addFace(vertexIDs: vertices)
    return try builder.build()
}

/// An axis-aligned quad in the z plane. Wound counter-clockwise in x-y, which
/// is the winding both frames draw.
private func regionQuad(
    identity: String,
    width: Double,
    height: Double,
    z: Double,
    reversed: Bool = false
) throws -> MeshSource {
    let corners = [
        GeometryPoint3D(x: 0, y: 0, z: z),
        GeometryPoint3D(x: width, y: 0, z: z),
        GeometryPoint3D(x: width, y: height, z: z),
        GeometryPoint3D(x: 0, y: height, z: z),
    ]
    return try regionSource(
        identity: identity,
        points: reversed ? Array(corners.reversed()) : corners
    )
}

private func regionQuad(
    identity: String, side: Double, z: Double, reversed: Bool = false
) throws -> MeshSource {
    try regionQuad(
        identity: identity, width: side, height: side, z: z, reversed: reversed
    )
}

private func regionTransform(
    x: Double = 0, y: Double = 0, z: Double = 0
) throws -> GeometryTransform3D {
    try GeometryTransform3D(values: [
        1, 0, 0, x,
        0, 1, 0, y,
        0, 0, 1, z,
        0, 0, 0, 1,
    ])
}

// MARK: - Plans

private func regionPlan(
    _ items: [(source: MeshSource, transform: GeometryTransform3D)]
) throws -> MeshSourcePresentationRenderPlan {
    try MeshSourcePresentationRenderPlan(scene: try regionScene(items))
}

private func regionScene(
    _ items: [(source: MeshSource, transform: GeometryTransform3D)]
) throws -> UniversalViewportScene {
    let projectID = ProjectID(rawValue: "project.region-raster")
    var objectDefinitions: [ObjectDefinitionID: ObjectDefinition] = [:]
    var occurrences: [SceneOccurrenceID: SceneOccurrence] = [:]
    var evaluated: [SceneOccurrenceID: EvaluatedOccurrenceSnapshot] = [:]
    var authored: [GeometrySourceID: AuthoredMeshAsset] = [:]
    var roots: [SceneOccurrenceID] = []

    for index in items.indices {
        let item = items[index]
        let definitionID = ObjectDefinitionID(
            rawValue: "object.region-raster.\(index)"
        )
        let representationID = GeometryRepresentationID(
            rawValue: "representation.region-raster.\(index)"
        )
        let occurrenceID = SceneOccurrenceID(
            rawValue: "occurrence.region-raster.\(index)"
        )
        let reference = GeometrySourceReference.authoredMesh(
            item.source.identity
        )
        objectDefinitions[definitionID] = ObjectDefinition(
            id: definitionID,
            name: "Region \(index)",
            representations: GeometryRepresentationSet(
                representations: [
                    representationID: GeometryRepresentation(
                        id: representationID, source: reference
                    ),
                ],
                selection: GeometryRepresentationSelection(
                    modeling: representationID,
                    presentation: representationID
                )
            )
        )
        occurrences[occurrenceID] = SceneOccurrence(
            id: occurrenceID, definitionID: definitionID
        )
        evaluated[occurrenceID] = EvaluatedOccurrenceSnapshot(
            occurrenceID: occurrenceID,
            definitionID: definitionID,
            representationID: representationID,
            reference: reference,
            mesh: item.source,
            worldTransform: item.transform,
            worldBounds: try item.source.bounds()
                .transformed(by: item.transform)
        )
        authored[item.source.identity] = try AuthoredMeshAsset(
            source: item.source, provenance: .created
        )
        roots.append(occurrenceID)
    }

    let project = try ProjectSourceModel(
        id: projectID,
        name: "Region raster",
        authoredMeshAssets: authored,
        objectDefinitions: objectDefinitions,
        occurrences: occurrences,
        rootOccurrenceIDs: roots
    )
    let snapshot = EvaluatedProjectSnapshot(
        id: EvaluationSnapshotID(
            projectID: projectID,
            purpose: .presentation,
            sourceRevision: DocumentTransactionRevision()
        ),
        projectID: projectID,
        occurrences: evaluated,
        copyTelemetry: GeometryCopyTelemetry()
    )
    return try UniversalViewportSceneBuilder()
        .build(from: snapshot, project: project)
}
