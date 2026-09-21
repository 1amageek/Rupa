import Foundation

public struct CADPlaneFrame: Codable, Equatable, Hashable, Sendable {
    public let orientation: CADSketchPlane
    public let origin: CADPoint3D

    public init(orientation: CADSketchPlane, origin: CADPoint3D) {
        self.orientation = orientation
        self.origin = origin
    }

    public var normal: CADDirection3D {
        orientation.normal
    }

    public func signedNormalDistance(to point: CADPoint3D) -> Double {
        let frameOrigin = origin.meters
        let candidate = point.meters
        return (candidate.x - frameOrigin.x) * normal.x
            + (candidate.y - frameOrigin.y) * normal.y
            + (candidate.z - frameOrigin.z) * normal.z
    }

    public func validate(caseID: CADBenchmarkCaseID) throws {
        try origin.validate(caseID: caseID, field: "plane.origin")
    }
}
