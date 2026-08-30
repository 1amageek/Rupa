public enum CADBenchmarkBaselineError: Error, Equatable, Sendable {
    case invalidContextCount(expected: Int, actual: Int)
    case invalidContextIdentity
    case missingCapabilityStatus(caseID: String)
    case capabilitySnapshotVersionDrift(expected: String, actual: String)
    case capabilityStatusDrift(identity: String)
    case baselineAlreadyExists
    case invalidEnvironmentFingerprint
    case invalidExecutionBaseline
    case invalidReport
    case encodedArtifactTooLarge(limit: Int, actual: Int)
}
