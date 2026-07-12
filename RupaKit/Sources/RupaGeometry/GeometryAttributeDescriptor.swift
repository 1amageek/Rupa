import Foundation

public struct GeometryAttributeDescriptor: Codable, Equatable, Sendable {
    public var id: GeometryAttributeID
    public var name: String
    public var domain: GeometryAttributeDomain
    public var valueType: GeometryAttributeValueType
    public var interpolation: GeometryAttributeInterpolation
    public var isSparse: Bool

    public init(
        id: GeometryAttributeID,
        name: String,
        domain: GeometryAttributeDomain,
        valueType: GeometryAttributeValueType,
        interpolation: GeometryAttributeInterpolation,
        isSparse: Bool = false
    ) {
        self.id = id
        self.name = name
        self.domain = domain
        self.valueType = valueType
        self.interpolation = interpolation
        self.isSparse = isSparse
    }

    public func validate() throws {
        try id.validate()
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeshSourceError(
                code: .invalidIdentity,
                message: "Geometry attribute names must not be empty."
            )
        }
        if interpolation == .linear {
            switch valueType {
            case .boolean, .int32:
                throw MeshSourceError(
                    code: .invalidBuffer,
                    message: "Boolean and integer attributes cannot use linear interpolation."
                )
            case .float32, .float64, .vector2, .vector3, .vector4:
                break
            }
        }
    }
}
