import Foundation

public enum GeometryAttributeStorage: Codable, Equatable, Sendable {
    case boolean(GeometryBuffer<Bool>)
    case int32(GeometryBuffer<Int32>)
    case float32(GeometryBuffer<Float>)
    case float64(GeometryBuffer<Double>)
    case vector2(GeometryBuffer<GeometryVector2D>)
    case vector3(GeometryBuffer<GeometryPoint3D>)
    case vector4(GeometryBuffer<GeometryVector4D>)

    public var count: Int {
        switch self {
        case .boolean(let values):
            values.count
        case .int32(let values):
            values.count
        case .float32(let values):
            values.count
        case .float64(let values):
            values.count
        case .vector2(let values):
            values.count
        case .vector3(let values):
            values.count
        case .vector4(let values):
            values.count
        }
    }

    public var valueType: GeometryAttributeValueType {
        switch self {
        case .boolean:
            .boolean
        case .int32:
            .int32
        case .float32:
            .float32
        case .float64:
            .float64
        case .vector2:
            .vector2
        case .vector3:
            .vector3
        case .vector4:
            .vector4
        }
    }
}
