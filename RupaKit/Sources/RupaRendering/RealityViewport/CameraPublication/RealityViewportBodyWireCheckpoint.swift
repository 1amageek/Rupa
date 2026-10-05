import Foundation
import RealityKit

/// Original native body-wire publication for one synchronous camera boundary.
@MainActor
final class RealityViewportBodyWireCheckpoint {
    private struct WireState {
        let entity: ModelEntity
        let model: ModelComponent?
        let transform: Transform
        let enabled: Bool
    }
    private struct RasterState {
        let raster: NativeLineRasterizer
        let mesh: LowLevelMesh
        let vertices: [UInt8]
        let indices: [UInt8]
        let parts: [LowLevelMesh.Part]
    }
    private let wires: [WireState]
    private let rasters: [RasterState]
    private let lease: OpticalVolumeFrameStore.StorageLease

    init(entities: [(surface: ModelEntity, lines: ModelEntity?)],
        rasterSources: [Int: NativeLineRasterizer], images: OpticalVolumeFrameStore) throws {
        var bytes = MemoryLayout<RealityViewportBodyWireCheckpoint>.stride
        func charge(_ count: Int, _ stride: Int) throws {
            let size = count.multipliedReportingOverflow(by: stride)
            let sum = bytes.addingReportingOverflow(size.partialValue)
            guard count >= 0, !size.overflow, !sum.overflow else { throw RealityViewportSpatialBatch.exhausted() }
            bytes = sum.partialValue
        }
        try charge(entities.count, MemoryLayout<WireState>.stride)
        try charge(rasterSources.count, MemoryLayout<RasterState>.stride + MemoryLayout<(Int, NativeLineRasterizer)>.stride)
        for entry in entities {
            try Task.checkCancellation()
            if let materials = entry.lines?.model?.materials {
                try charge(materials.count, MemoryLayout<any Material>.stride)
            }
        }
        for raster in rasterSources.values {
            try Task.checkCancellation()
            let mesh = raster.mesh
            var count = 0
            mesh.withUnsafeBytes(bufferIndex: 0) { count = $0.count }
            try charge(count, MemoryLayout<UInt8>.stride)
            mesh.withUnsafeIndices { count = $0.count }
            try charge(count, MemoryLayout<UInt8>.stride)
            try charge(mesh.parts.count, MemoryLayout<LowLevelMesh.Part>.stride)
        }
        let admittedLease = try images.retainStorage(bytes: bytes)
        var capturedWires: [WireState] = []; var capturedRasters: [RasterState] = []
        capturedWires.reserveCapacity(entities.count); capturedRasters.reserveCapacity(rasterSources.count)
        for entry in entities {
            try Task.checkCancellation()
            if let entity = entry.lines {
                capturedWires.append(.init(entity: entity, model: entity.model,
                    transform: entity.transform, enabled: entity.isEnabled))
            }
        }
        for raster in rasterSources.values {
            try Task.checkCancellation()
            let mesh = raster.mesh
            // Admitted owned bytes survive later native writes; scoped borrows do not escape.
            var vertices: [UInt8] = [], indices: [UInt8] = []
            mesh.withUnsafeBytes(bufferIndex: 0) { vertices = Array($0) }
            mesh.withUnsafeIndices { indices = Array($0) }
            capturedRasters.append(.init(raster: raster, mesh: mesh, vertices: vertices,
                indices: indices, parts: Array(mesh.parts)))
        }
        wires = capturedWires; rasters = capturedRasters; lease = admittedLease
    }

    func restore() throws {
        for state in rasters {
            var count = 0
            state.mesh.withUnsafeBytes(bufferIndex: 0) { count = $0.count }
            guard count == state.vertices.count else { throw RealityViewportSpatialBatch.invalid("Original body wire vertex capacity changed.") }
            state.mesh.withUnsafeIndices { count = $0.count }
            guard count == state.indices.count else { throw RealityViewportSpatialBatch.invalid("Original body wire index capacity changed.") }
        }
        for state in rasters {
            state.mesh.withUnsafeMutableBytes(bufferIndex: 0) { destination in
                state.vertices.withUnsafeBytes { destination.copyMemory(from: $0) }
            }
            state.mesh.withUnsafeMutableIndices { destination in
                state.indices.withUnsafeBytes { destination.copyMemory(from: $0) }
            }
            state.mesh.parts.replaceAll(state.parts)
            try state.raster.restorePublishedMesh(state.mesh)
        }
        for state in wires {
            state.entity.model = state.model; state.entity.transform = state.transform
            state.entity.isEnabled = state.enabled
        }
    }
}
