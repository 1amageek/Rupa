import Darwin
import Foundation
import Testing
import RupaCore
import SwiftCAD
@testable import RupaAgent
@testable import RupaAgentTransport

func withRunningListener<T>(
    controller: sending AgentCommandController,
    socketURL: URL,
    operation: (AgentSocketListener, AgentClient) async throws -> T
) async throws -> T {
    let socketPath = AgentSocketPath(socketURL.path)
    let listener = AgentSocketListener(
        controller: controller,
        socketPath: socketPath
    )
    let client = AgentClient(socketPath: socketPath)

    try await listener.start()
    do {
        let result = try await operation(listener, client)
        await listener.stop()
        return result
    } catch {
        await listener.stop()
        throw error
    }
}

func sendRaw(_ data: Data, to socketURL: URL) throws -> Data {
    let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
        throw EditorError(
            code: .agentUnavailable,
            message: "Failed to create test socket. errno=\(errno)"
        )
    }
    defer {
        Darwin.close(descriptor)
    }

    try AgentSocketAddress.withUnixAddress(path: socketURL.path) { address, length in
        guard Darwin.connect(descriptor, address, length) == 0 else {
            throw EditorError(
                code: .agentConnectionFailed,
                message: "Failed to connect test socket. errno=\(errno)"
            )
        }
    }
    try AgentSocketIO.writeAll(data, to: descriptor)
    Darwin.shutdown(descriptor, SHUT_WR)
    return try AgentSocketIO.readAll(from: descriptor)
}

func sendThroughDetachedClient(
    _ request: AgentRequest,
    socketPath: AgentSocketPath
) async throws -> AgentResponse {
    try await Task.detached {
        let client = AgentClient(socketPath: socketPath)
        return try client.send(request)
    }.value
}

func makeTemporaryDirectory() throws -> URL {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: temporaryDirectory,
        withIntermediateDirectories: true
    )
    return temporaryDirectory
}

func removeTemporaryDirectory(_ url: URL) {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to remove temporary directory: \(error)")
    }
}
