import CoreGraphics
import RupaCore
import RupaCoreTypes
import RupaGeometry

/// Resolves which occurrences of one mounted frame a selection rectangle
/// selects, from that frame's own projection and its own drawn pixels.
///
/// The occurrence rectangle is the `all` and `object` counterpart of the CAD
/// sub-shape rectangle: it names whole occurrences rather than sub-shapes, and
/// it asks the same frame that answers the pointer instead of projecting the
/// plan through a second camera. The resolver owns no projection model, no
/// section predicate and no culling rule of its own — `project` and
/// `drawnOccurrenceID` are the mounted frame's answers, and the frame draws
/// only what survived the section, only what nothing nearer covers, and only
/// the faces it retains.
enum ViewportNativeOccurrenceRectangleResolver {
    /// The occurrences the mounted frame draws inside `rect`, in plan order and
    /// de-duplicated.
    ///
    /// An empty result is a valid answer: the frame drew no occurrence inside
    /// the rectangle. Readiness, camera revision and projection failures stay
    /// typed and are propagated from the injected native queries.
    ///
    /// `occurrences` and `drawnOccurrenceID` must describe one plan. A query
    /// naming an occurrence the candidate list does not hold would mean the
    /// answering frame and the projected geometry came from two different
    /// plans, so it is reported as a failure rather than dropped.
    ///
    /// Cost per candidate: eight bounding-box projections, one projection per
    /// retained source position, CPU clipping per triangle until the first
    /// overlap, and exactly one native surface query. Across a plan those are
    /// bounded by `MeshSourcePresentationPlanLimits.standard`, and the surface
    /// queries by one per candidate — never one per triangle. The bound is a
    /// correctness contract, not an optimization: a rectangle drag re-runs this
    /// query on every pointer move.
    static func occurrenceIDs(
        intersecting rect: CGRect,
        occurrences: [MeshSourcePresentationOccurrenceView],
        project: (Point3D) throws -> (point: CGPoint, depth: Double)?,
        drawnOccurrenceID: (CGPoint) throws -> SceneOccurrenceID?
    ) throws -> [SceneOccurrenceID] {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite,
              rect.width > 0.0, rect.height > 0.0 else {
            throw MeshSourcePresentationRenderError(
                code: .invalidSceneItem,
                message: "The occurrence rectangle query has no finite, non-empty rectangle."
            )
        }
        var admitted: Set<SceneOccurrenceID> = []
        for occurrence in occurrences {
            // An occurrence a previous query already named is drawn inside the
            // rectangle, so asking again could only repeat that answer.
            guard admitted.contains(occurrence.occurrenceID) == false else { continue }
            guard try mayMeetRectangle(occurrence, rect: rect, project: project) else { continue }
            let projected = try projectedPositions(occurrence, project: project)
            guard let point = representativePoint(
                occurrence, projected: projected, rect: rect
            ) else { continue }
            guard let drawn = try drawnOccurrenceID(point) else { continue }
            admitted.insert(drawn)
        }
        guard admitted.isEmpty == false else { return [] }
        var result: [SceneOccurrenceID] = []
        result.reserveCapacity(admitted.count)
        var emitted: Set<SceneOccurrenceID> = []
        for occurrence in occurrences where admitted.contains(occurrence.occurrenceID) {
            guard emitted.insert(occurrence.occurrenceID).inserted else { continue }
            result.append(occurrence.occurrenceID)
        }
        guard result.count == admitted.count else {
            throw MeshSourcePresentationRenderError(
                code: .invalidSceneItem,
                message: "The native frame drew an occurrence the queried plan does not hold."
            )
        }
        return result
    }

