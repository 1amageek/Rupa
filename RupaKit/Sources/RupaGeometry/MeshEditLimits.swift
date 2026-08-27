import Foundation

/// Caller-lowerable resource limits for one plan execution.
public struct MeshEditLimits: Codable, Equatable, Sendable {
    public static let standard = MeshEditLimits(
        unchecked: (
            256,
            1_048_576,
            8_192,
            8_192,
            8_192,
            GeometryBufferPerformanceContract.maximumCopiedBytesPerLocalEdit
        )
    )

    public static let hardCeiling = standard

    public let maxSteps: Int
    public let maxScannedRecords: Int
    public let maxSelectedIDs: Int
    public let maxGeneratedIDs: Int
    public let maxReceiptIDs: Int
    public let maxCopiedBytes: UInt64

    public init(
        maxSteps: Int = MeshEditLimits.standard.maxSteps,
        maxScannedRecords: Int = MeshEditLimits.standard.maxScannedRecords,
        maxSelectedIDs: Int = MeshEditLimits.standard.maxSelectedIDs,
        maxGeneratedIDs: Int = MeshEditLimits.standard.maxGeneratedIDs,
        maxReceiptIDs: Int = MeshEditLimits.standard.maxReceiptIDs,
        maxCopiedBytes: UInt64 = MeshEditLimits.standard.maxCopiedBytes
    ) throws {
        let values = [
            (maxSteps, MeshEditLimits.standard.maxSteps, "steps"),
            (maxScannedRecords, MeshEditLimits.standard.maxScannedRecords, "scanned records"),
            (maxSelectedIDs, MeshEditLimits.standard.maxSelectedIDs, "selected IDs"),
            (maxGeneratedIDs, MeshEditLimits.standard.maxGeneratedIDs, "generated IDs"),
            (maxReceiptIDs, MeshEditLimits.standard.maxReceiptIDs, "receipt IDs"),
        ]
        for (value, ceiling, label) in values {
            guard value >= 0 else {
                throw MeshEditError(
                    code: .limitExceeded,
                    message: "Mesh edit \(label) limit cannot be negative."
                )
            }
            guard value <= ceiling else {
                throw MeshEditError(
                    code: .callerLimitAboveCeiling,
                    message: "Mesh edit \(label) limit exceeds the executor ceiling."
                )
            }
        }
        guard maxCopiedBytes <= MeshEditLimits.standard.maxCopiedBytes else {
            throw MeshEditError(
                code: .callerLimitAboveCeiling,
                message: "Mesh edit copied-byte limit exceeds the executor ceiling."
            )
        }
        self.maxSteps = maxSteps
        self.maxScannedRecords = maxScannedRecords
        self.maxSelectedIDs = maxSelectedIDs
        self.maxGeneratedIDs = maxGeneratedIDs
        self.maxReceiptIDs = maxReceiptIDs
        self.maxCopiedBytes = maxCopiedBytes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            maxSteps: container.decode(Int.self, forKey: .maxSteps),
            maxScannedRecords: container.decode(Int.self, forKey: .maxScannedRecords),
            maxSelectedIDs: container.decode(Int.self, forKey: .maxSelectedIDs),
            maxGeneratedIDs: container.decode(Int.self, forKey: .maxGeneratedIDs),
            maxReceiptIDs: container.decode(Int.self, forKey: .maxReceiptIDs),
            maxCopiedBytes: container.decode(UInt64.self, forKey: .maxCopiedBytes)
        )
    }

    init(unchecked values: (Int, Int, Int, Int, Int, UInt64)) {
        maxSteps = values.0
        maxScannedRecords = values.1
        maxSelectedIDs = values.2
        maxGeneratedIDs = values.3
        maxReceiptIDs = values.4
        maxCopiedBytes = values.5
    }

    /// Validates values decoded through a synthesized parent type.
    func validate() throws {
        let values = [
            (maxSteps, MeshEditLimits.standard.maxSteps, "steps"),
            (maxScannedRecords, MeshEditLimits.standard.maxScannedRecords, "scanned records"),
            (maxSelectedIDs, MeshEditLimits.standard.maxSelectedIDs, "selected IDs"),
            (maxGeneratedIDs, MeshEditLimits.standard.maxGeneratedIDs, "generated IDs"),
            (maxReceiptIDs, MeshEditLimits.standard.maxReceiptIDs, "receipt IDs"),
        ]
        for (value, ceiling, label) in values {
            guard value >= 0 else {
                throw MeshEditError(
                    code: .limitExceeded,
                    message: "Mesh edit \(label) limit cannot be negative."
                )
            }
            guard value <= ceiling else {
                throw MeshEditError(
                    code: .callerLimitAboveCeiling,
                    message: "Mesh edit \(label) limit exceeds the executor ceiling."
                )
            }
        }
        guard maxCopiedBytes <= MeshEditLimits.standard.maxCopiedBytes else {
            throw MeshEditError(
                code: .callerLimitAboveCeiling,
                message: "Mesh edit copied-byte limit exceeds the executor ceiling."
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case maxSteps
        case maxScannedRecords
        case maxSelectedIDs
        case maxGeneratedIDs
        case maxReceiptIDs
        case maxCopiedBytes
    }
}
