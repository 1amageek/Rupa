import SwiftCAD

public struct SurfaceControlPointDisplayID: Codable, Hashable, RawRepresentable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(reference: SurfaceControlPointReference) {
        self.rawValue = [
            "surfaceControlPoint",
            Self.persistentNameString(reference.surface.faceName),
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

    private static func persistentNameString(_ name: PersistentName) -> String {
        name.components.map { component in
            switch component {
            case .feature(let featureID):
                return "feature:\(featureID.description)"
            case .generated(let value):
                return "generated:\(value)"
            case .subshape(let value):
                return "subshape:\(value)"
            case .index(let index):
                return "index:\(index)"
            }
        }
        .joined(separator: "/")
    }
}