    /// Whether the rectangle can meet the occurrence at all, from the screen
    /// bounds of its world-space bounding box.
    ///
    /// The box is CPU arithmetic over the retained positions; only its eight
    /// corners reach the frame. A candidate is skipped only when the camera
    /// answers for all eight and their screen bounds miss the rectangle, so a
    /// corner the camera cannot project widens the search instead of losing the
    /// occurrence. This is the same rule the CAD face runs use.
    private static func mayMeetRectangle(
        _ occurrence: MeshSourcePresentationOccurrenceView,
        rect: CGRect,
        project: (Point3D) throws -> (point: CGPoint, depth: Double)?
    ) throws -> Bool {
        guard let bounds = worldBounds(occurrence) else { return true }
        var minimum = CGPoint(x: CGFloat.infinity, y: CGFloat.infinity)
        var maximum = CGPoint(x: -CGFloat.infinity, y: -CGFloat.infinity)
        for corner in 0..<8 {
            let point = Point3D(
                x: corner & 1 == 0 ? bounds.minimum.x : bounds.maximum.x,
                y: corner & 2 == 0 ? bounds.minimum.y : bounds.maximum.y,
                z: corner & 4 == 0 ? bounds.minimum.z : bounds.maximum.z
            )
            guard let projected = try project(point),
                  projected.point.x.isFinite, projected.point.y.isFinite else {
                return true
            }
            minimum = CGPoint(
                x: min(minimum.x, projected.point.x),
                y: min(minimum.y, projected.point.y)
            )
            maximum = CGPoint(
                x: max(maximum.x, projected.point.x),
                y: max(maximum.y, projected.point.y)
            )
        }
        return maximum.x >= rect.minX && minimum.x <= rect.maxX
            && maximum.y >= rect.minY && minimum.y <= rect.maxY
    }

    /// The world bounding box of the occurrence's retained positions, or nil
    /// when no finite box describes them.
    private static func worldBounds(
        _ occurrence: MeshSourcePresentationOccurrenceView
    ) -> (minimum: Point3D, maximum: Point3D)? {
        var minimum = Point3D(x: .infinity, y: .infinity, z: .infinity)
        var maximum = Point3D(x: -.infinity, y: -.infinity, z: -.infinity)
        for position in occurrence.positions {
            minimum = Point3D(
                x: min(minimum.x, position.x),
                y: min(minimum.y, position.y),
                z: min(minimum.z, position.z)
            )
            maximum = Point3D(
                x: max(maximum.x, position.x),
                y: max(maximum.y, position.y),
                z: max(maximum.z, position.z)
            )
        }
        guard minimum.x.isFinite, minimum.y.isFinite, minimum.z.isFinite,
              maximum.x.isFinite, maximum.y.isFinite, maximum.z.isFinite else {
            return nil
        }
        return (minimum, maximum)
    }

    /// Each retained world position projected once, nil where the camera does
    /// not answer for it.
    ///
    /// The plan retains one position per source vertex and indexes it per
    /// triangle, which is the shape `MeshSourcePresentationOccurrenceView`
    /// exists for: projecting here costs `positions.count` calls instead of
    /// `3 * triangleCount`.
    private static func projectedPositions(
        _ occurrence: MeshSourcePresentationOccurrenceView,
        project: (Point3D) throws -> (point: CGPoint, depth: Double)?
    ) throws -> [CGPoint?] {
        var projected: [CGPoint?] = []
        projected.reserveCapacity(occurrence.positions.count)
        for position in occurrence.positions {
            guard let result = try project(
                Point3D(x: position.x, y: position.y, z: position.z)
            ), result.point.x.isFinite, result.point.y.isFinite else {
                projected.append(nil)
                continue
            }
            projected.append(result.point)
        }
        return projected
    }

    /// The first triangle of the occurrence whose projection meets the
    /// rectangle, reported as a point inside both.
    ///
    /// The scan follows emission order and stops at the first such triangle:
    /// one point of the overlap is enough to ask the frame what it draws there.
    /// That the answer is taken at this one point is what makes an occurrence
    /// occluded there a miss even when another part of it is visible inside the
    /// rectangle. The clipping rule itself is owned by
    /// `ViewportNativeCADTopologyResolver`, so the two rectangles cannot
    /// disagree about what "meets the rectangle" means.
    private static func representativePoint(
        _ occurrence: MeshSourcePresentationOccurrenceView,
        projected: [CGPoint?],
        rect: CGRect
    ) -> CGPoint? {
        for index in 0..<occurrence.triangleCount {
            let indices = occurrence.positionIndices(at: index)
            guard let first = projected[indices.first],
                  let second = projected[indices.second],
                  let third = projected[indices.third] else {
                continue
            }
            if let centroid = ViewportNativeCADTopologyResolver.clippedCentroid(
                first, second, third, in: rect
            ) {
                return centroid
            }
        }
        return nil
    }
}
