import Metal
import simd

/// Owns immutable GPU inputs after one checked CPU-to-GPU publication boundary.
struct OpticalVolumeScene: Sendable {
    let triangles: any MTLBuffer
    let nodes: any MTLBuffer
    let opticalOccurrences: any MTLBuffer
    let mediumCapacity: UInt32
    let triangleCount: UInt32
    let nodeCount: UInt32
    let byteCount: Int
    let limits: OpticalVolumeLimits
    private let storageLease: OpticalVolumeFrameStore.StorageLease

    @MainActor
    init(triangles original: [OpticalVolumeTriangle], opticalOccurrenceIndices: [UInt32], device: any MTLDevice, limits: OpticalVolumeLimits, images: OpticalVolumeFrameStore) throws {
        guard !original.isEmpty, original.count <= Int(UInt32.max) / 2,
              !opticalOccurrenceIndices.isEmpty, opticalOccurrenceIndices.count <= Int(UInt32.max) else {
            throw MeshSourcePresentationRenderError(code: .invalidSceneItem, message: "Optical scene must have addressable original triangles.")
        }
        let occurrenceBytes = try Self.bytes(opticalOccurrenceIndices.count, MemoryLayout<UInt32>.stride)
        let triangleBytes = try Self.bytes(original.count, MemoryLayout<OpticalVolumeTriangle>.stride)
        let nodeBytes = try Self.bytes(original.count * 2 - 1, MemoryLayout<OpticalVolumeNode>.stride)
        let (geometryBytes, geometryOverflow) = triangleBytes.addingReportingOverflow(nodeBytes)
        let (single, sumOverflow) = geometryBytes.addingReportingOverflow(occurrenceBytes)
        let occurrenceFootprint = max(occurrenceBytes, device.heapBufferSizeAndAlign(length: occurrenceBytes, options: .storageModeShared).size)
        let triangleFootprint = max(triangleBytes, device.heapBufferSizeAndAlign(length: triangleBytes, options: .storageModeShared).size)
        let nodeFootprint = max(nodeBytes, device.heapBufferSizeAndAlign(length: nodeBytes, options: .storageModeShared).size)
        guard !geometryOverflow, !sumOverflow else {
            throw MeshSourcePresentationRenderError(code: .resourceExhausted, message: "Optical source storage overflowed.")
        }
        let remaining = try OpticalVolumeStorageBudget.remaining(limit: limits.maxRetainedByteCount,
            used: single, triangleBytes)
        do {
            _ = try OpticalVolumeStorageBudget.remaining(limit: remaining,
                used: occurrenceFootprint, triangleFootprint, nodeFootprint)
        } catch {
            throw MeshSourcePresentationRenderError(code: .resourceExhausted, message: "Optical staging and GPU buffers exceed their shared allowance.")
        }
        let gpuBytes = try Self.sum([occurrenceFootprint, triangleFootprint, nodeFootprint])
        let stagingBytes = geometryBytes
        let stagingLease = try images.retainStorage(bytes: stagingBytes)
        storageLease = try images.retainStorage(bytes: gpuBytes)
        defer { withExtendedLifetime(stagingLease) {} }
        var ordered = original
        var hierarchy: [OpticalVolumeNode] = []
        hierarchy.reserveCapacity(original.count * 2 - 1)
        try Self.append(range: 0..<ordered.count, triangles: &ordered, nodes: &hierarchy)
        // Copies are confined to the Metal upload boundary. Swift staging and
        // GPU immutable storage coexist here and were both admitted above.
        guard let occurrenceBuffer = opticalOccurrenceIndices.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: occurrenceBytes, options: .storageModeShared) }),
              let triangleBuffer = ordered.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: triangleBytes, options: .storageModeShared) }),
              let nodeBuffer = hierarchy.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }) else {
            throw MeshSourcePresentationRenderError(code: .gpuFailure, message: "Optical immutable buffer allocation failed.")
        }
        guard occurrenceBuffer.allocatedSize <= occurrenceFootprint,
              triangleBuffer.allocatedSize <= triangleFootprint, nodeBuffer.allocatedSize <= nodeFootprint else {
            throw MeshSourcePresentationRenderError(code: .resourceExhausted, message: "Optical native source allocation exceeds its admitted footprint.")
        }
        opticalOccurrences = occurrenceBuffer
        mediumCapacity = UInt32(opticalOccurrenceIndices.count)
        triangles = triangleBuffer
        nodes = nodeBuffer
        triangleCount = UInt32(ordered.count)
        nodeCount = UInt32(hierarchy.count)
        byteCount = triangleBuffer.allocatedSize + nodeBuffer.allocatedSize + occurrenceBuffer.allocatedSize
        self.limits = limits
    }

    private static func sum(_ counts: [Int]) throws -> Int {
        var total = 0
        for count in counts {
            let next = total.addingReportingOverflow(count)
            guard count >= 0, !next.overflow else {
                throw MeshSourcePresentationRenderError(code: .resourceExhausted, message: "Optical scene storage sum overflowed.")
            }
            total = next.partialValue
        }
        return total
    }

    private static func bytes(_ count: Int, _ stride: Int) throws -> Int {
        let (value, overflow) = count.multipliedReportingOverflow(by: stride)
        guard !overflow else { throw MeshSourcePresentationRenderError(code: .sizeOverflow, message: "Optical storage size overflowed.") }
        return value
    }

    private static func append(range: Range<Int>, triangles: inout [OpticalVolumeTriangle], nodes: inout [OpticalVolumeNode]) throws {
        try Task.checkCancellation()
        var minimum = triangles[range.lowerBound].minimum
        var maximum = triangles[range.lowerBound].maximum
        for index in range.dropFirst() {
            minimum = simd_min(minimum, triangles[index].minimum)
            maximum = simd_max(maximum, triangles[index].maximum)
        }
        let nodeIndex = nodes.count
        nodes.append(.init(minimum: SIMD4(minimum, 0), maximum: SIMD4(maximum, 0), indices: .zero))
        if range.count == 1 {
            nodes[nodeIndex].indices = [UInt32(range.lowerBound), 1, UInt32(nodes.count), 0]
            return
        }
        let extent = maximum - minimum
        let axis = extent.x >= extent.y && extent.x >= extent.z ? 0 : (extent.y >= extent.z ? 1 : 2)
        // Mutate only this admitted contiguous range. No partition arrays are retained.
        triangles[range].sort { $0.minimum[axis] + $0.maximum[axis] < $1.minimum[axis] + $1.maximum[axis] }
        let middle = range.lowerBound + range.count / 2
        try append(range: range.lowerBound..<middle, triangles: &triangles, nodes: &nodes)
        try append(range: middle..<range.upperBound, triangles: &triangles, nodes: &nodes)
        nodes[nodeIndex].indices = [0, 0, UInt32(nodes.count), 0]
    }
}
