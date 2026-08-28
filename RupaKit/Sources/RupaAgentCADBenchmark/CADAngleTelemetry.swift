import Foundation

/// Measured durations and operation counts for one angle case.
struct CADAngleTelemetry: Codable, Equatable, Sendable {
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

    func replacing(
        totalWallNanoseconds: UInt64? = nil,
        oracleWallNanoseconds: UInt64? = nil,
        readCount: Int? = nil,
        entityCount: Int? = nil,
        featureCount: Int? = nil,
        bodyCount: Int? = nil
    ) -> CADAngleTelemetry {
        CADAngleTelemetry(
            planningWallNanoseconds: planningWallNanoseconds,
            routeWallNanoseconds: routeWallNanoseconds,
            oracleWallNanoseconds: oracleWallNanoseconds ?? self.oracleWallNanoseconds,
            totalWallNanoseconds: totalWallNanoseconds ?? self.totalWallNanoseconds,
            actionCount: actionCount,
            commandCount: commandCount,
            readCount: readCount ?? self.readCount,
            entityCount: entityCount ?? self.entityCount,
            featureCount: featureCount ?? self.featureCount,
            bodyCount: bodyCount ?? self.bodyCount,
            timeoutWallNanoseconds: timeoutWallNanoseconds,
            cancellationCheckpointCount: cancellationCheckpointCount
        )
    }

    func validate(caseID: CADBenchmarkCaseID) throws {
        guard actionCount >= 0,
              commandCount >= 0,
              readCount >= 0,
              entityCount >= 0,
              featureCount >= 0,
              bodyCount >= 0,
              cancellationCheckpointCount >= 0,
              timeoutWallNanoseconds > 0,
              planningWallNanoseconds <= totalWallNanoseconds,
              routeWallNanoseconds <= totalWallNanoseconds,
              oracleWallNanoseconds <= totalWallNanoseconds else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "Angle telemetry counts, timeout, and phase durations must be valid."
            )
        }
    }
}
