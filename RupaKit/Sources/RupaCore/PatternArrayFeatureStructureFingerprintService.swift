import Foundation
import SwiftCAD
import RupaCoreTypes

struct PatternArrayFeatureStructureFingerprint: Hashable, Sendable {
    var algorithm: String
    var value: String
}

struct PatternArrayFeatureStructureFingerprintService: Sendable {
    private static let algorithm = "sha256-pattern-feature-structure-v2"

    func fingerprints(
        featureIDs: [FeatureID],
        cadDocument: CADDocument
    ) throws -> [PatternArrayFeatureStructureFingerprint] {
        let tokenMap = try PatternArrayFeatureIDTokenMapService().tokenMap(for: featureIDs)
        return try featureIDs.map { featureID in
            guard let feature = cadDocument.designGraph.nodes[featureID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Pattern array feature fingerprint requires existing CAD features."
                )
            }
            let tokenized = try feature.remappingFeatureReferences(tokenMap)
            let payload = PatternArrayFeatureStructurePayload(
                operation: tokenized.operation,
                inputs: tokenized.inputs,
                outputs: tokenized.outputs,
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
}

private struct PatternArrayFeatureStructurePayload: Encodable {
    var operation: FeatureOperation
    var inputs: [FeatureInput]
    var outputs: [FeatureOutput]
    var isSuppressed: Bool
}
