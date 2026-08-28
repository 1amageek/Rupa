import Foundation

public struct CADAngle: Codable, Equatable, Hashable, Sendable {
    public let value: Double
    public let unit: CADAngleUnit

    public init(value: Double, unit: CADAngleUnit = .degree) {
        self.value = value
        self.unit = unit
    }

    public var radians: Double {
        value * unit.radiansPerUnit
    }

    public func validate(caseID: CADBenchmarkCaseID, field: String) throws {
        guard value.isFinite, radians.isFinite, radians > 0.0, radians < (2.0 * .pi) else {
            throw CADBenchmarkError.invalidDimension(
                caseID: caseID.rawValue,
                field: field,
                value: value
            )
        }
    }
}
