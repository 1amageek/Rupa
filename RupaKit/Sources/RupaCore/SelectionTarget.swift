import Foundation
import SwiftCAD
import RupaCoreTypes

public struct SelectionTarget: Codable, Equatable, Hashable, Sendable {
    public var sceneNodeID: SceneNodeID
    public var component: SelectionComponent
    public var occurrenceID: SceneOccurrenceID?
    public var sourceSceneNodeID: SceneNodeID?
    public var sourceFeatureID: FeatureID?
    public var sourceBodyID: BodyID?

    public init(sceneNodeID: SceneNodeID, component: SelectionComponent = .object,
                occurrenceID: SceneOccurrenceID? = nil, sourceSceneNodeID: SceneNodeID? = nil,
                sourceFeatureID: FeatureID? = nil, sourceBodyID: BodyID? = nil) {
        self.sceneNodeID = sceneNodeID
        self.component = component
        self.occurrenceID = occurrenceID
        self.sourceSceneNodeID = sourceSceneNodeID
        self.sourceFeatureID = sourceFeatureID
        self.sourceBodyID = sourceBodyID
    }

    private enum CodingKeys: String, CodingKey {
        case sceneNodeID, component, occurrenceID, sourceSceneNodeID, sourceFeatureID, sourceBodyID
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sceneNodeID = try container.decode(SceneNodeID.self, forKey: .sceneNodeID)
        component = try container.decode(SelectionComponent.self, forKey: .component)
        occurrenceID = try container.decodeIfPresent(SceneOccurrenceID.self, forKey: .occurrenceID)
        sourceSceneNodeID = try container.decodeIfPresent(SceneNodeID.self, forKey: .sourceSceneNodeID)
        sourceFeatureID = try container.decodeIfPresent(FeatureID.self, forKey: .sourceFeatureID)
        sourceBodyID = try container.decodeIfPresent(BodyID.self, forKey: .sourceBodyID)
        guard sourceBodyID == nil || sourceFeatureID != nil else {
            throw DecodingError.dataCorruptedError(forKey: .sourceBodyID, in: container,
                debugDescription: "Body-bound selection requires its original feature witness.")
        }
        guard (occurrenceID == nil) == (sourceSceneNodeID == nil), occurrenceID != nil || sourceFeatureID == nil else {
            throw DecodingError.dataCorruptedError(forKey: .occurrenceID, in: container,
                debugDescription: "Selection occurrence and original source node must be retained together.")
        }
    }
}
