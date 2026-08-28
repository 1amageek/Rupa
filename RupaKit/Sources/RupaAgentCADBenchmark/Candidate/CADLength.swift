import Foundation

public struct CADLength: Codable, Equatable, Hashable, Sendable {
    public let value: Double
    public let unit: CADLengthUnit

    public init(value: Double, unit: CADLengthUnit = .millimeter) {
        self.value = value
        self.unit = unit
    }

    public var meters: Double {
        value * unit.metersPerUnit
    }

    public func validate(caseID: CADBenchmarkCaseID, field: String, allowsZero: Bool = false) throws {
        guard value.isFinite, meters.isFinite else {
            throw CADBenchmarkError.invalidDimension(
                caseID: caseID.rawValue,
                field: field,
                value: value
            )
        }
        if allowsZero == false && meters <= 0.0 {
            throw CADBenchmarkError.invalidDimension(
                caseID: caseID.rawValue,
                field: field,
                value: value
            )
        }
        if allowsZero && meters < 0.0 {
            throw CADBenchmarkError.invalidDimension(
                caseID: caseID.rawValue,
                field: field,
                value: value
            )
        }
    }
}
