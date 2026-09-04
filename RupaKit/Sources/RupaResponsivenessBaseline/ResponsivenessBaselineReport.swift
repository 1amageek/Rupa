import Foundation

/// One measured iteration of the production preparation and draw work.
public struct ResponsivenessIterationSample: Equatable, Sendable, Codable {
    public let index: Int
    /// Time spent in `MeshSourcePresentationRenderPlan(scene:)`, the first half
    /// of what the production cache performs synchronously on the MainActor.
    public let planConstructionSeconds: Double
    /// Time spent in the discarded validation traversal, the second half of the
    /// same synchronous cache call. Reported separately so the duplicate full
    /// traversal is attributable rather than folded into one number.
    public let validationTraversalSeconds: Double
    /// The synchronous MainActor cost of publishing one plan.
    public let preparationSeconds: Double
    /// Time spent reproducing the Canvas closure's per-triangle work.
    public let drawWorkSeconds: Double
    /// The total uninterruptible MainActor interval one scene change causes.
    public let mainActorBlockedSeconds: Double
    public let triangleCount: Int
    public let projectedPointCount: Int
    public let pathCount: Int
    public let fillCount: Int
    public let strokeCount: Int
}

/// Sampled `phys_footprint` values. Every value is a proxy for resident memory,
/// never a measurement of the plan's exact retained allocation.
public struct ResponsivenessFootprintSample: Equatable, Sendable, Codable {
    /// Footprint after warm-up with no plan retained.
    public let baselineBytes: UInt64
    /// Footprint with exactly one plan retained.
    public let planRetainedBytes: UInt64
    /// Peak footprint observed by a concurrent sampler while preparation ran.
    public let preparationPeakBytes: UInt64
    /// Sampling interval of the concurrent peak sampler.
    public let peakSamplingIntervalSeconds: Double
    /// Number of samples the concurrent sampler completed during preparation.
    public let peakSampleCount: Int

    public var planRetainedDeltaBytes: Int64 {
        Int64(bitPattern: planRetainedBytes) - Int64(bitPattern: baselineBytes)
    }

    public var preparationPeakDeltaBytes: Int64 {
        Int64(bitPattern: preparationPeakBytes) - Int64(bitPattern: baselineBytes)
    }
}

/// The environment the report was produced in, recorded so a later report is
/// only compared against a matching context.
public struct ResponsivenessReportContext: Equatable, Sendable, Codable {
    public let buildConfiguration: String
    public let operatingSystemVersion: String
    public let hostModel: String
    public let physicalMemoryBytes: UInt64
    public let processorCount: Int
    public let recordedAt: String
    /// The revision of this package the measurement was taken from.
    public let rupaKitRevision: String
    /// The revision of the geometry kernel the measurement was taken against.
    public let swiftCADRevision: String

    public init(
        buildConfiguration: String,
        operatingSystemVersion: String,
        hostModel: String,
        physicalMemoryBytes: UInt64,
        processorCount: Int,
        recordedAt: String,
        rupaKitRevision: String,
        swiftCADRevision: String
    ) {
        self.buildConfiguration = buildConfiguration
        self.operatingSystemVersion = operatingSystemVersion
        self.hostModel = hostModel
        self.physicalMemoryBytes = physicalMemoryBytes
        self.processorCount = processorCount
        self.recordedAt = recordedAt
        self.rupaKitRevision = rupaKitRevision
        self.swiftCADRevision = swiftCADRevision
    }
}

public struct ResponsivenessBaselineReport: Equatable, Sendable, Codable {
    public let fixture: ResponsivenessFixture.Parameters
    public let contentDigest: String
    public let sceneItemCount: Int
    public let vertexCount: Int
    public let faceCount: Int
    public let planTriangleCount: Int
    public let predictedTriangleCount: Int
    public let warmupCount: Int
    public let environment: ResponsivenessEnvironment
    public let environmentDerivationRule: String
    public let samples: [ResponsivenessIterationSample]
    public let footprint: ResponsivenessFootprintSample
    public let rows: [ResponsivenessRowResult]
    public let context: ResponsivenessReportContext

    /// True when every acceptance row accepts. A `notMeasured` row is never an
    /// acceptance.
    public var accepts: Bool {
        rows.allSatisfy { $0.verdict == .accepts }
    }

    public var worstPreparationSeconds: Double {
        samples.map(\.preparationSeconds).max() ?? 0.0
    }

    public var worstDrawWorkSeconds: Double {
        samples.map(\.drawWorkSeconds).max() ?? 0.0
    }

    public var worstMainActorBlockedSeconds: Double {
        samples.map(\.mainActorBlockedSeconds).max() ?? 0.0
    }
}
