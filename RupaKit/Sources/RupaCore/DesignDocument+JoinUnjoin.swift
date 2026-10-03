import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Join on sheets: the sheets are sewn along their exactly matching edges into one object, a
    /// solid when they close and a sheet otherwise, which the first sheet's object shows. Every
    /// sheet is joined where it is displayed, in the first sheet's frame. The other sheets'
    /// objects are taken away.
    @discardableResult
    public mutating func joinSheets(
        name: String = "Join",
        targets: [SelectionTarget],
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> FeatureID {
        let operationName = "Join"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
        var sheets: [(nodeID: SceneNodeID, featureID: FeatureID)] = []
        for target in targets where sheets.contains(where: { $0.nodeID == target.sceneNodeID }) == false {
            let resolved = try bodyObject(target, operationName: operationName)
            guard try bodyOrSheetPort(of: resolved.featureID, owner: operationName) == .sheet else {
                throw EditorError(code: .commandInvalid, message: "\(operationName) sews sheets; a solid is not joined.")
            }
            sheets.append(resolved)
        }
        guard sheets.count >= 2 else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) needs at least two sheets.")
        }
        let frame = sheets[0].nodeID
        let references = try sheets.map { sheet in
            JoinBodiesTargetReference(
                featureID: sheet.featureID,
                placement: try relativeRigidPlacement(
                    of: sheet.nodeID, inFrameOf: frame, owner: "Every sheet to join", relation: "the first sheet"
                )
            )
        }
        let evaluated = try DocumentEvaluationContextResolver().evaluatedDocument(
            document: self, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration,
            failurePrefix: "\(operationName) requires its sheets evaluated"
        )
        let closes: Bool
        do {
            closes = try JoinSheetClosure().closes(sheets: references, in: evaluated)
        } catch let error as KernelError where error.code == .invalidInput || error.code == .nonManifoldResult {
            throw EditorError(code: .commandInvalid, message: "\(operationName): \(error.message)")
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
        try appendFeature(try FeatureNodeFactory.make(
            operation: .joinBodies(JoinBodiesFeature(targets: references, mode: closes ? .sewnSolid : .sewnSheet)),
            id: featureID, name: trimmedName, in: cadDocument, tolerance: modelingSettings.tolerance
        ))
        let firstName = productMetadata.sceneNodes[frame]?.name ?? trimmedName
        try retargetBodyNode(frame, to: featureID, name: firstName, geometryRole: closes ? .solid : .surface)
        try removeSceneNodes(presenting: sheets.dropFirst().map(\.featureID))
        try cadDocument.validate(tolerance: modelingSettings.tolerance)
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommit = true
        return featureID
    }

    /// Unjoin on faces: each chosen face leaves its body as a sheet of its own, and what remains
    /// of the body stays as sheets, one per piece that still hangs together. The pieces are shown
    /// where the body was, and the body's object is taken away.
    @discardableResult
    public mutating func unjoinFaces(
        name: String = "Unjoin",
        targets: [SelectionTarget],
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> [FeatureID] {
        let operationName = "Unjoin"
        _ = try normalizedMetadataName(name, owner: operationName)
        guard targets.isEmpty == false else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) requires at least one face.")
        }
        let topology = try TopologySnapshotService().snapshot(
            document: self, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        var chosenByBody: [(body: (nodeID: SceneNodeID, featureID: FeatureID), faces: Set<String>)] = []
        for target in targets {
            guard case .face(let componentID) = target.component,
                  let subshapeID = componentID.generatedTopologySubshapeID else {
                throw EditorError(code: .commandInvalid, message: "\(operationName) separates faces of bodies.")
            }
            let body = try bodyObject(SelectionTarget(sceneNodeID: target.sceneNodeID), operationName: operationName)
            let identity = GeneratedSubshapeIdentity.string(for: subshapeID)
            if let index = chosenByBody.firstIndex(where: { $0.body.nodeID == body.nodeID }) {
                chosenByBody[index].faces.insert(identity)
            } else {
                chosenByBody.append((body, [identity]))
            }
        }
        return try separatingFaces(
            chosenByBody.map { ($0.body, Optional($0.faces)) }, topology: topology,
            objectRegistry: objectRegistry, currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration, operationName: operationName
        )
    }

    /// Unjoin on solids or sheets: every face of each becomes a sheet of its own, shown where the
    /// object was, and the object is taken away.
    @discardableResult
    public mutating func unjoinShells(
        name: String = "Unjoin",
        targets: [SelectionTarget],
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> [FeatureID] {
        let operationName = "Unjoin"
        _ = try normalizedMetadataName(name, owner: operationName)
        var bodies: [(nodeID: SceneNodeID, featureID: FeatureID)] = []
        for target in targets where bodies.contains(where: { $0.nodeID == target.sceneNodeID }) == false {
            guard target.component == .object else {
                throw EditorError(code: .commandInvalid, message: "\(operationName) separates the faces of whole solids or sheets.")
            }
            bodies.append(try bodyObject(target, operationName: operationName))
        }
        guard bodies.isEmpty == false else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) requires a solid or a sheet.")
        }
        let topology = try TopologySnapshotService().snapshot(
            document: self, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        return try separatingFaces(
            bodies.map { ($0, nil) }, topology: topology,
            objectRegistry: objectRegistry, currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration, operationName: operationName
        )
    }

    /// The object `target` names, when it shows a body of its own (not an instance of one).
    func bodyObject(
        _ target: SelectionTarget, operationName: String
    ) throws -> (nodeID: SceneNodeID, featureID: FeatureID) {
        guard let node = productMetadata.sceneNodes[target.sceneNodeID],
              let reference = node.reference, reference.kind == .body, let featureID = reference.featureID else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) works on solid and sheet objects; realize an instance first."
            )
        }
        return (target.sceneNodeID, featureID)
    }

    /// Each body's chosen faces (every face when `nil`) become sheets of their own, and the rest
    /// of the body stays as sheets, one per piece. One Unjoin feature consumes the body and holds
    /// the pieces as its shells; each piece is extracted as an object of its own beside the body's,
    /// which is taken away. A body that stays in one piece keeps its object.
    private mutating func separatingFaces(
        _ bodies: [(body: (nodeID: SceneNodeID, featureID: FeatureID), chosen: Set<String>?)],
        topology: TopologySnapshot,
        objectRegistry: ObjectTypeRegistry,
        currentEvaluation: DocumentEvaluationContext?,
        currentGeneration: DocumentGeneration?,
        operationName: String
    ) throws -> [FeatureID] {
        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommit = false
        defer {
            if didCommit == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        var pieces: [FeatureID] = []
        for (body, chosen) in bodies {
            let sourceName = productMetadata.sceneNodes[body.nodeID]?.name ?? operationName
            let selection: UnjoinFacesSelection
            if let chosen {
                let faces = topology.entries.filter {
                    $0.kind == .face && $0.sceneNodeID == body.nodeID.description && chosen.contains($0.subshapeID)
                }
                guard faces.count == chosen.count else {
                    throw EditorError(code: .referenceUnresolved, message: "\(operationName) could not resolve a chosen face.")
                }
                selection = .faces(try faces.map { face in
                    guard let reference = face.stableReference else {
                        throw EditorError(code: .referenceUnresolved, message: "\(operationName) found a face with no stable reference.")
                    }
                    return reference
                })
            } else {
                selection = .everyFace
            }
            let unjoinID = FeatureID()
            try appendFeature(try FeatureNodeFactory.make(
                operation: .unjoinFaces(UnjoinFacesFeature(
                    target: PatternTargetReference(featureID: body.featureID), selection: selection
                )),
                id: unjoinID, name: sourceName, in: cadDocument, tolerance: modelingSettings.tolerance
            ))
            let count = try bodyComponentCount(
                of: unjoinID, objectRegistry: objectRegistry,
                currentEvaluation: currentEvaluation, currentGeneration: currentGeneration, owner: operationName
            )
            if count == 1 {
                try retargetBodyNode(body.nodeID, to: unjoinID, name: sourceName, geometryRole: .surface)
                pieces.append(unjoinID)
                continue
            }
            // Insert in reverse so the pieces read in order beside the body.
            var created: [FeatureID] = []
            for index in (0..<count).reversed() {
                let pieceID = FeatureID()
                let pieceName = "\(sourceName) \(index + 1)"
                try appendFeature(try FeatureNodeFactory.make(
                    operation: .extract(ExtractFeature(
                        target: PatternTargetReference(featureID: unjoinID),
                        selection: .component(index: index, count: count)
                    )),
                    id: pieceID, name: pieceName, in: cadDocument, tolerance: modelingSettings.tolerance
                ))
                try insertBooleanResultNode(
                    name: pieceName, featureID: pieceID, geometryRole: .surface,
                    besideTargetNode: body.nodeID, hierarchy: try SceneNodeHierarchy(metadata: productMetadata),
                    objectRegistry: objectRegistry
                )
                created.append(pieceID)
            }
            pieces += created.reversed()
            try removeSceneNodes(presenting: [body.featureID])
        }
        try cadDocument.validate(tolerance: modelingSettings.tolerance)
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommit = true
        return pieces
    }
}
