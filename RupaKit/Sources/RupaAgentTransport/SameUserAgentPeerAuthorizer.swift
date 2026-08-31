public struct SameUserAgentPeerAuthorizer: AgentPeerAuthorizing {
    public let expectedUserID: UInt32

    public init(expectedUserID: UInt32) {
        self.expectedUserID = expectedUserID
    }

    public func authorize(_ peer: UnixSocketPeerIdentity) throws {
        guard peer.userID == expectedUserID else {
            throw AgentPeerAuthorizationError.unauthorizedUser(
                actual: peer.userID,
                expected: expectedUserID
            )
        }
    }
}
