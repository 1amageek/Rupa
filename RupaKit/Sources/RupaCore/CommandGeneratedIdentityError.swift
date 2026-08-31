import SwiftCAD

enum CommandGeneratedIdentityError: Error, Equatable, Sendable {
    case identityChangedWithoutMutation
    case duplicateFeatureIdentity(FeatureID)
    case missingFeature(FeatureID)
    case featureKeyMismatch(FeatureID)
    case bodyOutputWithoutGeneratedFeature(FeatureID)
    case duplicateBodyOutput(FeatureID, SourceBodyOutputRole)
    case ambiguousBodyOutput(FeatureID)
    case wrongBodyOutputRole(FeaturePort)
    case duplicateSceneIdentity(SceneNodeID)
    case missingSceneNode(SceneNodeID)
    case duplicateSceneNode(SceneNodeID)
    case sceneNodeKeyMismatch(SceneNodeID)
    case unreachableSceneNodes
    case duplicateComponentDefinitionIdentity(ComponentDefinitionID)
    case componentDefinitionKeyMismatch(ComponentDefinitionID)
    case duplicateComponentInstanceIdentity(ComponentInstanceID)
    case componentInstanceKeyMismatch(ComponentInstanceID)
    case duplicatePatternArraySourceIdentity(PatternArraySourceID)
    case patternArraySourceKeyMismatch(PatternArraySourceID)
}
