import Foundation
import SwiftCAD
import RupaCoreTypes

/// What a Cut cuts with.
public enum CutCutter: Codable, Hashable, Sendable {
    /// A generated face of a body: the face itself, as a sheet.
    case face(SelectionTarget)
    /// An object whose feature yields curves (a sketch, a spatial curve): the curves extruded
    /// through the targets as a sheet.
    case curve(SceneNodeID)
}

/// How a Cut makes sheets of its curve cutters.
public struct CutOptions: Codable, Hashable, Sendable {
    /// Lengthens each curve cutter past both ends so it reaches through the targets.
    public var extendsCurves: Bool
    /// The world direction curve cutters are extruded along; `nil` extrudes each along its plane's
    /// normal.
    public var direction: Vector3D?

    public init(extendsCurves: Bool = false, direction: Vector3D? = nil) {
        self.extendsCurves = extendsCurves
        self.direction = direction
    }
}

extension DesignDocument {
    /// Cuts the target bodies, solids or sheets, with each cutter in turn, and shows every
    /// resulting piece as an object of its own.
    ///
    /// Each cutter becomes a sheet that reaches through the targets, kept by a hidden object
    /// placed where the cutter is displayed: a face through a Swift-CAD `extract` of it, a curve
    /// through a sheet extrusion (after a `curveExtend` of both ends when asked) whose extent
    /// spans the targets along its direction. The targets are sliced by the first cutter, the
    /// pieces by the next, and so on, each cutter taken as solid behind its normals so the pieces
    /// on both sides are kept; the last slice's pieces are extracted one object each.
    @discardableResult
    public mutating func cut(
        name: String,
        targets: [SceneNodeID],
        cutters: [CutCutter],
        options: CutOptions = CutOptions(),
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let operationName = "Cut"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
        guard targets.isEmpty == false else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) requires at least one target body.")
        }
        guard cutters.isEmpty == false else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) requires at least one cutter.")
        }
        if let direction = options.direction {
            guard direction.x.isFinite, direction.y.isFinite, direction.z.isFinite, direction.length > 0 else {
                throw EditorError(code: .commandInvalid, message: "\(operationName) direction must be a finite nonzero vector.")
            }
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

        let targetFeatures = try targets.map { nodeID -> FeatureID in
            guard let node = productMetadata.sceneNodes[nodeID], node.reference?.kind == .body,
                  let featureID = node.reference?.featureID else {
                throw EditorError(code: .commandInvalid, message: "\(operationName) targets must be body objects.")
            }
            _ = try bodyOrSheetPort(of: featureID, owner: "\(operationName) target")
            return featureID
        }
        let evaluated = try DocumentEvaluationContextResolver().evaluatedDocument(
            document: self,
            objectRegistry: objectRegistry,
            failurePrefix: "\(operationName) requires its targets evaluated"
        )
        let reach = try targetReach(targets: targets, features: targetFeatures, in: evaluated, owner: operationName)

        var cutterFeatures: [FeatureID] = []
        for (index, cutter) in cutters.enumerated() {
            let cutterName = "\(trimmedName) Cutter \(index + 1)"
            switch cutter {
            case let .face(target):
                cutterFeatures.append(try appendFaceCutter(target, name: cutterName, owner: operationName, objectRegistry: objectRegistry))
            case let .curve(nodeID):
                cutterFeatures.append(try appendCurveCutter(
                    nodeID, name: cutterName, reach: reach, options: options,
                    evaluated: evaluated, owner: operationName, objectRegistry: objectRegistry
                ))
            }
        }

        var current = targetFeatures
        // The targets, the cutters and every intermediate slice are consumed by the next slice.
        var consumed = targetFeatures + cutterFeatures
        var last: AppendedBoolean?
        for (index, cutter) in cutterFeatures.enumerated() {
            let isLast = index == cutterFeatures.count - 1
            let boolean = try appendBooleanFeature(
                name: isLast ? trimmedName : "\(trimmedName) Step \(index + 1)",
                targets: current,
                tools: [cutter],
                operation: .slice,
                keepTools: false,
                targetMaterial: .default,
                toolMaterial: .inside
            )
            if isLast == false {
                // The next slice places this one's pieces where the first target is.
                try insertBooleanResultNode(
                    name: "\(trimmedName) Step \(index + 1)", featureID: boolean.featureID,
                    geometryRole: boolean.resultPort == FeaturePort.sheet ? ObjectDescriptor.GeometryRole.surface : .solid,
                    besideTargetNode: try SceneNodeHierarchy(metadata: productMetadata).presentingSceneNodeID(for: targetFeatures[0]),
                    hierarchy: try SceneNodeHierarchy(metadata: productMetadata),
                    isVisible: false,
                    objectRegistry: objectRegistry
                )
            }
            if isLast == false { consumed.append(boolean.featureID) }
            current = [boolean.featureID]
            last = boolean
        }
        guard let last else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) produced no slice.")
        }
        try publishBooleanResult(
            last, name: trimmedName, asPieces: true, besideTarget: targetFeatures[0],
            consumed: consumed, objectRegistry: objectRegistry
        )
        try cadDocument.validate(tolerance: modelingSettings.tolerance)
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommit = true
        return last.featureID
    }

    /// The world corners of a box around every target and how far apart they lie at most.
    private func targetReach(
        targets: [SceneNodeID],
        features: [FeatureID],
        in evaluated: EvaluatedDocument,
        owner: String
    ) throws -> (corners: [Point3D], diagonal: Double) {
        let hierarchy = try SceneNodeHierarchy(metadata: productMetadata)
        var corners: [Point3D] = []
        for (nodeID, featureID) in zip(targets, features) {
            guard case let .body(bodyID) = evaluated.subshapes[SubshapeID(featureID: featureID, role: GeneratedSubshapeRole.body.rawValue, ordinal: 0)] else {
                throw EditorError(code: .referenceUnresolved, message: "\(owner) target has no evaluated body.")
            }
            let bounds = try BRepBodyBoundingBoxBuilder().bounds(for: bodyID, in: evaluated.brep, tolerance: modelingSettings.tolerance)
            let world = try hierarchy.worldTransform(of: nodeID)
            for x in [bounds.minimum.x, bounds.maximum.x] {
                for y in [bounds.minimum.y, bounds.maximum.y] {
                    for z in [bounds.minimum.z, bounds.maximum.z] {
                        corners.append(try world.applied(to: Point3D(x: x, y: y, z: z)))
                    }
                }
            }
        }
        var diagonal = 0.0
        for a in corners {
            for b in corners { diagonal = max(diagonal, (a - b).length) }
        }
        return (corners, diagonal)
    }

    /// A face cutter: the face copied as a sheet, kept by a hidden object placed like its body.
    private mutating func appendFaceCutter(
        _ target: SelectionTarget,
        name: String,
        owner: String,
        objectRegistry: ObjectTypeRegistry
    ) throws -> FeatureID {
        guard case .face(let componentID) = target.component,
              let subshapeID = componentID.generatedTopologySubshapeID else {
            throw EditorError(code: .commandInvalid, message: "\(owner) face cutters must be generated faces.")
        }
        let resolved = try editableBodyTargetResolution(for: target, operationName: owner)
        let identity = GeneratedSubshapeIdentity.string(for: subshapeID)
        let topology = try TopologySnapshotService().snapshot(document: self, objectRegistry: objectRegistry)
        guard let entry = topology.entries.first(where: { $0.subshapeID == identity }), entry.kind == .face,
              let stableReference = entry.stableReference else {
            throw EditorError(code: .referenceUnresolved, message: "\(owner) face cutter is not in the current evaluation.")
        }
        let featureID = FeatureID()
        try appendFeature(try FeatureNodeFactory.make(
            operation: .extract(ExtractFeature(
                target: PatternTargetReference(featureID: resolved.featureID),
                selection: .faces([stableReference])
            )),
            id: featureID, name: name, in: cadDocument, tolerance: modelingSettings.tolerance
        ))
        try insertBooleanResultNode(
            name: name, featureID: featureID, geometryRole: .surface,
            besideTargetNode: resolved.sceneNodeID, hierarchy: try SceneNodeHierarchy(metadata: productMetadata),
            isVisible: false, objectRegistry: objectRegistry
        )
        return featureID
    }

    /// A curve cutter: the curves extruded as a sheet along the cut direction far enough to pass
    /// through every target, lengthened first when asked, kept by a hidden object placed like the
    /// curves.
    private mutating func appendCurveCutter(
        _ nodeID: SceneNodeID,
        name: String,
        reach: (corners: [Point3D], diagonal: Double),
        options: CutOptions,
        evaluated: EvaluatedDocument,
        owner: String,
        objectRegistry: ObjectTypeRegistry
    ) throws -> FeatureID {
        guard let node = productMetadata.sceneNodes[nodeID], let curveFeature = node.reference?.featureID,
              cadDocument.designGraph.nodes[curveFeature]?.outputs.contains(where: { $0.role == .curve }) == true else {
            throw EditorError(code: .commandInvalid, message: "\(owner) curve cutters must be curve objects.")
        }
        let curves = evaluated.curves[curveFeature] ?? []
        let points = curves.flatMap(\.points)
        guard points.isEmpty == false else {
            throw EditorError(code: .referenceUnresolved, message: "\(owner) curve cutter has no evaluated curve.")
        }
        let world = try SceneNodeHierarchy(metadata: productMetadata).worldTransform(of: nodeID)
        // Everything below is in the curves' own frame.
        let axis: Vector3D
        let direction: ExtrudeDirection
        if let worldDirection = options.direction {
            let local = try world.inverseApplyingLinearPart(to: worldDirection)
            axis = local * (1 / local.length)
            direction = .vector(axis)
        } else {
            guard let plane = curves.first?.plane, curves.allSatisfy({ $0.plane == plane }) else {
                throw EditorError(code: .commandInvalid, message: "\(owner) needs a direction for a curve cutter that does not lie in one plane.")
            }
            axis = try SketchPlaneCoordinateSystem(plane: plane).normal
            direction = .normal
        }
        let inverse = try world.inverse()
        let corners = try reach.corners.map { try inverse.applied(to: $0) }
        func along(_ point: Point3D) -> Double { point.x * axis.x + point.y * axis.y + point.z * axis.z }
        let margin = max(reach.diagonal * 0.1, modelingSettings.tolerance.distance * 1_000)
        let cornerSpan = corners.map(along), curveSpan = points.map(along)
        guard let cornerLow = cornerSpan.min(), let cornerHigh = cornerSpan.max(),
              let curveLow = curveSpan.min(), let curveHigh = curveSpan.max() else {
            throw EditorError(code: .referenceUnresolved, message: "\(owner) could not size its cutter.")
        }
        var sectionFeature = curveFeature
        if options.extendsCurves {
            let extendID = FeatureID()
            try appendFeature(try FeatureNodeFactory.make(
                operation: .curveExtend(CurveExtendFeature(
                    source: CurveOutputReference(featureID: curveFeature),
                    end: .both,
                    distance: .length(reach.diagonal + margin, .meter)
                )),
                id: extendID, name: "\(name) Extension", in: cadDocument, tolerance: modelingSettings.tolerance
            ))
            sectionFeature = extendID
        }
        let extrudeID = FeatureID()
        let extrude = ExtrudeFeature(
            section: .curve(CurveSectionReference(featureID: sectionFeature)),
            distance: .length(cornerHigh - curveLow + margin, .meter),
            startDistance: .length(cornerLow - curveHigh - margin, .meter),
            direction: direction,
            resultKind: .sheet
        )
        try appendFeature(try FeatureNodeFactory.make(
            operation: .extrude(extrude), id: extrudeID, name: name, in: cadDocument, tolerance: modelingSettings.tolerance
        ))
        try insertBooleanResultNode(
            name: name, featureID: extrudeID, geometryRole: .surface,
            besideTargetNode: nodeID, hierarchy: try SceneNodeHierarchy(metadata: productMetadata),
            isVisible: false, objectRegistry: objectRegistry
        )
        return extrudeID
    }
}
