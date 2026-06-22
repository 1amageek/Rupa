import Foundation
import SwiftCAD

public struct SceneNodeReference: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case feature
        case body
        case sketch
        case componentInstance
        case construction
    }

    public var kind: Kind
    public var featureID: FeatureID?
    public var componentInstanceID: ComponentInstanceID?
    public var constructionPlaneID: ConstructionPlaneSourceID?

    public init(
        kind: Kind,
        featureID: FeatureID? = nil,
        componentInstanceID: ComponentInstanceID? = nil,
        constructionPlaneID: ConstructionPlaneSourceID? = nil
    ) {
        self.kind = kind
        self.featureID = featureID
        self.componentInstanceID = componentInstanceID
        self.constructionPlaneID = constructionPlaneID
    }

    public static func feature(_ id: FeatureID) -> SceneNodeReference {
        SceneNodeReference(kind: .feature, featureID: id)
    }

    public static func body(_ id: FeatureID) -> SceneNodeReference {
        SceneNodeReference(kind: .body, featureID: id)
    }

    public static func sketch(_ id: FeatureID) -> SceneNodeReference {
        SceneNodeReference(kind: .sketch, featureID: id)
    }

    public static func componentInstance(_ id: ComponentInstanceID) -> SceneNodeReference {
        SceneNodeReference(kind: .componentInstance, componentInstanceID: id)
    }

    public static func constructionPlane(_ id: ConstructionPlaneSourceID) -> SceneNodeReference {
        SceneNodeReference(kind: .construction, constructionPlaneID: id)
    }

    public static let construction = SceneNodeReference(kind: .construction)

    public func validate() throws {
        switch kind {
        case .feature, .body, .sketch:
            guard featureID != nil,
                  componentInstanceID == nil,
                  constructionPlaneID == nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Feature, body, and sketch scene references must contain exactly one feature ID."
                )
            }
        case .componentInstance:
            guard componentInstanceID != nil,
                  featureID == nil,
                  constructionPlaneID == nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Component instance scene references must contain exactly one component instance ID."
                )
            }
        case .construction:
            guard featureID == nil,
                  componentInstanceID == nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Construction scene references must not contain feature or component instance IDs."
                )
            }
        }
    }
}
