import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Match Face: faces of one object take the surface of a reference face, of that object or of
    /// another where it is shown, and the faces around them are re-solved to meet them (Swift-CAD
    /// `faceMatch`). With `front`, each face faces out the way the reference face does. The
    /// object shows the result in its place.
    @discardableResult
    public mutating func matchFaces(
        name: String = "Match Face",
        targets: [SelectionTarget],
        reference: SelectionTarget,
        front: Bool,
        grow: FaceEditGrow = .moving,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> FeatureID {
        let operationName = "Match Face"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
        let topology = try TopologySnapshotService().snapshot(
            document: self, objectRegistry: objectRegistry, currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        let object = try offsetObject(for: targets, operationName: operationName)
        let source = try offsetObject(for: [reference], operationName: operationName)
        let faces = try targets.map { try stableReference(of: $0, kind: .face, in: topology, operationName: operationName) }
        let referenceFace = try stableReference(of: reference, kind: .face, in: topology, operationName: operationName)
        guard faces.contains(referenceFace) == false else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) cannot match a face to itself.")
        }
        let placement = source.nodeID == object.nodeID ? nil : try relativeRigidPlacement(
            of: source.nodeID, inFrameOf: object.nodeID, owner: "The reference face's object", relation: "the matched object"
        )
        return try appendFeatureShownByObject(
            .faceMatch(FaceMatchFeature(
                target: PatternTargetReference(featureID: object.featureID), faces: faces,
                source: PatternTargetReference(featureID: source.featureID), referenceFace: referenceFace,
                sourcePlacement: placement, front: front, grow: grow
            )),
            name: trimmedName, object: object.nodeID, objectRegistry: objectRegistry
        )
    }
}

extension DesignDocument {
    /// Remove Fillets From Shell: the fillets of a solid object no wider than `maximumRadius`
    /// (any, when nil) and of `convexity` are taken out, and the faces they joined grow to meet
    /// (Swift-CAD `removeFillets`). The object shows the result in its place.
    @discardableResult
    public mutating func removeFillets(
        name: String = "Remove Fillets",
        target: SceneNodeID,
        maximumRadius: CADExpression?,
        convexity: FilletConvexity,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let operationName = "Remove Fillets"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
        if let maximumRadius {
            guard try resolvedLengthValue(maximumRadius, owner: "\(operationName) maximum radius") > 0 else {
                throw EditorError(code: .commandInvalid, message: "\(operationName) maximum radius must be positive.")
            }
        }
        let object = try offsetObject(for: [SelectionTarget(sceneNodeID: target)], operationName: operationName)
        guard productMetadata.sceneNodes[target]?.object?.geometryRole == .solid else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) works on solid objects.")
        }
        return try appendFeatureShownByObject(
            .removeFillets(RemoveFilletsFeature(
                target: PatternTargetReference(featureID: object.featureID), maximumRadius: maximumRadius, convexity: convexity
            )),
            name: trimmedName, object: object.nodeID, objectRegistry: objectRegistry
        )
    }
}

extension DesignDocument {
    /// Delete Redundant Topology on solid and sheet objects: each merges faces on one surface
    /// across the edges between them and edges on one curve across the vertices between them
    /// (Swift-CAD `removeRedundantTopology`), shown in its place, as one step.
    public mutating func removeRedundantTopology(targets: [SceneNodeID], objectRegistry: ObjectTypeRegistry = .builtIn) throws {
        let operationName = "Delete Redundant Topology"
        guard targets.isEmpty == false else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) requires solids or sheets.")
        }
        let previous = self
        var didCommit = false
        defer { if !didCommit { self = previous } }
        for target in targets {
            let object = try offsetObject(for: [SelectionTarget(sceneNodeID: target)], operationName: operationName)
            _ = try appendFeatureShownByObject(
                .removeRedundantTopology(RemoveRedundantTopologyFeature(target: PatternTargetReference(featureID: object.featureID))),
                name: operationName, object: object.nodeID, objectRegistry: objectRegistry
            )
        }
        didCommit = true
    }
}

