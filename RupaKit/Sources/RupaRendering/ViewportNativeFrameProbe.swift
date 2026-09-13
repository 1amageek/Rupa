import CoreGraphics
import RupaCore

/// The one reader of the mounted native frame on the CAD sub-shape hit paths.
///
/// Projection, depth, section retention, occlusion and the mapping from a
/// projected position back to a world parameter all belong to the frame that
/// drew the viewport. A resolver that asked some of those questions of the
/// frame and answered the rest from a model of its own would let a sub-shape be
/// visible to one rule and hidden to another. Routing every one of them through
/// a single probe is what keeps the point query, the rectangle query and the
/// drawn image sharing one projection, one section and one occlusion decision.
///
/// The requirements are the frame's primitive answers, so a conformer supplies
/// data and never a rule. The derived answers below are extension members for
/// the same reason: the composition of a surface hit with its projection, and
/// the recovery of a world parameter under the mounted camera, are rules this
/// path owns and a conformer must not be able to weaken.
///
/// `usesPerspectiveProjection` is a property rather than a query because it is
/// a property of the mounted camera and not of a point. Resolving it once when
/// the probe is made keeps the per-pixel edge walk free of a repeated frame
/// query that can only return the same answer.
protocol ViewportNativeFrameProbe {
    /// The projection the mounted frame was drawn with.
    var usesPerspectiveProjection: Bool { get }

    /// The projected point and camera depth of a world point the frame's depth
    /// interval admits, or nil for a valid depth rejection.
    func projectedPointWithinDepthRange(
        _ point: Point3D
    ) throws -> (point: CGPoint, depth: Double)?

    /// A world point's camera depth, reported whether or not the frame's depth
    /// interval admits it, together with its projected point wherever the
    /// mounted camera answers for one.
    func projectedPointWithDepth(
        _ point: Point3D
    ) throws -> (point: CGPoint?, depth: Double)

    /// Whether the frame's active section retains a world point.
    func retainsSectionedPoint(_ point: Point3D) throws -> Bool

    /// The surface the frame draws at a projected point, as the hit triangle
    /// and the world point of the hit, or nil over a pixel it draws nothing at.
    func surfaceHit(
        at point: CGPoint
    ) throws -> (triangle: MeshSourcePresentationTriangle, point: Point3D)?

    /// The fragment the frame's region raster holds at a projected point, as
    /// the drawn triangle and its camera depth, or nil over a pixel it draws
    /// nothing at.
    func regionFragment(
        at point: CGPoint
    ) throws -> (triangle: MeshSourcePresentationTriangle, depth: Double)?

    /// The mounted camera's depth interval.
    func cameraDepthInterval() throws -> ClosedRange<Double>

    /// The active section's signed distance over a world segment as one affine
    /// bound, or nil when the frame has no section.
    func sectionParameterBound(
        from start: Point3D,
        to end: Point3D
    ) throws -> ViewportCameraDepthClip.AffineScalarBound?

    /// Clips a projected segment to `rect`'s device pixels and reports the
    /// first drawn pixel at or after `step`.
    func regionSegmentProbe(
        from start: CGPoint,
        to end: CGPoint,
        within rect: CGRect,
        startingAt step: Int
    ) throws -> RealityViewportRegionSegmentProbe
}

extension ViewportNativeFrameProbe {
    /// The camera depth of the surface the frame draws at a projected point.
    ///
    /// A pixel the frame draws nothing at reports nil, and so does a surface
    /// whose own world point the camera's depth interval rejects. Both are the
    /// absence of an occluder rather than a failure: the hit point of a
    /// tessellated surface at a silhouette can fall either side of the
    /// boundary, and an occlusion test reads either as an unoccluded pixel.
    func drawnSurfaceDepth(at point: CGPoint) throws -> Double? {
        guard let surface = try surfaceHit(at: point) else { return nil }
        return try projectedPointWithinDepthRange(surface.point)?.depth
    }

    /// The camera depth of the fragment the frame's region raster holds at a
    /// projected point, or nil over a pixel it draws nothing at.
    func drawnRegionFragmentDepth(at point: CGPoint) throws -> Double? {
        try regionFragment(at: point)?.depth
    }

    /// Maps a parameter along a *projected* segment back to the segment's own
    /// parameter in world space.
    ///
    /// An orthographic camera projects the segment affinely, so the two
    /// parameters are the same. A perspective camera makes reciprocal depth —
    /// not depth — linear on screen, so the world parameter is recovered from
    /// the endpoint depths. Which of the two applies is a property of the
    /// mounted camera, never of the sign of the sampled depths: with an
    /// orthographic camera both depths are positive and the perspective rule
    /// would still report the wrong point. Returns nil when the perspective
    /// recovery has no finite solution, which drops the candidate rather than
    /// substituting the other camera's rule.
    func worldParameter(
        forScreenParameter parameter: Double,
        startDepth: Double,
        endDepth: Double
    ) -> Double? {
        guard parameter.isFinite else { return nil }
        guard usesPerspectiveProjection else { return parameter }
        guard startDepth > 0, endDepth > 0 else { return nil }
        let reciprocal = (1.0 - parameter) / startDepth + parameter / endDepth
        guard reciprocal.isFinite, reciprocal > 0 else { return nil }
        let world = (parameter / endDepth) / reciprocal
        guard world.isFinite else { return nil }
        return world
    }
}
