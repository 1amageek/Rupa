import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Project Body Body: the curves where two selected bodies' faces meet (Swift-CAD's
    /// `BodySectionCurveEvaluator`, trimmed to both faces), fitted within ten modeling distances
    /// and joined end to end into spatial paths, one object per path, in one step. Bodies that
    /// do not meet are refused. Returns the paths.
    @discardableResult
    public mutating func projectBodyIntersection(
        first: SelectionTarget,
        second: SelectionTarget,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [FeatureID] {
        let owner = "Project Body Body"
        let tolerance = modelingSettings.tolerance
        let topology = try TopologySnapshotService().snapshot(document: self, objectRegistry: objectRegistry)
        guard let evaluated = topology.evaluatedDocument else {
            throw EditorError(code: .referenceUnresolved, message: "\(owner) needs the evaluated document.")
        }
        func bodies(_ target: SelectionTarget) throws -> (name: String, ids: [BodyID]) {
            guard target.component == .object,
                  let node = productMetadata.sceneNodes[target.sceneNodeID],
                  node.reference?.kind == .body,
                  let featureID = node.reference?.featureID else {
                throw EditorError(code: .commandInvalid, message: "\(owner) takes two generated bodies.")
            }
            let ids = GeneratedBodyIdentityResolver().bodyIdentities(in: evaluated.subshapes)
                .filter { $0.sourceFeatureID == featureID }.map(\.bodyID)
            guard !ids.isEmpty else {
                throw EditorError(code: .referenceUnresolved, message: "\(owner) found no evaluated body for \(node.name).")
            }
            return (node.name, ids)
        }
        let a = try bodies(first), b = try bodies(second)
        guard first.sceneNodeID != second.sceneNodeID else {
            throw EditorError(code: .commandInvalid, message: "\(owner) takes two different bodies.")
        }
        // Both bodies' evaluated faces are in their source frames; one shared placement carries
        // their section into the world.
        let placement = try worldPlacement(of: first.sceneNodeID)
        guard placementsMatch(placement, try worldPlacement(of: second.sceneNodeID)) else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): bodies placed differently need one body's faces
            // carried into the other's frame before the kernel section. Production path: Project
            // Body Body (I on two bodies) refuses them here. Done when differently placed bodies
            // are sectioned with their own tests.
            throw EditorError(code: .commandInvalid, message: "\(owner) needs the two bodies to share one placement; they have been moved apart.")
        }
        let evaluator = BodySectionCurveEvaluator(tolerance: tolerance)
        let fitter = try SpatialCurveFitter(deviation: tolerance.distance * Self.spatialFitDeviationFactor)
        var pieces: [[(p0: Point3D, p1: Point3D, p2: Point3D, p3: Point3D)]] = []
        for firstBody in a.ids {
            for secondBody in b.ids {
                for section in try evaluator.sections(between: firstBody, and: secondBody, in: evaluated.brep) {
                    let fitted = try fitter.fit(breakpoints: [section.lower, section.upper], isClosed: false, tolerance: tolerance) { t in
                        try placement.applied(to: try section.curve.point(at: t, tolerance: tolerance))
                    }
                    let knots = fitted.path.knots
                    pieces.append((0..<fitted.path.segmentCount).map { index in
                        (p0: knots[index].position, p1: knots[index].position + knots[index].outgoing,
                         p2: knots[index + 1].position + knots[index + 1].incoming, p3: knots[index + 1].position)
                    })
                }
            }
        }
        guard !pieces.isEmpty else {
            throw EditorError(code: .commandInvalid, message: "\(owner): \(a.name) and \(b.name) do not meet.")
        }
        var candidate = self
        var paths: [FeatureID] = []
        for (index, chain) in Self.chainedOutlineSpans(pieces, tolerance: tolerance.distance).enumerated() {
            paths.append(try candidate.createWorldSpatialPath(
                name: "\(a.name) \(b.name) Intersection\(index == 0 ? "" : " \(index + 1)")",
                path: chain, objectRegistry: objectRegistry
            ))
        }
        self = candidate
        return paths
    }
}
