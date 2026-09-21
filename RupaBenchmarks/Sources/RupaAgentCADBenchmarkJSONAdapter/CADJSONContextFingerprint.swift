import Foundation
import RupaAgentCADBenchmark
import RupaCoreTypes

enum CADJSONContextFingerprint {
    static func validate(_ fingerprint: String) throws {
        guard fingerprint.count == 64,
              fingerprint.unicodeScalars.allSatisfy({ scalar in
                  (scalar.value >= 48 && scalar.value <= 57)
                      || (scalar.value >= 97 && scalar.value <= 102)
              }) else {
            throw CADJSONAdapterError.fingerprintMismatch
        }
    }

    static func value(for context: CADCandidateContext) throws -> String {
        let canonicalContext = try canonicalContextData(for: context)
        var payload = Data(CADJSONAdapterSchema.contextFingerprintDomain.utf8)
        payload.append(0x0A)
        payload.append(canonicalContext)
        return StableDigest.sha256Hex(for: payload)
    }

    static func canonicalContextData(for context: CADCandidateContext) throws -> Data {
        do {
            try context.validate()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return try encoder.encode(context)
        } catch let error as CADJSONAdapterError {
            throw error
        } catch {
            throw CADJSONAdapterError.malformedJSON
        }
    }
}
