import Foundation

/// Measured durations and exact source/B-rep counts for one sphere case.
struct CADSphereTelemetry: Codable, Equatable, Sendable {
    let planningWallNanoseconds: UInt64
    let routeWallNanoseconds: UInt64
    let oracleWallNanoseconds: UInt64
    let totalWallNanoseconds: UInt64
    let actionCount: Int
    let commandCount: Int
    let readCount: Int
    let featureCount: Int
    let bodyCount: Int
    let faceCount: Int
    let edgeCount: Int
    let vertexCount: Int
    let analyticSurfaceCount: Int
    let timeoutWallNanoseconds: UInt64
    let cancellationCheckpointCount: Int

    func replacing(
        totalWallNanoseconds: UInt64? = nil,
        oracleWallNanoseconds: UInt64? = nil,
        readCount: Int? = nil,
        featureCount: Int? = nil,
        bodyCount: Int? = nil,
        faceCount: Int? = nil,
        edgeCount: Int? = nil,
        vertexCount: Int? = nil,
        analyticSurfaceCount: Int? = nil
    ) -> CADSphereTelemetry {
        CADSphereTelemetry(
            planningWallNanoseconds: planningWallNanoseconds,
            routeWallNanoseconds: routeWallNanoseconds,
            oracleWallNanoseconds: oracleWallNanoseconds ?? self.oracleWallNanoseconds,
            totalWallNanoseconds: totalWallNanoseconds ?? self.totalWallNanoseconds,
            actionCount: actionCount,
            commandCount: commandCount,
            readCount: readCount ?? self.readCount,
            featureCount: featureCount ?? self.featureCount,
            bodyCount: bodyCount ?? self.bodyCount,
            faceCount: faceCount ?? self.faceCount,
            edgeCount: edgeCount ?? self.edgeCount,
            vertexCount: vertexCount ?? self.vertexCount,
            analyticSurfaceCount: analyticSurfaceCount ?? self.analyticSurfaceCount,
            timeoutWallNanoseconds: timeoutWallNanoseconds,
            cancellationCheckpointCount: cancellationCheckpointCount
        )
    }

    func validate(caseID: CADBenchmarkCaseID) throws {
        guard actionCount >= 0,
              commandCount >= 0,
              readCount >= 0,
              featureCount >= 0,
              bodyCount >= 0,
              faceCount >= 0,
              edgeCount >= 0,
              vertexCount >= 0,
              analyticSurfaceCount >= 0,
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
    }
}
