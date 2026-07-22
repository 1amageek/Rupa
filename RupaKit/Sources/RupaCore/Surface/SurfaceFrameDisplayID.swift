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
        let hasStableReference = query.faceStableReference != nil
        let hasSelectionReference = query.selectionReference != nil
        guard [hasFaceID, hasStableReference, hasSelectionReference].filter({ $0 }).count == 1 else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface frame display queries require exactly one faceID, faceStableReference, or selectionReference."
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
        if let faceStableReference = query.faceStableReference {
            let uv = try explicitUVComponents(query)
            return [
                "surfaceFrame",
                "faceStableReference",
                stableSubshapeKey(faceStableReference),
                uv.u,
                uv.v,
            ].joined(separator: "/")
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
        case .subshape(let reference):
            let uv = try explicitUVComponents(query)
            return ["surfaceFrame", "subshape", stableSubshapeKey(reference), uv.u, uv.v].joined(separator: "/")
        case .surface(.whole(let reference)):
            let uv = try explicitUVComponents(query)
            return ["surfaceFrame", "surface", stableSubshapeKey(reference.subshape), uv.u, uv.v].joined(separator: "/")
        case .surface(.parameter(let reference)):
            try rejectExplicitUV(query)
            return [
                "surfaceFrame",
                "surfaceParameter",
                stableSubshapeKey(reference.surface.subshape),
                parameterComponent("u", reference.u),
                parameterComponent("v", reference.v),
            ].joined(separator: "/")
        case .surface(.controlPoint(let reference)):
            try rejectExplicitUV(query)
            return [
                "surfaceFrame",
                "surfaceControlPoint",
                stableSubshapeKey(reference.surface.subshape),
                "uIndex:\(reference.uIndex)",
                "vIndex:\(reference.vIndex)",
            ].joined(separator: "/")
        case .surface(.trimSpan(let reference)):
            try rejectExplicitUV(query)
            return [
                "surfaceFrame",
                "surfaceTrimSpan",
                stableSubshapeKey(reference.trim.surface.subshape),
                "loop:\(reference.trim.loopIndex)",
                "edge:\(reference.trim.edgeIndex)",
                "span:\(reference.spanIndex)",
            ].joined(separator: "/")
        case .surface(.trimKnot(let reference)):
            try rejectExplicitUV(query)
            return [
                "surfaceFrame",
                "surfaceTrimKnot",
                stableSubshapeKey(reference.trim.surface.subshape),
                "loop:\(reference.trim.loopIndex)",
                "edge:\(reference.trim.edgeIndex)",
                "knot:\(reference.knotIndex)",
            ].joined(separator: "/")
        case .surface(.span),
             .surface(.knot),
             .surface(.trim),
             .edge,
             .curve,
             .sketchPoint:
            throw EditorError(
                code: .commandInvalid,
                message: "Surface frame display requires a generated face, surface parameter, surface control point, or trim p-curve parameter reference."
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
                message: "Surface frame display parameter, control-point, and trim p-curve references carry their own UV address and must not also provide u or v."
            )
        }
    }

    private static func parameterComponent(_ axis: String, _ value: Double) -> String {
        "\(axis)Bits:\(value.bitPattern)"
    }

    private static func stableSubshapeKey(_ reference: StableSubshapeReference) -> String {
        let id = reference.subshapeID
        return "feature:\(id.featureID.description)/role:\(id.role)/ordinal:\(id.ordinal)"
    }
}
