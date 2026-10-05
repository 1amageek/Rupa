import Foundation
import Metal
import RealityKit
import _RealityKit_SwiftUI
import simd

/// MainActor-owned raster buffers shared by actual native drawing and optical capture.
@MainActor
final class NativeLineRasterizer {
    struct Limits {
        let maximumPositionCount: Int
        let maximumTriangleCount: Int
        let maximumRetainedByteCount: Int
    }
    let source: LowLevelMesh
    private struct Frame {
        let mesh: LowLevelMesh
        let resource: MeshResource
    }
    private let firstFrame: Frame
    private let secondFrame: Frame
    private var activeFirst = true
    private var pendingEntity: ObjectIdentifier?
    private var pendingWorld: simd_float4x4?
    private var pendingOriginalWorld: simd_float4x4?
    private var pendingParent: Entity?
    private var pendingParentWorld: simd_float4x4?
    private var pendingLocalTransform: Transform?
    private var pendingMountedMesh: MeshResource?
    private var pendingMaterialCount: Int?
    var mesh: LowLevelMesh { activeFirst ? firstFrame.mesh : secondFrame.mesh }
    var resource: MeshResource { activeFirst ? firstFrame.resource : secondFrame.resource }
    private var inactiveFrame: Frame { activeFirst ? secondFrame : firstFrame }
    var stagedMesh: LowLevelMesh? { pendingEntity == nil ? nil : inactiveFrame.mesh }
    let positionCount: Int
    let triangleCount: Int
    let retainedByteCount: Int
    private let maximumLineCount: Int
    private let maximumPartCount: Int
    private var parts: [LowLevelMesh.Part] = []

