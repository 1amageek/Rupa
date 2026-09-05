public enum GeometryAttributeValueType: String, Codable, Equatable, Hashable, Sendable {
    case boolean
    case int32
    case float32
    case float64
    case vector2
    case vector3
    case vector4
}

extension GeometryAttributeValueType {
    /// The resident bytes one stored value of this type accounts for.
    public var stride: Int {
        switch self {
        case .boolean: MemoryLayout<Bool>.stride
        case .int32: MemoryLayout<Int32>.stride
        case .float32: MemoryLayout<Float>.stride
        case .float64: MemoryLayout<Double>.stride
        case .vector2: MemoryLayout<GeometryVector2D>.stride
        case .vector3: MemoryLayout<GeometryPoint3D>.stride
        case .vector4: MemoryLayout<GeometryVector4D>.stride
        }
    }
}
