import Foundation
import RupaAgentTransport
import Synchronization
import Testing

@Test
func unixSocketEndpointRequiresAFileURL() throws {
    let fileURL = URL(fileURLWithPath: "/tmp/rupa.sock")
    let endpoint = try UnixSocketEndpoint(fileURL: fileURL)
    #expect(endpoint.path == fileURL.standardizedFileURL.path)

    let networkURL = try #require(URL(string: "https://example.com/rupa.sock"))
    #expect(throws: UnixSocketEndpointError.invalidFileURL(networkURL)) {
        try UnixSocketEndpoint(fileURL: networkURL)
    }
}

@Test
func peerAuthorizerReceivesTheTransportIdentity() throws {
    let authorizer = RecordingPeerAuthorizer()
    let peer = UnixSocketPeerIdentity(userID: 501)
    try authorizer.authorize(peer)
    #expect(authorizer.lastPeer == peer)
}

private final class RecordingPeerAuthorizer: AgentPeerAuthorizing {
    private let state = Mutex<UnixSocketPeerIdentity?>(nil)

    var lastPeer: UnixSocketPeerIdentity? {
        state.withLock { $0 }
    }

    func authorize(_ peer: UnixSocketPeerIdentity) throws {
        state.withLock { $0 = peer }
    }
}
