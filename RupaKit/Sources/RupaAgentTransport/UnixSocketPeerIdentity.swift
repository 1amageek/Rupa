public struct UnixSocketPeerIdentity: Equatable, Sendable {
    public let userID: UInt32

    public init(userID: UInt32) {
        self.userID = userID
    }
}
