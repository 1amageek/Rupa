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
            GeneratedSubshapeIdentity.string(for: reference.surface.subshape.subshapeID),
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

}