extension DesignDocument {
    /// Hollow: a solid object emptied to walls `thickness` thick inside it, opening through the
    /// chosen faces, or closed inside it when the object itself is chosen (Swift-CAD `shell`). The
    /// object shows the result in its place.
    @discardableResult
    public mutating func hollow(
        name: String = "Hollow",
        targets: [SelectionTarget],
        thickness: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> FeatureID {
        let operationName = "Hollow"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
        guard try resolvedLengthValue(thickness, owner: "\(operationName) thickness") > 0 else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) thickness must be positive.")
        }
        let object = try offsetObject(for: targets, operationName: operationName)
        guard productMetadata.sceneNodes[object.nodeID]?.object?.geometryRole == .solid else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) empties a solid object.")
        }
        let faceTargets = targets.filter { if case .face = $0.component { true } else { false } }
        guard faceTargets.count == targets.count || targets.count == 1 && targets[0].component == .object else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) opens through faces of a solid, or closes inside the solid chosen whole.")
        }
        let topology = try TopologySnapshotService().snapshot(
            document: self, objectRegistry: objectRegistry, currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        let faces = try faceTargets.map { try stableReference(of: $0, kind: .face, in: topology, operationName: operationName) }
        return try appendFeatureShownByObject(
            .shell(ShellFeature(target: ShellTargetReference(featureID: object.featureID), removedFaces: faces, thickness: thickness)),
            name: trimmedName, object: object.nodeID, objectRegistry: objectRegistry
        )
    }

    /// Thicken: a sheet object grown into a solid `front` along its normal and `back` against it,
    /// shown in its place; or, Thicken Face, faces of a body copied as a sheet and grown into a new
    /// solid object beside it (Swift-CAD `extract` then `thicken`), the body kept.
    @discardableResult
    public mutating func thicken(
        name: String = "Thicken",
        targets: [SelectionTarget],
        front: CADExpression,
        back: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> FeatureID {
        let operationName = "Thicken"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
        let frontValue = try resolvedLengthValue(front, owner: "\(operationName) front")
        let backValue = try resolvedLengthValue(back, owner: "\(operationName) back")
        guard frontValue >= 0, backValue >= 0, frontValue + backValue > 0 else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) takes a front and a back thickness, neither negative, not both zero.")
        }
        let object = try offsetObject(for: targets, operationName: operationName)
        let faceTargets = targets.filter { if case .face = $0.component { true } else { false } }
        if faceTargets.isEmpty {
            guard targets.count == 1, productMetadata.sceneNodes[object.nodeID]?.object?.geometryRole == .surface else {
                throw EditorError(code: .commandInvalid, message: "\(operationName) grows a sheet object, or faces of a body.")
            }
            return try appendFeatureShownByObject(
                .thicken(ThickenFeature(target: ThickenTargetReference(featureID: object.featureID), front: front, back: back)),
                name: trimmedName, object: object.nodeID, geometryRole: .solid, objectRegistry: objectRegistry
            )
        }
        guard faceTargets.count == targets.count else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) grows either a sheet object or faces, not both.")
        }
        let topology = try TopologySnapshotService().snapshot(
            document: self, objectRegistry: objectRegistry, currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        let faces = try faceTargets.map { try stableReference(of: $0, kind: .face, in: topology, operationName: operationName) }
        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommit = false
        defer {
            if didCommit == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        let sheetID = FeatureID()
        try appendFeature(try FeatureNodeFactory.make(
            operation: .extract(ExtractFeature(target: PatternTargetReference(featureID: object.featureID), selection: .faces(faces))),
            id: sheetID, name: "\(trimmedName) Faces", in: cadDocument, tolerance: modelingSettings.tolerance
        ))
        let solidID = FeatureID()
        try appendFeature(try FeatureNodeFactory.make(
            operation: .thicken(ThickenFeature(target: ThickenTargetReference(featureID: sheetID), front: front, back: back)),
            id: solidID, name: trimmedName, in: cadDocument, tolerance: modelingSettings.tolerance
        ))
        let sourceName = productMetadata.sceneNodes[object.nodeID]?.name ?? trimmedName
        try insertBooleanResultNode(
            name: "\(sourceName) \(trimmedName)", featureID: solidID, geometryRole: .solid,
            besideTargetNode: object.nodeID, hierarchy: try SceneNodeHierarchy(metadata: productMetadata),
            objectRegistry: objectRegistry
        )
        try cadDocument.validate(tolerance: modelingSettings.tolerance)
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommit = true
        return solidID
    }
}

