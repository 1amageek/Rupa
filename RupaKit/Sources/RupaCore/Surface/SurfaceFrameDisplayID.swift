import Foundation
import SwiftCAD
import RupaCoreTypes

public struct SurfaceFrameDisplayID: Codable, Hashable, RawRepresentable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(query: SurfaceFrameQuery) throws {
        self.rawValue = try Self.rawValue(for: query)
    }

    private static func rawValue(for query: SurfaceFrameQuery) throws -> String {
        let hasFaceID = query.faceID.map {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? false
        let hasPersistentName = query.facePersistentName.map {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? false
        let hasSelectionReference = query.selectionReference != nil
        guard [hasFaceID, hasPersistentName, hasSelectionReference].filter({ $0 }).count == 1 else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface frame display queries require exactly one faceID, facePersistentName, or selectionReference."
            )
        }

        if let faceID = query.faceID {
            let trimmed = faceID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard UUID(uuidString: trimmed) != nil else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Surface frame display faceID must be a valid generated face UUID."
                )
            }
            let uv = try explicitUVComponents(query)
            return ["surfaceFrame", "faceID", trimmed, uv.u, uv.v].joined(separator: "/")
        }
        if let facePersistentName = query.facePersistentName {
            let trimmed = facePersistentName.trimmingCharacters(in: .whitespacesAndNewlines)
            let uv = try explicitUVComponents(query)
            return ["surfaceFrame", "facePersistentName", trimmed, uv.u, uv.v].joined(separator: "/")
        }
        guard let selectionReference = query.selectionReference else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface frame display query is missing a surface target."
            )
        }
        do {
            try selectionReference.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Surface frame display selectionReference is invalid: \(String(describing: error))."
            )
        }
        switch selectionReference {
        case .topology(let name):
            let uv = try explicitUVComponents(query)
            return ["surfaceFrame", "topology", persistentNameString(name), uv.u, uv.v].joined(separator: "/")
        case .surface(.whole(let reference)):
            let uv = try explicitUVComponents(query)
            return ["surfaceFrame", "surface", persistentNameString(reference.faceName), uv.u, uv.v].joined(separator: "/")
        case .surface(.parameter(let reference)):
            try rejectExplicitUV(query)
            return [
                "surfaceFrame",
                "surfaceParameter",
                persistentNameString(reference.surface.faceName),
                parameterComponent("u", reference.u),
                parameterComponent("v", reference.v),
            ].joined(separator: "/")
        case .surface(.controlPoint(let reference)):
            try rejectExplicitUV(query)
            return [
                "surfaceFrame",
                "surfaceControlPoint",
                persistentNameString(reference.surface.faceName),
                "uIndex:\(reference.uIndex)",
                "vIndex:\(reference.vIndex)",
            ].joined(separator: "/")
        case .surface(.span), .surface(.knot), .surface(.trim), .edge, .curve, .sketchPoint:
            throw EditorError(
                code: .commandInvalid,
                message: "Surface frame display requires a generated face, surface parameter, or surface control point reference."
            )
        }
    }

    private static func explicitUVComponents(_ query: SurfaceFrameQuery) throws -> (u: String, v: String) {
        guard let u = query.u,
              let v = query.v else {
            throw EditorError(
                code: .commandInvalid,
                message: "Surface frame display face queries require both u and v parameters."
            )
        }
        guard u.isFinite,
              v.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "Surface frame display UV parameters must be finite."
            )
        }
        return (parameterComponent("u", u), parameterComponent("v", v))
    }

    private static func rejectExplicitUV(_ query: SurfaceFrameQuery) throws {
        guard query.u == nil,
              query.v == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Surface frame display parameter and control-point references carry their own UV address and must not also provide u or v."
            )
        }
    }

    private static func parameterComponent(_ axis: String, _ value: Double) -> String {
        "\(axis)Bits:\(value.bitPattern)"
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
