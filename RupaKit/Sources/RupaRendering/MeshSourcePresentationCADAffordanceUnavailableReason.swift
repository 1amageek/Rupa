public enum MeshSourcePresentationCADAffordanceUnavailableReason: Equatable, Sendable {
    case nonCADPresentation
    case missingNavigation
    case missingSceneNode
    case presentationSelectionMismatch
    case sceneNodeReferenceMismatch
    case sourceDocumentMismatch
    case invalidOutputIdentifier
    case missingFeature
    case missingCADInteractionContext
    case staleCADInteractionContext
    case missingEvaluatedBody
    case ambiguousEvaluatedBody
}
