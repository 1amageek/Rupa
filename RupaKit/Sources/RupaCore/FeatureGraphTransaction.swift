import SwiftCAD

public struct FeatureGraphTransaction: Codable, Hashable, Sendable {
    public var features: [FeatureNode]
    public var presentations: [FeaturePresentation]
    public var primaryFeatureID: FeatureID?

    public init(
        features: [FeatureNode],
        presentations: [FeaturePresentation] = [],
        primaryFeatureID: FeatureID? = nil
    ) {
        self.features = features
        self.presentations = presentations
        self.primaryFeatureID = primaryFeatureID
    }

    public func validate() throws {
        guard !features.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "A feature graph transaction must contain at least one feature."
            )
        }
        let featureIDs = features.map { $0.id }
        guard Set(featureIDs).count == featureIDs.count else {
            throw EditorError(
                code: .commandInvalid,
                message: "Feature graph transaction feature IDs must be unique."
            )
        }
        if let primaryFeatureID, !featureIDs.contains(primaryFeatureID) {
            throw EditorError(
                code: .commandInvalid,
                message: "The primary feature ID must identify a feature in the transaction."
            )
        }
        let sceneNodeIDs = presentations.map { $0.sceneNodeID }
        guard Set(sceneNodeIDs).count == sceneNodeIDs.count else {
            throw EditorError(
                code: .commandInvalid,
                message: "Feature graph transaction scene node IDs must be unique."
            )
        }
        let presentedFeatureIDs = presentations.map { $0.featureID }
        guard Set(presentedFeatureIDs).count == presentedFeatureIDs.count,
              Set(presentedFeatureIDs).isSubset(of: Set(featureIDs)) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Each presentation must identify one unique feature in the transaction."
            )
        }
    }
}
