import Foundation

/// Bounded measurements for one sphere capability observation.
struct CADSphereTelemetry: Codable, Equatable, Sendable {
    let planningWallNanoseconds: UInt64
    let routeWallNanoseconds: UInt64
    let oracleWallNanoseconds: UInt64
    let totalWallNanoseconds: UInt64
    let capabilityRequestCount: Int
    let actionCount: Int
    let commandCount: Int
    let readCount: Int
    let entityCount: Int
    let featureCount: Int
    let bodyCount: Int
    let publicationCount: Int
    let sourceMutationCount: Int
    let timeoutWallNanoseconds: UInt64
    let cancellationCheckpointCount: Int

    init(
        planningWallNanoseconds: UInt64,
        routeWallNanoseconds: UInt64,
        oracleWallNanoseconds: UInt64,
        totalWallNanoseconds: UInt64,
        capabilityRequestCount: Int,
        actionCount: Int,
        commandCount: Int,
        readCount: Int,
        entityCount: Int,
        featureCount: Int,
        bodyCount: Int,
        publicationCount: Int,
        sourceMutationCount: Int,
        timeoutWallNanoseconds: UInt64,
        cancellationCheckpointCount: Int
    ) {
        self.planningWallNanoseconds = planningWallNanoseconds
        self.routeWallNanoseconds = routeWallNanoseconds
        self.oracleWallNanoseconds = oracleWallNanoseconds
        self.totalWallNanoseconds = totalWallNanoseconds
        self.capabilityRequestCount = capabilityRequestCount
        self.actionCount = actionCount
        self.commandCount = commandCount
        self.readCount = readCount
        self.entityCount = entityCount
        self.featureCount = featureCount
        self.bodyCount = bodyCount
        self.publicationCount = publicationCount
        self.sourceMutationCount = sourceMutationCount
        self.timeoutWallNanoseconds = timeoutWallNanoseconds
        self.cancellationCheckpointCount = cancellationCheckpointCount
    }

    func replacing(
        totalWallNanoseconds: UInt64? = nil,
        oracleWallNanoseconds: UInt64? = nil,
        readCount: Int? = nil,
        featureCount: Int? = nil,
        bodyCount: Int? = nil
    ) -> CADSphereTelemetry {
        CADSphereTelemetry(
            planningWallNanoseconds: planningWallNanoseconds,
            routeWallNanoseconds: routeWallNanoseconds,
            oracleWallNanoseconds: oracleWallNanoseconds ?? self.oracleWallNanoseconds,
            totalWallNanoseconds: totalWallNanoseconds ?? self.totalWallNanoseconds,
            capabilityRequestCount: capabilityRequestCount,
            actionCount: actionCount,
            commandCount: commandCount,
            readCount: readCount ?? self.readCount,
            entityCount: entityCount,
            featureCount: featureCount ?? self.featureCount,
            bodyCount: bodyCount ?? self.bodyCount,
            publicationCount: publicationCount,
            sourceMutationCount: sourceMutationCount,
            timeoutWallNanoseconds: timeoutWallNanoseconds,
            cancellationCheckpointCount: cancellationCheckpointCount
        )
    }

    func validate(caseID: CADBenchmarkCaseID) throws {
        guard capabilityRequestCount >= 0,
              actionCount >= 0,
              commandCount >= 0,
              readCount >= 0,
              entityCount >= 0,
              featureCount >= 0,
              bodyCount >= 0,
              publicationCount >= 0,
              sourceMutationCount >= 0,
              cancellationCheckpointCount >= 0,
              timeoutWallNanoseconds > 0,
              planningWallNanoseconds <= totalWallNanoseconds,
              routeWallNanoseconds <= totalWallNanoseconds,
              oracleWallNanoseconds <= totalWallNanoseconds else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "Sphere telemetry counts and phase durations must be bounded."
            )
        }
        guard capabilityRequestCount <= 1,
              actionCount == 0,
              commandCount == 0,
              readCount <= 1,
              entityCount == 0,
              featureCount == 0,
              bodyCount == 0,
              publicationCount == 0,
              sourceMutationCount == 0 else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "A sphere capability observation must remain within the zero-mutation envelope."
            )
        }
    }
}
