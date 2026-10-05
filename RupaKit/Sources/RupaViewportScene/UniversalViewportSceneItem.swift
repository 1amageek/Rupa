import RupaCoreTypes
import RupaEvaluation
import RupaGeometry
import RupaProjectModel

public struct UniversalViewportSceneItem: Equatable, Sendable, Identifiable {
    public let id: SceneOccurrenceID
    public let occurrenceID: SceneOccurrenceID
    public let sourceBodyID: String?
    public let sourceFeatureID: String?
    public let outputRole: String?
    public var presentationID: SceneOccurrenceID { id }
    public let definitionID: ObjectDefinitionID
    public let displayName: String
    public let representationID: GeometryRepresentationID
    public let reference: GeometrySourceReference
    public let mesh: MeshSource
    public let copyTelemetry: GeometryCopyTelemetry
    public let worldTransform: GeometryTransform3D
    public let worldBounds: GeometryBounds3D

    /// The occurrence identity used by selection and navigation.

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
            try occurrenceID.validate()
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

        guard (sourceBodyID == nil) == (sourceFeatureID == nil),
              (sourceBodyID == nil) == (outputRole == nil),
              sourceBodyID?.isEmpty != true, sourceFeatureID?.isEmpty != true, outputRole?.isEmpty != true else {
            throw UniversalViewportSceneError(code: .sourceMismatch, message: "Presentation part lacks its original body witness.")
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
        worldBounds: GeometryBounds3D,
        occurrenceID: SceneOccurrenceID? = nil,
        sourceBodyID: String? = nil,
        sourceFeatureID: String? = nil,
        outputRole: String? = nil
    ) {
        self.id = id
        self.occurrenceID = occurrenceID ?? id
        self.sourceBodyID = sourceBodyID
        self.sourceFeatureID = sourceFeatureID
        self.outputRole = outputRole
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
