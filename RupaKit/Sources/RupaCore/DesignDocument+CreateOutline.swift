import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Create Outline: the silhouette of each selected body seen along the plane's normal (the
    /// edges Project Outline keeps, `outlinePieces`), left where it is on the body as 3D curves.
    /// Pieces that meet end to end are joined into one spatial path; each path is one object.
    /// Returns the paths.
    @discardableResult
    public mutating func createBodyOutlines(
        targets: [SelectionTarget],
        plane: SketchPlane,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [FeatureID] {
        let owner = "Create Outline"
        guard !targets.isEmpty else {
            throw EditorError(code: .commandInvalid, message: "\(owner) needs at least one selected body.")
        }
        let tolerance = modelingSettings.tolerance
        let system = try SketchPlaneCoordinateSystem(plane: plane)
        let topology = try TopologySnapshotService().snapshot(document: self, objectRegistry: objectRegistry)
        guard let evaluated = topology.evaluatedDocument else {
            throw EditorError(code: .referenceUnresolved, message: "\(owner) needs the evaluated document.")
        }
        let edgeEvaluator = EdgeQueryEvaluator(tolerance: tolerance)
        let fitter = try SpatialCurveFitter(deviation: tolerance.distance * Self.spatialFitDeviationFactor)
        var candidate = self
        var paths: [FeatureID] = []
        for target in Set(targets.map(\.sceneNodeID)).sorted(by: { $0.description < $1.description }) {
            guard let node = productMetadata.sceneNodes[target], node.reference?.kind == .body else {
                throw EditorError(code: .commandInvalid, message: "\(owner) takes generated bodies.")
            }
            let entries = topology.entries.filter { $0.sceneNodeID == target.description }
            let faces = try entries.filter { $0.kind == .face }.map { entry in
                guard let reference = entry.stableReference else {
                    throw EditorError(code: .referenceUnresolved, message: "\(owner) body face has no stable reference.")
                }
                return SurfaceReference(subshape: reference)
            }
            // Every outline piece of every edge, as fitted 3D spans. Pieces that project onto the
            // same curve (a box's top and bottom rims seen from above) keep the one nearest the
            // viewer on the normal's side.
            var spansByProjection: [String: (height: Double, spans: [(p0: Point3D, p1: Point3D, p2: Point3D, p3: Point3D)])] = [:]
            for entry in entries where entry.kind == .edge {
                guard let reference = entry.stableReference else {
                    throw EditorError(code: .referenceUnresolved, message: "\(owner) body edge has no stable reference.")
                }
                let edge = try edgeEvaluator.resolve(EdgeReference(subshape: reference), in: evaluated)
                for piece in try outlinePieces(edge: edge, faces: faces, in: evaluated, system: system) {
                    let fitted = try fitter.fit(breakpoints: [piece.lower, piece.upper], isClosed: false, tolerance: tolerance) { t in
                        try edge.curve.point(at: t, tolerance: tolerance)
                    }
                    let knots = fitted.path.knots
                    let pieceSpans = (0..<fitted.path.segmentCount).map { index in
                        (p0: knots[index].position, p1: knots[index].position + knots[index].outgoing,
                         p2: knots[index + 1].position + knots[index + 1].incoming, p3: knots[index + 1].position)
                    }
                    let middle = try edge.curve.point(at: (piece.lower + piece.upper) / 2, tolerance: tolerance)
                    let ends = [knots[0].position, knots[knots.count - 1].position]
                        .map { quantizedPointKey(system.project($0).point) }.sorted()
                    let key = ends.joined(separator: "|") + "|" + quantizedPointKey(system.project(middle).point)
                    let height = (middle - system.origin).dot(system.normal)
                    if let kept = spansByProjection[key], kept.height >= height { continue }
                    spansByProjection[key] = (height, pieceSpans)
                }
            }
            let spans = spansByProjection.keys.sorted().compactMap { spansByProjection[$0]?.spans }
            guard !spans.isEmpty else {
                throw EditorError(code: .commandInvalid, message: "\(owner) found no outline on \(node.name) along the plane's normal.")
            }
            for (index, chain) in Self.chainedOutlineSpans(spans, tolerance: tolerance.distance).enumerated() {
                paths.append(try candidate.createSpatialPath(
                    name: "\(node.name) Outline\(index == 0 ? "" : " \(index + 1)")",
                    path: chain, objectRegistry: objectRegistry
                ))
            }
        }
        self = candidate
        return paths
    }

    /// Joins pieces whose ends meet into Bezier paths, each joint a corner knot; a chain that
    /// returns to its start is closed.
    static func chainedOutlineSpans(
        _ pieces: [[(p0: Point3D, p1: Point3D, p2: Point3D, p3: Point3D)]], tolerance: Double
    ) -> [SpatialPathFeature] {
        var remaining = pieces
        var result: [SpatialPathFeature] = []
        while !remaining.isEmpty {
            var chain = remaining.removeFirst()
            var extended = true
            while extended {
                extended = false
                for (index, piece) in remaining.enumerated() {
                    let reversed = piece.reversed().map { ($0.p3, $0.p2, $0.p1, $0.p0) }
                    if (piece[0].p0 - chain[chain.count - 1].p3).length <= tolerance {
                        chain += piece
                    } else if (piece[piece.count - 1].p3 - chain[chain.count - 1].p3).length <= tolerance {
                        chain += reversed
                    } else if (piece[piece.count - 1].p3 - chain[0].p0).length <= tolerance {
                        chain = piece + chain
                    } else if (piece[0].p0 - chain[0].p0).length <= tolerance {
                        chain = reversed + chain
                    } else {
                        continue
                    }
                    remaining.remove(at: index)
                    extended = true
                    break
                }
            }
            let isClosed = chain.count > 1 && (chain[chain.count - 1].p3 - chain[0].p0).length <= tolerance
            var knots = [SpatialPathKnot(position: chain[0].p0, outgoing: chain[0].p1 - chain[0].p0)]
            for (index, span) in chain.enumerated() {
                knots[knots.count - 1].outgoing = span.p1 - span.p0
                knots.append(SpatialPathKnot(
                    position: span.p3,
                    incoming: span.p2 - span.p3,
                    outgoing: index + 1 < chain.count ? chain[index + 1].p1 - chain[index + 1].p0 : .zero
                ))
            }
            if isClosed {
                let last = knots.removeLast()
                knots[0].incoming = last.incoming
            }
            result.append(SpatialPathFeature(kind: .bezier, knots: knots, isClosed: isClosed))
        }
        return result
    }
}
