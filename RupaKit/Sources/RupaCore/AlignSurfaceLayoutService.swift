import Foundation
import SwiftCAD

/// The control layout Align Surface's Degree/Spans opens on: the degrees and spans of the B-spline
/// sheet whose edge is aligned, as Plasticity's dialog shows the target's own layout.
public struct AlignSurfaceLayoutService: Sendable {
    public init() {}

    /// The layout of the B-spline face along `edge`, or nil when the face is not a B-spline or
    /// its layout lies outside the degrees and spans a refit takes (the dialog then opens on its
    /// own default layout, which the user sets).
    public func layout(ofFaceAlong edge: SelectionTarget, topology: TopologySnapshot) throws -> SurfaceControlLayout? {
        guard case .edge = edge.component else {
            throw EditorError(code: .commandInvalid, message: "Align Surface's layout is read from an edge of a sheet.")
        }
        guard let evaluated = topology.evaluatedDocument else {
            throw EditorError(code: .referenceUnresolved, message: "Align Surface's layout needs the evaluated sheet.")
        }
        guard let entry = topology.entries.first(where: { $0.kind == .edge && $0.selectionTarget() == edge }),
              let reference = entry.stableReference else {
            throw EditorError(code: .referenceUnresolved, message: "The aligned edge is no longer in the model.")
        }
        guard case let .edge(edgeID) = try evaluated.topologyReference(for: reference) else {
            throw EditorError(code: .referenceUnresolved, message: "The aligned edge does not resolve to an edge.")
        }
        let brep = evaluated.brep
        for face in brep.faces.values {
            let touches = face.loops.contains { loopID in
                brep.loops[loopID]?.coedges.contains { $0.edgeID == edgeID } == true
            }
            guard touches else { continue }
            guard case let .bSpline(surface)? = brep.geometry.surfaces[face.surfaceID] else { return nil }
            let layout = SurfaceControlLayout(
                uDegree: surface.uDegree, vDegree: surface.vDegree,
                uSpans: Self.spanCount(surface.uKnots), vSpans: Self.spanCount(surface.vKnots)
            )
            do {
                try layout.validate()
            } catch {
                return nil
            }
            return layout
        }
        throw EditorError(code: .referenceUnresolved, message: "The aligned edge bounds no face.")
    }

    /// The knot spans of non-zero length a knot vector holds.
    static func spanCount(_ knots: [Double]) -> Int {
        zip(knots, knots.dropFirst()).filter { $1 > $0 }.count
    }
}
