import RealityKit
import Foundation

/// Original mounted decoration state for one synchronous publication boundary.
@MainActor
final class RealityViewportSpatialCameraCheckpoint {
    struct Footprint {
        let bytes: Int
        let entities: Int
        let meshes: Int
    }
    private struct EntityState {
        let entity: Entity
        let parent: Entity?
        let transform: Transform
        let enabled: Bool
        let model: ModelComponent?
    }
    private struct MeshState {
        let mesh: LowLevelMesh
        let bytes: [UInt8]
        let indices: [UInt8]
        let parts: [LowLevelMesh.Part]
    }
    let owner: Entity
    let byteCount: Int
    private let entities: [EntityState]
    private let meshes: [MeshState]
    private let lease: OpticalVolumeFrameStore.StorageLease?
    private let release: @MainActor () -> Void
    private let restoreLogicalState: @MainActor () throws -> Void

    static func measure(owner: Entity, secondary: Entity,
        additionalBytes: Int, visitMeshes: (((LowLevelMesh) throws -> Void) throws -> Void)
    ) throws -> Footprint {
        var bytes = additionalBytes; var entities = 0; var meshes = 0
        guard bytes >= 0 else { throw RealityViewportSpatialBatch.exhausted() }
        func charge(_ count: Int, _ stride: Int) throws {
            let size = count.multipliedReportingOverflow(by: stride)
            let sum = bytes.addingReportingOverflow(size.partialValue)
            guard count >= 0, !size.overflow, !sum.overflow else { throw RealityViewportSpatialBatch.exhausted() }
            bytes = sum.partialValue
        }
        func visit(_ entity: Entity) throws {
            try Task.checkCancellation()
            if entity === owner || entity === secondary {
                for child in entity.children { try visit(child) }
                return
            }
            try charge(1, MemoryLayout<EntityState>.stride)
            let count = entities.addingReportingOverflow(1)
            guard !count.overflow else { throw RealityViewportSpatialBatch.exhausted() }
            entities = count.partialValue
            for child in entity.children { try visit(child) }
        }
        for child in owner.children { try visit(child) }
        for child in secondary.children { try visit(child) }
        try visitMeshes { mesh in
            try charge(1, MemoryLayout<MeshState>.stride)
            var count = 0
            mesh.withUnsafeBytes(bufferIndex: 0) { count = $0.count }
            try charge(count, MemoryLayout<UInt8>.stride)
            mesh.withUnsafeIndices { count = $0.count }
            try charge(count, MemoryLayout<UInt8>.stride)
            try charge(mesh.parts.count, MemoryLayout<LowLevelMesh.Part>.stride)
            let next = meshes.addingReportingOverflow(1)
            guard !next.overflow else { throw RealityViewportSpatialBatch.exhausted() }
            meshes = next.partialValue
        }
        return Footprint(bytes: bytes, entities: entities, meshes: meshes)
    }

    init(owner: Entity, secondary: Entity, footprint: Footprint,
         visitMeshes: (((LowLevelMesh) throws -> Void) throws -> Void),
         lease: OpticalVolumeFrameStore.StorageLease?,
         restoreLogicalState: @escaping @MainActor () throws -> Void,
         release: @escaping @MainActor () -> Void) throws {
        var entityStates: [EntityState] = []; var meshStates: [MeshState] = []
        entityStates.reserveCapacity(footprint.entities); meshStates.reserveCapacity(footprint.meshes)
        func visit(_ entity: Entity) throws {
            try Task.checkCancellation()
            if entity === owner || entity === secondary {
                for child in entity.children { try visit(child) }
                return
            }
            guard entityStates.count < footprint.entities else { throw RealityViewportSpatialBatch.exhausted() }
            entityStates.append(EntityState(entity: entity, parent: entity.parent, transform: entity.transform,
                enabled: entity.isEnabled, model: entity.components[ModelComponent.self]))
            for child in entity.children { try visit(child) }
        }
        for child in owner.children { try visit(child) }
        for child in secondary.children { try visit(child) }
        try visitMeshes { mesh in
            try Task.checkCancellation()
            guard meshStates.count < footprint.meshes else { throw RealityViewportSpatialBatch.exhausted() }
            // These admitted owned bytes are required to restore the previous actual
            // Native buffer after a later sibling fails; the SDK borrow never escapes.
            var bytes: [UInt8] = []
            mesh.withUnsafeBytes(bufferIndex: 0) { bytes = Array($0) }
            var indices: [UInt8] = []
            mesh.withUnsafeIndices { indices = Array($0) }
            meshStates.append(MeshState(mesh: mesh, bytes: bytes, indices: indices, parts: Array(mesh.parts)))
        }
        guard entityStates.count == footprint.entities, meshStates.count == footprint.meshes else {
            throw RealityViewportSpatialBatch.invalid("Spatial checkpoint source changed during synchronous capture.")
        }
        self.owner = owner; byteCount = footprint.bytes; entities = entityStates; meshes = meshStates
        self.lease = lease; self.restoreLogicalState = restoreLogicalState; self.release = release
    }

    func restore(owner: Entity) throws {
        guard self.owner === owner else { throw RealityViewportSpatialBatch.invalid("Spatial checkpoint belongs to another source owner.") }
        // Validate every native capacity before changing any original buffer.
        for state in meshes {
            var count = 0
            state.mesh.withUnsafeBytes(bufferIndex: 0) { count = $0.count }
            guard count == state.bytes.count else {
                throw RealityViewportSpatialBatch.invalid("Spatial checkpoint Native buffer capacity changed.")
            }
            state.mesh.withUnsafeIndices { count = $0.count }
            guard count == state.indices.count else {
                throw RealityViewportSpatialBatch.invalid("Spatial checkpoint Native index capacity changed.")
            }
        }
        for state in meshes {
            state.mesh.withUnsafeMutableBytes(bufferIndex: 0) { destination in
                state.bytes.withUnsafeBytes { destination.copyMemory(from: $0) }
            }
            state.mesh.withUnsafeMutableIndices { destination in
                state.indices.withUnsafeBytes { destination.copyMemory(from: $0) }
            }
            state.mesh.parts.replaceAll(state.parts)
        }
        try restoreLogicalState()
        for state in entities {
            if state.entity.parent !== state.parent {
                state.entity.removeFromParent()
                state.parent?.addChild(state.entity)
            }
            state.entity.transform = state.transform; state.entity.isEnabled = state.enabled
            if let model = state.model { state.entity.components.set(model) }
            else { state.entity.components.remove(ModelComponent.self) }
        }
    }

    isolated deinit { release() }
}
