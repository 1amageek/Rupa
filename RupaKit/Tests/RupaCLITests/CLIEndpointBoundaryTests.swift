import ArgumentParser
import Foundation
import RupaAgentTransport
import Testing
@testable import RupaCLIKit

@Suite
struct CLIEndpointBoundaryTests {
    @Test
    func fileModeWithoutLiveCoordinatesDoesNotResolveAnEndpoint() throws {
        let client = try CLIAgentClientFactory.makeAgentClient(
            mode: .file,
            sessionID: nil,
            socket: nil
        )

        #expect(client == nil)
    }

    @Test
    func requiredClientUsesOnlyTheInjectedProductEndpoint() throws {
        let endpoint = try UnixSocketEndpoint(
            fileURL: URL(fileURLWithPath: "/private/tmp/rupa-product.sock")
        )
        let client = try CLIAgentClientFactory.makeRequiredAgentClient(
            socket: nil,
            endpointResolver: { endpoint }
        )

        #expect(client.endpoint == endpoint)
    }

    @Test
    func explicitEndpointOverrideIsRejectedBeforeResolution() throws {
        var didResolve = false

        #expect(throws: ValidationError.self) {
            _ = try CLIAgentClientFactory.makeRequiredAgentClient(
                socket: "/private/tmp/rupa-override.sock",
                endpointResolver: {
                    didResolve = true
                    return try UnixSocketEndpoint(
                        fileURL: URL(fileURLWithPath: "/private/tmp/unreachable.sock")
                    )
                }
            )
        }
        #expect(didResolve == false)
    }
}
