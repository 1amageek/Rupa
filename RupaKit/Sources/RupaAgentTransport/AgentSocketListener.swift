import Darwin
import Foundation
import RupaAgentProtocol
import RupaCoreTypes

public actor AgentSocketListener {
    private struct ActiveConnection: Sendable {
        let descriptor: Int32
        let task: Task<Void, Never>
    }

    static let maximumConcurrentConnectionCount = 32

    private let endpoint: UnixSocketEndpoint
    private let peerAuthorizer: any AgentPeerAuthorizing
    private let service: AgentSocketService
    private let requestTimeout: Duration
    private let shutdownTimeout: Duration
    private var listenDescriptor: Int32?
    private var acceptTask: Task<Void, Never>?
    private var activeConnections: [UInt64: ActiveConnection] = [:]
    private var nextConnectionID: UInt64 = 0
    private var isStopping = false

    public init(
        handler: any AgentRequestHandling,
        endpoint: UnixSocketEndpoint,
        peerAuthorizer: any AgentPeerAuthorizing,
        requestTimeout: Duration = .seconds(30),
        shutdownTimeout: Duration = .seconds(5)
    ) {
        self.endpoint = endpoint
        self.peerAuthorizer = peerAuthorizer
        self.service = AgentSocketService(handler: handler)
        self.requestTimeout = requestTimeout
        self.shutdownTimeout = shutdownTimeout
    }

    public var isRunning: Bool {
        listenDescriptor != nil && !isStopping
    }

    var activeConnectionCount: Int {
        activeConnections.count
    }

    public func start() async throws {
        guard !isStopping else {
            throw EditorError(
                code: .agentUnavailable,
                message: "Rupa agent listener is still stopping."
            )
        }
        guard listenDescriptor == nil else {
            return
        }

        try prepareSocketDirectory()
        try removeStaleSocketIfNeeded()

        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw EditorError(
                code: .agentUnavailable,
                message: "Failed to create agent listener socket. errno=\(errno)"
            )
        }

        do {
            try AgentSocketAddress.withUnixAddress(path: endpoint.path) { address, length in
                guard Darwin.bind(descriptor, address, length) == 0 else {
                    throw EditorError(
                        code: .agentUnavailable,
                        message: "Failed to bind Rupa agent socket. errno=\(errno)"
                    )
                }
            }
            guard chmod(endpoint.path, mode_t(0o600)) == 0 else {
                throw EditorError(
                    code: .agentUnavailable,
                    message: "Failed to set owner-only Rupa agent socket permissions. errno=\(errno)"
                )
            }

            guard Darwin.listen(descriptor, SOMAXCONN) == 0 else {
                throw EditorError(
                    code: .agentUnavailable,
                    message: "Failed to listen on Rupa agent socket. errno=\(errno)"
                )
            }

            listenDescriptor = descriptor
            acceptTask = Task.detached {
                await Self.runAcceptLoop(
                    descriptor: descriptor,
                    listener: self
                )
            }
        } catch {
            Darwin.close(descriptor)
            removeSocketFile()
            throw error
        }
    }

    public func stop() async {
        if isStopping {
            while isStopping {
                await Task.yield()
            }
            return
        }
        guard listenDescriptor != nil
                || acceptTask != nil
                || !activeConnections.isEmpty else {
            removeSocketFile()
            return
        }

        isStopping = true
        let descriptor = listenDescriptor
        let task = acceptTask
        listenDescriptor = nil
        acceptTask = nil

        task?.cancel()
        if let descriptor {
            Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
        }
        for connection in activeConnections.values {
            connection.task.cancel()
            Darwin.shutdown(connection.descriptor, SHUT_RDWR)
        }
        removeSocketFile()

        let deadline: AgentSocketDeadline?
        do {
            deadline = try AgentSocketDeadline.request(timeout: shutdownTimeout)
        } catch {
            deadline = nil
        }
        while !activeConnections.isEmpty {
            guard let deadline else {
                break
            }
            do {
                _ = try deadline.remainingMilliseconds()
                try await Task.sleep(for: .milliseconds(5))
            } catch {
                break
            }
        }

        for connection in activeConnections.values {
            Darwin.close(connection.descriptor)
        }
        activeConnections.removeAll(keepingCapacity: true)
        isStopping = false
    }

    private func prepareSocketDirectory() throws {
        let directory = endpoint.fileURL.deletingLastPathComponent()
        var directoryState = stat()
        if lstat(directory.path, &directoryState) == 0 {
            guard directoryState.st_uid == getuid(),
                  directoryState.st_mode & S_IFMT == S_IFDIR else {
                throw EditorError(
                    code: .agentUnavailable,
                    message: "Rupa agent socket directory must be an owner-controlled directory."
                )
            }
        } else if errno == ENOENT {
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                throw EditorError(
                    code: .agentUnavailable,
                    message: "Failed to create Rupa agent socket directory: \(error.localizedDescription)"
                )
            }
        } else {
            throw EditorError(
                code: .agentUnavailable,
                message: "Failed to inspect Rupa agent socket directory. errno=\(errno)"
            )
        }

        guard chmod(directory.path, mode_t(0o700)) == 0 else {
            throw EditorError(
                code: .agentUnavailable,
                message: "Failed to set owner-only Rupa agent directory permissions. errno=\(errno)"
            )
        }
    }

    private func removeStaleSocketIfNeeded() throws {
        guard FileManager.default.fileExists(atPath: endpoint.path) else {
            return
        }

        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw EditorError(
                code: .agentUnavailable,
                message: "Failed to create stale socket probe. errno=\(errno)"
            )
        }
        defer {
            Darwin.close(descriptor)
        }

        let isActive = try AgentSocketAddress.withUnixAddress(path: endpoint.path) {
            address,
            length in
            Darwin.connect(descriptor, address, length) == 0
        }
        guard !isActive else {
            throw EditorError(
                code: .agentUnavailable,
                message: "The injected Rupa agent endpoint is already in use."
            )
        }

        guard unlink(endpoint.path) == 0 || errno == ENOENT else {
            throw EditorError(
                code: .agentUnavailable,
                message: "Failed to remove stale Rupa agent socket. errno=\(errno)"
            )
        }
    }

    private func removeSocketFile() {
        guard unlink(endpoint.path) == 0 || errno == ENOENT else {
            return
        }
    }

    private func acceptConnection(_ descriptor: Int32) {
        guard listenDescriptor != nil,
              !isStopping,
              activeConnections.count < Self.maximumConcurrentConnectionCount else {
            Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
            return
        }
        do {
            try AgentSocketIO.configure(descriptor)
        } catch {
            Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
            return
        }

        let connectionID = nextConnectionID
        nextConnectionID += 1
        let service = service
        let peerAuthorizer = peerAuthorizer
        let requestTimeout = requestTimeout
        let task = Task.detached {
            await Self.handle(
                connection: descriptor,
                service: service,
                peerAuthorizer: peerAuthorizer,
                requestTimeout: requestTimeout
            )
            await self.connectionDidFinish(connectionID)
        }
        activeConnections[connectionID] = ActiveConnection(
            descriptor: descriptor,
            task: task
        )
    }

    private func connectionDidFinish(_ connectionID: UInt64) {
        guard let connection = activeConnections.removeValue(
            forKey: connectionID
        ) else {
            return
        }
        Darwin.close(connection.descriptor)
    }

    private nonisolated static func runAcceptLoop(
        descriptor: Int32,
        listener: AgentSocketListener
    ) async {
        while !Task.isCancelled {
            let connection = Darwin.accept(descriptor, nil, nil)
            if connection >= 0 {
                await listener.acceptConnection(connection)
            } else if errno == EINTR {
                continue
            } else {
                break
            }
        }
    }

    private nonisolated static func handle(
        connection: Int32,
        service: AgentSocketService,
        peerAuthorizer: any AgentPeerAuthorizing,
        requestTimeout: Duration
    ) async {
        do {
            let peer = try peerIdentity(for: connection)
            try peerAuthorizer.authorize(peer)
        } catch {
            return
        }

        let deadline: AgentSocketDeadline
        do {
            deadline = try AgentSocketDeadline.request(timeout: requestTimeout)
        } catch {
            return
        }

        do {
            let requestData = try await AgentSocketIO.readFrameAsynchronously(
                from: connection,
                deadline: deadline
            )
            let responseData = try await service.responseData(for: requestData)
            try await AgentSocketIO.writeFrameAsynchronously(
                responseData,
                to: connection,
                deadline: deadline
            )
        } catch is CancellationError {
            return
        } catch {
            do {
                let responseData = try await service.failureResponseData(for: error)
                try await AgentSocketIO.writeFrameAsynchronously(
                    responseData,
                    to: connection,
                    deadline: deadline
                )
            } catch {
                return
            }
        }
    }

    private nonisolated static func peerIdentity(
        for descriptor: Int32
    ) throws -> UnixSocketPeerIdentity {
        var userID: uid_t = 0
        var groupID: gid_t = 0
        guard getpeereid(descriptor, &userID, &groupID) == 0 else {
            throw AgentPeerAuthorizationError.identityUnavailable(
                errorNumber: errno
            )
        }
        return UnixSocketPeerIdentity(userID: userID)
    }
}
