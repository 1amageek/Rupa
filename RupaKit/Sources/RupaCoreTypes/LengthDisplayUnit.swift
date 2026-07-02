import Foundation

public enum LengthDisplayUnit: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case micrometer
    case millimeter
    case centimeter
    case meter
    case kilometer
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
        case .kilometer:
            "km"
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
        case .kilometer:
            1_000.0
        case .inch:
            0.0254
        case .foot:
            0.3048
        }
    }

    public var isMetric: Bool {
        switch self {
        case .micrometer, .millimeter, .centimeter, .meter, .kilometer:
            true
        case .inch, .foot:
            false
        }
    }

    public func readableUnit(forMeters meters: Double) -> LengthDisplayUnit {
        let magnitude = abs(meters)
        guard magnitude.isFinite, magnitude > 0.0 else {
            return self
        }

        if isMetric {
            let preferredValue = abs(value(fromMeters: magnitude))
            if preferredValue >= 0.1, preferredValue < 1_000.0 {
                return self
            }
            return Self.readableMetricUnit(forMeters: magnitude)
        }

        switch self {
        case .inch where abs(value(fromMeters: magnitude)) >= 12.0:
            return .foot
        case .foot where abs(value(fromMeters: magnitude)) < 1.0:
            return .inch
        default:
            return self
        }
    }

    public static func readableMetricUnit(forMeters meters: Double) -> LengthDisplayUnit {
        let magnitude = abs(meters)
        guard magnitude.isFinite, magnitude > 0.0 else {
            return .meter
        }
        if magnitude >= 1_000.0 {
            return .kilometer
        }
        if magnitude >= 1.0 {
            return .meter
        }
        if magnitude >= 0.01 {
            return .centimeter
        }
        if magnitude >= 0.001 {
            return .millimeter
        }
        return .micrometer
    }

    public func meters(from value: Double) -> Double {
        value * metersPerUnit
    }

    public func value(fromMeters value: Double) -> Double {
        value / metersPerUnit
    }
}
