import RupaCoreTypes
import RupaEvaluation
import RupaGeometry
import RupaProjectModel

public struct UniversalViewportSceneItem: Equatable, Sendable, Identifiable {
    public let id: SceneOccurrenceID
    public let definitionID: ObjectDefinitionID
    public let displayName: String
    public let representationID: GeometryRepresentationID
    public let reference: GeometrySourceReference
    public let mesh: MeshSource
    public let copyTelemetry: GeometryCopyTelemetry
    public let worldTransform: GeometryTransform3D
    public let worldBounds: GeometryBounds3D

    /// The occurrence identity used by selection and navigation.
    public var occurrenceID: SceneOccurrenceID {
        id
    }

    /// The selected presentation source authority.
    public var sourceReference: GeometrySourceReference {
        reference
    }

    /// Validates the presentation input without changing or rematerializing the
    /// borrowed MeshSource buffers. Buffer structure is validated by evaluation;
    /// this occurrence boundary checks identifiers and source authority without
    /// allocating per-occurrence validation indexes.
    public func validate() throws {
        do {
            try id.validate()
            try definitionID.validate()
            try representationID.validate()
            try reference.validate()
        } catch let error as ProjectModelError {
            throw UniversalViewportSceneError(
                code: .sourceMismatch,
                message: error.message
            )
        } catch let error as EditorError {
            throw UniversalViewportSceneError(
                code: .invalidIdentifier,
                message: error.message
            )
        }

        if case .authoredMesh(let sourceID) = reference,
           mesh.identity != sourceID {
            throw UniversalViewportSceneError(
                code: .sourceIdentityMismatch,
                message: "Authored Mesh presentation source identity does not match its MeshSource."
            )
        }
    }

    public init(
        id: SceneOccurrenceID,
        definitionID: ObjectDefinitionID,
        displayName: String,
        representationID: GeometryRepresentationID,
        reference: GeometrySourceReference,
        mesh: MeshSource,
        copyTelemetry: GeometryCopyTelemetry = GeometryCopyTelemetry(),
        worldTransform: GeometryTransform3D,
        worldBounds: GeometryBounds3D
    ) {
        self.id = id
        self.definitionID = definitionID
        self.displayName = displayName
        self.representationID = representationID
        self.reference = reference
        self.mesh = mesh
        self.copyTelemetry = copyTelemetry
        self.worldTransform = worldTransform
        self.worldBounds = worldBounds
    }

    public init(_ snapshot: EvaluatedOccurrenceSnapshot, displayName: String) {
        self.init(
            id: snapshot.occurrenceID,
            definitionID: snapshot.definitionID,
            displayName: displayName,
            representationID: snapshot.representationID,
            reference: snapshot.reference,
            mesh: snapshot.mesh,
            copyTelemetry: snapshot.copyTelemetry,
            worldTransform: snapshot.worldTransform,
            worldBounds: snapshot.worldBounds
        )
    }
}