extension DesignDocument {
    /// Extend Sheet: open edges of one sheet object carried on by `distance` in `shape` (Swift-CAD
    /// `sheetExtend`). Modifying, the sheet shows the extended sheet in its place; otherwise the
    /// extensions are a new sheet object beside it.
    @discardableResult
    public mutating func extendSheet(
        name: String = "Extend Sheet",
        targets: [SelectionTarget],
        distance: CADExpression,
        shape: SheetExtensionShape,
        modifies: Bool,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> FeatureID {
        let operationName = "Extend Sheet"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
        guard try resolvedLengthValue(distance, owner: "\(operationName) distance") > 0 else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) distance must be positive.")
        }
        let object = try offsetObject(for: targets, operationName: operationName)
        guard productMetadata.sceneNodes[object.nodeID]?.object?.geometryRole == .surface else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) extends edges of a sheet.")
        }
        let topology = try TopologySnapshotService().snapshot(
            document: self, objectRegistry: objectRegistry, currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        let edges = try targets.map { try stableReference(of: $0, kind: .edge, in: topology, operationName: operationName) }
        let operation = FeatureOperation.sheetExtend(SheetExtendFeature(
            target: PatternTargetReference(featureID: object.featureID), edges: edges, distance: distance, shape: shape, modifies: modifies
        ))
        if modifies {
            return try appendFeatureShownByObject(operation, name: trimmedName, object: object.nodeID, objectRegistry: objectRegistry)
        }
        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommit = false
        defer {
            if didCommit == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        let featureID = FeatureID()
        try appendFeature(try FeatureNodeFactory.make(operation: operation, id: featureID, name: trimmedName, in: cadDocument, tolerance: modelingSettings.tolerance))
        let sourceName = productMetadata.sceneNodes[object.nodeID]?.name ?? trimmedName
        try insertBooleanResultNode(
            name: "\(sourceName) \(trimmedName)", featureID: featureID, geometryRole: .surface,
            besideTargetNode: object.nodeID, hierarchy: try SceneNodeHierarchy(metadata: productMetadata), objectRegistry: objectRegistry
        )
        try cadDocument.validate(tolerance: modelingSettings.tolerance)
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommit = true
        return featureID
    }
}

extension DesignDocument {
    /// Align Surface: the first target, an edge of a sheet object, follows the second, an edge of
    /// another object where it is shown, with `continuity`, the speed across the edge scaled by
    /// `tension` and the change faded over `blendRows` further control rows keeping
    /// `inputShapeInfluence` of their shape, faded in and out over `partialStart` and `partialEnd`
    /// of the edge, the sheet refitted to `layout` first when given (Swift-CAD `surfaceAlign`). The
    /// sheet shows the result in its place.
    @discardableResult
    public mutating func alignSurface(
        name: String = "Align Surface",
        targets: [SelectionTarget],
        continuity: SurfaceContinuityLevel,
        tension: Double,
        blendRows: Int,
        inputShapeInfluence: Double = 1,
        partialStart: Double = 0,
        partialEnd: Double = 0,
        layout: SurfaceControlLayout? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> FeatureID {
        let operationName = "Align Surface"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
        guard targets.count == 2 else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) takes an edge of a sheet, then the reference edge.")
        }
        guard tension.isFinite, tension > 0 else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) tension must be positive.")
        }
        guard (0...64).contains(blendRows) else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) blends from none to 64 further rows.")
        }
        guard (0...1).contains(inputShapeInfluence) else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) input shape influence runs from 0 to 1.")
        }
        guard (0...1).contains(partialStart), (0...1).contains(partialEnd), partialStart + partialEnd <= 1 else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) partial start and end are fractions of the edge that do not overlap.")
        }
        if let layout {
            do {
                try layout.validate()
            } catch {
                throw EditorError(code: .commandInvalid, message: "\(operationName) layout: \(error)")
            }
        }
        let object = try offsetObject(for: [targets[0]], operationName: operationName)
        let source = try offsetObject(for: [targets[1]], operationName: operationName)
        guard productMetadata.sceneNodes[object.nodeID]?.object?.geometryRole == .surface else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) aligns an edge of a sheet.")
        }
        guard source.nodeID != object.nodeID else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) aligns a sheet to an edge of another object.")
        }
        let topology = try TopologySnapshotService().snapshot(
            document: self, objectRegistry: objectRegistry, currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        let targetEdge = try stableReference(of: targets[0], kind: .edge, in: topology, operationName: operationName)
        let referenceEdge = try stableReference(of: targets[1], kind: .edge, in: topology, operationName: operationName)
        let placement = try relativeRigidPlacement(
            of: source.nodeID, inFrameOf: object.nodeID, owner: "The reference edge's object", relation: "the aligned sheet"
        )
        return try appendFeatureShownByObject(
            .surfaceAlign(SurfaceAlignFeature(
                target: PatternTargetReference(featureID: object.featureID), targetEdge: targetEdge,
                reference: PatternTargetReference(featureID: source.featureID), referenceEdge: referenceEdge,
                referencePlacement: placement, continuity: continuity, tension: tension, blendRows: blendRows,
                inputShapeInfluence: inputShapeInfluence, partialStart: partialStart, partialEnd: partialEnd, layout: layout
            )),
            name: trimmedName, object: object.nodeID, objectRegistry: objectRegistry
        )
    }
}

