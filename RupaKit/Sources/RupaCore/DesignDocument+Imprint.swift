import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Imprint Curve Body: the selected curves (sketch curves, or every curve of a curve object)
    /// are projected onto the target object where each is shown, and the target's faces are split
    /// along them (Swift-CAD `imprintCurves`). A vector projection's direction is given in the
    /// world and carried into the target's frame. The target shows the result in its place.
    @discardableResult
    public mutating func imprintCurves(
        name: String = "Imprint",
        target: SceneNodeID,
        curves: [SelectionTarget],
        projection: ImprintProjection,
        completion: ImprintCompletion,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> FeatureID {
        let operationName = "Imprint"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
        let targetFeatureID = try imprintedObject(target, operationName: operationName)
        guard curves.isEmpty == false else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) requires curves to imprint.")
        }
        let evaluated = try DocumentEvaluationContextResolver().evaluatedDocument(
            document: self, objectRegistry: objectRegistry, currentEvaluation: currentEvaluation, currentGeneration: currentGeneration,
            failurePrefix: "\(operationName) requires its curves evaluated"
        )
        var references: [ImprintCurveReference] = []
        for selection in curves {
            let placement = try relativeRigidPlacement(of: selection.sceneNodeID, inFrameOf: target, owner: "Every imprinted curve", relation: "the target")
            for curve in try curveOutputs(of: selection, in: evaluated, operationName: operationName)
            where references.contains(where: { $0.curve == curve }) == false {
                references.append(ImprintCurveReference(curve: curve, placement: placement))
            }
        }
        var localProjection = projection
        if case let .vector(direction, bidirectional, hidesOcclusion) = projection {
            let frame = try SceneNodeHierarchy(metadata: productMetadata).worldTransform(of: target)
            localProjection = .vector(
                direction: try frame.inverseApplyingLinearPart(to: direction),
                bidirectional: bidirectional, hidesOcclusion: hidesOcclusion
            )
        }
        return try appendFeatureShownByObject(
            .imprintCurves(ImprintCurvesFeature(
                target: PatternTargetReference(featureID: targetFeatureID), curves: references,
                projection: localProjection, completion: completion
            )),
            name: trimmedName, object: target, objectRegistry: objectRegistry
        )
    }

    /// Imprint Body Body: the target's faces are split where the tool crosses them, each where it
    /// is shown (Swift-CAD `imprintBody`), and with `imprintsTool` the tool's faces too, where the
    /// imprinted target crosses them. Each object shows its result in its place.
    @discardableResult
    public mutating func imprintBodies(
        name: String = "Imprint",
        target: SceneNodeID,
        tool: SceneNodeID,
        targetCompletion: ImprintCompletion,
        imprintsTool: Bool,
        toolCompletion: ImprintCompletion,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [FeatureID] {
        let operationName = "Imprint"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
        guard target != tool else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) needs a tool other than its target.")
        }
        let targetFeatureID = try imprintedObject(target, operationName: operationName)
        let toolFeatureID = try imprintedObject(tool, operationName: operationName)
        let previous = self
        var didCommit = false
        defer { if !didCommit { self = previous } }
        let imprintedTarget = try appendFeatureShownByObject(
            .imprintBody(ImprintBodyFeature(
                target: PatternTargetReference(featureID: targetFeatureID), tool: PatternTargetReference(featureID: toolFeatureID),
                toolPlacement: try relativeRigidPlacement(of: tool, inFrameOf: target, owner: "The tool", relation: "the target"),
                completion: targetCompletion
            )),
            name: trimmedName, object: target, objectRegistry: objectRegistry
        )
        var result = [imprintedTarget]
        if imprintsTool {
            result.append(try appendFeatureShownByObject(
                .imprintBody(ImprintBodyFeature(
                    target: PatternTargetReference(featureID: toolFeatureID), tool: PatternTargetReference(featureID: imprintedTarget),
                    toolPlacement: try relativeRigidPlacement(of: target, inFrameOf: tool, owner: "The target", relation: "the tool"),
                    completion: toolCompletion
                )),
                name: trimmedName, object: tool, objectRegistry: objectRegistry
            ))
        }
        didCommit = true
        return result
    }

    /// Isoparam on a face: lines along the face's surface parameters at `fractions` of its
    /// extent across `direction` are imprinted (Swift-CAD `isoparam`), subdividing a B-spline
    /// control net when asked. The object shows the result in its place.
    @discardableResult
    public mutating func isoparam(
        name: String = "Isoparam",
        face: SelectionTarget,
        direction: SurfaceParameterDirection,
        fractions: [Double],
        subdividesControlNet: Bool,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> FeatureID {
        let operationName = "Isoparam"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
        let targetFeatureID = try imprintedObject(face.sceneNodeID, operationName: operationName)
        let reference = try imprintedFaceReference(face, objectRegistry: objectRegistry, currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration, operationName: operationName)
        return try appendFeatureShownByObject(
            .isoparam(IsoparamFeature(
                target: PatternTargetReference(featureID: targetFeatureID), face: reference, direction: direction,
                fractions: fractions, subdividesControlNet: subdividesControlNet
            )),
            name: trimmedName, object: face.sceneNodeID, objectRegistry: objectRegistry
        )
    }

    /// Untrim on a face: a sheet of the face's untrimmed surface (Swift-CAD `untrimFace`), keeping
    /// the face's own edges on it when asked, as a new object beside the body's, placed like it.
    @discardableResult
    public mutating func untrimFace(
        name: String = "Untrim",
        face: SelectionTarget,
        keepsEdges: Bool,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> FeatureID {
        let operationName = "Untrim"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
        let targetFeatureID = try imprintedObject(face.sceneNodeID, operationName: operationName)
        let reference = try imprintedFaceReference(face, objectRegistry: objectRegistry, currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration, operationName: operationName)
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
            operation: .untrimFace(UntrimFaceFeature(
                target: PatternTargetReference(featureID: targetFeatureID), face: reference, keepsEdges: keepsEdges
            )),
            id: featureID, name: trimmedName, in: cadDocument, tolerance: modelingSettings.tolerance
        ))
        let sourceName = productMetadata.sceneNodes[face.sceneNodeID]?.name ?? trimmedName
        try insertBooleanResultNode(
            name: "\(sourceName) \(trimmedName)", featureID: featureID, geometryRole: .surface,
            besideTargetNode: face.sceneNodeID, hierarchy: try SceneNodeHierarchy(metadata: productMetadata),
            objectRegistry: objectRegistry
        )
        try cadDocument.validate(tolerance: modelingSettings.tolerance)
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommit = true
        return featureID
    }

    /// The body feature an object imprinted on shows; instances are refused.
    private func imprintedObject(_ nodeID: SceneNodeID, operationName: String) throws -> FeatureID {
        guard let reference = productMetadata.sceneNodes[nodeID]?.reference, reference.kind == .body, let featureID = reference.featureID else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) works on solid and sheet objects; realize an instance first.")
        }
        return featureID
    }

    /// The stable reference of a selected face of a body object.
    private func imprintedFaceReference(
        _ face: SelectionTarget, objectRegistry: ObjectTypeRegistry, currentEvaluation: DocumentEvaluationContext?,
        currentGeneration: DocumentGeneration?, operationName: String
    ) throws -> StableSubshapeReference {
        guard case .face(let componentID) = face.component else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) works on a face.")
        }
        let topology = try TopologySnapshotService().snapshot(
            document: self, objectRegistry: objectRegistry, currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        guard let reference = topology.entries.first(where: {
            $0.kind == .face && $0.sceneNodeID == face.sceneNodeID.description && $0.selectionComponentID == componentID.rawValue
        })?.stableReference else {
            throw EditorError(code: .referenceUnresolved, message: "\(operationName) could not resolve the selected face.")
        }
        return reference
    }

    /// The evaluated curves a selection names: one sketch curve, or every curve of a curve object.
    private func curveOutputs(of selection: SelectionTarget, in evaluated: EvaluatedDocument, operationName: String) throws -> [CurveOutputReference] {
        switch selection.component {
        case .sketchEntity(let componentID):
            guard let reference = componentID.sketchEntityReference,
                  componentID.sketchPointHandleReference == nil, componentID.sketchControlPointReference == nil,
                  let index = evaluated.curves[reference.featureID]?.firstIndex(where: { $0.source == .sketchEntity(reference.entityID) }) else {
                throw EditorError(code: .commandInvalid, message: "\(operationName) imprints whole curves, not their points.")
            }
            return [CurveOutputReference(featureID: reference.featureID, curveIndex: index)]
        case .object:
            guard let featureID = productMetadata.sceneNodes[selection.sceneNodeID]?.reference?.featureID,
                  let curves = evaluated.curves[featureID], curves.isEmpty == false else {
                throw EditorError(code: .commandInvalid, message: "\(operationName) imprints curves; the object has none.")
            }
            return curves.indices.map { CurveOutputReference(featureID: featureID, curveIndex: $0) }
        default:
            throw EditorError(code: .commandInvalid, message: "\(operationName) imprints curves.")
        }
    }

    /// Appends `operation` as a feature the object then shows in its place, keeping its name.
    mutating func appendFeatureShownByObject(
        _ operation: FeatureOperation, name: String, object: SceneNodeID, objectRegistry: ObjectTypeRegistry
    ) throws -> FeatureID {
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
            operation: operation, id: featureID, name: name, in: cadDocument, tolerance: modelingSettings.tolerance
        ))
        let node = productMetadata.sceneNodes[object]
        try retargetBodyNode(object, to: featureID, name: node?.name ?? name, geometryRole: node?.object?.geometryRole ?? .solid)
        try cadDocument.validate(tolerance: modelingSettings.tolerance)
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommit = true
        return featureID
    }
}
