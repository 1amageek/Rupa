import SwiftCAD

enum BSplineSurfaceBoundarySide: String, Codable, CaseIterable, Sendable {
    case vMin
    case uMax
    case vMax
    case uMin

    init(trimEdgeIndex: Int, owner: String) throws {
        switch trimEdgeIndex {
        case 0:
            self = .vMin
        case 1:
            self = .uMax
        case 2:
            self = .vMax
        case 3:
            self = .uMin
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a direct B-spline rectangular outer trim edge."
            )
        }
    }

    var boundaryDirection: SurfaceParameterDirection {
        switch self {
        case .vMin, .vMax:
            return .u
        case .uMin, .uMax:
            return .v
        }
    }

    var inwardDirection: SurfaceParameterDirection {
        switch self {
        case .vMin, .vMax:
            return .v
        case .uMin, .uMax:
            return .u
        }
    }

    var usesReversedInwardParameter: Bool {
        switch self {
        case .vMin, .uMin:
            return false
        case .vMax, .uMax:
            return true
        }
    }

    func inwardIndex(offset: Int, in surface: BSplineSurface3D) -> Int {
        switch self {
        case .vMin:
            return offset
        case .vMax:
            return surface.vControlPointCount - 1 - offset
        case .uMin:
            return offset
        case .uMax:
            return surface.uControlPointCount - 1 - offset
        }
    }
}
