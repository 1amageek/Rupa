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

    private struct Frame {
        let mesh: LowLevelMesh
        let resource: MeshResource
        let wireSource: LowLevelMesh
    }
    private let firstFrame: Frame
    private let secondFrame: Frame
    private var activeFirst = true
    private var stageReady = false
    private var activeFrame: Frame { activeFirst ? firstFrame : secondFrame }
    private var inactiveFrame: Frame { activeFirst ? secondFrame : firstFrame }
    var mesh: LowLevelMesh { activeFrame.mesh }
    var resource: MeshResource { activeFrame.resource }
    var wireSource: LowLevelMesh { activeFrame.wireSource }
    var stagedMesh: LowLevelMesh? { stageReady ? inactiveFrame.mesh : nil }
    var stagedResource: MeshResource? { stageReady ? inactiveFrame.resource : nil }
    var stagedWireSource: LowLevelMesh? { stageReady ? inactiveFrame.wireSource : nil }
    let byteCount: Int
    private let sourceOccurrence: MeshSourcePresentationRenderPlan.Occurrence
    private let cornerCount: Int
    private let lineIndexCount: Int

    init(occurrence: MeshSourcePresentationRenderPlan.Occurrence, availableBytes: Int) throws {
        let cornerCount = occurrence.vertexIndices.count
        let lineIndexCount = occurrence.boundaryIndexCount
        self.sourceOccurrence = occurrence
        self.cornerCount = cornerCount
        self.lineIndexCount = lineIndexCount
        guard cornerCount >= 0, cornerCount <= Int(UInt32.max), cornerCount.isMultiple(of: 3),
              occurrence.boundaryCornerIndices.count == cornerCount, lineIndexCount >= 0,
              lineIndexCount.isMultiple(of: 2) else {
            throw RealityViewportSpatialBatch.exhausted()
        }
        var boundaryCount = 0
        for marker in occurrence.boundaryCornerIndices where marker != UInt32.max {
            let next = boundaryCount.addingReportingOverflow(2)
            guard !next.overflow else { throw RealityViewportSpatialBatch.exhausted() }
            boundaryCount = next.partialValue
        }
        guard boundaryCount == lineIndexCount else { throw RealityViewportSpatialBatch.invalid("Original preview boundary count differs from its authored indices.") }
        var admittedBytes = MemoryLayout<LowLevelMesh.Part>.stride * 8 + MemoryLayout<MeshSourcePresentationRenderPlan.Occurrence>.stride
        for (count, stride) in [(cornerCount, MemoryLayout<Vertex>.stride + MemoryLayout<UInt32>.stride),
                               (lineIndexCount, 2 * MemoryLayout<UInt32>.stride),
                               (cornerCount, MemoryLayout<SIMD3<Float>>.stride)] {
            let amount = count.multipliedReportingOverflow(by: stride * 2)
            let total = admittedBytes.addingReportingOverflow(amount.partialValue)
            guard !amount.overflow, !total.overflow, total.partialValue <= availableBytes else {
                throw RealityViewportSpatialBatch.exhausted()
            }
            admittedBytes = total.partialValue
        }
        byteCount = admittedBytes
        func allocateFrame() throws -> Frame {
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
            let wireSource = try LowLevelMesh(descriptor: .init(vertexCapacity: cornerCount,
                vertexAttributes: [.init(semantic: .position, format: .float3, offset: 0)],
                vertexLayouts: [.init(bufferIndex: 0, bufferStride: MemoryLayout<SIMD3<Float>>.stride)],
                indexCapacity: lineIndexCount, indexType: .uint32))
            wireSource.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
                let vertices = bytes.bindMemory(to: SIMD3<Float>.self)
                for index in vertices.indices { vertices[index] = .zero }
            }
            wireSource.withUnsafeMutableIndices { bytes in
                let indices = bytes.bindMemory(to: UInt32.self)
                for index in indices.indices { indices[index] = 0 }
                var output = 0
                for corner in 0..<cornerCount where occurrence.boundaryCornerIndices[corner] != UInt32.max {
                    indices[output] = UInt32(corner)
                    indices[output + 1] = UInt32(corner - corner % 3 + (corner % 3 + 1) % 3)
                    output += 2
                }
            }
            wireSource.parts.replaceAll([.init(indexCount: lineIndexCount, topology: .line,
                bounds: .init(min: .zero, max: .zero))])
            return Frame(mesh: mesh, resource: try RealityViewport.nativeResource(from: mesh), wireSource: wireSource)
        }
        firstFrame = try allocateFrame()
        secondFrame = try allocateFrame()
    }

    func update(occurrence: MeshSourcePresentationRenderPlan.Occurrence,
                mutation: Transform3D, origin: Point3D, showsEdges: Bool) throws {
        try stage(occurrence: occurrence, mutation: mutation, origin: origin, showsEdges: showsEdges)
        try commit()
    }

    func stage(occurrence: MeshSourcePresentationRenderPlan.Occurrence,
               mutation: Transform3D, origin: Point3D, showsEdges: Bool) throws {
        stageReady = false
        let mesh = inactiveFrame.mesh
        let wireSource = inactiveFrame.wireSource
        guard occurrence.occurrenceID == sourceOccurrence.occurrenceID,
              occurrence.presentationID == sourceOccurrence.presentationID,
              occurrence.sourceBodyID == sourceOccurrence.sourceBodyID,
              occurrence.sourceFeatureID == sourceOccurrence.sourceFeatureID,
              occurrence.outputRole == sourceOccurrence.outputRole,
              occurrence.definitionID == sourceOccurrence.definitionID,
              occurrence.representationID == sourceOccurrence.representationID,
              occurrence.sourceReference == sourceOccurrence.sourceReference,
              occurrence.positions == sourceOccurrence.positions,
              occurrence.vertexIndices == sourceOccurrence.vertexIndices,
              occurrence.boundaryCornerIndices == sourceOccurrence.boundaryCornerIndices,
              occurrence.vertexIndices.count == cornerCount, occurrence.boundaryIndexCount == lineIndexCount else {
            throw RealityViewportSpatialBatch.invalid("Object preview source capacity changed.")
        }
        var bounds = BoundingBox()
        let m = mutation.matrix.values
        let determinant = m[0] * (m[5] * m[10] - m[6] * m[9])
            - m[1] * (m[4] * m[10] - m[6] * m[8]) + m[2] * (m[4] * m[9] - m[5] * m[8])
        guard determinant.isFinite else { throw RealityViewportSpatialBatch.invalid("Object preview basis is not finite.") }
        let reflected = determinant < 0
        var updateResult: Result<Void, Error> = .success(())
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
          mesh.withUnsafeMutableIndices { indexBytes in
          updateResult = Result {
            let vertices = bytes.bindMemory(to: Vertex.self)
            let indices = indexBytes.bindMemory(to: UInt32.self)
            for base in stride(from: 0, to: cornerCount, by: 3) {
                if base.isMultiple(of: 768) { try Task.checkCancellation() }
                for offset in 0..<3 {
                    guard let positionIndex = Int(exactly: occurrence.vertexIndices[base + offset]),
                          occurrence.positions.indices.contains(positionIndex) else {
                        throw RealityViewportSpatialBatch.invalid("Object preview original position index is absent.")
                    }
                    let source = occurrence.positions[positionIndex]
                    let point = try ViewportWorldTransformAlgebra.transformedPoint(
                        .init(x: source.x, y: source.y, z: source.z), by: mutation)
                    let native = try RealityViewportSpatialBatch.nativePoint(point, relativeTo: origin)
                    vertices[base + offset].position = native
                    bounds.formUnion(.init(min: native, max: native))
                }
                let cross = simd_cross(vertices[base + 1].position - vertices[base].position,
                                       vertices[base + 2].position - vertices[base].position)
                let length = simd_length(cross)
                guard length.isFinite else {
                    throw RealityViewportSpatialBatch.invalid("Object preview normal is not finite.")
                }
                // Zero-area faces draw no fragments; retain finite attributes
                // and restore their indices when the drag crosses the plane.
                let normal: SIMD3<Float> = length > 0 ? cross / length * (reflected ? -1 : 1) : [0, 0, 1]
                for offset in 0..<3 { vertices[base + offset].normal = normal }
                indices[base] = UInt32(base)
                indices[base + 1] = UInt32(length == 0 ? base : base + (reflected ? 2 : 1))
                indices[base + 2] = UInt32(length == 0 ? base : base + (reflected ? 1 : 2))
            }
          }
          }
        }
        try updateResult.get()
        // The wire producer uses the exact native shaded positions, not another
        // independently rounded transform or a proxy. Borrows are synchronous.
        mesh.withUnsafeBytes(bufferIndex: 0) { shadedBytes in
            wireSource.withUnsafeMutableBytes(bufferIndex: 0) { wireBytes in
                let shaded = shadedBytes.bindMemory(to: Vertex.self)
                let wire = wireBytes.bindMemory(to: SIMD3<Float>.self)
                for index in 0..<cornerCount { wire[index] = shaded[index].position }
            }
        }
        wireSource.parts.replaceAll([.init(indexCount: lineIndexCount, topology: .line, bounds: bounds)])
        var parts: [LowLevelMesh.Part] = [.init(indexCount: cornerCount, topology: .triangle, bounds: bounds)]
        if showsEdges && lineIndexCount > 0 {
            parts.append(.init(indexOffset: cornerCount * MemoryLayout<UInt32>.stride,
                               indexCount: lineIndexCount, topology: .line, materialIndex: 1, bounds: bounds))
        }
        mesh.parts.replaceAll(parts)
        stageReady = true
    }
    func validateStagedFrame() throws {
        guard stageReady else { throw RealityViewportSpatialBatch.invalid("Object preview has no complete staged frame.") }
    }

    func commit() throws {
        try validateStagedFrame()
        activeFirst.toggle()
        stageReady = false
    }

    func discardStagedFrame() { stageReady = false }

}
