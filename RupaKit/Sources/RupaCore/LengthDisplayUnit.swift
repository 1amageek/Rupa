import Foundation

public enum LengthDisplayUnit: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case micrometer
    case millimeter
    case centimeter
    case meter
    case inch
    case foot

    public var id: String {
        rawValue
    }

    public var symbol: String {
        switch self {
        case .micrometer:
            "μm"
        case .millimeter:
            "mm"
        case .centimeter:
            "cm"
        case .meter:
            "m"
        case .inch:
            "in"
        case .foot:
            "ft"
        }
    }

    public var metersPerUnit: Double {
        switch self {
        case .micrometer:
            0.000_001
        case .millimeter:
            0.001
        case .centimeter:
            0.01
        case .meter:
            1.0
        case .inch:
            0.0254
        case .foot:
            0.3048
        }
    }

    public func meters(from value: Double) -> Double {
        value * metersPerUnit
    }

    public func value(fromMeters value: Double) -> Double {
        value / metersPerUnit
    }
}
