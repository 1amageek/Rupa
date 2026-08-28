import Foundation

public struct CADPoint3D: Codable, Equatable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double
    public let unit: CADLengthUnit

    public init(x: Double, y: Double, z: Double, unit: CADLengthUnit = .millimeter) {
        self.x = x
        self.y = y
        self.z = z
        self.unit = unit
    }

    public var meters: CADPoint3D {
        CADPoint3D(
            x: x * unit.metersPerUnit,
            y: y * unit.metersPerUnit,
            z: z * unit.metersPerUnit,
            unit: .meter
        )
    }

    public var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite && meters.x.isFinite && meters.y.isFinite && meters.z.isFinite
    }

    public func validate(caseID: CADBenchmarkCaseID, field: String = "point") throws {
        guard isFinite else {
            throw CADBenchmarkError.invalidInput(caseID: caseID.rawValue, reason: "Non-finite \(field).")
        }
    }
}
