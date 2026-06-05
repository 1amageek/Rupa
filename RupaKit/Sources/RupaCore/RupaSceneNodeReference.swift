import Foundation
import SwiftCAD

public struct RupaSceneNodeReference: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case feature
        case body
        case sketch
        case componentInstance
        case construction
    }

    public var kind: Kind
    public var featureID: FeatureID?
    public var componentInstanceID: RupaComponentInstanceID?

    public init(
        kind: Kind,
        featureID: FeatureID? = nil,
        componentInstanceID: RupaComponentInstanceID? = nil
    ) {
        self.kind = kind
        self.featureID = featureID
        self.componentInstanceID = componentInstanceID
    }

    public static func feature(_ id: FeatureID) -> RupaSceneNodeReference {
        RupaSceneNodeReference(kind: .feature, featureID: id)
    }

    public static func body(_ id: FeatureID) -> RupaSceneNodeReference {
        RupaSceneNodeReference(kind: .body, featureID: id)
    }

    public static func sketch(_ id: FeatureID) -> RupaSceneNodeReference {
        RupaSceneNodeReference(kind: .sketch, featureID: id)
    }

    public static func componentInstance(_ id: RupaComponentInstanceID) -> RupaSceneNodeReference {
        RupaSceneNodeReference(kind: .componentInstance, componentInstanceID: id)
    }

    public static let construction = RupaSceneNodeReference(kind: .construction)

    public func validate() throws {
        switch kind {
        case .feature, .body, .sketch:
            guard featureID != nil, componentInstanceID == nil else {
                throw RupaDocumentValidationError.invalidProductMetadata(
                    "Feature, body, and sketch scene references must contain exactly one feature ID."
                )
            }
        case .componentInstance:
            guard componentInstanceID != nil, featureID == nil else {
                throw RupaDocumentValidationError.invalidProductMetadata(
                    "Component instance scene references must contain exactly one component instance ID."
                )
            }
        case .construction:
            guard featureID == nil, componentInstanceID == nil else {
                throw RupaDocumentValidationError.invalidProductMetadata(
                    "Construction scene references must not contain feature or component instance IDs."
                )
            }
        }
    }
}
