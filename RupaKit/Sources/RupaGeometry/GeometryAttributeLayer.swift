import Foundation

public struct GeometryAttributeLayer: Codable, Equatable, Sendable {
    public var descriptor: GeometryAttributeDescriptor
    public var values: GeometryAttributeStorage
    public var indices: GeometryBuffer<UInt32>?

    public init(
        descriptor: GeometryAttributeDescriptor,
        values: GeometryAttributeStorage,
        indices: GeometryBuffer<UInt32>? = nil
    ) {
        self.descriptor = descriptor
        self.values = values
        self.indices = indices
    }

    public func validate(counts: GeometryAttributeDomainCounts) throws {
        try descriptor.validate()
        guard descriptor.valueType == values.valueType else {
            throw MeshSourceError(
                code: .invalidBuffer,
                message: "Geometry attribute storage type does not match its descriptor."
            )
        }
        let domainCount = counts.count(for: descriptor.domain)
        if descriptor.isSparse {
            guard let indices else {
                throw MeshSourceError(
                    code: .invalidBuffer,
                    message: "Sparse geometry attributes must provide indices."
                )
            }
            guard indices.count == values.count else {
                throw MeshSourceError(
                    code: .invalidBuffer,
                    message: "Sparse geometry attribute indices and values must have equal counts."
                )
            }
            guard Set(indices).count == indices.count else {
                throw MeshSourceError(
                    code: .invalidBuffer,
                    message: "Sparse geometry attribute indices must be unique."
                )
            }
            guard indices.allSatisfy({ Int($0) < domainCount }) else {
                throw MeshSourceError(
                    code: .invalidReference,
                    message: "Sparse geometry attribute indices must reference their domain."
                )
            }
        } else {
            guard indices == nil, values.count == domainCount else {
                throw MeshSourceError(
                    code: .invalidBuffer,
                    message: "Dense geometry attributes must match their domain count."
                )
            }
        }
        try validateFiniteValues()
    }

    private func validateFiniteValues() throws {
        switch values {
        case .boolean, .int32:
            break
        case .float32(let values):
            guard values.allSatisfy({ $0.isFinite }) else {
                throw MeshSourceError(
                    code: .invalidBuffer,
                    message: "Float attributes must be finite."
                )
            }
        case .float64(let values):
            guard values.allSatisfy({ $0.isFinite }) else {
                throw MeshSourceError(
                    code: .invalidBuffer,
                    message: "Double attributes must be finite."
                )
            }
        case .vector2(let values):
            for value in values {
                try value.validate()
            }
        case .vector3(let values):
            for value in values {
                try value.validate()
            }
        case .vector4(let values):
            for value in values {
                try value.validate()
            }
        }
    }
}
