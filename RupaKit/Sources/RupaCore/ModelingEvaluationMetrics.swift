import SwiftCAD

public struct ModelingEvaluationMetrics: Codable, Equatable, Sendable {
    public var totalFeatureCount: Int
    public var rebuiltFeatureCount: Int
    public var reusedFeatureCount: Int
    public var invalidatedFeatureCount: Int
    public var replayFallbackCount: Int
    public var tessellatedBodyCount: Int
    public var reusedMeshCount: Int
    public var scopedBodyReadCount: Int
    public var maximumScopedBodyReadCount: Int
    public var topologyMutationCount: Int

    public init(
        totalFeatureCount: Int,
        rebuiltFeatureCount: Int,
        reusedFeatureCount: Int,
        invalidatedFeatureCount: Int,
        replayFallbackCount: Int,
        tessellatedBodyCount: Int,
        reusedMeshCount: Int,
        scopedBodyReadCount: Int,
        maximumScopedBodyReadCount: Int,
        topologyMutationCount: Int
    ) {
        self.totalFeatureCount = totalFeatureCount
        self.rebuiltFeatureCount = rebuiltFeatureCount
        self.reusedFeatureCount = reusedFeatureCount
        self.invalidatedFeatureCount = invalidatedFeatureCount
        self.replayFallbackCount = replayFallbackCount
        self.tessellatedBodyCount = tessellatedBodyCount
        self.reusedMeshCount = reusedMeshCount
        self.scopedBodyReadCount = scopedBodyReadCount
        self.maximumScopedBodyReadCount = maximumScopedBodyReadCount
        self.topologyMutationCount = topologyMutationCount
    }

    init(_ metrics: DocumentEvaluationMetrics) {
        self.init(
            totalFeatureCount: metrics.totalFeatureCount,
            rebuiltFeatureCount: metrics.rebuiltFeatureCount,
            reusedFeatureCount: metrics.reusedFeatureCount,
            invalidatedFeatureCount: metrics.invalidatedFeatureCount,
            replayFallbackCount: metrics.replayFallbackCount,
            tessellatedBodyCount: metrics.tessellatedBodyCount,
            reusedMeshCount: metrics.reusedMeshCount,
            scopedBodyReadCount: metrics.scopedBodyReadCount,
            maximumScopedBodyReadCount: metrics.maximumScopedBodyReadCount,
            topologyMutationCount: metrics.topologyMutationCount
        )
    }
}
