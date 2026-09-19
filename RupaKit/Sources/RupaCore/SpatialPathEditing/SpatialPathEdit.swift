import Foundation
import SwiftCAD

public enum SpatialPathEdit: Codable, Equatable, Sendable {
    case move(knotID: UUID, handle: SpatialPathFeature.Handle, point: Point3D)
    case setMode(knotID: UUID, mode: SpatialPathKnot.Mode)
    case insert(after: UUID, fraction: Double)
    case remove(knotID: UUID)
    case setClosed(Bool)
    case reverse

    public func applying(to path: SpatialPathFeature, tolerance: ModelingTolerance) throws -> SpatialPathFeature {
        var result = path
        switch self {
        case let .move(id, handle, point):
            try result.move(knotID: id, handle: handle, to: point, tolerance: tolerance)
        case let .setMode(id, mode):
            try result.setMode(mode, knotID: id, tolerance: tolerance)
        case let .insert(id, fraction):
            try result.insert(after: id, fraction: fraction, tolerance: tolerance)
        case let .remove(id):
            try result.remove(knotID: id, tolerance: tolerance)
        case let .setClosed(closed):
            result.isClosed = closed
        case .reverse:
            try result.reverse(tolerance: tolerance)
        }
        try result.validate(tolerance: tolerance)
        return result
    }
}
