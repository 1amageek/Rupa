public protocol AgentPeerAuthorizing: Sendable {
    func authorize(_ peer: UnixSocketPeerIdentity) throws
}