extension DesignDocument {
    /// Rebuild Face: faces of one object refitted as B-splines on their own parameters by
    /// `method`, widened by `extendU` and `extendV` of their extent, over the face's extent when
    /// `shrinks` (Swift-CAD `faceRebuild`). The object shows the result in its place.
    @discardableResult
    public mutating func rebuildFaces(
        name: String = "Rebuild Face",
        targets: [SelectionTarget],
        method: FaceRebuildMethod,
        extendU: Double,
        extendV: Double,
        shrinks: Bool,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> FeatureID {
        let operationName = "Rebuild Face"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
        switch method {
        case let .explicit(layout):
            do {
                try layout.validate()
            } catch {
                throw EditorError(code: .commandInvalid, message: "\(operationName) layout: \(error)")
            }
        case let .tolerance(distance):
            guard try resolvedLengthValue(distance, owner: "\(operationName) tolerance") > 0 else {
                throw EditorError(code: .commandInvalid, message: "\(operationName) tolerance must be positive.")
            }
        }
        guard FaceRebuildFeature.extensions.contains(extendU), FaceRebuildFeature.extensions.contains(extendV) else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) extends each way by 0 to 1 of the face's extent.")
        }
        let object = try offsetObject(for: targets, operationName: operationName)
        let topology = try TopologySnapshotService().snapshot(
            document: self, objectRegistry: objectRegistry, currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        let faces = try targets.map { try stableReference(of: $0, kind: .face, in: topology, operationName: operationName) }
        return try appendFeatureShownByObject(
            .faceRebuild(FaceRebuildFeature(
                target: PatternTargetReference(featureID: object.featureID), faces: faces, method: method,
                extendU: extendU, extendV: extendV, shrinks: shrinks
            )),
            name: trimmedName, object: object.nodeID, objectRegistry: objectRegistry
        )
    }

