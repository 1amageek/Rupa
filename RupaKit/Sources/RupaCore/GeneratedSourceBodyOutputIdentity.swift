import SwiftCAD

public struct GeneratedSourceBodyOutputIdentity: Codable, Equatable, Hashable, Sendable {
    public let featureID: FeatureID
    public let role: SourceBodyOutputRole

    init(featureID: FeatureID, sourcePort: FeaturePort) throws {
        self.featureID = featureID
        role = try SourceBodyOutputRole(sourcePort: sourcePort)
    }
}
