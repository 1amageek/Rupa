import Foundation

/// Caller-lowerable budgets for bounded Mesh reads.
public struct ProjectMeshReadLimits: Codable, Equatable, Sendable {
    public static let standard = ProjectMeshReadLimits(
        maxSources: 4_096,
        maxPageRecords: 1_024,
        maxNeighborhoodDepth: 8,
        maxScannedRecords: 1_048_576,
        maxOutputRecords: 4_096,
        maxReferenceUnits: 8_192
    )

    public static let hard = standard

    public let maxSources: Int
    public let maxPageRecords: Int
    public let maxNeighborhoodDepth: Int
    public let maxScannedRecords: Int
    public let maxOutputRecords: Int
    public let maxReferenceUnits: Int

    public init(
        maxSources: Int = 4_096,
        maxPageRecords: Int = 1_024,
        maxNeighborhoodDepth: Int = 8,
        maxScannedRecords: Int = 1_048_576,
        maxOutputRecords: Int = 4_096,
        maxReferenceUnits: Int = 8_192
    ) {
        self.maxSources = maxSources
        self.maxPageRecords = maxPageRecords
        self.maxNeighborhoodDepth = maxNeighborhoodDepth
        self.maxScannedRecords = maxScannedRecords
        self.maxOutputRecords = maxOutputRecords
        self.maxReferenceUnits = maxReferenceUnits
    }

    func validate() throws {
        let values = [
            maxSources,
            maxPageRecords,
            maxNeighborhoodDepth,
            maxScannedRecords,
            maxOutputRecords,
            maxReferenceUnits,
        ]
        guard values.allSatisfy({ $0 > 0 }) else {
            throw ProjectMeshReadError(
                code: .invalidLimit,
                message: "Project Mesh read limits must be positive."
            )
        }
        let hard = Self.hard
        guard maxSources <= hard.maxSources,
              maxPageRecords <= hard.maxPageRecords,
              maxNeighborhoodDepth <= hard.maxNeighborhoodDepth,
              maxScannedRecords <= hard.maxScannedRecords,
              maxOutputRecords <= hard.maxOutputRecords,
              maxReferenceUnits <= hard.maxReferenceUnits else {
            throw ProjectMeshReadError(
                code: .limitExceeded,
                message: "Project Mesh read limits must not exceed the hard ceiling."
            )
        }
    }
}
