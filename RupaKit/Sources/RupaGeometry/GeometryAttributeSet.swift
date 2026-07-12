import Foundation

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
