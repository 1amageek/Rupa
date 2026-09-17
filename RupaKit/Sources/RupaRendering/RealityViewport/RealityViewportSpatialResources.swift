import AppKit
import Foundation
import Metal
import RealityKit
import RupaCoreTypes
import RupaCore
import RupaViewportScene
import SwiftCAD
import SwiftUI
import simd

/// Prepared resources only. The viewport cache owns request identity and publication.
@MainActor
final class RealityViewportSpatialResources {
    enum CameraReadinessError: Error {
        case projectionUnavailable
    }
    let root = Entity()
    let sectionedRoot = Entity()
    private let batch: RealityViewportSpatialBatch
    private var labels: [(Entity, RealityViewportSpatialBatch.Label, Entity?)] = []
    private var markers: [(Entity, RealityViewportSpatialBatch.Marker)] = []
    private var cameraLines: [(ModelEntity, LowLevelMesh, RealityViewportSpatialBatch.CameraLine, [Entity], [ModelEntity])] = []
    private var cameraPaths: [(Entity, RealityViewportSpatialBatch.CameraPath, Entity?)] = []
    private var boundsRulers: [(ViewportMeasurementRulerAxis, Entity, ModelEntity, LowLevelMesh)] = []
    private var grid: (entity: ModelEntity, mesh: LowLevelMesh)?
    private var gridLabels: [Entity] = []
    private var gridPlacement: ModelEntity?
    private var handleIndices: [ObjectIdentifier: UInt32] = [:]
    struct MarkerCollision {
        let visual: Entity
        let collider: Entity
        let index: UInt32
        let depth: RealityViewportSpatialBatch.Depth
        let attachment: RealityViewportSpatialBatch.Attachment
    }
    private var markerCollisions: [ObjectIdentifier: MarkerCollision] = [:]
    struct LabelCollision {
        let visual: Entity
        let collider: Entity
        let index: UInt32
        let depth: RealityViewportSpatialBatch.Depth
        let attachment: RealityViewportSpatialBatch.Attachment
        let rect: CGRect
        let heightPoints: Float
    }
    private var labelCollisions: [ObjectIdentifier: LabelCollision] = [:]
    private struct FillCollision {
        let entity: ModelEntity
        let index: UInt32
        let depth: RealityViewportSpatialBatch.Depth
        let attachment: RealityViewportSpatialBatch.Attachment
    }
    private var fillCollisions: [ObjectIdentifier: FillCollision] = [:]
    private(set) var preparedItemCount: Int
    private(set) var preparedPositionCount: Int
    private(set) var preparedTriangleCount: Int
    private(set) var preparedByteCount: Int
    struct LineCollision {
        let visual: Entity
        let collider: Entity
        let index: UInt32
        let depth: RealityViewportSpatialBatch.Depth
        let attachment: RealityViewportSpatialBatch.Attachment
        let tolerance: Float
        var sourceFirst: SIMD3<Float>
        var sourceLast: SIMD3<Float>
        var first: SIMD3<Float> = .zero
        var last: SIMD3<Float> = .zero
        var firstDepth: Float = 1
        var lastDepth: Float = 1
        var perspective = false
    }
    private var lineCollisions: [LineCollision] = []
    private var lineCollisionIndex: [ObjectIdentifier: Int] = [:]
    private var lineCollisionShape: ShapeResource?
    private var sphereCollision: ShapeResource?
    private struct AxisResource {
        let axis: ViewportCoordinateAxis
        let line: ModelEntity
        let mesh: LowLevelMesh
        let label: Entity
    }
    private var axes: [AxisResource] = []
    private(set) var collisionBounds: BoundingBox?
    private let surfacePositionCount: Int
    private let byteLimit: Int
    /// Bounds ruler axes the mounted frame refused to place. `nil` means
    /// the frame has not placed the rulers yet, which a camera without a
    /// ready projection restores; it never means every axis is drawn.
    private(set) var disabledRulerAxes: Set<ViewportMeasurementRulerAxis>?
    private(set) var scaleReadout: ViewportProjectedGrid.ScaleReadout?

    /// True when the prepared batch admitted native grid resources, independent
    /// of whether the grid is currently enabled for a frame.
    var hasGrid: Bool { grid != nil }

    private static func axisColor(_ axis: ViewportCoordinateAxis) -> SIMD4<Float> {
        switch axis {
        case .x: return [1, 0.32, 0.35, 1]
        case .y: return [0.22, 0.82, 0.60, 1]
        case .z: return [0.25, 0.58, 1, 1]
        }
    }

    let hasSectionedCameraGeometry: Bool

    private struct WorldGeometry: Sendable {
        let positions: [SIMD3<Float>]
        let indices: [UInt32]
        let parts: [LowLevelMesh.Part]
        let appearances: [RealityViewportSpatialBatch.Appearance]
    }

    private struct WorldGroup: Sendable {
        let attachment: RealityViewportSpatialBatch.Attachment
        let handleIndex: UInt32?
        var meshIndices: [Int]
    }

    /// Lookup coordinates only; the host owns CAD identity and frame matching.
    func handleIndex(for entity: Entity) -> UInt32? {
        var candidate: Entity? = entity
        while let current = candidate {
            if let index = handleIndices[ObjectIdentifier(current)] { return index }
            if current === root || current === sectionedRoot { return nil }
            candidate = current.parent
        }
        return nil
    }

    func handleMetadata(for entity: Entity) -> (
        index: UInt32, isMarker: Bool, depth: RealityViewportSpatialBatch.Depth,
        attachment: RealityViewportSpatialBatch.Attachment
    )? {
        if let record = fillCollisions[ObjectIdentifier(entity)] {
            return (record.index, false, record.depth, record.attachment)
        }
        if let record = labelCollisions[ObjectIdentifier(entity)] {
            return (record.index, false, record.depth, record.attachment)
        }
        if let record = markerCollisions[ObjectIdentifier(entity)] {
            return (record.index, true, record.depth, record.attachment)
        }
        if let index = lineCollisionIndex[ObjectIdentifier(entity)] {
            let record = lineCollisions[index]
            return (record.index, false, record.depth, record.attachment)
        }
        return nil
    }

    func projectedHandleDistance(
        for entity: Entity, at point: CGPoint,
        section: RealityViewportSectionHalfSpace? = nil,
        project: (SIMD3<Float>) -> CGPoint?
    ) throws -> (distance: CGFloat, position: SIMD3<Float>?)? {
        if let record = fillCollisions[ObjectIdentifier(entity)] {
            return record.entity.isEnabled ? (0, nil) : nil
        }
        if let record = labelCollisions[ObjectIdentifier(entity)] {
            guard record.visual.isEnabled, record.collider.isEnabled else { return nil }
            // The native quad owns exact rectangle acceptance. It is already
            // the closest valid point for ordering purposes.
            return (0, nil)
        }
        if let index = lineCollisionIndex[ObjectIdentifier(entity)] {
            let line = lineCollisions[index]
            guard line.visual.isEnabled, line.collider.isEnabled else { return nil }
            guard let clipped = try Self.clippedLine(first: line.first, last: line.last, section: section) else { return nil }
            guard let a = project(clipped.first), let b = project(clipped.last),
                  a.x.isFinite, a.y.isFinite, b.x.isFinite, b.y.isFinite else {
                throw RealityViewportSpatialBatch.invalid("The native line hit has no finite prepared projection.")
            }
            let depthDifference = line.lastDepth - line.firstDepth
            return Self.lineHit(at: point, first: clipped.first, last: clipped.last,
                projectedFirst: a, projectedLast: b, tolerance: line.tolerance,
                firstDepth: line.firstDepth + depthDifference * clipped.lower,
                lastDepth: line.firstDepth + depthDifference * clipped.upper, perspective: line.perspective)
        }
        guard let record = markerCollisions[ObjectIdentifier(entity)],
              record.visual.isEnabled, record.collider.isEnabled,
              let center = project(record.collider.convert(position: .zero,
                                                          to: self.root(for: record.attachment))),
              center.x.isFinite, center.y.isFinite else {
            throw RealityViewportSpatialBatch.invalid("The native marker hit has no finite prepared projection.")
        }
        // The native sphere owns acceptance. Projection only orders valid hits.
        return (hypot(center.x - point.x, center.y - point.y), nil)
    }

    static func clippedLine(first: SIMD3<Float>, last: SIMD3<Float>,
                            section: RealityViewportSectionHalfSpace?) throws
        -> (first: SIMD3<Float>, last: SIMD3<Float>, lower: Float, upper: Float)? {
        guard let section else { return (first, last, 0, 1) }
        // The half-space owns the distance and the tolerance. Shifting the
        // distance by the tolerance puts the cut at zero, which is where this
        // clip interpolates its crossing.
        let a = section.signedDistance(to: SIMD3<Double>(first)) + section.tolerance
        let b = section.signedDistance(to: SIMD3<Double>(last)) + section.tolerance
        guard a.isFinite, b.isFinite else {
            throw RealityViewportSpatialBatch.invalid("The native line section distance is not finite.")
        }
        if a < 0 && b < 0 { return nil }
        if a >= 0 && b >= 0 { return (first, last, 0, 1) }
        let t = Float(a / (a - b))
        let intersection = first + (last - first) * t
        return a < 0 ? (intersection, last, t, 1) : (first, intersection, 0, t)
    }

