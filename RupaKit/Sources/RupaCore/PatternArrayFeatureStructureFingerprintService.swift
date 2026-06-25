import Foundation
import SwiftCAD

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
        let remapper = PatternArrayFeatureIDRemapper(
            featureIDMap: try PatternArrayFeatureIDTokenMapService().tokenMap(for: featureIDs)
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
}

private struct PatternArrayFeatureStructurePayload: Encodable {
    var operation: FeatureOperation
    var inputs: [FeatureInput]
    var outputs: [FeatureOutput]
    var isSuppressed: Bool
}
