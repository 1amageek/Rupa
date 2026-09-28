import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Project Curve Body along a direction: every point of each selected sketch curve moves
    /// along `direction` (both ways when `bidirectional`) to the one selected face, and the
    /// curve becomes a spatial path, one per curve, in one step. Each point must meet the face
    /// within its trim, or the command fails and nothing changes. A planar face met square on
    /// (direction along its normal) takes the curves as a sketch on its plane, as
    /// `projectCurvesToGeneratedFace` makes it. Curves, the face and the direction follow the
    /// shared world-placed coordinate flow (`DesignDocument+WorldPlacedCurves`). Returns the
    /// created features.
    @discardableResult
    public mutating func projectCurvesAlongDirection(
        targets: [SelectionTarget],
        face: SelectionTarget,
        direction: Vector3D,
        bidirectional: Bool,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [FeatureID] {
        let owner = "Project Curve Body"
        guard !targets.isEmpty else {
            throw EditorError(code: .commandInvalid, message: "\(owner) needs at least one selected curve.")
        }
        let tolerance = modelingSettings.tolerance
        let unit: Vector3D
        do {
            unit = try direction.normalized(tolerance: tolerance.distance)
        } catch {
            throw EditorError(code: .commandInvalid, message: "\(owner) needs a direction that is not zero.")
        }
        let topology = try TopologySnapshotService().snapshot(document: self, objectRegistry: objectRegistry)
        guard let evaluated = topology.evaluatedDocument else {
            throw EditorError(code: .referenceUnresolved, message: "\(owner) needs the evaluated document.")
        }
        guard case .face = face.component,
              let entry = topology.entries.first(where: { $0.kind == .face && $0.selectionTarget() == face }),
              let stableReference = entry.stableReference else {
            throw EditorError(code: .referenceUnresolved, message: "\(owner) face is not a face of an evaluated body.")
        }
        // The face is read in its body's source frame, placed by the body's world placement.
        let placement = try worldPlacement(of: face.sceneNodeID)
        let inverse = try placement.inverse()
        let bodyDirection = try inverse.applyingLinearPart(to: unit).normalized(tolerance: tolerance.distance)
        if entry.surfaceKind == "plane", let normal = entry.normal,
           abs(abs(bodyDirection.dot(Vector3D(x: normal.x, y: normal.y, z: normal.z))) - 1) <= tolerance.angle {
            return [try projectCurvesToGeneratedFace(targets: targets, face: face, objectRegistry: objectRegistry)]
        }
        let surface = SurfaceReference(subshape: stableReference)
        let evaluator = SurfaceQueryEvaluator(tolerance: tolerance)
        let options = SurfaceDirectionalProjectionOptions(range: bidirectional ? .line : .ray)
        let fitter = try SpatialCurveFitter(deviation: tolerance.distance * Self.spatialFitDeviationFactor)

        var candidate = self
        var paths: [FeatureID] = []
        var seen = Set<SketchEntityID>()
        for target in targets {
            let selection = try editableSketchEntity(for: target, operationName: owner)
            guard seen.insert(selection.entityID).inserted else {
                throw EditorError(code: .commandInvalid, message: "\(owner) received the same curve more than once.")
            }
            let source = try spatialSourceCurve(
                selection.entity, system: try placedSketchSystem(for: target, plane: selection.sketch.plane), owner: owner
            )
            let fitted = try fitter.fit(breakpoints: source.breakpoints, isClosed: source.isClosed, tolerance: tolerance) { w in
                let origin = try inverse.applied(to: try source.point(w))
                let hit = try evaluator.project(origin, along: bodyDirection, onto: surface, in: evaluated, options: options)
                return try placement.applied(to: hit.projectedPoint)
            }
            paths.append(try candidate.createWorldSpatialPath(
                name: "\(selection.feature.name ?? "Curve") Face Projection", path: fitted.path, objectRegistry: objectRegistry
            ))
        }
        self = candidate
        return paths
    }
}