    static func lineHit(at point: CGPoint, first: SIMD3<Float>, last: SIMD3<Float>,
                         projectedFirst a: CGPoint, projectedLast b: CGPoint, tolerance: Float,
                         firstDepth: Float, lastDepth: Float, perspective: Bool)
        -> (distance: CGFloat, position: SIMD3<Float>?)? {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        let t = lengthSquared > 0 ? max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared)) : 0
        let distance = hypot(point.x - a.x - t * dx, point.y - a.y - t * dy)
        guard distance <= CGFloat(tolerance) else { return nil }
        // Screen interpolation is not world interpolation under perspective.
        let fraction = perspective
            ? Float(t) * firstDepth / ((1 - Float(t)) * lastDepth + Float(t) * firstDepth)
            : Float(t)
        return (distance, first + (last - first) * fraction)
    }

    /// Clips one mathematical camera-local axis against the mounted frustum.
    /// Perspective uses homogeneous screen coordinates so an infinite far
    /// endpoint is represented by its direction limit rather than a guessed
    /// large world coordinate.
    nonisolated static func projectedAxis(
        origin: SIMD3<Double>, direction: SIMD3<Double>, forward: CGAffineTransform,
        sampleDepth: Double, perspective: Bool, near: Double, far: Double,
        viewportSize: CGSize
    ) throws -> (start: CGPoint, end: CGPoint)? {
        let a = Double(forward.a)
        let b = Double(forward.b)
        let c = Double(forward.c)
        let d = Double(forward.d)
        let tx = Double(forward.tx)
        let ty = Double(forward.ty)
        guard origin.x.isFinite, origin.y.isFinite, origin.z.isFinite,
              direction.x.isFinite, direction.y.isFinite, direction.z.isFinite,
              a.isFinite, b.isFinite, c.isFinite, d.isFinite, tx.isFinite, ty.isFinite,
              sampleDepth.isFinite, near.isFinite,
              sampleDepth > 0, near > 0,
              viewportSize.width.isFinite, viewportSize.height.isFinite,
              viewportSize.width > 0, viewportSize.height > 0,
              far > near, far.isFinite || far.isInfinite else {
            throw RealityViewportSpatialBatch.invalid("The native reference-axis frame is invalid.")
        }
        guard direction.x != 0 || direction.y != 0 || direction.z != 0 else { return nil }

        struct Linear {
            let constant: Double
            let slope: Double
        }
        var lower = -Double.infinity
        var upper = Double.infinity

        func checked(_ value: Double) throws -> Double {
            guard value.isFinite else {
                throw RealityViewportSpatialBatch.invalid("The native reference-axis projection overflowed.")
            }
            return value
        }

        func clipLess(_ value: Linear, _ bound: Double) throws -> Bool {
            guard value.constant.isFinite, value.slope.isFinite, bound.isFinite else {
                throw RealityViewportSpatialBatch.invalid("The native reference-axis clip is not finite.")
            }
            if value.slope == 0 {
                return value.constant <= bound
            }
            let limit = try checked((bound - value.constant) / value.slope)
            if value.slope > 0 { upper = min(upper, limit) }
            else { lower = max(lower, limit) }
            return lower <= upper
        }
        func clipGreater(_ value: Linear, _ bound: Double) throws -> Bool {
            try clipLess(Linear(constant: try checked(-value.constant), slope: try checked(-value.slope)),
                         try checked(-bound))
        }
        func linear(_ constant: Double, _ slope: Double) -> Linear {
            Linear(constant: constant, slope: slope)
        }

        let z = linear(origin.z, direction.z)
        guard try clipLess(z, -near) else { return nil }
        if far.isFinite {
            guard try clipGreater(z, -far) else { return nil }
        }

        if perspective {
            let originXY = try checked(a * origin.x + c * origin.y)
            let directionXY = try checked(a * direction.x + c * direction.y)
            let nxConstant = try checked(-sampleDepth * originXY + tx * origin.z)
            let nxSlope = try checked(-sampleDepth * directionXY + tx * direction.z)
            let originYY = try checked(b * origin.x + d * origin.y)
            let directionYY = try checked(b * direction.x + d * direction.y)
            let nyConstant = try checked(-sampleDepth * originYY + ty * origin.z)
            let nySlope = try checked(-sampleDepth * directionYY + ty * direction.z)
            let nx = linear(
                nxConstant, nxSlope
            )
            let ny = linear(
                nyConstant, nySlope
            )
            let rightConstant = try checked(nx.constant - Double(viewportSize.width) * z.constant)
            let rightSlope = try checked(nx.slope - Double(viewportSize.width) * z.slope)
            let bottomConstant = try checked(ny.constant - Double(viewportSize.height) * z.constant)
            let bottomSlope = try checked(ny.slope - Double(viewportSize.height) * z.slope)
            guard try clipLess(nx, 0),
                  try clipGreater(Linear(constant: rightConstant, slope: rightSlope), 0),
                  try clipLess(ny, 0),
                  try clipGreater(Linear(constant: bottomConstant, slope: bottomSlope), 0) else {
                return nil
            }
        } else {
            let sx = linear(try checked(a * origin.x + c * origin.y + tx),
                            try checked(a * direction.x + c * direction.y))
            let sy = linear(try checked(b * origin.x + d * origin.y + ty),
                            try checked(b * direction.x + d * direction.y))
            guard try clipGreater(sx, 0), try clipLess(sx, Double(viewportSize.width)),
                  try clipGreater(sy, 0), try clipLess(sy, Double(viewportSize.height)) else { return nil }
        }
        guard lower <= upper else { return nil }

        func finiteProjection(_ parameter: Double) throws -> CGPoint? {
            guard parameter.isFinite else {
                throw RealityViewportSpatialBatch.invalid("The native reference-axis endpoint is not finite.")
            }
            let px = try checked(origin.x + direction.x * parameter)
            let py = try checked(origin.y + direction.y * parameter)
            let pz = try checked(origin.z + direction.z * parameter)
            guard pz < 0 else { return nil }
            if perspective {
                let scale = try checked(-pz / sampleDepth)
                guard scale > 0 else { return nil }
                let point = CGPoint(x: CGFloat(try checked(px / scale)),
                                    y: CGFloat(try checked(py / scale))).applying(forward)
                guard point.x.isFinite, point.y.isFinite else {
                    throw RealityViewportSpatialBatch.invalid("The native reference-axis endpoint is not finite.")
                }
                return point
            }
            let point = CGPoint(x: CGFloat(px), y: CGFloat(py)).applying(forward)
            guard point.x.isFinite, point.y.isFinite else {
                throw RealityViewportSpatialBatch.invalid("The native reference-axis endpoint is not finite.")
            }
            return point
        }

        func endpoint(_ parameter: Double) throws -> CGPoint? {
            guard parameter.isInfinite else { return try finiteProjection(parameter) }
            if perspective {
                let nx = try checked(-sampleDepth * (a * direction.x + c * direction.y) + tx * direction.z)
                let ny = try checked(-sampleDepth * (b * direction.x + d * direction.y) + ty * direction.z)
                if direction.z != 0 {
                    let x = try checked(nx / direction.z)
                    let y = try checked(ny / direction.z)
                    let point = CGPoint(x: CGFloat(x), y: CGFloat(y))
                    guard point.x.isFinite, point.y.isFinite else {
                        throw RealityViewportSpatialBatch.invalid("The native reference-axis vanishing point is not finite.")
                    }
                    return point
                }
                guard nx == 0, ny == 0 else { return nil }
                return try finiteProjection(0)
            }
            let sx = try checked(a * direction.x + c * direction.y)
            let sy = try checked(b * direction.x + d * direction.y)
            guard sx == 0, sy == 0 else { return nil }
            return try finiteProjection(0)
        }
        guard let start = try endpoint(lower), let end = try endpoint(upper),
              start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite else {
            return nil
        }
        let endpointBounds = CGRect(origin: .zero, size: viewportSize).insetBy(dx: -1, dy: -1)
        guard endpointBounds.contains(start), endpointBounds.contains(end) else { return nil }
        guard hypot(end.x - start.x, end.y - start.y) > 0 else { return nil }
        return (start, end)
    }

    /// Records the frame-local provenance of a drawn entity.
    ///
    /// The index means nothing outside the frame that built it, and
    /// `handleIndex(for:)` is its only reader: it walks up from a descendant
    /// until it finds a registered ancestor or reaches a root. Input
    /// reachability is a separate matter. `spatialHandleHits` resolves a hit
    /// through `handleMetadata(for:)`, which reads the collision tables the
    /// marker, label, line and camera-path footprints populate, so an entity
    /// registered here is still unreachable without one. Passing nil leaves the
    /// entity out of this table, which is what an entity with no prepared
    /// record wants.
    private func register(_ entity: Entity, handleIndex: UInt32?) {
        if let handleIndex { handleIndices[ObjectIdentifier(entity)] = handleIndex }
    }

    private func admitFill(positions: Int, indices: Int, tolerance: Float, generated: Bool) throws {
        guard positions > 0, indices > 0, indices.isMultiple(of: 3) else {
            throw RealityViewportSpatialBatch.invalid("Native fill has no complete triangles.")
        }
        let edges = tolerance > 0 ? indices : 0
        func add(_ value: inout Int, _ count: Int, limit: Int) throws {
            let sum = value.addingReportingOverflow(count)
            guard !sum.overflow, count >= 0, sum.partialValue <= limit else {
                throw RealityViewportSpatialBatch.exhausted()
            }
            value = sum.partialValue
        }
        func charge(_ count: Int, _ stride: Int) throws {
            let size = count.multipliedReportingOverflow(by: stride)
            guard !size.overflow else { throw RealityViewportSpatialBatch.exhausted() }
            try add(&preparedByteCount, size.partialValue, limit: byteLimit)
        }
        try add(&preparedItemCount, edges, limit: batch.limits.maxItemCount)
        try add(&preparedPositionCount, positions, limit: batch.limits.maxPositionCount)
        // Source mesh triangles were admitted by the batch; native generated
        // paths and the reversed collision-only mesh each add one triangle set.
        try add(&preparedTriangleCount, indices / 3, limit: batch.limits.maxTriangleCount)
        try charge(1, MemoryLayout<FillCollision>.stride + MemoryLayout<ObjectIdentifier>.stride
            + MemoryLayout<CollisionComponent>.stride + MemoryLayout<[ShapeResource]>.stride
            + MemoryLayout<ShapeResource>.stride + MemoryLayout<MeshDescriptor>.stride
            + MemoryLayout<MeshResource>.stride)
        try charge(positions, MemoryLayout<SIMD3<Float>>.stride)
        try charge(indices, (generated ? 1 : 2) * MemoryLayout<UInt32>.stride)
        try charge(edges, MemoryLayout<Entity>.stride + MemoryLayout<LineCollision>.stride
            + MemoryLayout<CollisionComponent>.stride + MemoryLayout<[ShapeResource]>.stride
            + MemoryLayout<ShapeResource>.stride + 2 * MemoryLayout<ObjectIdentifier>.stride
            + MemoryLayout<Int>.stride + MemoryLayout<UInt32>.stride)
        lineCollisions.reserveCapacity(lineCollisions.count + edges)
        lineCollisionIndex.reserveCapacity(lineCollisionIndex.count + edges)
    }

    private func addFillCollision(_ entity: ModelEntity, mesh: MeshResource, index: UInt32,
                                  depth: RealityViewportSpatialBatch.Depth,
                                  attachment: RealityViewportSpatialBatch.Attachment) async throws {
        let shape = try await ShapeResource.generateStaticMesh(from: mesh)
        try Task.checkCancellation()
        entity.components.set(CollisionComponent(shapes: [shape],
            filter: .init(group: RealityViewport.spatialCollisionGroup, mask: .all)))
        fillCollisions[ObjectIdentifier(entity)] = .init(entity: entity, index: index,
            depth: depth, attachment: attachment)
    }

    static func pathParts(_ contents: MeshResource.Contents,
        _ body: (MeshResource.Part, simd_float4x4) throws -> Void) throws {
        guard !contents.instances.isEmpty else {
            throw RealityViewportSpatialBatch.invalid("Native path has no placed geometry instance.")
        }
        for instance in contents.instances {
            guard let model = contents.models.first(where: { $0.id == instance.model }), !model.parts.isEmpty else {
                throw RealityViewportSpatialBatch.invalid("Native path instance references absent model geometry.")
            }
            let transform = instance.transform
            guard (0..<4).allSatisfy({ column in (0..<4).allSatisfy { transform[column][$0].isFinite } }),
                  transform.columns.0.w == 0, transform.columns.1.w == 0,
                  transform.columns.2.w == 0, transform.columns.3.w == 1 else {
                throw RealityViewportSpatialBatch.invalid("Native path instance has an invalid affine transform.")
            }
            for part in model.parts { try body(part, transform) }
        }
    }

    private func addTriangleBoundary(_ entity: Entity, positions: [SIMD3<Float>], a: UInt32, b: UInt32, c: UInt32,
        transform: simd_float4x4, index: UInt32, depth: RealityViewportSpatialBatch.Depth,
        attachment: RealityViewportSpatialBatch.Attachment, tolerance: Float) throws {
        func point(_ index: UInt32) throws -> SIMD3<Float> {
            guard Int(index) < positions.count else {
                throw RealityViewportSpatialBatch.invalid("Native path triangle references an absent position.")
            }
            let point = transform * SIMD4(positions[Int(index)], 1)
            guard point.x.isFinite, point.y.isFinite, point.z.isFinite else {
                throw RealityViewportSpatialBatch.invalid("Native fill exceeds finite coordinate precision.")
            }
            return SIMD3(point.x, point.y, point.z)
        }
        let first = try point(a), second = try point(b), third = try point(c)
        _ = try addLineCollision(visual: entity, first: first, last: second, index: index,
            depth: depth, attachment: attachment, tolerance: tolerance)
        _ = try addLineCollision(visual: entity, first: second, last: third, index: index,
            depth: depth, attachment: attachment, tolerance: tolerance)
        _ = try addLineCollision(visual: entity, first: third, last: first, index: index,
            depth: depth, attachment: attachment, tolerance: tolerance)
    }

    private func addLineCollision(visual: Entity, first: SIMD3<Float>, last: SIMD3<Float>,
                                  index: UInt32, depth: RealityViewportSpatialBatch.Depth,
                                  attachment: RealityViewportSpatialBatch.Attachment, tolerance: Float) throws -> Entity {
        if lineCollisionShape == nil { lineCollisionShape = .generateBox(size: SIMD3(repeating: 1)) }
        guard let lineCollisionShape else { throw RealityViewportSpatialBatch.invalid("Native line collision is unavailable.") }
        let collider = Entity()
        collider.components.set(CollisionComponent(shapes: [lineCollisionShape],
            filter: .init(group: RealityViewport.spatialCollisionGroup, mask: .all)))
        collider.isEnabled = false
        // Source endpoints are attachment-root coordinates, including planar
        // paths whose visual Entity carries an independent plane transform.
        root(for: attachment).addChild(collider)
        handleIndices[ObjectIdentifier(collider)] = index
        lineCollisionIndex[ObjectIdentifier(collider)] = lineCollisions.count
        lineCollisions.append(.init(visual: visual, collider: collider,
            index: index, depth: depth, attachment: attachment, tolerance: tolerance,
            sourceFirst: first, sourceLast: last))
        return collider
    }

    private func updateCollisionBounds(projection: CameraProjection) throws {
        var bounds = BoundingBox()
        var hasBounds = false
        for record in fillCollisions.values where record.entity.isEnabled {
            bounds.formUnion(record.entity.visualBounds(relativeTo: root(for: record.attachment)))
            hasBounds = true
        }
        for record in markerCollisions.values where record.visual.isEnabled && record.collider.isEnabled {
            // Ancestor roots may be withheld until this camera update succeeds.
            let radius = record.collider.parent === record.visual
                ? record.visual.scale.x * record.collider.scale.x / 2
                : record.collider.scale.x / 2
            guard radius.isFinite, radius > 0 else {
                throw RealityViewportSpatialBatch.invalid("Native marker tolerance exceeds transform precision.")
            }
            let collisionRoot = self.root(for: record.attachment)
            let center = record.collider.convert(position: .zero, to: collisionRoot)
            guard center.x.isFinite, center.y.isFinite, center.z.isFinite else {
                throw RealityViewportSpatialBatch.invalid("Native primitive collision center exceeds transform precision.")
            }
            bounds.formUnion(BoundingBox(min: center - SIMD3(repeating: radius),
                                         max: center + SIMD3(repeating: radius)))
            hasBounds = true
        }
        for record in labelCollisions.values where record.visual.isEnabled && record.collider.isEnabled {
            let height = CGFloat(record.heightPoints)
            guard height.isFinite, height > 0 else {
                throw RealityViewportSpatialBatch.invalid("Native label collision scale is invalid.")
            }
            let collisionRoot = self.root(for: record.attachment)
            let corner0 = record.collider.convert(position: [-0.5, -0.5, 0], to: collisionRoot)
            let corner1 = record.collider.convert(position: [0.5, -0.5, 0], to: collisionRoot)
            let corner2 = record.collider.convert(position: [0.5, 0.5, 0], to: collisionRoot)
            let corner3 = record.collider.convert(position: [-0.5, 0.5, 0], to: collisionRoot)
            guard corner0.x.isFinite, corner0.y.isFinite, corner0.z.isFinite,
                  corner1.x.isFinite, corner1.y.isFinite, corner1.z.isFinite,
                  corner2.x.isFinite, corner2.y.isFinite, corner2.z.isFinite,
                  corner3.x.isFinite, corner3.y.isFinite, corner3.z.isFinite else {
                throw RealityViewportSpatialBatch.invalid("Native label collision bounds exceed transform precision.")
            }
            var labelBounds = BoundingBox(min: corner0, max: corner0)
            labelBounds.formUnion(BoundingBox(min: corner1, max: corner1))
            labelBounds.formUnion(BoundingBox(min: corner2, max: corner2))
            labelBounds.formUnion(BoundingBox(min: corner3, max: corner3))
            bounds.formUnion(labelBounds)
            hasBounds = true
        }
        for index in lineCollisions.indices {
            var line = lineCollisions[index]
            line.collider.isEnabled = false
            guard line.visual.isEnabled else { continue }
            let firstDepth = -projection.local(line.sourceFirst).z
            let lastDepth = -projection.local(line.sourceLast).z
            let difference = lastDepth - firstDepth
            guard firstDepth.isFinite, lastDepth.isFinite, difference.isFinite else {
                throw RealityViewportSpatialBatch.invalid("Native line depth exceeds transform precision.")
            }
            var lower: Float = 0, upper: Float = 1
            if difference == 0 {
                guard firstDepth >= projection.near, firstDepth <= projection.far else { continue }
            } else {
                let nearT = (projection.near - firstDepth) / difference
                let farT = (projection.far - firstDepth) / difference
                lower = max(0, min(nearT, farT))
                upper = min(1, max(nearT, farT))
                guard lower <= upper else { continue }
            }
            let delta = line.sourceLast - line.sourceFirst
            line.first = line.sourceFirst + delta * lower
            line.last = line.sourceFirst + delta * upper
            line.firstDepth = -projection.local(line.first).z
            line.lastDepth = -projection.local(line.last).z
            line.perspective = projection.perspective
            let nativeLength = simd_length(line.last - line.first)
            let depthScale = max(projection.depthScale(projection.local(line.first)),
                                 projection.depthScale(projection.local(line.last)))
            // One point minimum is only a conservative acquisition volume for
            // zero-tolerance lines; the projected filter still enforces zero.
            let radius = max(line.tolerance, 1) * depthScale / Float(hypot(projection.forward.c, projection.forward.d))
            guard nativeLength.isFinite, radius.isFinite, radius > 0,
                  (nativeLength + 2 * radius).isFinite else {
                throw RealityViewportSpatialBatch.invalid("Native line collision exceeds transform precision.")
            }
            line.collider.position = line.first / 2 + line.last / 2
            line.collider.orientation = nativeLength > 0
                ? simd_quatf(from: [1, 0, 0], to: (line.last - line.first) / nativeLength)
                : simd_quatf(angle: 0, axis: [1, 0, 0])
            line.collider.scale = [nativeLength + 2 * radius, 2 * radius, 2 * radius]
            line.collider.isEnabled = true
            let padding = SIMD3<Float>(repeating: radius * 2)
            let minimum = simd_min(line.first, line.last) - padding
            let maximum = simd_max(line.first, line.last) + padding
            guard minimum.x.isFinite, minimum.y.isFinite, minimum.z.isFinite,
                  maximum.x.isFinite, maximum.y.isFinite, maximum.z.isFinite else {
                throw RealityViewportSpatialBatch.invalid("Native line collision bounds exceed transform precision.")
            }
            bounds.formUnion(BoundingBox(min: minimum, max: maximum))
            hasBounds = true
            lineCollisions[index] = line
        }
        collisionBounds = hasBounds ? bounds : nil
    }

    private struct CameraProjection {
        let worldFromCamera: simd_float4x4
        let cameraFromWorld: simd_float4x4
        let forward: CGAffineTransform
        let inverseOffset: CGAffineTransform
        let sampleDepth: Float
        let perspective: Bool
        let annotationDepth: Float
        let near: Float
        let far: Float

        func local(_ point: SIMD3<Float>) -> SIMD3<Float> {
            let value = cameraFromWorld * SIMD4(point, 1)
            return SIMD3(value.x, value.y, value.z)
        }

        func depthScale(_ local: SIMD3<Float>) -> Float { perspective ? -local.z / sampleDepth : 1 }

        func project(_ point: SIMD3<Float>) -> CGPoint? {
            let point = local(point)
            guard point.x.isFinite, point.y.isFinite, point.z.isFinite, point.z < 0 else { return nil }
            let scale = depthScale(point)
            let result = CGPoint(x: CGFloat(point.x / scale), y: CGFloat(point.y / scale)).applying(forward)
            return result.x.isFinite && result.y.isFinite ? result : nil
        }

        func point(at screen: CGPoint, depth: Float) -> SIMD3<Float> {
            let offset = CGPoint(x: screen.x - forward.tx, y: screen.y - forward.ty).applying(inverseOffset)
            let scale = perspective ? depth / sampleDepth : 1
            let value = worldFromCamera * SIMD4(Float(offset.x) * scale, Float(offset.y) * scale, -depth, 1)
            return SIMD3(value.x, value.y, value.z)
        }

        func unproject(_ screen: CGPoint, onto plane: ViewportCanvasPlane, origin: Point3D) -> Point3D? {
            guard let normal = plane.normal else { return nil }
            let sample = point(at: screen, depth: sampleDepth)
            let start = perspective ? SIMD3(worldFromCamera.columns.3.x, worldFromCamera.columns.3.y, worldFromCamera.columns.3.z)
                : point(at: screen, depth: 0)
            let direction = SIMD3<Double>(sample - start)
            let worldStart = SIMD3<Double>(start) + SIMD3(origin.x, origin.y, origin.z)
            let n = SIMD3(normal.x, normal.y, normal.z)
            let denominator = simd_dot(direction, n)
            guard denominator.isFinite, abs(denominator) > 1e-12 else { return nil }
            let distance = -simd_dot(worldStart, n) / denominator
            guard distance.isFinite, distance >= 0 else { return nil }
            let result = worldStart + direction * distance
            guard result.x.isFinite, result.y.isFinite, result.z.isFinite else { return nil }
            return Point3D(x: result.x, y: result.y, z: result.z)
        }
    }

    private init(batch: RealityViewportSpatialBatch, surfacePlan: MeshSourcePresentationRenderPlan?) {
        self.batch = batch
        preparedItemCount = batch.itemCount + (surfacePlan?.itemCount ?? 0)
        preparedPositionCount = batch.positionCount + (surfacePlan?.positionCount ?? 0)
        preparedTriangleCount = batch.triangleCount + (surfacePlan?.triangleCount ?? 0)
        preparedByteCount = batch.admittedByteCount
        surfacePositionCount = surfacePlan?.positionCount ?? 0
        byteLimit = min(batch.limits.maxRetainedByteCount, surfacePlan?.nativePreparationByteLimit ?? batch.limits.maxRetainedByteCount)
        hasSectionedCameraGeometry = batch.labels.contains { $0.attachment == .sectionedGeometry }
            || batch.markers.contains { $0.attachment == .sectionedGeometry }
            || batch.cameraLines.contains { $0.attachment == .sectionedGeometry }
            || batch.cameraPaths.contains { $0.attachment == .sectionedGeometry }
        scaleReadout = nil
    }

    static func prepare(batch: RealityViewportSpatialBatch,
                        surfacePlan: MeshSourcePresentationRenderPlan? = nil) async throws -> RealityViewportSpatialResources {
        try Task.checkCancellation()
        try batch.validate(surfacePlan: surfacePlan)
        let result = RealityViewportSpatialResources(batch: batch, surfacePlan: surfacePlan)
        result.lineCollisions.reserveCapacity(batch.lineCollisionCount)
        result.lineCollisionIndex.reserveCapacity(batch.lineCollisionCount)
        if batch.includesGrid {
            let capacity = ViewportProjectedGrid.maximumGridLineCount * 2
            let mesh = try LowLevelMesh(descriptor: descriptor(vertices: capacity, indices: capacity))
            // The SDK owns the fully initialized fixed-capacity grid buffers.
            // These bounded borrows never escape and updates retain their owner.
            mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
                let vertices = bytes.bindMemory(to: SIMD3<Float>.self)
                for index in 0..<capacity { vertices[index] = .zero }
            }
            mesh.withUnsafeMutableIndices { bytes in
                let indices = bytes.bindMemory(to: UInt32.self)
                for index in 0..<capacity { indices[index] = UInt32(index) }
            }
            mesh.parts.replaceAll((0..<3).map {
                .init(indexCount: 0, topology: .line, materialIndex: $0,
                      bounds: .init(min: .zero, max: .zero))
            })
            let resource = try RealityViewport.nativeResource(from: mesh)
            try Task.checkCancellation()
            let entity = ModelEntity(mesh: resource, materials: [
                material([1, 1, 1, 0.055], depth: .scene),
                material([1, 1, 1, 0.135], depth: .scene),
                material([1, 1, 1, 0.22], depth: .scene)
            ])
            entity.isEnabled = false
            result.grid = (entity, mesh)
            result.root.addChild(entity)
        }
        if let placement = batch.gridPlacement {
            let mesh = try LowLevelMesh(descriptor: descriptor(vertices: 4, indices: 8))
            // Fixed unit rectangle; the native entity transform owns its world size.
            mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
                let vertices = bytes.bindMemory(to: SIMD3<Float>.self)
                vertices[0] = [-0.5, -0.5, 0]; vertices[1] = [0.5, -0.5, 0]
                vertices[2] = [0.5, 0.5, 0]; vertices[3] = [-0.5, 0.5, 0]
            }
            mesh.withUnsafeMutableIndices { bytes in
                let indices = bytes.bindMemory(to: UInt32.self)
                for edge in 0..<4 {
                    indices[edge * 2] = UInt32(edge)
                    indices[edge * 2 + 1] = UInt32((edge + 1) % 4)
                }
            }
            mesh.parts.replaceAll([.init(indexCount: 8, topology: .line, materialIndex: 0,
                                         bounds: .init(min: [-0.5, -0.5, 0], max: [0.5, 0.5, 0]))])
            let resource = try RealityViewport.nativeResource(from: mesh)
            try Task.checkCancellation()
            let entity = ModelEntity(mesh: resource, materials: [material(placement.color, depth: .annotation)])
            entity.isEnabled = false
            result.gridPlacement = entity
            result.root.addChild(entity)
        }
        if batch.includesAxes {
            let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
            for axis in ViewportCoordinateAxis.allCases {
                let mesh = try LowLevelMesh(descriptor: descriptor(vertices: 2, indices: 2))
                mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
                    let vertices = bytes.bindMemory(to: SIMD3<Float>.self)
                    vertices[0] = .zero
                    vertices[1] = .zero
                }
                mesh.withUnsafeMutableIndices { bytes in
                    let indices = bytes.bindMemory(to: UInt32.self)
                    indices[0] = 0
                    indices[1] = 1
                }
                mesh.parts.replaceAll([.init(indexCount: 2, topology: .line, materialIndex: 0,
                                             bounds: .init(min: .zero, max: .zero))])
                let resource = try RealityViewport.nativeResource(from: mesh)
                try Task.checkCancellation()
                let line = ModelEntity(mesh: resource, materials: [material(axisColor(axis), depth: .annotation)])
                line.name = "Reference Axis \(axis.label)"
                line.isEnabled = false

                let label = Entity()
                label.name = "Reference Axis \(axis.label) Label"
                var text = TextComponent()
                let attributed = NSAttributedString(string: axis.label, attributes: [
                    .font: font,
                    .foregroundColor: NSColor.white
                ])
                text.text = AttributedString(attributed)
                text.size = CGSize(width: 14, height: 14)
                label.components.set(text)
                label.components.set(BillboardComponent())
                label.isEnabled = false

                result.axes.append(.init(axis: axis, line: line, mesh: mesh, label: label))
                result.root.addChild(line)
                result.root.addChild(label)
            }
        }
        var pathResources: [CGPath: MeshResource] = [:]
        var textResources: [String: MeshResource] = [:]
        pathResources.reserveCapacity(batch.paths.count + batch.cameraPaths.count)
        let rulerLabelCount = ViewportMeasurementRulerAxis.allCases.reduce(0) {
            $0 + (batch.boundsRulers?.input.labels[$1] == nil ? 0 : 1)
        }
        textResources.reserveCapacity(batch.labels.count + rulerLabelCount)
        var groups: [WorldGroup] = []
        // ponytail: linear grouping is bounded by the admitted 640 descriptors;
        // use a keyed index only if preparation profiling makes this a bottleneck.
        for (index, source) in batch.meshes.enumerated() {
            try Task.checkCancellation()
            if let group = groups.firstIndex(where: {
                source.handleIndex == nil && $0.attachment == source.attachment && $0.handleIndex == nil
            }) {
                groups[group].meshIndices.append(index)
            } else {
                groups.append(.init(attachment: source.attachment, handleIndex: source.handleIndex,
                                    meshIndices: [index]))
            }
        }
        for group in groups {
            let geometry = try await worldGeometry(batch, meshIndices: group.meshIndices)
            try Task.checkCancellation()
            let mesh = try LowLevelMesh(descriptor: descriptor(vertices: geometry.positions.count, indices: geometry.indices.count))
            // All conversion and bounds work ran off MainActor. The SDK-owned
            // buffers receive two admitted bulk copies through nonescaping borrows.
            mesh.withUnsafeMutableBytes(bufferIndex: 0) { destination in
                geometry.positions.withUnsafeBytes { destination.copyMemory(from: $0) }
            }
            mesh.withUnsafeMutableIndices { destination in
                geometry.indices.withUnsafeBytes { destination.copyMemory(from: $0) }
            }
            mesh.parts.replaceAll(geometry.parts)
            let resource = try RealityViewport.nativeResource(from: mesh)
            try Task.checkCancellation()
            let entity = ModelEntity(mesh: resource, materials: geometry.appearances.map { material($0.color, depth: $0.depth) })
            result.register(entity, handleIndex: group.handleIndex)
            result.root(for: group.attachment).addChild(entity)
            if let index = group.handleIndex {
                let source = batch.meshes[group.meshIndices[0]]
                if source.topology == .lines, let tolerance = source.hitTolerancePoints {
                    for offset in stride(from: 0, to: geometry.indices.count, by: 2) {
                        _ = try result.addLineCollision(visual: entity,
                            first: geometry.positions[Int(geometry.indices[offset])],
                            last: geometry.positions[Int(geometry.indices[offset + 1])],
                            index: index, depth: source.depth, attachment: source.attachment, tolerance: tolerance)
                    }
                } else if source.topology == .triangles, let tolerance = source.hitTolerancePoints {
                    try result.admitFill(positions: geometry.positions.count, indices: geometry.indices.count,
                        tolerance: tolerance, generated: false)
                    var descriptor = MeshDescriptor()
                    descriptor.positions = MeshBuffers.Positions(geometry.positions)
                    let indices = try await Self.doubleWoundIndices(geometry.indices)
                    descriptor.primitives = .triangles(indices)
                    let collisionMesh = try await MeshResource(from: [descriptor])
                    try await result.addFillCollision(entity, mesh: collisionMesh, index: index,
                        depth: source.depth, attachment: source.attachment)
                    if tolerance > 0 {
                        for offset in stride(from: 0, to: geometry.indices.count, by: 3) {
                            try result.addTriangleBoundary(entity, positions: geometry.positions,
                                a: geometry.indices[offset], b: geometry.indices[offset + 1], c: geometry.indices[offset + 2],
                                transform: matrix_identity_float4x4, index: index, depth: source.depth,
                                attachment: source.attachment, tolerance: tolerance)
                        }
                    }
                }
            }
        }
        for path in batch.paths {
            try Task.checkCancellation()
            let resource = try await pathResource(planarPath(path), cache: &pathResources,
                additionalPositionLimit: batch.limits.maxPositionCount - result.preparedPositionCount,
                additionalByteLimit: result.byteLimit - result.preparedByteCount)
            try Task.checkCancellation()
            let entity = ModelEntity(mesh: resource, materials: [material(path.color, depth: path.depth)])
            entity.position = try RealityViewportSpatialBatch.nativePoint(path.origin, relativeTo: batch.renderOrigin)
            orient(entity, on: path)
            result.register(entity, handleIndex: path.handleIndex)
            result.root(for: path.attachment).addChild(entity)
            if let index = path.handleIndex, let tolerance = path.hitTolerancePoints {
                let contents = resource.contents
                var positionCount = 0, indexCount = 0
                try Self.pathParts(contents) { part, _ in
                    guard let indices = part.triangleIndices, indices.count.isMultiple(of: 3) else {
                        throw RealityViewportSpatialBatch.invalid("Native path has invalid triangle topology.")
                    }
                    let p = positionCount.addingReportingOverflow(part.positions.count)
                    let i = indexCount.addingReportingOverflow(indices.count)
                    guard !p.overflow, !i.overflow else { throw RealityViewportSpatialBatch.exhausted() }
                    positionCount = p.partialValue; indexCount = i.partialValue
                }
                try result.admitFill(positions: positionCount, indices: indexCount, tolerance: tolerance, generated: true)
                try await result.addFillCollision(entity, mesh: resource, index: index,
                    depth: path.depth, attachment: path.attachment)
                if tolerance > 0 {
                    try Self.pathParts(contents) { part, transform in
                        guard let indices = part.triangleIndices else {
                            throw RealityViewportSpatialBatch.invalid("Native path lost its triangle topology.")
                        }
                        let positions = part.positions.elements
                        let worldTransform = entity.transformMatrix(relativeTo: result.root(for: path.attachment)) * transform
                        try indices.forEach { a, b, c in
                            try result.addTriangleBoundary(entity, positions: positions, a: a, b: b, c: c,
                                transform: worldTransform, index: index, depth: path.depth,
                                attachment: path.attachment, tolerance: tolerance)
                        }
                    }
                }
            }
        }
        var quadCollision: ShapeResource?
        for label in batch.labels {
            try Task.checkCancellation()
            let resource = try await textResource(label.text, cache: &textResources)
            try Task.checkCancellation()
            let glyph = ModelEntity(mesh: resource, materials: [material(label.color, depth: label.depth)])
            let bounds = resource.bounds
            switch label.alignment {
            case .leading: glyph.position.x = -bounds.min.x
            case .center: glyph.position.x = -bounds.center.x
            case .trailing: glyph.position.x = -bounds.max.x
            }
            let entity = Entity()
            entity.addChild(glyph)
            entity.components.set(BillboardComponent())
            entity.isEnabled = false
            var collider: Entity?
            if let index = label.handleIndex, let rect = label.hitRectPoints {
                if quadCollision == nil { quadCollision = try await Self.unitQuadCollision() }
                guard let quadCollision else {
                    throw RealityViewportSpatialBatch.invalid("Native label collision is unavailable.")
                }
                let height = CGFloat(label.heightPoints)
                let hit = Entity()
                hit.position = SIMD3(Float(rect.midX / height), Float(rect.midY / height), 0)
                hit.scale = SIMD3(Float(rect.width / height), Float(rect.height / height), 1)
                hit.components.set(CollisionComponent(shapes: [quadCollision],
                    filter: .init(group: RealityViewport.spatialCollisionGroup, mask: .all)))
                hit.isEnabled = false
                // The hit plane is a camera-facing sibling. Keeping it outside
                // the Billboard visual avoids asynchronous inherited rotation
                // and lets updateCamera publish one exact native orientation.
                result.handleIndices[ObjectIdentifier(hit)] = index
                result.labelCollisions[ObjectIdentifier(hit)] = .init(
                    visual: entity, collider: hit, index: index, depth: label.depth,
                    attachment: label.attachment, rect: rect, heightPoints: label.heightPoints)
                collider = hit
                result.root(for: label.attachment).addChild(hit)
            }
            result.labels.append((entity, label, collider))
            result.register(entity, handleIndex: label.handleIndex)
            result.root(for: label.attachment).addChild(entity)
        }
        var sphere: MeshResource?
        var box: MeshResource?
        var cone: MeshResource?
        for marker in batch.markers {
            try Task.checkCancellation()
            let mesh: MeshResource
            switch marker.shape {
            case .sphere:
                if sphere == nil { sphere = .generateSphere(radius: 0.5) }
                guard let sphere else { throw RealityViewportSpatialBatch.invalid("Native marker resource is unavailable.") }
                mesh = sphere
            case .box:
                if box == nil { box = .generateBox(size: 1) }
                guard let box else { throw RealityViewportSpatialBatch.invalid("Native marker resource is unavailable.") }
                mesh = box
            case .cone:
                if cone == nil { cone = .generateCone(height: 1, radius: 0.35) }
                guard let cone else { throw RealityViewportSpatialBatch.invalid("Native arrow resource is unavailable.") }
                mesh = cone
            }
            let entity = ModelEntity(mesh: mesh, materials: [material(marker.color, depth: marker.depth)])
            let nativeAnchor = try RealityViewportSpatialBatch.nativePoint(marker.anchor, relativeTo: batch.renderOrigin)
            entity.position = nativeAnchor
            if case .cone = marker.shape {
                guard case .directed(let toward, _, _) = marker.offset else {
                    throw RealityViewportSpatialBatch.invalid("An arrowhead requires an explicit axis direction.")
                }
                let end = try RealityViewportSpatialBatch.nativePoint(toward, relativeTo: batch.renderOrigin)
                let direction = end - nativeAnchor
                guard simd_length_squared(direction) > 0 else {
                    throw RealityViewportSpatialBatch.invalid("An arrowhead axis is degenerate.")
                }
                entity.orientation = simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(direction))
            }
            entity.isEnabled = false
            result.markers.append((entity, marker))
            result.register(entity, handleIndex: marker.handleIndex)
            result.root(for: marker.attachment).addChild(entity)
            // A marker carries a footprint only where the producer asked for
            // one. State markers that repeat an identity while its drag is in
            // flight omit the tolerance deliberately: the grabbable handle is
            // drawn separately, so these stay decoration instead of adding a
            // second footprint for the same record.
            if let index = marker.handleIndex, let tolerance = marker.hitTolerancePoints, tolerance > 0 {
                if result.sphereCollision == nil { result.sphereCollision = .generateSphere(radius: 0.5) }
                guard let sphereCollision = result.sphereCollision else {
                    throw RealityViewportSpatialBatch.invalid("Native marker collision is unavailable.")
                }
                // A shared unit sphere avoids the native generation floor.
                // Its child transform separates input radius from visible size.
                let collider = Entity()
                let ratio = 2 * tolerance / marker.diameterPoints
                guard ratio.isFinite, ratio > 0 else {
                    throw RealityViewportSpatialBatch.invalid("Native marker tolerance exceeds transform precision.")
                }
                collider.scale = SIMD3(repeating: ratio)
                collider.components.set(CollisionComponent(shapes: [sphereCollision],
                    filter: .init(group: RealityViewport.spatialCollisionGroup, mask: .all)))
                entity.addChild(collider)
                result.handleIndices[ObjectIdentifier(collider)] = index
                result.markerCollisions[ObjectIdentifier(collider)] = .init(
                    visual: entity, collider: collider, index: index, depth: marker.depth,
                    attachment: marker.attachment)
            }
        }
        for line in batch.cameraLines {
            try Task.checkCancellation()
            let count = line.points.count
            let mesh = try LowLevelMesh(descriptor: descriptor(vertices: count, indices: (count - 1) * 2))
            // RealityKit owns these fixed-capacity buffers. Every vertex and index
            // is initialized before conversion; scoped pointers never escape.
            mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
                let vertices = bytes.bindMemory(to: SIMD3<Float>.self)
                for index in 0..<count { vertices[index] = .zero }
            }
            mesh.withUnsafeMutableIndices { bytes in
                let indices = bytes.bindMemory(to: UInt32.self)
                for index in 0..<(count - 1) {
                    indices[2 * index] = UInt32(index)
                    indices[2 * index + 1] = UInt32(index + 1)
                }
            }
            mesh.parts.replaceAll([.init(indexCount: (count - 1) * 2, topology: .line, bounds: .init(min: .zero, max: .zero))])
            let resource = try RealityViewport.nativeResource(from: mesh)
            try Task.checkCancellation()
            let entity = ModelEntity(mesh: resource, materials: [material(line.color, depth: line.depth)])
            entity.isEnabled = false
            var proxies: [Entity] = []
            if let index = line.handleIndex, let tolerance = line.hitTolerancePoints {
                proxies.reserveCapacity(count - 1)
                for _ in 0..<(count - 1) {
                    proxies.append(try result.addLineCollision(visual: entity, first: .zero, last: .zero,
                        index: index, depth: line.depth, attachment: line.attachment, tolerance: tolerance))
                }
            }
            var strokes: [ModelEntity] = []
            if line.widthPoints != nil {
                if box == nil { box = .generateBox(size: 1) }
                guard let box else { throw RealityViewportSpatialBatch.invalid("Native line resource is unavailable.") }
                for _ in 1..<count {
                    let stroke = ModelEntity(mesh: box, materials: [material(line.color, depth: line.depth)])
                    entity.addChild(stroke)
                    strokes.append(stroke)
                }
            }
            result.cameraLines.append((entity, mesh, line, proxies, strokes))
            result.register(entity, handleIndex: line.handleIndex)
            result.root(for: line.attachment).addChild(entity)
        }
        for path in batch.cameraPaths {
            try Task.checkCancellation()
            let resource = try await pathResource(path.path.applying(.init(scaleX: 1, y: -1)), cache: &pathResources,
                additionalPositionLimit: batch.limits.maxPositionCount - result.preparedPositionCount,
                additionalByteLimit: result.byteLimit - result.preparedByteCount)
            try Task.checkCancellation()
            let entity = ModelEntity(mesh: resource, materials: [material(path.color, depth: path.depth)])
            entity.components.set(BillboardComponent())
            entity.isEnabled = false
            var collider: Entity?
            if let index = path.handleIndex, let tolerance = path.hitTolerancePoints, tolerance > 0 {
                if result.sphereCollision == nil { result.sphereCollision = .generateSphere(radius: 0.5) }
                guard let sphereCollision = result.sphereCollision else {
                    throw RealityViewportSpatialBatch.invalid("Native camera-path collision is unavailable.")
                }
                let hit = Entity()
                let radiusScale = 2 * tolerance
                guard radiusScale.isFinite, radiusScale > 0 else {
                    throw RealityViewportSpatialBatch.invalid("Native camera-path tolerance exceeds transform precision.")
                }
                hit.scale = SIMD3(repeating: radiusScale)
                hit.components.set(CollisionComponent(shapes: [sphereCollision],
                    filter: .init(group: RealityViewport.spatialCollisionGroup, mask: .all)))
                hit.isEnabled = false
                result.handleIndices[ObjectIdentifier(hit)] = index
                result.markerCollisions[ObjectIdentifier(hit)] = .init(
                    visual: entity, collider: hit, index: index, depth: path.depth,
                    attachment: path.attachment)
                collider = hit
                result.root(for: path.attachment).addChild(hit)
            }
            result.cameraPaths.append((entity, path, collider))
            result.register(entity, handleIndex: path.handleIndex)
            result.root(for: path.attachment).addChild(entity)
        }
        if let group = batch.boundsRulers {
            for axis in ViewportMeasurementRulerAxis.allCases {
                guard let text = group.input.labels[axis] else { continue }
                let resource = try await textResource(text, cache: &textResources)
                let glyph = ModelEntity(mesh: resource, materials: [material(group.color, depth: .annotation)])
                glyph.position.x = -resource.bounds.center.x
                glyph.position.y = -resource.bounds.center.y
                let label = Entity()
                label.addChild(glyph)
                label.components.set(BillboardComponent())
                label.isEnabled = false
                let mesh = try LowLevelMesh(descriptor: descriptor(vertices: 6, indices: 6))
                // Fixed native capacity, fully initialized before publication.
                // The SDK owns both buffers; these borrows do not escape.
                mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
                    let vertices = bytes.bindMemory(to: SIMD3<Float>.self)
                    for index in 0..<6 { vertices[index] = .zero }
                }
                mesh.withUnsafeMutableIndices { bytes in
                    let indices = bytes.bindMemory(to: UInt32.self)
                    for index in 0..<6 { indices[index] = UInt32(index) }
                }
                mesh.parts.replaceAll([.init(indexCount: 6, topology: .line, bounds: .init(min: .zero, max: .zero))])
                let lineResource = try RealityViewport.nativeResource(from: mesh)
                try Task.checkCancellation()
                let line = ModelEntity(mesh: lineResource, materials: [material(group.color, depth: .annotation)])
                line.isEnabled = false
                result.root.addChild(label)
                result.root.addChild(line)
                result.boundsRulers.append((axis, label, line, mesh))
            }
        }
        try Task.checkCancellation()
        return result
    }

    /// Places a zero-thickness label hit quad in the current native camera
    /// plane. The authored rectangle is in screen points (y-down) relative to
    /// the placed anchor, so the collider cannot inherit the visual Billboard.
    private func updateLabelCollision(
        _ record: LabelCollision, rect: CGRect, anchor: SIMD3<Float>, projection: CameraProjection
    ) throws -> Bool {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite,
              rect.width > 0, rect.height > 0,
              rect.minX.isFinite, rect.minY.isFinite,
              rect.maxX.isFinite, rect.maxY.isFinite else {
            throw RealityViewportSpatialBatch.invalid("Native label interaction rectangle is invalid.")
        }
        guard let anchorScreen = projection.project(anchor) else { return false }
        let local = projection.local(anchor)
        let depth = -local.z
        guard depth.isFinite, depth >= projection.near, depth <= projection.far else { return false }

        let centerScreen = CGPoint(x: anchorScreen.x + rect.midX, y: anchorScreen.y + rect.midY)
        let leftScreen = CGPoint(x: centerScreen.x - rect.width / 2, y: centerScreen.y)
        let rightScreen = CGPoint(x: centerScreen.x + rect.width / 2, y: centerScreen.y)
        let topScreen = CGPoint(x: centerScreen.x, y: centerScreen.y - rect.height / 2)
        let bottomScreen = CGPoint(x: centerScreen.x, y: centerScreen.y + rect.height / 2)
        let center = projection.point(at: centerScreen, depth: depth)
        let rightPoint = projection.point(at: rightScreen, depth: depth)
        let leftPoint = projection.point(at: leftScreen, depth: depth)
        let topPoint = projection.point(at: topScreen, depth: depth)
        let bottomPoint = projection.point(at: bottomScreen, depth: depth)
        let horizontal = rightPoint - leftPoint
        let vertical = bottomPoint - topPoint
        let width = simd_length(horizontal)
        let height = simd_length(vertical)
        guard center.x.isFinite, center.y.isFinite, center.z.isFinite,
              width.isFinite, width > 0, height.isFinite, height > 0 else {
            return false
        }
        let xAxis = horizontal / width
        let verticalProjection = vertical - xAxis * simd_dot(vertical, xAxis)
        let verticalLength = simd_length(verticalProjection)
        guard verticalLength.isFinite, verticalLength > 0 else { return false }
        let yAxis = verticalProjection / verticalLength
        let zAxis = simd_normalize(simd_cross(xAxis, yAxis))
        guard zAxis.x.isFinite, zAxis.y.isFinite, zAxis.z.isFinite else { return false }
        let orientation = simd_quatf(simd_float4x4(columns: (
            SIMD4(xAxis, 0), SIMD4(yAxis, 0), SIMD4(zAxis, 0), SIMD4(0, 0, 0, 1)
        )))
        record.collider.position = center
        record.collider.orientation = orientation
        record.collider.scale = [width, height, 1]
        return true
    }

    /// Native world geometry remains untouched. Only the already admitted
    /// camera-relative annotations change, synchronously with the mounted camera.
    @discardableResult
    func updateCamera(camera: Entity, content: RealityViewCameraContent,
                      safeRect: CGRect = .zero, excludedRects: [CGRect] = [],
                      gridRuler: RulerConfiguration? = nil, gridBasis: ViewportProjectionBasis = .isometric,
                      gridSize: CGSize = .zero, gridSpacing: ViewportGridVisualSpacingMode = .adaptive,
                      objectPreviews: [String: Transform3D] = [:]) throws -> MeshSourcePresentationRenderError? {
        guard grid != nil || !axes.isEmpty || !cameraPaths.isEmpty || !labels.isEmpty || !markers.isEmpty || !cameraLines.isEmpty || !lineCollisions.isEmpty || !fillCollisions.isEmpty || !boundsRulers.isEmpty else { return nil }
        guard let projection = cameraProjection(camera: camera, content: content) else {
            for (entity, _, collider) in cameraPaths {
                entity.isEnabled = false
                collider?.isEnabled = false
            }
            for (entity, _, collider) in labels {
                entity.isEnabled = false
                collider?.isEnabled = false
            }
            for (entity, _) in markers { entity.isEnabled = false }
            for (entity, _, _, _, _) in cameraLines { entity.isEnabled = false }
            for (_, label, line, _) in boundsRulers {
                label.isEnabled = false; line.isEnabled = false
            }
            disabledRulerAxes = nil
            disableAxes()
            hideGrid()
            throw CameraReadinessError.projectionUnavailable
        }
        try updateAxes(projection: projection, viewportSize: gridSize,
                       safeRect: safeRect, excludedRects: excludedRects)
        for (entity, path, collider) in cameraPaths {
            entity.isEnabled = false
            collider?.isEnabled = false
            guard let placement = placement(anchor: path.anchor, offset: path.offset, projection: projection) else {
                continue
            }
            entity.position = placement.position
            entity.scale = SIMD3(repeating: placement.metersPerPoint)
            if let collider, let tolerance = path.hitTolerancePoints {
                let scale = 2 * tolerance * placement.metersPerPoint
                guard scale.isFinite, scale > 0 else {
                    throw RealityViewportSpatialBatch.invalid("Native camera-path tolerance exceeds transform precision.")
                }
                // Camera-path hit geometry is a sibling, so it receives the
                // complete native point scale rather than inheriting Billboard
                // or visual transforms.
                collider.position = placement.position
                collider.scale = SIMD3(repeating: scale)
                collider.isEnabled = true
            }
            entity.isEnabled = true
        }
        for (entity, label, collider) in labels {
            entity.isEnabled = false
            collider?.isEnabled = false
            guard let placement = placement(anchor: label.anchor, offset: label.offset, projection: projection) else {
                continue
            }
            entity.position = placement.position
            entity.scale = SIMD3(repeating: placement.metersPerPoint * label.heightPoints)
            if let collider {
                guard let rect = label.hitRectPoints,
                      let record = labelCollisions[ObjectIdentifier(collider)] else {
                    throw RealityViewportSpatialBatch.invalid("Native label collision lost its prepared rectangle.")
                }
                guard try updateLabelCollision(record, rect: rect, anchor: placement.position, projection: projection) else {
                    continue
                }
                collider.isEnabled = true
            }
            entity.isEnabled = true
        }
        for (entity, marker) in markers {
            let point = try RealityViewportSpatialBatch.CameraPoint(anchor: marker.anchor, offset: marker.offset)
                .applying(marker.objectPreviewOccurrenceID.flatMap { objectPreviews[$0] })
            guard let placement = placement(anchor: point.anchor, offset: point.offset, projection: projection) else {
                entity.isEnabled = false
                continue
            }
            // The collider is a child of this entity and both the collision
            // bounds union and the projected handle distance read live
            // transforms, so moving the parent needs no separate bookkeeping.
            entity.position = placement.position
            entity.scale = SIMD3(repeating: placement.metersPerPoint * marker.diameterPoints)
            entity.isEnabled = true
        }
        for (entity, mesh, line, proxies, strokes) in cameraLines {
            let mutation = line.objectPreviewOccurrenceID.flatMap { objectPreviews[$0] }
            var valid = true
            var missingProvenance = false
            var bounds = BoundingBox()
            var updateResult: Result<Void, Error> = .success(())
            mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
              updateResult = Result {
                let vertices = bytes.bindMemory(to: SIMD3<Float>.self)
                for (index, point) in line.points.enumerated() {
                    let point = try point.applying(mutation)
                    guard let placement = placement(anchor: point.anchor, offset: point.offset, projection: projection,
                                                    allowsBehindCamera: true) else {
                        valid = false
                        vertices[index] = .zero
                        continue
                    }
                    vertices[index] = placement.position
                    bounds.formUnion(BoundingBox(min: placement.position, max: placement.position))
                }
                if valid {
                    for (offset, stroke) in strokes.enumerated() {
                        let first = vertices[offset], last = vertices[offset + 1]
                        let delta = last - first
                        let length = simd_length(delta)
                        let point = try line.points[offset].applying(mutation)
                        guard let width = line.widthPoints,
                              let placement = placement(anchor: point.anchor,
                                offset: point.offset, projection: projection, allowsBehindCamera: true) else {
                            valid = false
                            break
                        }
                        let thickness = width * placement.metersPerPoint
                        stroke.isEnabled = length > 0 && thickness.isFinite && thickness > 0
                        if stroke.isEnabled {
                            stroke.position = (first + last) / 2
                            stroke.orientation = simd_quatf(from: SIMD3<Float>(1, 0, 0), to: delta / length)
                            stroke.scale = [length, thickness, thickness]
                        }
                    }
                    for (offset, proxy) in proxies.enumerated() {
                        guard let index = lineCollisionIndex[ObjectIdentifier(proxy)] else {
                            missingProvenance = true
                            break
                        }
                        lineCollisions[index].sourceFirst = vertices[offset]
                        lineCollisions[index].sourceLast = vertices[offset + 1]
                    }
                }
              }
            }
            try updateResult.get()
            if missingProvenance {
                throw RealityViewportSpatialBatch.invalid("The native camera line lost its prepared collision provenance.")
            }
            if valid {
                // Mutate one native part; do not allocate a replacement mesh or array.
                var part = mesh.parts[0]
                part.bounds = bounds
                mesh.parts[0] = part
            }
            entity.isEnabled = valid
        }
        try updateBoundsRulers(projection: projection, safeRect: safeRect, excludedRects: excludedRects)
        try updateCollisionBounds(projection: projection)
        do {
            if let gridRuler {
                guard grid != nil else { throw RealityViewportSpatialBatch.invalid("The mounted frame did not admit a grid.") }
                let remaining = batch.limits.maxItemCount - preparedItemCount
                guard excludedRects.count <= remaining else { throw RealityViewportSpatialBatch.exhausted() }
                let plane = ViewportCanvasPlane.displayed(for: gridBasis)
                var scaleAnchor: Point3D?
                for screen in [CGPoint(x: gridSize.width / 2, y: gridSize.height / 2), .zero,
                               CGPoint(x: gridSize.width, y: 0), CGPoint(x: 0, y: gridSize.height),
                               CGPoint(x: gridSize.width, y: gridSize.height)] {
                    if let point = projection.unproject(screen, onto: plane, origin: batch.renderOrigin) {
                        scaleAnchor = point
                        break
                    }
                }
                guard let scaleAnchor else {
                    hideGrid()
                    return nil
                }
                let nativeAnchor = try RealityViewportSpatialBatch.nativePoint(scaleAnchor, relativeTo: batch.renderOrigin)
                let projectedScale = hypot(projection.forward.c, projection.forward.d)
                    / CGFloat(projection.depthScale(projection.local(nativeAnchor)))
                let frame = try ViewportProjectedGrid.makeNativeFrame(.init(
                    ruler: gridRuler, basis: gridBasis, viewportSize: gridSize,
                    projectedScale: projectedScale,
                    project: { point in
                        let relative = SIMD3(Float(point.x - self.batch.renderOrigin.x),
                                             Float(point.y - self.batch.renderOrigin.y), Float(point.z - self.batch.renderOrigin.z))
                        return projection.project(relative)
                    },
                    unproject: { projection.unproject($0, onto: $1, origin: self.batch.renderOrigin) },
                    chromeExclusionRects: excludedRects, visualSpacingMode: gridSpacing
                ))
                if let frame {
                    try updateGrid(frame, projection: projection)
                } else {
                    hideGrid()
                }
            } else {
                hideGrid()
            }
        } catch let error as MeshSourcePresentationRenderError {
            return error
        } catch {
            return RealityViewportSpatialBatch.invalid("Native grid frame failed: \(error)")
        }
        return nil
    }

    private func hideGrid() {
        scaleReadout = nil
        grid?.entity.isEnabled = false
        gridPlacement?.isEnabled = false
        for label in gridLabels {
            label.components.remove(TextComponent.self)
            label.isEnabled = false
        }
    }

    private func disableAxes() {
        for axis in axes {
            axis.line.isEnabled = false
            axis.label.isEnabled = false
            axis.mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
                let vertices = bytes.bindMemory(to: SIMD3<Float>.self)
                vertices[0] = .zero
                vertices[1] = .zero
            }
            var part = axis.mesh.parts[0]
            part.bounds = .init(min: .zero, max: .zero)
            axis.mesh.parts[0] = part
        }
    }

    private func updateAxes(projection: CameraProjection, viewportSize: CGSize,
                            safeRect: CGRect, excludedRects: [CGRect]) throws {
        guard !axes.isEmpty else { return }
        guard viewportSize.width.isFinite, viewportSize.height.isFinite,
              viewportSize.width > 0, viewportSize.height > 0 else {
            throw RealityViewportSpatialBatch.invalid("The native reference-axis viewport is invalid.")
        }
        // Use the same checked CAD-to-native boundary as surface geometry.
        // Mixing a Double origin with the already rounded native camera moves
        // a view-aligned axis off its true native origin in perspective.
        let nativeOrigin = try RealityViewportSpatialBatch.nativePoint(.origin, relativeTo: batch.renderOrigin)
        let originLocal = SIMD3<Double>(projection.local(nativeOrigin))
        guard originLocal.x.isFinite, originLocal.y.isFinite, originLocal.z.isFinite else {
            throw RealityViewportSpatialBatch.invalid("The native reference-axis origin is not finite.")
        }
        let cameraFromWorld = projection.cameraFromWorld
        func direction(_ axis: ViewportCoordinateAxis) -> SIMD3<Double> {
            let column: SIMD4<Float>
            switch axis {
            case .x: column = cameraFromWorld.columns.0
            case .y: column = cameraFromWorld.columns.1
            case .z: column = cameraFromWorld.columns.2
            }
            return SIMD3<Double>(Double(column.x), Double(column.y), Double(column.z))
        }
        let annotationDepth = projection.annotationDepth
        let unitsPerPoint = projection.depthScale([0, 0, -annotationDepth])
            / Float(hypot(projection.forward.c, projection.forward.d))
        guard annotationDepth.isFinite, annotationDepth > 0,
              unitsPerPoint.isFinite, unitsPerPoint > 0 else {
            throw RealityViewportSpatialBatch.invalid("The native reference-axis annotation plane is invalid.")
        }
        typealias Prepared = (start: SIMD3<Float>, end: SIMD3<Float>, label: SIMD3<Float>?, scale: Float)
        func prepare(_ axis: ViewportCoordinateAxis) throws -> Prepared? {
            guard let screen = try Self.projectedAxis(
                origin: originLocal, direction: direction(axis), forward: projection.forward,
                sampleDepth: Double(projection.sampleDepth), perspective: projection.perspective,
                near: Double(projection.near), far: Double(projection.far), viewportSize: viewportSize
            ) else { return nil }
            // Reference lines ignore scene depth. Use the native calibration
            // plane, not the near plane where world-space Float cancellation
            // can visibly shorten the projected segment.
            var start = projection.point(at: screen.start, depth: projection.sampleDepth)
            var end = projection.point(at: screen.end, depth: projection.sampleDepth)
            guard start.x.isFinite, start.y.isFinite, start.z.isFinite,
                  end.x.isFinite, end.y.isFinite, end.z.isFinite else {
                throw RealityViewportSpatialBatch.invalid("The native reference-axis endpoint is not finite.")
            }
            let pointResolution = CGFloat(Float.ulpOfOne) * max(viewportSize.width, viewportSize.height)
            let screenLength = hypot(screen.end.x - screen.start.x, screen.end.y - screen.start.y)
            guard screenLength > pointResolution else { return nil }
            let unit = CGPoint(x: (screen.end.x - screen.start.x) / screenLength,
                               y: (screen.end.y - screen.start.y) / screenLength)
            func shift(_ point: CGPoint, from target: CGPoint) -> CGFloat {
                (point.x - target.x) * unit.x + (point.y - target.y) * unit.y
            }
            // Correct measured inward quantization, not a guessed world extent.
            // The final check rejects a frame if native Float cannot represent it.
            func corrected(_ point: SIMD3<Float>, target: CGPoint, outward: CGFloat) throws -> SIMD3<Float> {
                guard let projected = projection.project(point) else {
                    throw RealityViewportSpatialBatch.invalid("The native reference-axis endpoint is not projectable.")
                }
                let error = shift(projected, from: target) * outward
                guard error < 0 else { return point }
                let amount = (-error + pointResolution) * outward
                return projection.point(at: CGPoint(x: target.x + unit.x * amount, y: target.y + unit.y * amount),
                                        depth: projection.sampleDepth)
            }
            start = try corrected(start, target: screen.start, outward: -1)
            end = try corrected(end, target: screen.end, outward: 1)
            start = Self.roundedOutward(start, awayFrom: end)
            end = Self.roundedOutward(end, awayFrom: start)
            guard let projectedStart = projection.project(start), let projectedEnd = projection.project(end) else {
                throw RealityViewportSpatialBatch.invalid("The native reference-axis endpoint is not projectable.")
            }
            guard hypot(projectedEnd.x - projectedStart.x, projectedEnd.y - projectedStart.y) > pointResolution,
                  shift(projectedStart, from: screen.start) <= pointResolution,
                  shift(projectedEnd, from: screen.end) >= -pointResolution else {
                throw RealityViewportSpatialBatch.invalid("The native reference-axis segment lost its clipped interval.")
            }
            let labelPoint = Self.axisLabelPoint(start: screen.start, end: screen.end,
                                                 viewportSize: viewportSize, safeRect: safeRect,
                                                 excludedRects: excludedRects)
            let label: SIMD3<Float>?
            if let labelPoint {
                label = projection.point(at: labelPoint, depth: annotationDepth)
            } else {
                label = nil
            }
            if let label {
                guard label.x.isFinite, label.y.isFinite, label.z.isFinite else {
                    throw RealityViewportSpatialBatch.invalid("The native reference-axis label endpoint is not finite.")
                }
            }
            let scale = unitsPerPoint * 72 / 0.0254
            guard scale.isFinite, scale > 0 else {
                throw RealityViewportSpatialBatch.invalid("The native reference-axis label scale is invalid.")
            }
            return (start: start, end: end, label: label, scale: scale)
        }
        let x = try prepare(.x)
        let y = try prepare(.y)
        let z = try prepare(.z)
        func prepared(_ axis: ViewportCoordinateAxis) -> Prepared? {
            switch axis {
            case .x: return x
            case .y: return y
            case .z: return z
            }
        }
        for axisResource in axes {
            guard let value = prepared(axisResource.axis) else {
                axisResource.line.isEnabled = false
                axisResource.label.isEnabled = false
                axisResource.mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
                    let vertices = bytes.bindMemory(to: SIMD3<Float>.self)
                    vertices[0] = .zero
                    vertices[1] = .zero
                }
                var part = axisResource.mesh.parts[0]
                part.bounds = .init(min: .zero, max: .zero)
                axisResource.mesh.parts[0] = part
                continue
            }
            axisResource.mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
                let vertices = bytes.bindMemory(to: SIMD3<Float>.self)
                vertices[0] = value.start
                vertices[1] = value.end
            }
            var part = axisResource.mesh.parts[0]
            part.bounds = .init(min: simd_min(value.start, value.end), max: simd_max(value.start, value.end))
            axisResource.mesh.parts[0] = part
            axisResource.line.isEnabled = true
            if let labelPosition = value.label {
                axisResource.label.position = labelPosition
                axisResource.label.orientation = simd_quatf(projection.worldFromCamera)
                axisResource.label.scale = SIMD3(repeating: value.scale)
                axisResource.label.isEnabled = true
            } else {
                axisResource.label.isEnabled = false
            }
        }
    }

    private static func roundedOutward(_ point: SIMD3<Float>, awayFrom other: SIMD3<Float>) -> SIMD3<Float> {
        var result = point
        if other.x > point.x { result.x = point.x.nextDown }
        else if other.x < point.x { result.x = point.x.nextUp }
        if other.y > point.y { result.y = point.y.nextDown }
        else if other.y < point.y { result.y = point.y.nextUp }
        if other.z > point.z { result.z = point.z.nextDown }
        else if other.z < point.z { result.z = point.z.nextUp }
        return result
    }

    private static func axisLabelPoint(start: CGPoint, end: CGPoint, viewportSize: CGSize,
                                       safeRect: CGRect, excludedRects: [CGRect]) -> CGPoint? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length.isFinite, length > 0 else { return nil }
        let direction = CGPoint(x: dx / length, y: dy / length)
        let base = CGPoint(x: end.x - direction.x * 11, y: end.y - direction.y * 11)
        let viewport = CGRect(origin: .zero, size: viewportSize)
        let safe = (safeRect.isEmpty ? viewport : safeRect).intersection(viewport)
        guard !safe.isNull, !safe.isEmpty else { return nil }
        let inset = min(4, min(safe.width, safe.height) / 2)
        let allowed = safe.insetBy(dx: inset, dy: inset)
        for index in 0..<5 {
            let candidate: CGPoint
            switch index {
            case 0:
                candidate = base
            case 1:
                candidate = CGPoint(x: end.x - direction.x * 18, y: end.y - direction.y * 18)
            case 2:
                candidate = CGPoint(x: end.x + direction.x * 8, y: end.y + direction.y * 8)
            case 3:
                candidate = CGPoint(x: end.x - direction.y * 11, y: end.y + direction.x * 11)
            default:
                candidate = CGPoint(x: end.x + direction.y * 11, y: end.y - direction.x * 11)
            }
            let clamped = CGPoint(x: min(max(candidate.x, allowed.minX), allowed.maxX),
                                  y: min(max(candidate.y, allowed.minY), allowed.maxY))
            let labelBounds = CGRect(x: clamped.x - 7, y: clamped.y - 7, width: 14, height: 14)
            guard excludedRects.allSatisfy({ !$0.intersects(labelBounds) }) else { continue }
            return clamped
        }
        return nil
    }

    private func updateGrid(_ frame: ViewportProjectedGrid.NativeFrame, projection: CameraProjection) throws {
        guard let grid, frame.worldLines.count <= ViewportProjectedGrid.maximumGridLineCount else {
            throw RealityViewportSpatialBatch.exhausted()
        }
        let placementTransform = try batch.gridPlacement?.transform(
            minorStepMeters: frame.minorStepMeters, renderOrigin: batch.renderOrigin
        )
        let slotCount = max(gridLabels.count, frame.screenLabels.count)
        guard slotCount <= batch.limits.maxItemCount - preparedItemCount else {
            throw RealityViewportSpatialBatch.exhausted()
        }
        var byteCount = preparedByteCount
        var positionCount = preparedPositionCount
        func charge(_ count: Int, _ stride: Int) throws {
            let size = count.multipliedReportingOverflow(by: stride)
            let sum = byteCount.addingReportingOverflow(size.partialValue)
            guard !size.overflow, !sum.overflow, sum.partialValue <= byteLimit else {
                throw RealityViewportSpatialBatch.exhausted()
            }
            byteCount = sum.partialValue
        }
        try charge(slotCount, MemoryLayout<Entity>.stride + MemoryLayout<TextComponent>.stride)
        try charge(frame.worldLines.count, MemoryLayout<ViewportProjectedGrid.NativeFrame.WorldLine>.stride + 2 * MemoryLayout<SIMD3<Float>>.stride)
        try charge(frame.screenLabels.count, MemoryLayout<ViewportProjectedGrid.NativeFrame.ScreenLabel>.stride)
        try charge(frame.screenLabels.count, MemoryLayout<(TextComponent, SIMD3<Float>)>.stride)
        for label in frame.screenLabels {
            guard !label.text.isEmpty, label.position.x.isFinite, label.position.y.isFinite else {
                throw RealityViewportSpatialBatch.invalid("Grid label has invalid text or placement.")
            }
            try charge(label.text.utf8.count, 4)
            let count = positionCount.addingReportingOverflow(label.text.unicodeScalars.count)
            guard !count.overflow, count.partialValue <= batch.limits.maxPositionCount else {
                throw RealityViewportSpatialBatch.exhausted()
            }
            positionCount = count.partialValue
        }
        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(frame.worldLines.count * 2)
        var parts: [LowLevelMesh.Part] = []
        for style in 0..<3 {
            let start = vertices.count
            var bounds = BoundingBox()
            for line in frame.worldLines where (line.isOrigin ? 2 : (line.isMajor ? 1 : 0)) == style {
                let start = try RealityViewportSpatialBatch.nativePoint(line.start, relativeTo: batch.renderOrigin)
                let end = try RealityViewportSpatialBatch.nativePoint(line.end, relativeTo: batch.renderOrigin)
                bounds.formUnion(.init(min: simd_min(start, end), max: simd_max(start, end)))
                vertices.append(start)
                vertices.append(end)
            }
            parts.append(.init(indexOffset: start * MemoryLayout<UInt32>.stride,
                               indexCount: vertices.count - start, topology: .line, materialIndex: style,
                               bounds: vertices.count == start ? .init(min: .zero, max: .zero) : bounds))
        }
        let unitsPerPoint = projection.depthScale([0, 0, -projection.annotationDepth])
            / Float(hypot(projection.forward.c, projection.forward.d))
        guard unitsPerPoint.isFinite, unitsPerPoint > 0 else {
            throw RealityViewportSpatialBatch.invalid("Grid text has no finite native point scale.")
        }
        let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        var text: [(TextComponent, SIMD3<Float>)] = []
        text.reserveCapacity(frame.screenLabels.count)
        for label in frame.screenLabels {
            let attributed = NSAttributedString(string: label.text, attributes: [
                .font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.42)
            ])
            let size = attributed.size()
            guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
                throw RealityViewportSpatialBatch.invalid("Native grid text has invalid measured bounds.")
            }
            var component = TextComponent()
            component.size = CGSize(width: ceil(size.width) + 2, height: ceil(size.height) + 2)
            component.text = AttributedString(attributed)
            let point = projection.point(at: label.position, depth: projection.annotationDepth)
            guard point.x.isFinite, point.y.isFinite, point.z.isFinite else {
                throw RealityViewportSpatialBatch.invalid("Native grid label position exceeds precision.")
            }
            text.append((component, point))
        }
        // Every fallible conversion and aggregate admission finished above. The
        // following synchronous publication changes the complete grid together.
        while gridLabels.count < slotCount {
            let label = Entity()
            label.isEnabled = false
            root.addChild(label)
            gridLabels.append(label)
        }
        grid.mesh.withUnsafeMutableBytes(bufferIndex: 0) { destination in
            vertices.withUnsafeBytes { source in destination.copyMemory(from: source) }
        }
        for index in 0..<3 { grid.mesh.parts[index] = parts[index] }
        grid.entity.isEnabled = !vertices.isEmpty
        if let placementTransform {
            gridPlacement?.transform = Transform(matrix: placementTransform)
            gridPlacement?.isEnabled = true
        }
        for (index, label) in gridLabels.enumerated() {
            guard text.indices.contains(index) else {
                label.components.remove(TextComponent.self)
                label.isEnabled = false
                continue
            }
            let (component, position) = text[index]
            let existing = label.components[TextComponent.self]
            if existing?.text != component.text || existing?.size != component.size {
                label.components.set(component)
            }
            label.position = position
            label.orientation = simd_quatf(projection.worldFromCamera)
            // TextComponent's native plane uses typographic points (1/72 inch).
            label.scale = .init(repeating: unitsPerPoint * 72 / 0.0254)
            label.isEnabled = true
        }
        scaleReadout = frame.scaleReadout
    }

    private func updateBoundsRulers(projection: CameraProjection,
                                    safeRect: CGRect, excludedRects: [CGRect]) throws {
        guard let group = batch.boundsRulers else { return }
        // Every exit from here answers about all three axes, so a refusal is
        // never published as the absence of an answer.
        var disabled = Set(ViewportMeasurementRulerAxis.allCases)
        defer { disabledRulerAxes = disabled }
        for (_, label, line, _) in boundsRulers {
            label.isEnabled = false
            line.isEnabled = false
        }
        guard excludedRects.count <= batch.limits.maxItemCount - preparedItemCount else {
            throw MeshSourcePresentationRenderError(code: .resourceExhausted,
                message: "Current chrome exclusions exceed bounds ruler placement admission.")
        }
        // A point the camera cannot project is a placement refusal the layout
        // resolves. A point that leaves native coordinate precision is a scene
        // failure instead, so it is carried out of the non-throwing closure and
        // rethrown rather than reported as an axis the layout declined. Batch
        // admission converts the same bounds corners, so no admitted group
        // reaches this failure; nothing in this file may assume that, because
        // the refusal it would otherwise publish is read as measured text.
        var sceneFailure: (any Error)?
        let layout = ViewportMeasurementBoundsRulerLayout().placement(
            for: group.input.bounds, labels: group.input.labels,
            project: { point in
                do {
                    let native = try RealityViewportSpatialBatch.nativePoint(point, relativeTo: self.batch.renderOrigin)
                    return projection.project(native)
                } catch {
                    if sceneFailure == nil { sceneFailure = error }
                    return nil
                }
            }, safeRect: safeRect, excludedRects: excludedRects)
        if let sceneFailure { throw sceneFailure }
        disabled = layout.disabledAxes
        for ruler in layout.rulers {
            guard let (_, label, line, mesh) = boundsRulers.first(where: { $0.0 == ruler.axis }) else {
                throw RealityViewportSpatialBatch.invalid("Bounds ruler placement references an unprepared axis.")
            }
            let start = ruler.worldExtensionStart
            let end = ruler.worldExtensionEnd
            // Screen center is placed at the actual edge midpoint's depth.
            let midpoint = Point3D(x: start.x * 0.5 + end.x * 0.5,
                                   y: start.y * 0.5 + end.y * 0.5,
                                   z: start.z * 0.5 + end.z * 0.5)
            let nativeMidpoint = try RealityViewportSpatialBatch.nativePoint(midpoint, relativeTo: batch.renderOrigin)
            guard let projected = projection.project(nativeMidpoint),
                  let labelPlacement = placement(anchor: midpoint,
                    offset: .fixed(CGPoint(x: ruler.labelRect.midX - projected.x, y: ruler.labelRect.midY - projected.y)),
                    projection: projection) else {
                disabled.insert(ruler.axis)
                continue
            }
            var valid = true
            var bounds = BoundingBox()
            mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
                let vertices = bytes.bindMemory(to: SIMD3<Float>.self)
                for index in 0..<6 {
                    let anchor = index < 2 || index == 4 ? start : end
                    let offset = index == 0 || index == 2 ? CGPoint.zero : ruler.dimensionOffset
                    guard let value = placement(anchor: anchor, offset: .fixed(offset), projection: projection) else {
                        vertices[index] = .zero
                        valid = false
                        continue
                    }
                    vertices[index] = value.position
                    bounds.formUnion(.init(min: value.position, max: value.position))
                }
            }
            guard valid else { disabled.insert(ruler.axis); continue }
            var part = mesh.parts[0]
            part.bounds = bounds
            mesh.parts[0] = part
            label.position = labelPlacement.position
            label.scale = SIMD3(repeating: labelPlacement.metersPerPoint * group.heightPoints)
            label.isEnabled = true
            line.isEnabled = true
        }
    }

    /// Typographic points that `MeshResource(extruding:)` maps onto one mesh
    /// unit. Pinned by `boundsRulerLabelsDrawVisibleGlyphs`.
    private static let textPointsPerMeshUnit: CGFloat = 72

    private static func textResource(_ value: String, cache: inout [String: MeshResource]) async throws -> MeshResource {
        try Task.checkCancellation()
        if let existing = cache[value] { return existing }
        var text = AttributedString(value)
        // Shape extrusion emits one mesh unit per `textPointsPerMeshUnit`
        // typographic points, so sizing the font at that value makes one em
        // exactly one unit. Callers scale the glyph by their requested point
        // height, which therefore names the font size the label is drawn at.
        text.font = NSFont.monospacedSystemFont(ofSize: Self.textPointsPerMeshUnit, weight: .medium)
        var extrusion = MeshResource.ShapeExtrusionOptions()
        extrusion.extrusionMethod = .linear(depth: 0)
        let resource = try await MeshResource(extruding: text, extrusionOptions: extrusion)
        try Task.checkCancellation()
        cache[value] = resource
        return resource
    }

    private func root(for attachment: RealityViewportSpatialBatch.Attachment) -> Entity {
        attachment == .world ? root : sectionedRoot
    }

    @concurrent
    private nonisolated static func worldGeometry(
        _ batch: RealityViewportSpatialBatch, meshIndices: [Int]
    ) async throws -> WorldGeometry {
        let vertexCount = meshIndices.reduce(0) { $0 + batch.meshes[$1].positions.count }
        let indexCount = meshIndices.reduce(0) { $0 + batch.meshes[$1].indices.count }
        let meshCount = meshIndices.count
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var appearances: [RealityViewportSpatialBatch.Appearance] = []
        var parts: [LowLevelMesh.Part] = []
        positions.reserveCapacity(vertexCount)
        indices.reserveCapacity(indexCount)
        appearances.reserveCapacity(meshCount)
        parts.reserveCapacity(meshCount)
        var vertexOffset = 0
        var indexOffset = 0
        for sourceIndex in meshIndices {
            let geometry = batch.meshes[sourceIndex]
            try Task.checkCancellation()
            let materialIndex: Int
            let appearance = RealityViewportSpatialBatch.Appearance(color: geometry.color, depth: geometry.depth)
            if let existing = appearances.firstIndex(of: appearance) {
                materialIndex = existing
            } else {
                materialIndex = appearances.count
                appearances.append(appearance)
            }
            var bounds = BoundingBox()
            for point in geometry.positions {
                try Task.checkCancellation()
                let value = try RealityViewportSpatialBatch.nativePoint(point, relativeTo: batch.renderOrigin)
                positions.append(value)
                bounds.formUnion(BoundingBox(min: value, max: value))
            }
            for value in geometry.indices {
                try Task.checkCancellation()
                indices.append(UInt32(vertexOffset) + value)
            }
            parts.append(.init(indexOffset: indexOffset * MemoryLayout<UInt32>.stride,
                               indexCount: geometry.indices.count,
                               topology: geometry.topology == .lines ? .line : .triangle,
                               materialIndex: materialIndex, bounds: bounds))
            vertexOffset += geometry.positions.count
            indexOffset += geometry.indices.count
        }
        return WorldGeometry(positions: positions, indices: indices, parts: parts, appearances: appearances)
    }

    private func cameraProjection(camera: Entity, content: RealityViewCameraContent) -> CameraProjection? {
        let orthographic = camera.components[OrthographicCameraComponent.self]
        let perspective = camera.components[PerspectiveCameraComponent.self]
        guard (orthographic != nil) != (perspective != nil) else { return nil }
        let near: Float
        let far: Float
        if let orthographic { near = orthographic.near; far = orthographic.far }
        else if let perspective { near = perspective.near; far = perspective.far }
        else { return nil }
        guard near.isFinite, near > 0, far > near,
              orthographic == nil || far.isFinite else { return nil }
        let depth = Float(min((Double(near) + Double(far)) / 2, max(Double(near) * 2, 1)))
        let step = orthographic?.scale ?? depth
        guard depth.isFinite, depth > 0, step.isFinite, step > 0 else { return nil }
        func project(_ local: SIMD3<Float>) -> CGPoint? {
            content.project(point: camera.convert(position: local, to: nil), to: .local)
        }
        guard let a = project([0, 0, -depth]), let b = project([step, 0, -depth]),
              let c = project([0, step, -depth]), a.x.isFinite, a.y.isFinite,
              b.x.isFinite, b.y.isFinite, c.x.isFinite, c.y.isFinite else { return nil }
        let mapping = CGAffineTransform(a: (b.x - a.x) / CGFloat(step), b: (b.y - a.y) / CGFloat(step),
                                        c: (c.x - a.x) / CGFloat(step), d: (c.y - a.y) / CGFloat(step), tx: a.x, ty: a.y)
        let determinant = mapping.a * mapping.d - mapping.b * mapping.c
        guard determinant.isFinite, determinant != 0 else { return nil }
        var offsetMapping = mapping
        offsetMapping.tx = 0; offsetMapping.ty = 0
        let transform = camera.transformMatrix(relativeTo: nil)
        return CameraProjection(worldFromCamera: transform, cameraFromWorld: simd_inverse(transform),
                                forward: mapping, inverseOffset: offsetMapping.inverted(),
                                sampleDepth: depth, perspective: perspective != nil, annotationDepth: near * 1.01,
                                near: near, far: far)
    }

    private static func unitQuadCollision() async throws -> ShapeResource {
        let mesh = try LowLevelMesh(descriptor: descriptor(vertices: 4, indices: 12))
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
            let vertices = bytes.bindMemory(to: SIMD3<Float>.self)
            vertices[0] = [-0.5, -0.5, 0]
            vertices[1] = [0.5, -0.5, 0]
            vertices[2] = [0.5, 0.5, 0]
            vertices[3] = [-0.5, 0.5, 0]
        }
        mesh.withUnsafeMutableIndices { bytes in
            let indices = bytes.bindMemory(to: UInt32.self)
            let winding: [UInt32] = [0, 1, 2, 0, 2, 3, 2, 1, 0, 3, 2, 0]
            for index in winding.indices { indices[index] = winding[index] }
        }
        mesh.parts.replaceAll([.init(indexCount: 12, topology: .triangle,
                                     bounds: .init(min: [-0.5, -0.5, 0], max: [0.5, 0.5, 0]))])
        let resource = try RealityViewport.nativeResource(from: mesh)
        try Task.checkCancellation()
        return try await ShapeResource.generateStaticMesh(from: resource)
    }

    private func placement(anchor: Point3D, offset: RealityViewportSpatialBatch.Offset,
                           projection: CameraProjection, allowsBehindCamera: Bool = false)
        -> (position: SIMD3<Float>, metersPerPoint: Float)? {
        let point: SIMD3<Float>
        do { point = try RealityViewportSpatialBatch.nativePoint(anchor, relativeTo: batch.renderOrigin) }
        catch { return nil }
        let local = projection.local(point)
        let extendsLine: Bool
        if allowsBehindCamera, case .fixed = offset { extendsLine = true }
        else { extendsLine = false }
        guard local.x.isFinite, local.y.isFinite, local.z.isFinite,
              local.z < 0 || extendsLine else { return nil }
        let screenOffset: CGPoint
        switch offset {
        case .fixed(let value): screenOffset = value
        case .directed(let toward, let parallel, let perpendicular),
             .projected(let toward, _, let parallel, let perpendicular):
            let target: SIMD3<Float>
            do { target = try RealityViewportSpatialBatch.nativePoint(toward, relativeTo: batch.renderOrigin) }
            catch { return nil }
            guard let a = projection.project(point), let b = projection.project(target) else { return nil }
            let dx = b.x - a.x, dy = b.y - a.y
            let length = hypot(dx, dy)
            guard length.isFinite, length > 0 else { return nil }
            let distance: CGFloat
            if case .projected(_, let minimumLength, _, _) = offset {
                distance = max(length, minimumLength) + parallel
            } else {
                distance = parallel
            }
            screenOffset = CGPoint(x: (dx * distance - dy * perpendicular) / length,
                                   y: (dy * distance + dx * perpendicular) / length)
        case .worldDirected(let direction, let lengthPoints):
            // Resolved in native scene space. The requested point length is
            // converted to meters at the anchor's own depth, and the resolved
            // point then reports its own depth and its own scale. Converting a
            // screen offset here instead would normalize the projected
            // direction and erase the foreshortening this case exists to keep.
            let magnitude = direction.length
            guard magnitude.isFinite, magnitude > 0 else { return nil }
            let anchorScale = projection.depthScale(local) / Float(hypot(projection.forward.c, projection.forward.d))
            guard anchorScale.isFinite, anchorScale > 0 else { return nil }
            let unit = SIMD3<Float>(Float(direction.x / magnitude),
                                    Float(direction.y / magnitude),
                                    Float(direction.z / magnitude))
            let resolved = point + unit * (Float(lengthPoints) * anchorScale)
            let resolvedLocal = projection.local(resolved)
            guard resolved.x.isFinite, resolved.y.isFinite, resolved.z.isFinite,
                  resolvedLocal.x.isFinite, resolvedLocal.y.isFinite, resolvedLocal.z.isFinite,
                  resolvedLocal.z < 0 else { return nil }
            let resolvedScale = projection.depthScale(resolvedLocal) / Float(hypot(projection.forward.c, projection.forward.d))
            guard resolvedScale.isFinite, resolvedScale > 0 else { return nil }
            return (resolved, resolvedScale)
        }
        let delta = screenOffset.applying(projection.inverseOffset)
        // Fixed-offset line vertices extend continuously through the camera
        // plane. Native rendering and segment collision own near/far clipping;
        // this signed scale is never used as an Entity size.
        let depthScale = projection.depthScale(local)
        let world = projection.worldFromCamera * SIMD4(local + SIMD3(Float(delta.x) * depthScale, Float(delta.y) * depthScale, 0), 1)
        let scale = depthScale / Float(hypot(projection.forward.c, projection.forward.d))
        guard world.x.isFinite, world.y.isFinite, world.z.isFinite, scale.isFinite,
              scale > 0 || extendsLine else { return nil }
        return (SIMD3(world.x, world.y, world.z), scale)
    }

    @concurrent
    private nonisolated static func doubleWoundIndices(_ source: [UInt32]) async throws -> [UInt32] {
        try Task.checkCancellation()
        var result = source
        result.reserveCapacity(source.count * 2)
        for offset in stride(from: 0, to: source.count, by: 3) {
            if offset.isMultiple(of: 3072) { try Task.checkCancellation() }
            result.append(source[offset + 2])
            result.append(source[offset + 1])
            result.append(source[offset])
        }
        return result
    }

    private static func descriptor(vertices: Int, indices: Int) -> LowLevelMesh.Descriptor {
        .init(vertexCapacity: vertices,
              vertexAttributes: [.init(semantic: .position, format: .float3, offset: 0)],
              vertexLayouts: [.init(bufferIndex: 0, bufferStride: MemoryLayout<SIMD3<Float>>.stride)],
              indexCapacity: indices, indexType: .uint32)
    }

    private static func planarPath(_ path: RealityViewportSpatialBatch.PlanarPath) -> Path {
        let right = simd_normalize(path.xAxis)
        let normal = simd_normalize(simd_cross(path.xAxis, path.yAxis))
        let up = simd_cross(normal, right)
        return path.path.applying(CGAffineTransform(
            a: simd_dot(path.xAxis, right), b: 0,
            c: simd_dot(path.yAxis, right), d: simd_dot(path.yAxis, up), tx: 0, ty: 0
        ))
    }

    @concurrent
    nonisolated static func normalizedPath(
        _ path: Path, additionalPositionLimit: Int, additionalByteLimit: Int
    ) async throws -> Path {
        try Task.checkCancellation()
        guard additionalPositionLimit >= 0, additionalByteLimit >= 0 else {
            throw RealityViewportSpatialBatch.exhausted()
        }
        func controlCount(_ value: Path) throws -> Int {
            var count = 0
            var valid = true
            var overflow = false
            func check(_ point: CGPoint) {
                valid = valid && Float(point.x).isFinite && Float(point.y).isFinite
                let next = count.addingReportingOverflow(1)
                overflow = overflow || next.overflow
                count = next.partialValue
            }
            value.forEach { element in
                switch element {
                case .move(let p), .line(let p): check(p)
                case .quadCurve(let p, let c): check(p); check(c)
                case .curve(let p, let c1, let c2): check(p); check(c1); check(c2)
                case .closeSubpath: break
                }
            }
            guard !overflow else { throw RealityViewportSpatialBatch.exhausted() }
            guard valid else { throw RealityViewportSpatialBatch.invalid("Native path contains invalid control points.") }
            return count
        }
        let sourceCount = try controlCount(path)
        let normalized = Path(path.cgPath.normalized(using: .evenOdd))
        try Task.checkCancellation()
        let count = try controlCount(normalized)
        guard !normalized.isEmpty, count > 0 else {
            throw RealityViewportSpatialBatch.invalid("Native normalized path has no filled topology.")
        }
        let growth = max(0, count - sourceCount)
        let bytes = growth.multipliedReportingOverflow(by: MemoryLayout<Path.Element>.stride)
        guard growth <= additionalPositionLimit, !bytes.overflow, bytes.partialValue <= additionalByteLimit else {
            throw RealityViewportSpatialBatch.exhausted()
        }
        return normalized
    }

    private static func pathResource(
        _ path: Path, cache: inout [CGPath: MeshResource],
        additionalPositionLimit: Int, additionalByteLimit: Int
    ) async throws -> MeshResource {
        let key = path.cgPath
        if let existing = cache[key] { return existing }
        let normalized = try await normalizedPath(path, additionalPositionLimit: additionalPositionLimit,
            additionalByteLimit: additionalByteLimit)
        var extrusion = MeshResource.ShapeExtrusionOptions()
        extrusion.extrusionMethod = .linear(depth: 0)
        let resource = try await MeshResource(extruding: normalized, extrusionOptions: extrusion)
        try Task.checkCancellation()
        cache[key] = resource
        return resource
    }

    private static func orient(_ entity: Entity, on path: RealityViewportSpatialBatch.PlanarPath) {
        let right = simd_normalize(path.xAxis)
        let normal = simd_normalize(simd_cross(path.xAxis, path.yAxis))
        let up = simd_cross(normal, right)
        entity.orientation = simd_quatf(simd_float3x3(SIMD3<Float>(right), SIMD3<Float>(up), SIMD3<Float>(normal)))
    }

    private static func material(_ color: SIMD4<Float>, depth: RealityViewportSpatialBatch.Depth) -> UnlitMaterial {
        var material = UnlitMaterial(color: NSColor(red: CGFloat(color.x), green: CGFloat(color.y),
                                                   blue: CGFloat(color.z), alpha: CGFloat(color.w)))
        material.faceCulling = .none
        material.readsDepth = depth == .scene
        material.writesDepth = depth == .scene && color.w == 1
        if color.w < 1 { material.blending = .transparent(opacity: .init(scale: 1)) }
        return material
    }
}
