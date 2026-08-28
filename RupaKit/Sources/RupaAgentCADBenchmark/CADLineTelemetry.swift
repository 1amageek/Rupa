import Foundation

/// Measured wall time and operation counts for one activated line case.
struct CADLineTelemetry: Codable, Equatable, Sendable {
    let planningWallNanoseconds: UInt64
    let routeWallNanoseconds: UInt64
    let oracleWallNanoseconds: UInt64
    let totalWallNanoseconds: UInt64
    let actionCount: Int
    let commandCount: Int
    let readCount: Int
    let entityCount: Int
    let featureCount: Int
    let bodyCount: Int
    let timeoutWallNanoseconds: UInt64
    let cancellationCheckpointCount: Int

    init(
        planningWallNanoseconds: UInt64,
        routeWallNanoseconds: UInt64,
        oracleWallNanoseconds: UInt64,
        totalWallNanoseconds: UInt64,
        actionCount: Int,
        commandCount: Int,
        readCount: Int,
        entityCount: Int,
        featureCount: Int,
        bodyCount: Int,
        timeoutWallNanoseconds: UInt64,
        cancellationCheckpointCount: Int
    ) {
        self.planningWallNanoseconds = planningWallNanoseconds
        self.routeWallNanoseconds = routeWallNanoseconds
        self.oracleWallNanoseconds = oracleWallNanoseconds
        self.totalWallNanoseconds = totalWallNanoseconds
        self.actionCount = actionCount
        self.commandCount = commandCount
        self.readCount = readCount
        self.entityCount = entityCount
        self.featureCount = featureCount
        self.bodyCount = bodyCount
        self.timeoutWallNanoseconds = timeoutWallNanoseconds
        self.cancellationCheckpointCount = cancellationCheckpointCount
    }

    static let empty = CADLineTelemetry(
        planningWallNanoseconds: 0,
        routeWallNanoseconds: 0,
        oracleWallNanoseconds: 0,
        totalWallNanoseconds: 0,
        actionCount: 0,
        commandCount: 0,
        readCount: 0,
        entityCount: 0,
        featureCount: 0,
        bodyCount: 0,
        timeoutWallNanoseconds: 10_000_000_000,
        cancellationCheckpointCount: 0
    )

    func validate(caseID: CADBenchmarkCaseID) throws {
        guard actionCount >= 0,
              commandCount >= 0,
              readCount >= 0,
              entityCount >= 0,
              featureCount >= 0,
              bodyCount >= 0,
              cancellationCheckpointCount >= 0 else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "Line telemetry counts must be non-negative."
            )
        }
        guard timeoutWallNanoseconds > 0 else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "An activated line case must declare a positive bounded timeout."
            )
        }
        guard planningWallNanoseconds <= totalWallNanoseconds,
              routeWallNanoseconds <= totalWallNanoseconds,
              oracleWallNanoseconds <= totalWallNanoseconds else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "Line phase durations cannot exceed total duration."
            )
        }
    }
}
