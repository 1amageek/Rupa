import RupaCore
import SwiftCAD

/// A reference address within an already-matched source frame. Geometry
/// signatures remain owned by CAD; this value cannot validate or edit geometry.
enum ViewportSpatialReferenceAddress: Equatable, Sendable {
    case subshape(SubshapeID)
    case edge(SubshapeID)
    case edgeParameter(SubshapeID, Double)
    case curve(CurveSubobjectReference)
    case sketchPoint(SketchPointSelectionReference)
    case surface(SubshapeID)
    case surfaceParameter(SubshapeID, Double, Double)
    case surfaceSpan(SubshapeID, SurfaceParameterDirection, Int)
    case surfaceControlPoint(SubshapeID, Int, Int)
    case surfaceKnot(SubshapeID, SurfaceParameterDirection, Int)
    case surfaceTrim(SubshapeID, Int, Int)
    case surfaceTrimSpan(SubshapeID, Int, Int, Int)
    case surfaceTrimKnot(SubshapeID, Int, Int, Int)

    init(_ reference: SelectionReference) {
        switch reference {
        case .subshape(let value): self = .subshape(value.subshapeID)
        case .edge(.whole(let value)): self = .edge(value.subshape.subshapeID)
        case .edge(.parameter(let value)): self = .edgeParameter(value.edge.subshape.subshapeID, value.parameter)
        case .curve(let value): self = .curve(value)
        case .sketchPoint(let value): self = .sketchPoint(value)
        case .surface(.whole(let value)): self = .surface(value.subshape.subshapeID)
        case .surface(.parameter(let value)):
            self = .surfaceParameter(value.surface.subshape.subshapeID, value.u, value.v)
        case .surface(.span(let value)):
            self = .surfaceSpan(value.surface.subshape.subshapeID, value.direction, value.spanIndex)
        case .surface(.controlPoint(let value)):
            self = .surfaceControlPoint(value.surface.subshape.subshapeID, value.uIndex, value.vIndex)
        case .surface(.knot(let value)):
            self = .surfaceKnot(value.surface.subshape.subshapeID, value.direction, value.knotIndex)
        case .surface(.trim(let value)):
            self = .surfaceTrim(value.surface.subshape.subshapeID, value.loopIndex, value.edgeIndex)
        case .surface(.trimSpan(let value)):
            self = .surfaceTrimSpan(value.trim.surface.subshape.subshapeID, value.trim.loopIndex, value.trim.edgeIndex, value.spanIndex)
        case .surface(.trimKnot(let value)):
            self = .surfaceTrimKnot(value.trim.surface.subshape.subshapeID, value.trim.loopIndex, value.trim.edgeIndex, value.knotIndex)
        }
    }

    static func project(_ references: [SelectionReference]) throws -> [Self] {
        let limits = MeshSourcePresentationPlanLimits.standard
        let bytes = references.count.multipliedReportingOverflow(by: MemoryLayout<Self>.stride)
        guard references.count <= limits.maxPositionCount, !bytes.overflow,
              bytes.partialValue <= limits.maxRetainedByteCount else { throw RealityViewportSpatialBatch.exhausted() }
        try Task.checkCancellation()
        var result: [Self] = []
        result.reserveCapacity(references.count)
        for reference in references {
            try Task.checkCancellation()
            result.append(Self(reference))
        }
        return result
    }

    /// The only variable-size payload in this address is the stable role name.
    var subshapeID: SubshapeID? {
        switch self {
        case .subshape(let id), .edge(let id), .edgeParameter(let id, _), .surface(let id),
             .surfaceParameter(let id, _, _), .surfaceSpan(let id, _, _),
             .surfaceControlPoint(let id, _, _), .surfaceKnot(let id, _, _),
             .surfaceTrim(let id, _, _), .surfaceTrimSpan(let id, _, _, _),
             .surfaceTrimKnot(let id, _, _, _): id
        case .curve, .sketchPoint: nil
        }
    }
}
