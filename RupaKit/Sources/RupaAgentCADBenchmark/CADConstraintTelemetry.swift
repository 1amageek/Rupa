import Foundation

/// Measured phase time and operation counts for one constraint case.
struct CADConstraintTelemetry: Equatable, Sendable {
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

    func validate(caseID: CADBenchmarkCaseID, outcome: CADCaseOutcome) throws {
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
                reason: "Constraint telemetry is outside its bounded count or duration contract."
            )
        }
        if outcome == .timeout {
            guard totalWallNanoseconds >= timeoutWallNanoseconds else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A timed-out constraint case must reach its wall-time bound."
                )
            }
        } else if totalWallNanoseconds > timeoutWallNanoseconds {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "A non-timeout constraint case cannot exceed its wall-time bound."
            )
        }
    }
}
