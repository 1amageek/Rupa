import RupaCore
import RupaDomainFoundation
import SwiftCAD

public struct ProjectSemanticOutputBinding: Sendable, Equatable {
    public enum Value: Sendable, Equatable {
        case feature(FeatureID)
        case body(
            featureID: FeatureID,
            role: SourceBodyOutputRole,
            evaluatedBodyID: BodyID
        )
        case sceneNode(SceneNodeID)
        case componentDefinition(ComponentDefinitionID)
        case componentInstance(ComponentInstanceID)
        case patternArraySource(PatternArraySourceID)
    }

    public let output: SemanticOutputReference
    public let value: Value

    public init(output: SemanticOutputReference, value: Value) {
        self.output = output
        self.value = value
    }
}
