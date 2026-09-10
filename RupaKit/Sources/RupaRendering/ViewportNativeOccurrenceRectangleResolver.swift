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
/// section predicate and no culling rule of its own — `projectWithDepth`,
/// `depthInterval` and `drawnOccurrenceID` are the mounted frame's answers, and
/// the frame draws only what survived the section, only what nothing nearer
/// covers, and only the faces it retains.
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
    /// A candidate is clipped against the camera's depth interval in world
    /// space and then sampled on `ViewportRectangleSampleGrid`, the same kernel
    /// the CAD sub-shape rectangle uses, so the two rectangles cannot disagree
    /// about what meeting the rectangle means. The grid is what keeps this
    /// answer a function of the candidate's projected coverage rather than of
    /// the order or the granularity of the triangles the plan stores it as, and
    /// keeps an occurrence whose middle is covered by a nearer solid selectable
    /// by the part of it that is not. Its rule is sound and not complete: a
    /// visible sliver thinner than a grid cell can go unsampled, and nothing
    /// here reads an unsampled region as invisible.
    ///
    /// Cost per candidate: eight bounding-box projections, one projection per
    /// retained source position, at most two CPU clips per triangle — the grid
    /// scans a candidate once to anchor its cells and once more to measure the
    /// chord through the anchors that fell outside a cell's middle, both from
    /// the same projections — and at most
    /// `MeshSourcePresentationPlanLimits.maxRectangleSurfaceQueryCountPerCandidate`
    /// native surface queries — never one per triangle. Every candidate here is
    /// a plan item, so across a plan the surface queries are bounded by that
    /// same count times the plan's item ceiling, and the projections by that
    /// plan's own dimensions. The bound is a correctness contract, not an
    /// optimization: a rectangle drag re-runs this query on every pointer move.
    static func occurrenceIDs(
        intersecting rect: CGRect,
        occurrences: [MeshSourcePresentationOccurrenceView],
        depthInterval: ClosedRange<Double>,
        projectWithDepth: (Point3D) throws -> (point: CGPoint?, depth: Double),
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
        guard ViewportCameraDepthClip.canClip(against: depthInterval) else {
            throw MeshSourcePresentationRenderError(
                code: .invalidSceneItem,
                message: "The occurrence rectangle query has no camera depth interval it can clip against."
            )
        }
        let grid = ViewportRectangleSampleGrid(rect: rect)
        var admitted: Set<SceneOccurrenceID> = []
        for occurrence in occurrences {
            // An occurrence a previous query already named is drawn inside the
            // rectangle, so asking again could only repeat that answer.
            guard admitted.contains(occurrence.occurrenceID) == false else { continue }
            guard try mayMeetRectangle(
                occurrence,
                rect: rect,
                depthInterval: depthInterval,
                projectWithDepth: projectWithDepth
            ) else { continue }
            let projected = try projectedPositions(
                occurrence, projectWithDepth: projectWithDepth
            )
            let samples = try grid.polygonSamples { sink in
                for index in 0..<occurrence.triangleCount {
                    let indices = occurrence.positionIndices(at: index)
                    let drawn = ViewportCameraDepthClip.clipped(
                        [projected[indices.first], projected[indices.second], projected[indices.third]],
                        to: depthInterval
                    )
                    guard drawn.count >= 3 else { continue }
                    var screen: [CGPoint] = []
                    screen.reserveCapacity(drawn.count)
                    for vertex in drawn {
                        if let point = vertex.projected {
                            screen.append(point)
                            continue
                        }
                        // A vertex the depth clip created has no projection yet, and
                        // one the camera does not answer for is dropped rather than
                        // guessed: what remains still spans a convex subset of the
                        // drawn fragment, so the sample stays inside it.
                        guard let point = try projectWithDepth(vertex.point).point,
                              point.x.isFinite, point.y.isFinite else { continue }
                        screen.append(point)
                    }
                    guard screen.count >= 3 else { continue }
                    sink.admit(screen)
                }
            }
            for sample in samples {
                guard let drawn = try drawnOccurrenceID(sample) else { continue }
                admitted.insert(drawn)
                // Another occurrence covering this sample is still a real
                // answer for that occurrence, so it is admitted; only this
                // candidate's own confirmation ends its samples.
                if drawn == occurrence.occurrenceID { break }
            }
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
    /// answers for all eight, draws all eight, and their screen bounds miss the
    /// rectangle. A corner the camera cannot project and a corner outside the
    /// camera's depth interval both widen the search instead of losing the
    /// occurrence, because the box may still straddle a clip plane and be drawn
    /// in part. This is the same rule the CAD face runs use.
    private static func mayMeetRectangle(
        _ occurrence: MeshSourcePresentationOccurrenceView,
        rect: CGRect,
        depthInterval: ClosedRange<Double>,
        projectWithDepth: (Point3D) throws -> (point: CGPoint?, depth: Double)
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
            let camera = try projectWithDepth(point)
            guard depthInterval.contains(camera.depth) else { return true }
            guard let projected = camera.point,
                  projected.x.isFinite, projected.y.isFinite else {
                return true
            }
            minimum = CGPoint(
                x: min(minimum.x, projected.x),
                y: min(minimum.y, projected.y)
            )
            maximum = CGPoint(
                x: max(maximum.x, projected.x),
                y: max(maximum.y, projected.y)
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

    /// Each retained world position with the camera's depth for it and its
    /// projection, the latter nil where the camera does not answer for one.
    ///
    /// The plan retains one position per source vertex and indexes it per
    /// triangle, which is the shape `MeshSourcePresentationOccurrenceView`
    /// exists for: projecting here costs `positions.count` calls instead of
    /// `3 * triangleCount`. Depth is reported for every position, whether or not
    /// the camera draws it, because the depth clip interpolates the crossing of
    /// a clip plane from the depths on both sides of it.
    private static func projectedPositions(
        _ occurrence: MeshSourcePresentationOccurrenceView,
        projectWithDepth: (Point3D) throws -> (point: CGPoint?, depth: Double)
    ) throws -> [ViewportCameraDepthClip.Vertex] {
        var projected: [ViewportCameraDepthClip.Vertex] = []
        projected.reserveCapacity(occurrence.positions.count)
        for position in occurrence.positions {
            let point = Point3D(x: position.x, y: position.y, z: position.z)
            let camera = try projectWithDepth(point)
            guard let screen = camera.point, screen.x.isFinite, screen.y.isFinite else {
                projected.append(
                    ViewportCameraDepthClip.Vertex(
                        point: point, depth: camera.depth, projected: nil
                    )
                )
                continue
            }
            projected.append(
                ViewportCameraDepthClip.Vertex(
                    point: point, depth: camera.depth, projected: screen
                )
            )
        }
        return projected
    }
}