    /// Unwrap Face: one face of an object laid flat as a sheet object of its own in the world's XY
    /// plane about the origin (Swift-CAD `faceUnwrap`); the object stays as it is.
    @discardableResult
    public mutating func unwrapFace(
        name: String = "Unwrap Face",
        target: SelectionTarget,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> FeatureID {
        let operationName = "Unwrap Face"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
        let object = try offsetObject(for: [target], operationName: operationName)
        let topology = try TopologySnapshotService().snapshot(
            document: self, objectRegistry: objectRegistry, currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        let face = try stableReference(of: target, kind: .face, in: topology, operationName: operationName)
        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommit = false
        defer {
            if didCommit == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        let featureID = FeatureID()
        try appendFeature(try FeatureNodeFactory.make(
            operation: .faceUnwrap(FaceUnwrapFeature(target: PatternTargetReference(featureID: object.featureID), face: face)),
            id: featureID, name: trimmedName, in: cadDocument, tolerance: modelingSettings.tolerance
        ))
        // The flat sheet lies about the world's origin, not where its source is shown.
        let sourceName = productMetadata.sceneNodes[object.nodeID]?.name ?? trimmedName
        try insertBooleanResultNode(
            name: "\(sourceName) \(trimmedName)", featureID: featureID, geometryRole: .surface,
            besideTargetNode: nil, hierarchy: try SceneNodeHierarchy(metadata: productMetadata), objectRegistry: objectRegistry
        )
        try cadDocument.validate(tolerance: modelingSettings.tolerance)
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommit = true
        return featureID
    }

    /// The curve a selected edge of a body stands for, read from the body as it is now.
    public func edgeCurveFeature(
        for target: SelectionTarget,
        operationName: String,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext?,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> EdgeCurveFeature {
        let object = try offsetObject(for: [target], operationName: operationName)
        let role = productMetadata.sceneNodes[object.nodeID]?.object?.geometryRole
        let topology = try TopologySnapshotService().snapshot(
            document: self, objectRegistry: objectRegistry, currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        return EdgeCurveFeature(
            source: object.featureID,
            bodyRole: role == .surface ? .sheet : .body,
            edges: [try stableReference(of: target, kind: .edge, in: topology, operationName: operationName)]
        )
    }

    /// The vertex of a body a Loft ends at, read from the body as it is now.
    public func loftApex(
        for target: SelectionTarget,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext?,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> LoftApex {
        let object = try offsetObject(for: [target], operationName: "Loft")
        let role = productMetadata.sceneNodes[object.nodeID]?.object?.geometryRole
        let topology = try TopologySnapshotService().snapshot(
            document: self, objectRegistry: objectRegistry, currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        return LoftApex(source: object.featureID, bodyRole: role == .surface ? .sheet : .body,
                        vertex: try stableReference(of: target, kind: .vertex, in: topology, operationName: "Loft"))
    }

    /// The section a selected planar face of a body stands for, read from the body as it is now.
    public func faceSectionReference(
        for target: SelectionTarget,
        operationName: String,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext?,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> FaceSectionReference {
        let object = try offsetObject(for: [target], operationName: operationName)
        let role = productMetadata.sceneNodes[object.nodeID]?.object?.geometryRole
        let topology = try TopologySnapshotService().snapshot(
            document: self, objectRegistry: objectRegistry, currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        return FaceSectionReference(
            featureID: object.featureID,
            face: try stableReference(of: target, kind: .face, in: topology, operationName: operationName),
            bodyRole: role == .surface ? .sheet : .body
        )
    }
}

extension DesignDocument {
    /// Extrude on planar faces of one object: each face its own extrusion of the face (Swift-CAD
    /// `extrude` of a face section), along its outward normal when `individual` and otherwise
    /// along the first face's (Direct). A new-body extrusion shows as an object of its own; with a
    /// Boolean, the extrusions are the tools of one Boolean with the object the faces lie on, which
    /// takes over showing the result (Keep Tools keeps them).
    @discardableResult
    public mutating func extrudeFaces(
        name: String = "Extrude",
        targets: [SelectionTarget],
        distance: CADExpression,
        startDistance: CADExpression? = nil,
        individual: Bool,
        operation: SolidOperation = .newBody,
        keepTools: Bool = false,
        draftAngle: CADExpression? = nil,
        thickness: CADExpression? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> [FeatureID] {
        let operationName = "Extrude"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
        let object = try offsetObject(for: targets, operationName: operationName)
        let role = productMetadata.sceneNodes[object.nodeID]?.object?.geometryRole
        let bodyRole: FeaturePort = role == .surface ? .sheet : .body
        let previous = self
        var didCommit = false
        defer { if !didCommit { self = previous } }
        let topology = try TopologySnapshotService().snapshot(
            document: self, objectRegistry: objectRegistry, currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        // Direct runs every face along the first face's outward normal, in the object's frame.
        var direction = ExtrudeDirection.normal
        if individual == false, targets.count > 1 {
            guard let first = targets.first,
                  let entry = topology.entries.first(where: { $0.selectionTarget() == first }), let normal = entry.surfaceNormal else {
                throw EditorError(code: .commandInvalid, message: "\(operationName) needs the first face's normal.")
            }
            let world = Vector3D(x: normal.x, y: normal.y, z: normal.z)
            let local = try SceneNodeHierarchy(metadata: productMetadata).worldTransform(of: object.nodeID).inverseApplyingLinearPart(to: world)
            direction = .vector(try local.normalized(tolerance: modelingSettings.tolerance.distance))
        }
        // Every face read from the object as it is now, so each extrudes the face selected.
        let references = try targets.map { try stableReference(of: $0, kind: .face, in: topology, operationName: operationName) }
        var created: [FeatureID] = []
        for reference in references {
            created.append(try extrudeSection(
                name: trimmedName,
                section: .face(FaceSectionReference(featureID: object.featureID, face: reference, bodyRole: bodyRole)),
                distance: distance, startDistance: startDistance, direction: direction,
                resultKind: .solid, draftAngle: draftAngle, thickness: thickness, objectRegistry: objectRegistry
            ))
        }
        if operation != .newBody {
            let boolean: BooleanOperation = switch operation {
            case .union: .union
            case .difference: .difference
            case .intersect: .intersect
            case .slice: .slice
            case .newBody: .union
            }
            created.append(try createBoolean(
                name: trimmedName,
                targets: [BooleanTargetReference(featureID: object.featureID)],
                tools: created.map { BooleanToolReference(featureID: $0) },
                operation: boolean,
                keepTools: keepTools,
                objectRegistry: objectRegistry
            ))
        }
        didCommit = true
        return created
    }
}
