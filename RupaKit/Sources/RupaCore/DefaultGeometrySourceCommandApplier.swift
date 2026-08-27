import Foundation
import SwiftCAD
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel

public struct DefaultGeometrySourceCommandApplier: GeometrySourceCommandApplying {
    private let meshEditPlanExecutor: any MeshEditPlanExecuting

    public init() {
        self.meshEditPlanExecutor = DefaultMeshEditPlanExecutor()
    }

    package init(meshEditPlanExecutor: any MeshEditPlanExecuting) {
        self.meshEditPlanExecutor = meshEditPlanExecutor
    }

    public func apply(
        _ command: GeometrySourceCommand,
        to document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> GeometrySourceCommandApplication {
        _ = try document.validate(objectRegistry: objectRegistry)
        switch command {
        case .editAuthoredMesh(let edit):
            return try apply(
                edit,
                to: document,
                objectRegistry: objectRegistry
            )
        case .makeCADRepresentationEditable(let makeEditable):
            return try apply(
                makeEditable,
                to: document,
                objectRegistry: objectRegistry
            )
        case .selectRepresentation(let selection):
            return try apply(
                selection,
                to: document,
                objectRegistry: objectRegistry
            )
        }
    }

    private func apply(
        _ command: MakeCADRepresentationEditableCommand,
        to document: DesignDocument,
        objectRegistry: ObjectTypeRegistry
    ) throws -> GeometrySourceCommandApplication {
        try command.validate()
        guard command.evaluationSnapshotID.projectID == document.projectID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Make Editable evaluation snapshot belongs to a different project."
            )
        }
        guard var sceneNode = document.productMetadata.sceneNodes[command.sceneNodeID],
              var object = sceneNode.object else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Make Editable requires an existing Product Object."
            )
        }
        guard object.category == .body else {
            throw EditorError(
                code: .commandInvalid,
                message: "Make Editable currently supports CAD body representations only."
            )
        }
        guard let sourceRepresentation = object.geometryRepresentations
            .representations[command.sourceRepresentationID],
              sourceRepresentation.source == command.sourceReference else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Make Editable source representation is not retained by the target object."
            )
        }
        guard case .cad = sourceRepresentation.source else {
            throw EditorError(
                code: .commandInvalid,
                message: "Make Editable source representation must be CAD-authored."
            )
        }
        guard var selection = object.geometryRepresentations.selection,
              selection.modeling == command.sourceRepresentationID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Make Editable source representation must be the current modeling selection."
            )
        }
        let currentSourceIdentity: ContentIdentity
        do {
            currentSourceIdentity = try CADSourceContentIdentityService().identity(for: document)
        } catch let error as EditorError {
            throw error
        } catch {
            throw EditorError(
                code: .commandFailed,
                message: "Make Editable could not verify the current CAD source identity: \(error)."
            )
        }
        guard currentSourceIdentity == command.sourceIdentity else {
            throw EditorError(
                code: .sourceIdentityMismatch,
                message: "CAD source changed after the Make Editable snapshot was evaluated."
            )
        }
        guard document.authoredMeshAssets[command.authoredMeshSourceID] == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Make Editable Authored Mesh source identity is already retained."
            )
        }
        guard object.geometryRepresentations
            .representations[command.authoredMeshRepresentationID] == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Make Editable representation identity is already retained by the target object."
            )
        }

        let authoredSource = try command.evaluatedMesh.reidentified(
            as: command.authoredMeshSourceID
        )
        let asset = try AuthoredMeshAsset(
            source: authoredSource,
            provenance: .derivedFromCAD(
                representationID: command.sourceRepresentationID,
                sourceIdentity: command.sourceIdentity
            )
        )
        let authoredRepresentation = GeometryRepresentation(
            id: command.authoredMeshRepresentationID,
            source: .authoredMesh(command.authoredMeshSourceID)
        )
        object.geometryRepresentations.representations[
            command.authoredMeshRepresentationID
        ] = authoredRepresentation
        if command.switchesPresentationSelection {
            selection.presentation = command.authoredMeshRepresentationID
        }
        object.geometryRepresentations.selection = selection
        sceneNode.object = object

        var staged = document
        staged.authoredMeshAssets[asset.id] = asset
        staged.productMetadata.sceneNodes[command.sceneNodeID] = sceneNode
        _ = try staged.validate(objectRegistry: objectRegistry)
        return GeometrySourceCommandApplication(
            document: staged,
            result: .makeEditable(
                GeometrySourceCommandResult.MakeEditable(
                    sceneNodeID: command.sceneNodeID,
                    sourceRepresentationID: command.sourceRepresentationID,
                    authoredMeshSourceID: command.authoredMeshSourceID,
                    authoredMeshRepresentationID: command.authoredMeshRepresentationID,
                    evaluationSnapshotID: command.evaluationSnapshotID,
                    cadSourceIdentity: command.sourceIdentity,
                    authoredMeshContentIdentity: asset.contentIdentity,
                    switchedPresentationSelection: command.switchesPresentationSelection,
                    copyTelemetry: command.evaluationCopyTelemetry
                )
            )
        )
    }

    private func apply(
        _ command: AuthoredMeshEditCommand,
        to document: DesignDocument,
        objectRegistry: ObjectTypeRegistry
    ) throws -> GeometrySourceCommandApplication {
        let asset = try requireAsset(for: command.target, in: document)
        let execution: MeshEditPlanExecution
        do {
            execution = try meshEditPlanExecutor.execute(
                plan: command.plan,
                source: asset.source
            )
        } catch let error as MeshEditError {
            throw error
        } catch {
            throw EditorError(
                code: .commandFailed,
                message: "Authored Mesh plan execution failed: \(error)."
            )
        }

        let receipt = execution.receipt
        guard receipt.didChange else {
            return GeometrySourceCommandApplication(
                document: document,
                result: .authoredMeshEdit(
                    GeometrySourceCommandResult.AuthoredMeshEdit(
                        sourceID: asset.id,
                        previousSourceIdentity: asset.contentIdentity,
                        sourceIdentity: asset.contentIdentity,
                        receipt: receipt,
                        didMutate: false
                    )
                )
            )
        }

        let editedAsset = try asset.replacingSource(execution.source)
        var staged = document
        staged.authoredMeshAssets[asset.id] = editedAsset
        _ = try staged.validate(objectRegistry: objectRegistry)
        return GeometrySourceCommandApplication(
            document: staged,
            result: .authoredMeshEdit(
                GeometrySourceCommandResult.AuthoredMeshEdit(
                    sourceID: editedAsset.id,
                    previousSourceIdentity: asset.contentIdentity,
                    sourceIdentity: editedAsset.contentIdentity,
                    receipt: receipt,
                    didMutate: true
                )
            )
        )
    }

    private func apply(
        _ command: GeometryRepresentationSelectionCommand,
        to document: DesignDocument,
        objectRegistry: ObjectTypeRegistry
    ) throws -> GeometrySourceCommandApplication {
        try command.validate()
        guard var sceneNode = document.productMetadata.sceneNodes[command.sceneNodeID],
              var object = sceneNode.object else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Geometry representation selection requires an existing Product Object."
            )
        }
        guard let representation = object.geometryRepresentations
            .representations[command.representationID],
              var selection = object.geometryRepresentations.selection else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Geometry representation selection requires a retained representation."
            )
        }
        let previousRepresentationID = selection.representationID(for: command.purpose)
        guard previousRepresentationID != command.representationID else {
            return GeometrySourceCommandApplication(
                document: document,
                result: .representationSelection(
                    GeometrySourceCommandResult.RepresentationSelection(
                        sceneNodeID: command.sceneNodeID,
                        purpose: command.purpose,
                        previousRepresentationID: previousRepresentationID,
                        representationID: command.representationID,
                        didMutate: false
                    )
                )
            )
        }

        switch command.purpose {
        case .modeling:
            selection.modeling = command.representationID
            sceneNode.reference = try navigationReference(
                for: representation.source,
                object: object
            )
        case .presentation:
            selection.presentation = command.representationID
        }
        object.geometryRepresentations.selection = selection
        sceneNode.object = object
        var staged = document
        staged.productMetadata.sceneNodes[command.sceneNodeID] = sceneNode
        _ = try staged.validate(objectRegistry: objectRegistry)
        return GeometrySourceCommandApplication(
            document: staged,
            result: .representationSelection(
                GeometrySourceCommandResult.RepresentationSelection(
                    sceneNodeID: command.sceneNodeID,
                    purpose: command.purpose,
                    previousRepresentationID: previousRepresentationID,
                    representationID: command.representationID,
                    didMutate: true
                )
            )
        )
    }

    private func requireAsset(
        for target: AuthoredMeshEditTarget,
        in document: DesignDocument
    ) throws -> AuthoredMeshAsset {
        try target.validate()
        guard let asset = document.authoredMeshAssets[target.sourceID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Authored Mesh edit source is not retained by the document."
            )
        }
        guard asset.id == target.sourceID,
              asset.source.identity == target.sourceID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Authored Mesh asset key and source identity must match the edit target."
            )
        }
        guard asset.contentIdentity == target.expectedSourceIdentity else {
            throw EditorError(
                code: .sourceIdentityMismatch,
                message: "Authored Mesh source changed after the edit target was resolved."
            )
        }
        return asset
    }

    private func navigationReference(
        for source: GeometrySourceReference,
        object: ObjectDescriptor
    ) throws -> SceneNodeReference? {
        switch source {
        case .cad(_, let outputID):
            guard let uuid = UUID(uuidString: outputID) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Selected CAD representation has an invalid output identity."
                )
            }
            switch object.category {
            case .body:
                return .body(FeatureID(uuid))
            case .sketch:
                return .sketch(FeatureID(uuid))
            case .group, .componentInstance, .construction, .annotation, .camera, .light:
                throw EditorError(
                    code: .commandInvalid,
                    message: "Only geometry objects can select a CAD modeling representation."
                )
            }
        case .authoredMesh(let sourceID):
            guard object.category == .body,
                  object.geometryRole == .mesh else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Only Mesh body objects can select an Authored Mesh modeling representation."
                )
            }
            return .authoredMesh(sourceID)
        case .external:
            guard object.category == .body else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Only body objects can select an external modeling representation."
                )
            }
            return nil
        }
    }
}
