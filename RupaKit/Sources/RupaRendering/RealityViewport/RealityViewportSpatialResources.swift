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
    private var labels: [(Entity, RealityViewportSpatialBatch.Label)] = []
    private var markers: [(Entity, RealityViewportSpatialBatch.Marker)] = []
    private var cameraLines: [(ModelEntity, LowLevelMesh, RealityViewportSpatialBatch.CameraLine)] = []
    private var cameraPaths: [(Entity, RealityViewportSpatialBatch.CameraPath)] = []
    private var boundsRulers: [(ViewportMeasurementRulerAxis, Entity, ModelEntity, LowLevelMesh)] = []
    private var grid: (entity: ModelEntity, mesh: LowLevelMesh)?
    private var gridLabels: [Entity] = []
    private var gridPlacement: ModelEntity?
    private var handleIndices: [ObjectIdentifier: UInt32] = [:]
    private struct AxisResource {
        let axis: ViewportCoordinateAxis
        let line: ModelEntity
        let mesh: LowLevelMesh
        let label: Entity
    }
    private var axes: [AxisResource] = []
    private let surfaceItemCount: Int
    private let surfacePositionCount: Int
    private let byteLimit: Int
    private(set) var disabledRulerAxes: Set<ViewportMeasurementRulerAxis> = []
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

    private func register(_ entity: Entity, handleIndex: UInt32?) {
        if let handleIndex { handleIndices[ObjectIdentifier(entity)] = handleIndex }
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
        surfaceItemCount = surfacePlan?.itemCount ?? 0
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
            let resource = try await MeshResource(from: mesh)
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
            let resource = try await MeshResource(from: mesh)
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
                let resource = try await MeshResource(from: mesh)
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
                $0.attachment == source.attachment && $0.handleIndex == source.handleIndex
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
            let resource = try await MeshResource(from: mesh)
            try Task.checkCancellation()
            let entity = ModelEntity(mesh: resource, materials: geometry.appearances.map { material($0.color, depth: $0.depth) })
            result.register(entity, handleIndex: group.handleIndex)
            result.root(for: group.attachment).addChild(entity)
        }
        for path in batch.paths {
            try Task.checkCancellation()
            let resource = try await pathResource(planarPath(path), cache: &pathResources)
            try Task.checkCancellation()
            let entity = ModelEntity(mesh: resource, materials: [material(path.color, depth: path.depth)])
            entity.position = try RealityViewportSpatialBatch.nativePoint(path.origin, relativeTo: batch.renderOrigin)
            orient(entity, on: path)
            result.register(entity, handleIndex: path.handleIndex)
            result.root(for: path.attachment).addChild(entity)
        }
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
            result.labels.append((entity, label))
            result.register(entity, handleIndex: label.handleIndex)
            result.root(for: label.attachment).addChild(entity)
        }
        var sphere: MeshResource?
        var box: MeshResource?
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
            }
            let entity = ModelEntity(mesh: mesh, materials: [material(marker.color, depth: marker.depth)])
            entity.position = try RealityViewportSpatialBatch.nativePoint(marker.anchor, relativeTo: batch.renderOrigin)
            entity.isEnabled = false
            result.markers.append((entity, marker))
            result.register(entity, handleIndex: marker.handleIndex)
            result.root(for: marker.attachment).addChild(entity)
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
            let resource = try await MeshResource(from: mesh)
            try Task.checkCancellation()
            let entity = ModelEntity(mesh: resource, materials: [material(line.color, depth: line.depth)])
            entity.isEnabled = false
            result.cameraLines.append((entity, mesh, line))
            result.register(entity, handleIndex: line.handleIndex)
            result.root(for: line.attachment).addChild(entity)
        }
        for path in batch.cameraPaths {
            try Task.checkCancellation()
            let resource = try await pathResource(path.path.applying(.init(scaleX: 1, y: -1)), cache: &pathResources)
            try Task.checkCancellation()
            let entity = ModelEntity(mesh: resource, materials: [material(path.color, depth: path.depth)])
            entity.components.set(BillboardComponent())
            entity.isEnabled = false
            result.cameraPaths.append((entity, path))
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
                let lineResource = try await MeshResource(from: mesh)
                try Task.checkCancellation()
                let line = ModelEntity(mesh: lineResource, materials: [material(group.color, depth: .annotation)])
                line.isEnabled = false
                result.root.addChild(label)
                result.root.addChild(line)
                result.boundsRulers.append((axis, label, line, mesh))
                result.disabledRulerAxes.insert(axis)
            }
        }
        try Task.checkCancellation()
        return result
    }

    /// Native world geometry remains untouched. Only the already admitted
    /// camera-relative annotations change, synchronously with the mounted camera.
    @discardableResult
    func updateCamera(camera: Entity, content: RealityViewCameraContent,
                      safeRect: CGRect = .zero, excludedRects: [CGRect] = [],
                      gridRuler: RulerConfiguration? = nil, gridBasis: ViewportProjectionBasis = .isometric,
                      gridSize: CGSize = .zero, gridSpacing: ViewportGridVisualSpacingMode = .adaptive) throws -> MeshSourcePresentationRenderError? {
        guard grid != nil || !axes.isEmpty || !cameraPaths.isEmpty || !labels.isEmpty || !markers.isEmpty || !cameraLines.isEmpty || !boundsRulers.isEmpty else { return nil }
        guard let projection = cameraProjection(camera: camera, content: content) else {
            for (entity, _) in cameraPaths { entity.isEnabled = false }
            for (entity, _) in labels { entity.isEnabled = false }
            for (entity, _) in markers { entity.isEnabled = false }
            for (entity, _, _) in cameraLines { entity.isEnabled = false }
            for (axis, label, line, _) in boundsRulers {
                label.isEnabled = false; line.isEnabled = false; disabledRulerAxes.insert(axis)
            }
            disableAxes()
            hideGrid()
            throw CameraReadinessError.projectionUnavailable
        }
        try updateAxes(projection: projection, viewportSize: gridSize,
                       safeRect: safeRect, excludedRects: excludedRects)
        for (entity, path) in cameraPaths {
            guard let placement = placement(anchor: path.anchor, offset: path.offset, projection: projection) else {
                entity.isEnabled = false
                continue
            }
            entity.position = placement.position
            entity.scale = SIMD3(repeating: placement.metersPerPoint)
            entity.isEnabled = true
        }
        for (entity, label) in labels {
            guard let placement = placement(anchor: label.anchor, offset: label.offset, projection: projection) else {
                entity.isEnabled = false
                continue
            }
            entity.position = placement.position
            entity.scale = SIMD3(repeating: placement.metersPerPoint * label.heightPoints)
            entity.isEnabled = true
        }
        for (entity, marker) in markers {
            guard let placement = placement(anchor: marker.anchor, offset: .zero, projection: projection) else {
                entity.isEnabled = false
                continue
            }
            entity.scale = SIMD3(repeating: placement.metersPerPoint * marker.diameterPoints)
            entity.isEnabled = true
        }
        for (entity, mesh, line) in cameraLines {
            var valid = true
            var bounds = BoundingBox()
            mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
                let vertices = bytes.bindMemory(to: SIMD3<Float>.self)
                for (index, point) in line.points.enumerated() {
                    guard let placement = placement(anchor: point.anchor, offset: point.offset, projection: projection) else {
                        valid = false
                        vertices[index] = .zero
                        continue
                    }
                    vertices[index] = placement.position
                    bounds.formUnion(BoundingBox(min: placement.position, max: placement.position))
                }
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
        do {
            if let gridRuler {
                guard grid != nil else { throw RealityViewportSpatialBatch.invalid("The mounted frame did not admit a grid.") }
                let remaining = batch.limits.maxItemCount - batch.itemCount - surfaceItemCount
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
        guard slotCount <= batch.limits.maxItemCount - batch.itemCount - surfaceItemCount else {
            throw RealityViewportSpatialBatch.exhausted()
        }
        var byteCount = batch.admittedByteCount
        var positionCount = batch.positionCount + surfacePositionCount
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
        for (axis, label, line, _) in boundsRulers {
            label.isEnabled = false
            line.isEnabled = false
            disabledRulerAxes.insert(axis)
        }
        guard excludedRects.count <= batch.limits.maxItemCount - batch.itemCount else {
            throw MeshSourcePresentationRenderError(code: .resourceExhausted,
                message: "Current chrome exclusions exceed bounds ruler placement admission.")
        }
        let layout = ViewportMeasurementBoundsRulerLayout().placement(
            for: group.input.bounds, labels: group.input.labels,
            project: { point in
                do {
                    let native = try RealityViewportSpatialBatch.nativePoint(point, relativeTo: self.batch.renderOrigin)
                    return projection.project(native)
                } catch { return nil }
            }, safeRect: safeRect, excludedRects: excludedRects)
        disabledRulerAxes = layout.disabledAxes
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
                disabledRulerAxes.insert(ruler.axis)
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
            guard valid else { disabledRulerAxes.insert(ruler.axis); continue }
            var part = mesh.parts[0]
            part.bounds = bounds
            mesh.parts[0] = part
            label.position = labelPlacement.position
            label.scale = SIMD3(repeating: labelPlacement.metersPerPoint * group.heightPoints)
            label.isEnabled = true
            line.isEnabled = true
        }
    }

    private static func textResource(_ value: String, cache: inout [String: MeshResource]) async throws -> MeshResource {
        try Task.checkCancellation()
        if let existing = cache[value] { return existing }
        var text = AttributedString(value)
        text.font = NSFont.monospacedSystemFont(ofSize: 1, weight: .medium)
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
                                sampleDepth: depth, perspective: perspective != nil, annotationDepth: near * 1.01, near: near, far: far)
    }

    private func placement(anchor: Point3D, offset: RealityViewportSpatialBatch.Offset,
                           projection: CameraProjection) -> (position: SIMD3<Float>, metersPerPoint: Float)? {
        let point: SIMD3<Float>
        do { point = try RealityViewportSpatialBatch.nativePoint(anchor, relativeTo: batch.renderOrigin) }
        catch { return nil }
        let local = projection.local(point)
        guard local.x.isFinite, local.y.isFinite, local.z.isFinite, local.z < 0 else { return nil }
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
        }
        let delta = screenOffset.applying(projection.inverseOffset)
        let depthScale = projection.depthScale(local)
        let world = projection.worldFromCamera * SIMD4(local + SIMD3(Float(delta.x) * depthScale, Float(delta.y) * depthScale, 0), 1)
        let scale = depthScale / Float(hypot(projection.forward.c, projection.forward.d))
        guard world.x.isFinite, world.y.isFinite, world.z.isFinite, scale.isFinite, scale > 0 else { return nil }
        return (SIMD3(world.x, world.y, world.z), scale)
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

    private static func pathResource(_ path: Path, cache: inout [CGPath: MeshResource]) async throws -> MeshResource {
        let key = path.cgPath
        if let existing = cache[key] { return existing }
        var extrusion = MeshResource.ShapeExtrusionOptions()
        extrusion.extrusionMethod = .linear(depth: 0)
        let resource = try await MeshResource(extruding: path, extrusionOptions: extrusion)
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
