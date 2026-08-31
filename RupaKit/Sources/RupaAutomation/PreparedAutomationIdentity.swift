import SwiftCAD
import RupaCore

/// A server-owned source identity available to prepared steps.
public enum PreparedAutomationIdentity: Sendable, Equatable, Hashable {
    case feature(FeatureID)
    case sourceBody(featureID: FeatureID, role: SourceBodyOutputRole)
    case sceneNode(SceneNodeID)
    case componentDefinition(ComponentDefinitionID)
    case componentInstance(ComponentInstanceID)
    case patternArraySource(PatternArraySourceID)

    public var kind: PreparedAutomationIdentityKind {
        switch self {
        case .feature:
            .feature
        case .sourceBody(_, let role):
            .sourceBody(role: role)
        case .sceneNode:
            .sceneNode
        case .componentDefinition:
            .componentDefinition
        case .componentInstance:
            .componentInstance
        case .patternArraySource:
            .patternArraySource
        }
    }

    func exists(in document: DesignDocument) -> Bool {
        switch self {
        case .feature(let id):
            document.cadDocument.designGraph.nodes[id] != nil
        case .sourceBody(let featureID, let role):
            document.cadDocument.designGraph.nodes[featureID]?.outputs.contains {
                $0.role == role.featurePort
            } == true
        case .sceneNode(let id):
            document.productMetadata.sceneNodes[id] != nil
        case .componentDefinition(let id):
            document.productMetadata.componentDefinitions[id] != nil
        case .componentInstance(let id):
            document.productMetadata.componentInstances[id] != nil
        case .patternArraySource(let id):
            document.productMetadata.patternArrays[id] != nil
        }
    }
}

private extension SourceBodyOutputRole {
    var featurePort: FeaturePort {
        switch self {
        case .body:
            .body
        case .sheet:
            .sheet
        }
    }
}

extension PreparedAutomationIdentity {
    init(_ identity: GeneratedSourceBodyOutputIdentity) {
        self = .sourceBody(featureID: identity.featureID, role: identity.role)
    }

    init(_ id: FeatureID) {
        self = .feature(id)
    }

    init(_ id: SceneNodeID) {
        self = .sceneNode(id)
    }

    init(_ id: ComponentDefinitionID) {
        self = .componentDefinition(id)
    }

    init(_ id: ComponentInstanceID) {
        self = .componentInstance(id)
    }

    init(_ id: PatternArraySourceID) {
        self = .patternArraySource(id)
    }
}
