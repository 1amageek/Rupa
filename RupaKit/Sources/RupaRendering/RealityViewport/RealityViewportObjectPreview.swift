import RealityKit
import RupaGeometry
import SwiftCAD
import simd

/// Occurrence-local drawing storage; never shared with committed mesh assets.
@MainActor
final class RealityViewportObjectPreview {
    private struct Vertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
    }

    let mesh: LowLevelMesh
    let resource: MeshResource
    let byteCount: Int
    private let cornerCount: Int
    private let lineIndexCount: Int

    init(occurrence: MeshSourcePresentationRenderPlan.Occurrence, availableBytes: Int) throws {
        let cornerCount = occurrence.vertexIndices.count
        let lineIndexCount = occurrence.boundaryIndexCount
        self.cornerCount = cornerCount
        self.lineIndexCount = lineIndexCount
        guard cornerCount <= Int(UInt32.max), cornerCount <= Int.max / 64,
              lineIndexCount <= Int.max / 8 else { throw RealityViewportSpatialBatch.exhausted() }
        byteCount = cornerCount * (MemoryLayout<Vertex>.stride + MemoryLayout<UInt32>.stride)
            + lineIndexCount * MemoryLayout<UInt32>.stride
        guard byteCount <= availableBytes else { throw RealityViewportSpatialBatch.exhausted() }
        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexCapacity = cornerCount
        descriptor.indexCapacity = cornerCount + lineIndexCount
        descriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, offset: 0),
            .init(semantic: .normal, format: .float3, offset: MemoryLayout<SIMD3<Float>>.stride)
        ]
        descriptor.vertexLayouts = [.init(bufferIndex: 0, bufferStride: MemoryLayout<Vertex>.stride)]
        descriptor.indexType = .uint32
        let mesh = try LowLevelMesh(descriptor: descriptor)
        self.mesh = mesh
        // RealityKit owns and frees both buffers. Borrows do not escape; every
        // slot is initialized before resource creation, on this actor only.
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
            let vertices = bytes.bindMemory(to: Vertex.self)
            for index in 0..<cornerCount { vertices[index] = .init(position: .zero, normal: [0, 0, 1]) }
        }
        mesh.withUnsafeMutableIndices { bytes in
            let indices = bytes.bindMemory(to: UInt32.self)
            for index in 0..<cornerCount { indices[index] = UInt32(index) }
            var output = cornerCount
            for corner in 0..<cornerCount where occurrence.boundaryCornerIndices[corner] != UInt32.max {
                indices[output] = UInt32(corner)
                indices[output + 1] = UInt32(corner - corner % 3 + (corner % 3 + 1) % 3)
                output += 2
            }
        }
        mesh.parts.replaceAll([.init(indexCount: cornerCount, topology: .triangle,
                                    bounds: .init(min: .zero, max: .zero))])
        resource = try RealityViewport.nativeResource(from: mesh)
    }

    func update(occurrence: MeshSourcePresentationRenderPlan.Occurrence,
                mutation: Transform3D, origin: Point3D, showsEdges: Bool) throws {
        var bounds = BoundingBox()
        var updateResult: Result<Void, Error> = .success(())
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
          updateResult = Result {
            let vertices = bytes.bindMemory(to: Vertex.self)
            for base in stride(from: 0, to: cornerCount, by: 3) {
                if base.isMultiple(of: 768) { try Task.checkCancellation() }
                for offset in 0..<3 {
                    let source = occurrence.positions[Int(occurrence.vertexIndices[base + offset])]
                    let point = try ViewportWorldTransformAlgebra.transformedPoint(
                        .init(x: source.x, y: source.y, z: source.z), by: mutation)
                    let native = try RealityViewportSpatialBatch.nativePoint(point, relativeTo: origin)
                    vertices[base + offset].position = native
                    bounds.formUnion(.init(min: native, max: native))
                }
                let cross = simd_cross(vertices[base + 1].position - vertices[base].position,
                                       vertices[base + 2].position - vertices[base].position)
                let length = simd_length(cross)
                guard length.isFinite, length > 0 else {
                    throw RealityViewportSpatialBatch.invalid("Object preview collapsed a surface triangle.")
                }
                for offset in 0..<3 { vertices[base + offset].normal = cross / length }
            }
          }
        }
        try updateResult.get()
        var parts: [LowLevelMesh.Part] = [.init(indexCount: cornerCount, topology: .triangle, bounds: bounds)]
        if showsEdges && lineIndexCount > 0 {
            parts.append(.init(indexOffset: cornerCount * MemoryLayout<UInt32>.stride,
                               indexCount: lineIndexCount, topology: .line, materialIndex: 1, bounds: bounds))
        }
        mesh.parts.replaceAll(parts)
    }
}
