import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Moves B-spline surface control points by `delta` (in each surface's own coordinates) with
    /// Move Control Point's proportional falloff and mirror. `targets` are in selection order; the
    /// last target of each surface is its active control point. Every touched surface is replaced
    /// together or not at all.
    public mutating func moveSurfaceControlPointsProportionally(
        targets: [SelectionReference],
        deltaX: CADExpression,
        deltaY: CADExpression,
        deltaZ: CADExpression,
        options: SurfaceControlPointMoveOptions,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let owner = "Proportional control point move"
        let delta = Vector3D(
            x: try resolvedLengthValue(deltaX, owner: "\(owner) delta x"),
            y: try resolvedLengthValue(deltaY, owner: "\(owner) delta y"),
            z: try resolvedLengthValue(deltaZ, owner: "\(owner) delta z")
        )
        guard delta.length > ModelingTolerance.standard.distance else {
            throw EditorError(code: .commandInvalid, message: "\(owner) requires a non-zero delta.")
        }
        guard Set(targets).count == targets.count, !targets.isEmpty else {
            throw EditorError(code: .commandInvalid, message: "\(owner) requires distinct control point targets.")
        }
        // Targets grouped by surface, keeping selection order so the last one stays active.
        var order: [FeatureID] = []
        var selected: [FeatureID: [SurfaceControlPointProportionalMove.NetIndex]] = [:]
        let resolver = SurfaceControlPointSelectionTargetResolver()
        for target in targets {
            guard case .bSplineSurfaceControlPoint(let point) = try resolver.editTarget(for: target, in: self) else {
                throw EditorError(code: .commandInvalid, message: "\(owner) applies to B-spline surface control points.")
            }
            if selected[point.featureID] == nil { order.append(point.featureID) }
            selected[point.featureID, default: []].append(.init(u: point.uIndex, v: point.vIndex))
        }

        let move = SurfaceControlPointProportionalMove(options: options, distanceTolerance: modelingSettings.tolerance.distance)
        var updatedCADDocument = cadDocument
        for featureID in order {
            guard var feature = cadDocument.designGraph.nodes[featureID],
                  case .bSplineSurface(var surfaceFeature) = feature.operation else {
                throw EditorError(code: .referenceUnresolved, message: "\(owner) requires an existing direct B-spline surface source feature.")
            }
            let mirror = try options.mirrorAxis.map { try mirrorPlane(axis: $0, plane: options.mirrorPlane, for: featureID) }
            let displacements = try move.displacements(
                controlPoints: surfaceFeature.surface.controlPoints,
                selected: selected[featureID] ?? [],
                delta: delta,
                mirror: mirror
            )
            for (index, displacement) in displacements {
                surfaceFeature.surface.controlPoints[index.v][index.u] =
                    surfaceFeature.surface.controlPoints[index.v][index.u] + displacement
            }
            try surfaceFeature.validate(tolerance: modelingSettings.tolerance)
            feature.operation = .bSplineSurface(surfaceFeature)
            try updatedCADDocument.replaceFeature(feature, tolerance: modelingSettings.tolerance)
        }
        let previousCADDocument = cadDocument
        do {
            cadDocument = updatedCADDocument
            try validate(objectRegistry: objectRegistry)
        } catch {
            cadDocument = previousCADDocument
            throw EditorError(code: .commandInvalid, message: "\(owner) produced invalid source geometry: \(error).")
        }
    }

    /// The mirror plane for `axis` of the world construction plane, in the coordinates of the
    /// surface `featureID`, through the one scene node that presents it.
    private func mirrorPlane(
        axis: SurfaceControlPointMoveOptions.MirrorAxis,
        plane: SketchPlane,
        for featureID: FeatureID
    ) throws -> SurfaceControlPointProportionalMove.MirrorPlane {
        let system = try SketchPlaneCoordinateSystem(plane: plane)
        // The mirror plane's normal and the two construction-plane axes spanning it.
        let (worldNormal, spanA, spanB): (Vector3D, Vector3D, Vector3D) = switch axis {
        case .x: (system.u, system.v, system.normal)
        case .y: (system.v, system.normal, system.u)
        case .z: (system.normal, system.u, system.v)
        }
        let presenting = productMetadata.sceneNodes.values.filter { $0.reference?.featureID == featureID }
        guard presenting.count == 1, let node = presenting.first else {
            throw EditorError(
                code: .commandInvalid,
                message: "A mirrored control point move needs the surface presented by exactly one object."
            )
        }
        let world = try SceneNodeHierarchy(metadata: productMetadata).worldTransform(of: node.id)
        let local = try world.inverse()
        let origin = try local.applied(to: system.origin)
        func mapped(_ vector: Vector3D) throws -> Vector3D {
            try local.applied(to: system.origin + vector) - origin
        }
        let normal = try mapped(spanA).cross(try mapped(spanB))
        // A reflection stays a reflection in the surface's coordinates only when its placement
        // keeps angles; a sheared or unevenly scaled placement has no mirror plane there.
        let carried = try mapped(worldNormal)
        guard normal.length > 0, carried.length > 0,
              abs(abs(normal.dot(carried)) - normal.length * carried.length) <= 1.0e-9 * normal.length * carried.length else {
            throw EditorError(
                code: .commandInvalid,
                message: "A mirrored control point move needs the surface placed without shear or uneven scale."
            )
        }
        return .init(origin: origin, normal: normal)
    }
}
