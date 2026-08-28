import Foundation

public struct CADDirection3D: Codable, Equatable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public var length: Double {
        hypot(hypot(x, y), z)
    }

    public var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite && length.isFinite
    }

    public func validate(caseID: CADBenchmarkCaseID, field: String = "direction") throws {
        guard isFinite, length > 0.0 else {
            throw CADBenchmarkError.invalidDirection(caseID: caseID.rawValue, field: field)
        }
    }
}
