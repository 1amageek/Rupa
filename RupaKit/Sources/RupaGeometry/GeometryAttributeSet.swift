import Foundation
import RupaCoreTypes

public struct GeometryAttributeSet: Codable, Equatable, Sendable {
    private var layers: [GeometryAttributeID: GeometryAttributeLayer]

    public init() {
        self.layers = [:]
    }

    public init(layers: [GeometryAttributeLayer]) throws {
        var indexed: [GeometryAttributeID: GeometryAttributeLayer] = [:]
        for layer in layers {
            guard indexed[layer.descriptor.id] == nil else {
                throw MeshSourceError(
                    code: .duplicateID,
                    message: "Geometry attribute IDs must be unique."
                )
            }
            indexed[layer.descriptor.id] = layer
        }
        self.layers = indexed
    }

    public var count: Int {
        layers.count
    }

    /// Counts attribute value and sparse-index records without traversing either buffer.
    func scanRecordCount() throws -> Int {
        var count = 0
        for layer in layers.values {
            let valueCount = count.addingReportingOverflow(layer.values.count)
            guard !valueCount.overflow else {
                throw MeshSourceError(
                    code: .invalidBuffer,
                    message: "Geometry attribute value scan record count overflowed."
                )
            }
            count = valueCount.partialValue
            if let indices = layer.indices {
                let indexCount = count.addingReportingOverflow(indices.count)
                guard !indexCount.overflow else {
                    throw MeshSourceError(
                        code: .invalidBuffer,
                        message: "Geometry attribute index scan record count overflowed."
                    )
                }
                count = indexCount.partialValue
            }
        }
        return count
    }

    public func layer(for id: GeometryAttributeID) -> GeometryAttributeLayer? {
        layers[id]
    }

    public func sortedLayers() -> [GeometryAttributeLayer] {
        layers.values.sorted { $0.descriptor.id.rawValue < $1.descriptor.id.rawValue }
    }

    public func setting(_ layer: GeometryAttributeLayer) throws -> GeometryAttributeSet {
        var result = self
        result.layers[layer.descriptor.id] = layer
        return result
    }

    public func validate(counts: GeometryAttributeDomainCounts) throws {
        for (id, layer) in layers {
            guard id == layer.descriptor.id else {
                throw MeshSourceError(
                    code: .invalidIdentity,
                    message: "Geometry attribute dictionary keys must match descriptor IDs."
                )
            }
            try layer.validate(counts: counts)
        }
    }
}

extension GeometryAttributeSet {
    /// The resident bytes every layer's values and sparse indices account for.
    ///
    /// Attribute storage stays resident for as long as the mesh does, so a
    /// budget that charges a mesh must charge its layers with it.
    public func estimatedByteCount() throws -> Int {
        var byteCount = 0
        for layer in sortedLayers() {
            byteCount = try MeshResourceUsage.sum(
                byteCount,
                try MeshResourceUsage.product(
                    layer.values.count,
                    layer.values.valueType.stride
                )
            )
            if let indices = layer.indices {
                byteCount = try MeshResourceUsage.sum(
                    byteCount,
                    try MeshResourceUsage.product(
                        indices.count,
                        MemoryLayout<UInt32>.stride
                    )
                )
            }
        }
        return byteCount
    }
}
