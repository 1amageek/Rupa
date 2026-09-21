/// Bounded measurements for one prepared transform attempt.
struct CADTransformTelemetry: Equatable, Sendable {
    let planningWallNanoseconds: UInt64
    let routeWallNanoseconds: UInt64
    let oracleWallNanoseconds: UInt64
    let totalWallNanoseconds: UInt64
    let actionCount: Int
    let commandCount: Int
    let readCount: Int
    let featureCount: Int
    let sceneNodeCount: Int
    let bodyCount: Int
    let timeoutWallNanoseconds: UInt64
    let cancellationCheckpointCount: Int
}
