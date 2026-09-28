import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Deform Curve: each selected sketch curve is carried from the reference face onto the
    /// target face by `options` (see `CurveDeformationOptions`) and becomes a spatial path, as
    /// one step. Faces and curves are read in the evaluated document's frame, as Project Curve
    /// Body reads them. Without Keep Tools the source curves are removed. Returns the paths.
    @discardableResult
    public mutating func deformCurves(
        targets: [SelectionTarget],
        referenceFace: SelectionTarget,
        targetFace: SelectionTarget,
        options: CurveDeformationOptions,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [FeatureID] {
        let owner = "Deform Curve"
        guard !targets.isEmpty else {
            throw EditorError(code: .commandInvalid, message: "\(owner) needs at least one selected curve.")
        }
        try options.validate()
        let offsetN = try resolvedLengthValue(options.offsetN, owner: "\(owner) N offset")
        let tolerance = modelingSettings.tolerance
        let topology = try TopologySnapshotService().snapshot(document: self, objectRegistry: objectRegistry)
        guard let evaluated = topology.evaluatedDocument else {
            throw EditorError(code: .referenceUnresolved, message: "\(owner) needs the evaluated document.")
        }
        func chart(_ face: SelectionTarget, role: String) throws -> FaceUVNChart {
            guard case .face = face.component,
                  let entry = topology.entries.first(where: { $0.kind == .face && $0.selectionTarget() == face }),
                  let reference = entry.stableReference else {
                throw EditorError(code: .referenceUnresolved, message: "\(owner) \(role) face is not a face of an evaluated body.")
            }
            return try FaceUVNChart(face: SurfaceReference(subshape: reference), in: evaluated, tolerance: tolerance)
        }
        let from = try chart(referenceFace, role: "reference")
        let to = try chart(targetFace, role: "target")
        let fitter = try SpatialCurveFitter(deviation: tolerance.distance * Self.deformFitDeviationFactor)

        var candidate = self
        var paths: [FeatureID] = []
        var seen = Set<SketchEntityID>()
        for target in targets {
            let selection = try editableSketchEntity(for: target, operationName: owner)
            guard seen.insert(selection.entityID).inserted else {
                throw EditorError(code: .commandInvalid, message: "\(owner) received the same curve more than once.")
            }
            let source = try deformSourceCurve(selection.entity, plane: selection.sketch.plane, owner: owner)
            let fitted = try fitter.fit(breakpoints: source.breakpoints, isClosed: source.isClosed, tolerance: tolerance) { w in
                try to.point(at: options.mapped(from.coordinate(of: source.point(w)), offsetN: offsetN))
            }
            paths.append(try candidate.createSpatialPath(
                name: "\(selection.feature.name ?? "Curve") Deformed", path: fitted.path, objectRegistry: objectRegistry
            ))
        }
        if !options.keepsTools {
            try candidate.removeDeformedSources(targets, owner: owner, objectRegistry: objectRegistry)
        }
        self = candidate
        return paths
    }

    /// Without Keep Tools the deformed curves leave their sketches; a sketch left with no curve
    /// is deleted with its object, and one whose deletion would reach further (a feature built
    /// on it) is refused, since the curves it feeds cannot be replaced.
    private mutating func removeDeformedSources(
        _ targets: [SelectionTarget], owner: String, objectRegistry: ObjectTypeRegistry
    ) throws {
        var emptied: [SceneNodeID] = []
        for target in targets {
            let selection = try editableSketchEntity(for: target, operationName: owner)
            if selection.sketch.entities.count == 1 {
                let plan = try SceneNodeDeletionPlanner().plan(
                    metadata: productMetadata, designGraph: cadDocument.designGraph, ids: [target.sceneNodeID]
                )
                guard plan.featureIDs == [selection.featureID] else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) would empty a sketch other features are built on; turn on Keep Tools."
                    )
                }
                emptied.append(target.sceneNodeID)
            } else {
                try removeSketchCurve(selection, objectRegistry: objectRegistry)
            }
        }
        if !emptied.isEmpty {
            try deleteSceneNodes(ids: emptied, objectRegistry: objectRegistry)
        }
    }

    /// Deformed paths stay within this many modeling distances of the exact mapped curve at
    /// the fitter's check parameters.
    static let deformFitDeviationFactor = 10.0

    private struct DeformSourceCurve {
        var breakpoints: [Double]
        var isClosed: Bool
        var point: (Double) throws -> Point3D
    }

    /// A sketch curve as a function of one parameter into the sketch's 3D frame, with the
    /// parameters where it may turn a corner.
    private func deformSourceCurve(_ entity: SketchEntity, plane: SketchPlane, owner: String) throws -> DeformSourceCurve {
        let system = try SketchPlaneCoordinateSystem(plane: plane)
        switch entity {
        case .line(let line):
            let start = try resolvedProjectionPoint(line.start, owner: "\(owner) line start")
            let end = try resolvedProjectionPoint(line.end, owner: "\(owner) line end")
            return DeformSourceCurve(breakpoints: [0, 1], isClosed: false) { w in
                system.point(from: Point2D(x: start.x + (end.x - start.x) * w, y: start.y + (end.y - start.y) * w))
            }
        case .arc(let arc):
            let center = try resolvedProjectionPoint(arc.center, owner: "\(owner) arc center")
            let radius = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) arc radius")
            let startAngle = try resolvedAngleValue(arc.startAngle, owner: "\(owner) arc start angle")
            let span = try normalizedPartialArcSpan(
                startAngle: startAngle,
                endAngle: try resolvedAngleValue(arc.endAngle, owner: "\(owner) arc end angle")
            )
            return DeformSourceCurve(breakpoints: [0, 1], isClosed: false) { w in
                let angle = startAngle + span * w
                return system.point(from: Point2D(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
            }
        case .circle(let circle):
            let center = try resolvedProjectionPoint(circle.center, owner: "\(owner) circle center")
            let radius = try resolvedPositiveLengthValue(circle.radius, owner: "\(owner) circle radius")
            return DeformSourceCurve(breakpoints: [0, 1], isClosed: true) { w in
                let angle = 2 * Double.pi * w
                return system.point(from: Point2D(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
            }
        case .spline(let spline):
            let curve = try resolvedSketchSplineCurve(spline, owner: owner)
            var breakpoints = [curve.segments[0].lowerParameter]
            breakpoints.append(contentsOf: curve.segments.map(\.upperParameter))
            return DeformSourceCurve(breakpoints: breakpoints, isClosed: spline.isClosed) { w in
                system.point(from: try curve.bSpline.point(at: w, tolerance: .standard))
            }
        case .point:
            throw EditorError(code: .commandInvalid, message: "\(owner) deforms curves, not points.")
        }
    }
}
