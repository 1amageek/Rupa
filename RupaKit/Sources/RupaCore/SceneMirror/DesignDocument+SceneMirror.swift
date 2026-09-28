import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Mirrors the outermost of `ids` across `plane` with `options` and returns the objects the
    /// mirror made (copies or instances) or, when joining halves, the joined objects.
    @discardableResult
    public mutating func mirrorSceneNodes(
        ids: [SceneNodeID],
        plane: SceneMirrorPlane,
        options: SceneMirrorOptions,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [SceneNodeID] {
        guard !(options.unionsHalves && options.makesInstances) else {
            throw EditorError(code: .commandInvalid, message: "Mirror cannot both join halves and make instances.")
        }
        let hierarchy = try SceneNodeHierarchy(metadata: productMetadata)
        let roots = hierarchy.outermostSceneNodeIDs(among: ids)
        guard !roots.isEmpty else {
            throw EditorError(code: .commandInvalid, message: "Mirror needs a selected object.")
        }
        var updated = self
        var results: [SceneNodeID] = []
        for root in roots {
            guard let node = productMetadata.sceneNodes[root], !node.isLocked else {
                throw EditorError(code: .commandInvalid, message: "Mirror cannot change a locked or missing object.")
            }
            let world = try hierarchy.worldTransform(of: root)
            if options.makesInstances, !options.cutsAtPlane {
                // An instance shows the object as it is, so any object can be mirrored this way.
                results += try updated.placeSceneNodes(
                    ids: [root], placements: [try plane.reflection()], output: .componentInstance,
                    objectRegistry: objectRegistry
                )
                continue
            }
            if !options.cutsAtPlane && !options.unionsHalves,
               node.reference?.kind != .body && node.reference?.kind != .feature {
                results += try updated.placeSceneNodes(
                    ids: [root], placements: [try plane.reflection()], objectRegistry: objectRegistry)
                continue
            }
            let local = try mirrorPlane(plane, placedBy: world)
            try mirrorableBody(node)
            if options.makesInstances {
                try updated.appendMirror(to: root, plane: local, output: .kept, cuts: true, objectRegistry: objectRegistry)
                results += try updated.placeSceneNodes(
                    ids: [root], placements: [try plane.reflection()], output: .componentInstance,
                    objectRegistry: objectRegistry
                )
            } else if options.unionsHalves {
                try updated.appendMirror(
                    to: root, plane: local, output: .combined, cuts: options.cutsAtPlane, objectRegistry: objectRegistry
                )
                results.append(root)
            } else {
                // The reflection is an independent copy, so the copy is made before the object is cut.
                let copies = try updated.placeSceneNodes(ids: [root], placements: [.identity], objectRegistry: objectRegistry)
                guard copies.count == 1, let copy = copies.first else {
                    throw EditorError(code: .commandInvalid, message: "Mirror copies one object at a time.")
                }
                if options.cutsAtPlane {
                    try updated.appendMirror(to: root, plane: local, output: .kept, cuts: true, objectRegistry: objectRegistry)
                }
                try updated.appendMirror(
                    to: copy, plane: local, output: .reflection, cuts: options.cutsAtPlane, objectRegistry: objectRegistry
                )
                results.append(copy)
            }
        }
        self = updated
        return results
    }

    /// Refuses objects Swift-CAD cannot mirror as a feature.
    private func mirrorableBody(_ node: SceneNode) throws {
        guard let reference = node.reference, reference.kind == .body || reference.kind == .feature,
              reference.featureID != nil, node.object != nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Mirror cuts and joins bodies; other objects support reflected copies or instances."
            )
        }
    }

    /// The world plane in the coordinates of an object placed by `world`, which must keep angles.
    private func mirrorPlane(_ plane: SceneMirrorPlane, placedBy world: Transform3D) throws -> SceneMirrorPlane {
        let local = try world.inverse()
        let origin = try local.applied(to: plane.origin)
        let seed: Vector3D = abs(plane.normal.x) < 0.9 ? .unitX : .unitY
        let spanA = plane.normal.cross(seed)
        let spanB = plane.normal.cross(spanA)
        func mapped(_ vector: Vector3D) throws -> Vector3D {
            try local.applied(to: plane.origin + vector) - origin
        }
        let normal = try mapped(spanA).cross(try mapped(spanB))
        let carried = try mapped(plane.normal)
        guard normal.length > 0, carried.length > 0,
              abs(abs(normal.dot(carried)) - normal.length * carried.length) <= 1.0e-9 * normal.length * carried.length else {
            throw EditorError(
                code: .commandInvalid,
                message: "Mirror needs the object placed without shear or uneven scale."
            )
        }
        // Keep the normal pointing the way the world normal does.
        return try SceneMirrorPlane(origin: origin, normal: normal.dot(carried) < 0 ? normal * -1 : normal)
    }

    /// Replaces the feature `nodeID` presents with its mirror.
    private mutating func appendMirror(
        to nodeID: SceneNodeID,
        plane: SceneMirrorPlane,
        output: MirrorFeature.Output,
        cuts: Bool,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard let source = productMetadata.sceneNodes[nodeID]?.reference?.featureID else {
            throw EditorError(code: .referenceUnresolved, message: "Mirror needs the object's feature.")
        }
        let featureID = FeatureID()
        // The factory gives the mirror its target's output role: a solid mirrors to a solid and a
        // sheet to a sheet.
        var feature = try FeatureNodeFactory.make(
            operation: .mirror(MirrorFeature(
                target: PatternTargetReference(featureID: source),
                planeOrigin: plane.origin,
                planeNormal: plane.normal,
                output: output,
                cutsAtPlane: cuts
            )),
            id: featureID, in: cadDocument, tolerance: modelingSettings.tolerance
        )
        feature.name = "Mirror"
        try appendTopologyEdit(
            FeatureGraphTransaction(features: [feature], primaryFeatureID: featureID),
            replacing: SelectionTarget(sceneNodeID: nodeID),
            objectRegistry: objectRegistry
        )
    }
}
