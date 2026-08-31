public enum AgentPeerAuthorizationError: Error, Equatable, Sendable {
    case identityUnavailable(errorNumber: Int32)
    case unauthorizedUser(actual: UInt32, expected: UInt32)
}