    init(source: LowLevelMesh, maximumLineCount: Int, maximumPartCount: Int, limits: Limits) throws {
        let descriptor = source.descriptor
        guard descriptor.indexType == .uint32, descriptor.vertexAttributes.count == 1,
              descriptor.vertexLayouts.count == 1,
              descriptor.vertexAttributes[0].semantic == .position, descriptor.vertexAttributes[0].format == .float3,
              descriptor.vertexAttributes[0].offset == 0, descriptor.vertexAttributes[0].layoutIndex == 0,
              descriptor.vertexLayouts[0].bufferIndex == 0, descriptor.vertexLayouts[0].bufferOffset == 0,
              descriptor.vertexLayouts[0].bufferStride == MemoryLayout<SIMD3<Float>>.stride else {
            throw RealityViewportSpatialBatch.invalid("Native line raster source must retain the original position-only UInt32 layout.")
        }
        guard maximumLineCount >= 0, maximumPartCount >= source.parts.count,
              limits.maximumPositionCount >= 0, limits.maximumTriangleCount >= 0,
              limits.maximumRetainedByteCount >= 0 else { throw RealityViewportSpatialBatch.exhausted() }
        let extraVertices = maximumLineCount.multipliedReportingOverflow(by: 4)
        let extraIndices = maximumLineCount.multipliedReportingOverflow(by: 4)
        let vertices = source.vertexCapacity.addingReportingOverflow(extraVertices.partialValue)
        let indices = source.indexCapacity.addingReportingOverflow(extraIndices.partialValue)
        let triangles = maximumLineCount.multipliedReportingOverflow(by: 2)
        guard !extraVertices.overflow, !extraIndices.overflow, !vertices.overflow, !indices.overflow,
              !triangles.overflow, vertices.partialValue < Int(UInt32.max),
              vertices.partialValue <= limits.maximumPositionCount,
              triangles.partialValue <= limits.maximumTriangleCount else { throw RealityViewportSpatialBatch.exhausted() }
        let retainedVertices = vertices.partialValue.multipliedReportingOverflow(by: 2)
        let retainedTriangles = triangles.partialValue.multipliedReportingOverflow(by: 2)
        guard !retainedVertices.overflow, !retainedTriangles.overflow,
              retainedVertices.partialValue <= limits.maximumPositionCount,
              retainedTriangles.partialValue <= limits.maximumTriangleCount else { throw RealityViewportSpatialBatch.exhausted() }
        var bytes = MemoryLayout<NativeLineRasterizer>.stride
        for (count, stride) in [(vertices.partialValue, MemoryLayout<SIMD3<Float>>.stride * 2),
                                (indices.partialValue, MemoryLayout<UInt32>.stride * 2),
                                (maximumPartCount, MemoryLayout<LowLevelMesh.Part>.stride * 3)] {
            let amount = count.multipliedReportingOverflow(by: stride)
            let total = bytes.addingReportingOverflow(amount.partialValue)
            guard !amount.overflow, !total.overflow, total.partialValue <= limits.maximumRetainedByteCount else {
                throw RealityViewportSpatialBatch.exhausted()
            }
            bytes = total.partialValue
        }
        self.source = source
        self.maximumLineCount = maximumLineCount
        self.maximumPartCount = maximumPartCount
        positionCount = retainedVertices.partialValue
        triangleCount = retainedTriangles.partialValue
        retainedByteCount = bytes
        func allocateFrame() throws -> Frame {
            let mesh = try LowLevelMesh(descriptor: .init(vertexCapacity: vertices.partialValue,
            vertexAttributes: [.init(semantic: .position, format: .float3, offset: 0)],
            vertexLayouts: [.init(bufferIndex: 0, bufferStride: MemoryLayout<SIMD3<Float>>.stride)],
            indexCapacity: indices.partialValue, indexType: .uint32))
            // All native capacity is initialized before any scoped read or draw. The
            // service owns the meshes; borrowed pointers never outlive native callbacks.
            mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
                let vertices = bytes.bindMemory(to: SIMD3<Float>.self)
                for index in vertices.indices { vertices[index] = .zero }
            }
            mesh.withUnsafeMutableIndices { bytes in
                let indices = bytes.bindMemory(to: UInt32.self)
                for index in indices.indices { indices[index] = 0 }
            }
            mesh.parts.replaceAll([])
            return Frame(mesh: mesh, resource: try RealityViewport.nativeResource(from: mesh))
        }
        firstFrame = try allocateFrame()
        secondFrame = try allocateFrame()
        parts.reserveCapacity(maximumPartCount)
    }

    func update(entity: ModelEntity, camera: Entity, content: RealityViewCameraContent,
                nativePixelsPerPoint: CGFloat) throws {
        try stage(entity: entity, camera: camera, content: content, nativePixelsPerPoint: nativePixelsPerPoint)
        try commit(entity: entity)
    }

    func update(entity: ModelEntity, projection: NativeLineCameraProjection,
                nativePixelsPerPoint: CGFloat) throws {
        try stage(entity: entity, projection: projection, nativePixelsPerPoint: nativePixelsPerPoint)
        try commit(entity: entity)
    }

    func stage(entity: ModelEntity, plannedLocalTransform: Transform? = nil,
               camera: Entity, content: RealityViewCameraContent, nativePixelsPerPoint: CGFloat) throws {
        guard let projection = NativeLineCameraProjection.capture(camera: camera, content: content) else {
            throw RealityViewportSpatialResources.CameraReadinessError.projectionUnavailable
        }
        try stage(entity: entity, plannedLocalTransform: plannedLocalTransform,
            projection: projection, nativePixelsPerPoint: nativePixelsPerPoint)
    }

    func stage(entity: ModelEntity, plannedLocalTransform: Transform? = nil, projection: NativeLineCameraProjection,
               nativePixelsPerPoint: CGFloat) throws {
        discardStagedFrame()
        let mesh = inactiveFrame.mesh
        try Task.checkCancellation()
        guard nativePixelsPerPoint.isFinite, nativePixelsPerPoint > 0 else {
            throw RealityViewportSpatialBatch.invalid("Native line ribbons require the actual backing pixel scale.")
        }
        let halfWidth = 0.5 / nativePixelsPerPoint
        let originalWorld = entity.transformMatrix(relativeTo: nil)
        let parent = entity.parent
        let parentWorld = parent?.transformMatrix(relativeTo: nil) ?? matrix_identity_float4x4
        let world = plannedLocalTransform.map { parentWorld * $0.matrix } ?? originalWorld
        let inverseWorld = simd_inverse(world)
        guard (0..<4).allSatisfy({ column in (0..<4).allSatisfy { world[column][$0].isFinite && inverseWorld[column][$0].isFinite } }) else {
            throw RealityViewportSpatialBatch.invalid("Native ribbon placement has no finite affine inverse.")
        }
        parts.removeAll(keepingCapacity: true)
        guard source.parts.count <= maximumPartCount else { throw RealityViewportSpatialBatch.exhausted() }
        var consumedLines = 0
        var failure: (any Error)?
        source.withUnsafeBytes(bufferIndex: 0) { originalVertexBytes in
            source.withUnsafeIndices { originalIndexBytes in
                mesh.withUnsafeMutableBytes(bufferIndex: 0) { drawVertexBytes in
                    mesh.withUnsafeMutableIndices { drawIndexBytes in
                        do {
                            guard originalVertexBytes.count.isMultiple(of: MemoryLayout<SIMD3<Float>>.stride),
                                  originalIndexBytes.count.isMultiple(of: MemoryLayout<UInt32>.stride),
                                  drawVertexBytes.count.isMultiple(of: MemoryLayout<SIMD3<Float>>.stride),
                                  drawIndexBytes.count.isMultiple(of: MemoryLayout<UInt32>.stride) else {
                                throw RealityViewportSpatialBatch.invalid("Native ribbon buffer strides disagree.")
                            }
                            let originalVertices = originalVertexBytes.bindMemory(to: SIMD3<Float>.self)
                            let originalIndices = originalIndexBytes.bindMemory(to: UInt32.self)
                            let vertices = drawVertexBytes.bindMemory(to: SIMD3<Float>.self)
                            let indices = drawIndexBytes.bindMemory(to: UInt32.self)
                            guard originalVertices.count <= vertices.count else { throw RealityViewportSpatialBatch.exhausted() }
                            for index in originalVertices.indices { vertices[index] = originalVertices[index] }
                            var vertexEnd = originalVertices.count, indexEnd = 0
                            func original(_ index: UInt32) throws -> SIMD3<Float> {
                                guard let offset = Int(exactly: index), originalVertices.indices.contains(offset) else {
                                    throw RealityViewportSpatialBatch.invalid("Native ribbon source index is absent.")
                                }
                                let point = world * SIMD4(originalVertices[offset], 1)
                                return SIMD3(point.x, point.y, point.z)
                            }
                            for part in source.parts {
                                try Task.checkCancellation()
                                guard part.indexOffset >= 0, part.indexOffset.isMultiple(of: MemoryLayout<UInt32>.stride), part.indexCount >= 0 else {
                                    throw RealityViewportSpatialBatch.invalid("Native ribbon source range is invalid.")
                                }
                                let start = part.indexOffset / MemoryLayout<UInt32>.stride
                                let end = start.addingReportingOverflow(part.indexCount)
                                guard !end.overflow, end.partialValue <= originalIndices.count else {
                                    throw RealityViewportSpatialBatch.invalid("Native ribbon source index range exceeds storage.")
                                }
                                let partStart = indexEnd
                                var bounds = BoundingBox()
                                if part.topology == .triangle {
                                    guard part.indexCount.isMultiple(of: 3), part.indexCount <= indices.count - indexEnd else {
                                        throw RealityViewportSpatialBatch.exhausted()
                                    }
                                    for offset in start..<end.partialValue {
                                        let id = originalIndices[offset]
                                        guard Int(id) < originalVertices.count else { throw RealityViewportSpatialBatch.invalid("Native triangle index is invalid.") }
                                        indices[indexEnd] = id; indexEnd += 1
                                        bounds.formUnion(.init(min: originalVertices[Int(id)], max: originalVertices[Int(id)]))
                                    }
                                } else if part.topology == .line {
                                    guard part.indexCount.isMultiple(of: 2) else { throw RealityViewportSpatialBatch.invalid("Native line range is invalid.") }
                                    for offset in stride(from: start, to: end.partialValue, by: 2) {
                                        guard consumedLines < maximumLineCount else { throw RealityViewportSpatialBatch.exhausted() }
                                        consumedLines += 1
                                        var first = projection.local(try original(originalIndices[offset]))
                                        var last = projection.local(try original(originalIndices[offset + 1]))
                                        var lower: Float = 0, upper: Float = 1
                                        let z0 = first.z, dz = last.z - first.z
                                        guard (0..<3).allSatisfy({ first[$0].isFinite && last[$0].isFinite }), dz.isFinite else {
                                            throw RealityViewportSpatialBatch.invalid("Original line has nonfinite camera coordinates.")
                                        }
                                        func clip(_ constant: Float, _ slope: Float) -> Bool {
                                            if slope == 0 { return constant >= 0 }
                                            let root = -constant / slope
                                            if slope > 0 { lower = max(lower, root) } else { upper = min(upper, root) }
                                            return lower <= upper
                                        }
                                        guard clip(-projection.near - z0, -dz),
                                              !projection.far.isFinite || clip(projection.far + z0, dz) else { continue }
                                        let delta = last - first
                                        last = first + delta * upper; first += delta * lower
                                        let aWorld = projection.worldFromCamera * SIMD4(first, 1)
                                        let bWorld = projection.worldFromCamera * SIMD4(last, 1)
                                        guard let a = projection.project(SIMD3(aWorld.x, aWorld.y, aWorld.z)),
                                              let b = projection.project(SIMD3(bWorld.x, bWorld.y, bWorld.z)) else {
                                            throw RealityViewportSpatialBatch.invalid("Clipped native line has no projection.")
                                        }
                                        let dx = b.x - a.x, dy = b.y - a.y
                                        let length = hypot(dx, dy)
                                        guard length.isFinite, vertexEnd <= vertices.count - 4, indexEnd <= indices.count - 6 else {
                                            throw RealityViewportSpatialBatch.exhausted()
                                        }
                                        let side = length > 0 ? CGPoint(x: -dy * halfWidth / length, y: dx * halfWidth / length)
                                            : CGPoint(x: 0, y: halfWidth)
                                        let cap = length > 0 ? CGPoint.zero : CGPoint(x: halfWidth, y: 0)
                                        for corner in 0..<4 {
                                            let anchor = corner < 2 ? a : b
                                            let sideSign: CGFloat = corner.isMultiple(of: 2) ? 1 : -1
                                            let capSign: CGFloat = corner < 2 ? -1 : 1
                                            let screen = CGPoint(x: anchor.x + sideSign * side.x + capSign * cap.x,
                                                y: anchor.y + sideSign * side.y + capSign * cap.y)
                                            let value = projection.point(at: screen, depth: corner < 2 ? -first.z : -last.z)
                                            let local = inverseWorld * SIMD4(value, 1)
                                            let point = SIMD3(local.x, local.y, local.z)
                                            guard point.x.isFinite, point.y.isFinite, point.z.isFinite else {
                                                throw RealityViewportSpatialBatch.invalid("Native ribbon vertex is nonfinite.")
                                            }
                                            vertices[vertexEnd + corner] = point
                                            bounds.formUnion(.init(min: point, max: point))
                                        }
                                        let v = UInt32(vertexEnd)
                                        indices[indexEnd] = v
                                        indices[indexEnd + 1] = v + 1
                                        indices[indexEnd + 2] = v + 2
                                        indices[indexEnd + 3] = v + 2
                                        indices[indexEnd + 4] = v + 1
                                        indices[indexEnd + 5] = v + 3
                                        vertexEnd += 4; indexEnd += 6
                                    }
                                } else { throw RealityViewportSpatialBatch.invalid("Native ribbon topology is unsupported.") }
                                parts.append(.init(indexOffset: partStart * MemoryLayout<UInt32>.stride,
                                    indexCount: indexEnd - partStart, topology: .triangle,
                                    materialIndex: part.materialIndex, bounds: bounds))
                            }
                        } catch { failure = error }
                    }
                }
            }
        }
        if let failure { throw failure }
        mesh.parts.replaceAll(parts)
        guard let mounted = entity.model else { throw RealityViewportSpatialBatch.invalid("Native line model is absent.") }
        pendingEntity = ObjectIdentifier(entity)
        pendingWorld = world
        pendingOriginalWorld = originalWorld
        pendingParent = parent
        pendingParentWorld = parentWorld
        pendingLocalTransform = plannedLocalTransform
        pendingMountedMesh = mounted.mesh
        pendingMaterialCount = mounted.materials.count
    }

    func validateStagedFrame(entity: ModelEntity) throws {
        guard pendingEntity == ObjectIdentifier(entity), pendingWorld != nil,
              let originalWorld = pendingOriginalWorld, originalWorld == entity.transformMatrix(relativeTo: nil),
              pendingParent === entity.parent,
              pendingParentWorld == (entity.parent?.transformMatrix(relativeTo: nil) ?? matrix_identity_float4x4),
              let mounted = entity.model, mounted.mesh === pendingMountedMesh,
              mounted.materials.count == pendingMaterialCount else {
            throw RealityViewportSpatialBatch.invalid("Native line staged frame no longer matches its original occurrence placement.")
        }
    }

    func commit(entity: ModelEntity) throws {
        try validateStagedFrame(entity: entity)
        guard var component = entity.model else { throw RealityViewportSpatialBatch.invalid("Native line model is absent.") }
        component.mesh = inactiveFrame.resource
        if let transform = pendingLocalTransform { entity.transform = transform }
        entity.model = component
        activeFirst.toggle()
        discardStagedFrame()
    }

    /// Caller also restores the corresponding actual bytes and mounted model.
    func restorePublishedMesh(_ original: LowLevelMesh) throws {
        if original === firstFrame.mesh { activeFirst = true }
        else if original === secondFrame.mesh { activeFirst = false }
        else { throw RealityViewportSpatialBatch.invalid("Line checkpoint does not belong to the original raster owner.") }
        discardStagedFrame()
    }

    func discardStagedFrame() {
        pendingEntity = nil; pendingWorld = nil; pendingOriginalWorld = nil
        pendingParent = nil; pendingParentWorld = nil; pendingLocalTransform = nil
        pendingMountedMesh = nil; pendingMaterialCount = nil
    }

    struct Triangle: Sendable {
        let first: SIMD3<Float>
        let second: SIMD3<Float>
        let third: SIMD3<Float>
        let materialIndex: Int
    }

    /// Captures only the actual active draw parts. Material/depth authority remains
    /// with the caller; this immutable output owns its copied triangle vertices.
    func triangles(entity: ModelEntity, maximumTriangleCount: Int,
                   maximumRetainedByteCount: Int, staged: Bool = false) throws -> [Triangle] {
        if staged { try validateStagedFrame(entity: entity) }
        let mesh = staged ? inactiveFrame.mesh : self.mesh
        guard maximumTriangleCount >= 0, maximumRetainedByteCount >= 0 else {
            throw RealityViewportSpatialBatch.exhausted()
        }
        var count = 0
        for part in mesh.parts {
            guard part.topology == .triangle, part.indexCount >= 0, part.indexCount.isMultiple(of: 3) else {
                throw RealityViewportSpatialBatch.invalid("Native raster triangle part is invalid.")
            }
            let sum = count.addingReportingOverflow(part.indexCount / 3)
            guard !sum.overflow, sum.partialValue <= maximumTriangleCount else { throw RealityViewportSpatialBatch.exhausted() }
            count = sum.partialValue
        }
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<Triangle>.stride)
        guard !bytes.overflow, bytes.partialValue <= maximumRetainedByteCount else { throw RealityViewportSpatialBatch.exhausted() }
        let world: simd_float4x4
        if staged {
            guard let planned = pendingWorld else { throw RealityViewportSpatialBatch.invalid("Native line planned placement is absent.") }
            world = planned
        } else { world = entity.transformMatrix(relativeTo: nil) }
        var result: [Triangle] = []
        result.reserveCapacity(count)
        var failure: (any Error)?
        mesh.withUnsafeBytes(bufferIndex: 0) { vertexBytes in
            mesh.withUnsafeIndices { indexBytes in
                do {
                    guard vertexBytes.count.isMultiple(of: MemoryLayout<SIMD3<Float>>.stride),
                          indexBytes.count.isMultiple(of: MemoryLayout<UInt32>.stride) else {
                        throw RealityViewportSpatialBatch.invalid("Native raster snapshot stride is invalid.")
                    }
                    let vertices = vertexBytes.bindMemory(to: SIMD3<Float>.self)
                    let indices = indexBytes.bindMemory(to: UInt32.self)
                    func point(_ id: UInt32) throws -> SIMD3<Float> {
                        guard let index = Int(exactly: id), vertices.indices.contains(index) else {
                            throw RealityViewportSpatialBatch.invalid("Native raster snapshot index is absent.")
                        }
                        let value = world * SIMD4(vertices[index], 1)
                        guard (0..<4).allSatisfy({ value[$0].isFinite }), value.w == 1 else {
                            throw RealityViewportSpatialBatch.invalid("Native raster snapshot placement is not finite affine.")
                        }
                        return SIMD3(value.x, value.y, value.z)
                    }
                    for part in mesh.parts {
                        try Task.checkCancellation()
                        guard part.indexOffset >= 0, part.indexOffset.isMultiple(of: MemoryLayout<UInt32>.stride) else {
                            throw RealityViewportSpatialBatch.invalid("Native raster snapshot part offset is invalid.")
                        }
                        let start = part.indexOffset / MemoryLayout<UInt32>.stride
                        let end = start.addingReportingOverflow(part.indexCount)
                        guard !end.overflow, end.partialValue <= indices.count else { throw RealityViewportSpatialBatch.exhausted() }
                        for offset in stride(from: start, to: end.partialValue, by: 3) {
                            result.append(.init(first: try point(indices[offset]), second: try point(indices[offset + 1]),
                                third: try point(indices[offset + 2]), materialIndex: part.materialIndex))
                        }
                    }
                } catch { failure = error }
            }
        }
        if let failure { throw failure }
        return result
    }

}
