import SwiftCAD
import RupaCoreTypes

public struct SurfaceControlPointDisplayID: Codable, Hashable, RawRepresentable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(reference: SurfaceControlPointReference) {
        self.rawValue = [
            "surfaceControlPoint",
            Self.stableSubshapeKey(reference.surface.subshape),
            "u\(reference.uIndex)",
            "v\(reference.vIndex)",
        ].joined(separator: "/")
    }

    public init(selectionReference: SelectionReference) throws {
        guard case .surface(.controlPoint(let reference)) = selectionReference else {
            throw EditorError(
                code: .commandInvalid,
                message: "Surface control point display requires a surface control point selection reference."
            )
        }
        self.init(reference: reference)
    }

    private static func stableSubshapeKey(_ reference: StableSubshapeReference) -> String {
        let id = reference.subshapeID
        return "feature:\(id.featureID.description)/role:\(id.role)/ordinal:\(id.ordinal)"
    }
}
