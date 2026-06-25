import Foundation
import SwiftCAD

struct PatternArrayFeatureStructureFingerprint: Hashable, Sendable {
    var algorithm: String
    var value: String
}

struct PatternArrayFeatureStructureFingerprintService: Sendable {
    private static let algorithm = "fnv1a64-pattern-feature-structure-v1"

    func fingerprints(
        featureIDs: [FeatureID],
        cadDocument: CADDocument
    ) throws -> [PatternArrayFeatureStructureFingerprint] {
        let remapper = PatternArrayFeatureIDRemapper(
            featureIDMap: try featureTokenMap(for: featureIDs)
        )
        return try featureIDs.map { featureID in
            guard let feature = cadDocument.designGraph.nodes[featureID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Pattern array feature fingerprint requires existing CAD features."
                )
            }
            let payload = PatternArrayFeatureStructurePayload(
                operation: try remapper.remappedOperation(feature.operation),
                inputs: try feature.inputs.map(remapper.remappedInput),
                outputs: try feature.outputs.map(remapper.remappedOutput),
                isSuppressed: feature.isSuppressed
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(payload)
            return PatternArrayFeatureStructureFingerprint(
                algorithm: Self.algorithm,
                value: PatternArrayStableDigest.hexDigest(for: data)
            )
        }
    }

    private func featureTokenMap(
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
                message: "Pattern array feature fingerprint generated an invalid feature token."
            )
        }
        return FeatureID(uuid)
    }
}

private struct PatternArrayFeatureStructurePayload: Encodable {
    var operation: FeatureOperation
    var inputs: [FeatureInput]
    var outputs: [FeatureOutput]
    var isSuppressed: Bool
}
