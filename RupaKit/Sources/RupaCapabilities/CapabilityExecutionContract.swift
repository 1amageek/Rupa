public struct CapabilityExecutionContract: Codable, Equatable, Sendable {
    public var supportsDryRun: Bool
    public var supportsCancellation: Bool
    public var reportsProgress: Bool
    public var determinism: CapabilityDeterminism
    public var requiresTransactionRevision: Bool
    public var retrySafe: Bool

    public init(
        supportsDryRun: Bool,
        supportsCancellation: Bool = false,
        reportsProgress: Bool = false,
        determinism: CapabilityDeterminism = .deterministic,
        requiresTransactionRevision: Bool = false,
        retrySafe: Bool = false
    ) {
        self.supportsDryRun = supportsDryRun
        self.supportsCancellation = supportsCancellation
        self.reportsProgress = reportsProgress
        self.determinism = determinism
        self.requiresTransactionRevision = requiresTransactionRevision
        self.retrySafe = retrySafe
    }
}
