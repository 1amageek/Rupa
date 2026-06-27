import Foundation
import SwiftCAD
import RupaCoreTypes

struct PatternArrayFeatureIDTokenMapService: Sendable {
    func tokenMap(
        for featureIDs: [FeatureID]
    ) throws -> [FeatureID: FeatureID] {
        var values: [FeatureID: FeatureID] = [:]
        values.reserveCapacity(featureIDs.count)
        for (index, featureID) in featureIDs.enumerated() {
            values[featureID] = try tokenFeatureID(index: index)
        }
        return values
    }

    private func tokenFeatureID(index: Int) throws -> FeatureID {
        let suffix = String(format: "%012llx", UInt64(index + 1))
        guard let uuid = UUID(uuidString: "00000000-0000-0000-0000-\(suffix)") else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array feature token generation produced an invalid feature ID."
            )
        }
        return FeatureID(uuid)
    }
}
