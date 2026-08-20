import Darwin
import Foundation
import RupaAgentProtocol
import RupaCoreTypes

public actor AgentSocketListener {
    private struct ActiveConnection: Sendable {
        let descriptor: Int32
        let task: Task<Void, Never>
    }

    private static let maximumConcurrentConnectionCount = 32

    private let socketPath: AgentSocketPath
    private let service: AgentSocketService
    private var listenDescriptor: Int32?
    private var acceptTask: Task<Void, Never>?
    private var activeConnections: [UInt64: ActiveConnection] = [:]
    private var nextConnectionID: UInt64 = 0
    private var isStopping = false
    private var stoppingTasks: [Task<Void, Never>] = []

    public init(
        handler: any AgentSocketServing,
        socketPath: AgentSocketPath = AgentSocketPath()
    ) {
        self.socketPath = socketPath
        self.service = AgentSocketService(handler: handler)
    }

    public var path: String {
        socketPath.value
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
            try AgentSocketAddress.withUnixAddress(path: socketPath.value) { address, length in
                guard Darwin.bind(descriptor, address, length) == 0 else {
                    throw EditorError(
                        code: .agentUnavailable,
                        message: "Failed to bind Rupa agent socket. errno=\(errno)"
                    )
                }
            }

            guard Darwin.listen(descriptor, SOMAXCONN) == 0 else {
                throw EditorError(
                    code: .agentUnavailable,
                    message: "Failed to listen on Rupa agent socket. errno=\(errno)"
                )
            }

            listenDescriptor = descriptor
            await service.setSocketPath(socketPath.value)
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
            let tasks = stoppingTasks
            for task in tasks {
                await task.value
            }
            return
        }
        guard listenDescriptor != nil
                || acceptTask != nil
                || !activeConnections.isEmpty else {
            removeSocketFile()
            await service.setSocketPath(nil)
            return
        }

        isStopping = true
        let descriptor = listenDescriptor
        let task = acceptTask
        let connections = Array(activeConnections.values)
        listenDescriptor = nil
        acceptTask = nil
        stoppingTasks = connections.map(\.task)
        if let task {
            stoppingTasks.append(task)
        }

        task?.cancel()
        if let descriptor {
            Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
        }
        for connection in connections {
            Darwin.shutdown(connection.descriptor, SHUT_RDWR)
        }
        removeSocketFile()
        await service.setSocketPath(nil)
        await task?.value
        for connection in connections {
            await connection.task.value
        }
        stoppingTasks.removeAll(keepingCapacity: true)
        isStopping = false
    }

    private func prepareSocketDirectory() throws {
        let directory = URL(fileURLWithPath: socketPath.value).deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw EditorError(
                code: .agentUnavailable,
                message: "Failed to create Rupa agent socket directory: \(error.localizedDescription)"
            )
        }
    }

    private func removeStaleSocketIfNeeded() throws {
        guard FileManager.default.fileExists(atPath: socketPath.value) else {
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

        let isActive = try AgentSocketAddress.withUnixAddress(path: socketPath.value) {
            address,
            length in
            Darwin.connect(descriptor, address, length) == 0
        }
        guard !isActive else {
            throw EditorError(
                code: .agentUnavailable,
                message: "Rupa agent socket is already in use at \(socketPath.value)."
            )
        }

        guard unlink(socketPath.value) == 0 || errno == ENOENT else {
            throw EditorError(
                code: .agentUnavailable,
                message: "Failed to remove stale Rupa agent socket. errno=\(errno)"
            )
        }
    }

    private func removeSocketFile() {
        guard unlink(socketPath.value) == 0 || errno == ENOENT else {
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
        let task = Task.detached {
            await Self.handle(connection: descriptor, service: service)
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
        service: AgentSocketService
    ) async {
        do {
            let requestData = try AgentSocketIO.readFrame(from: connection)
            let responseData = try await service.responseData(for: requestData)
            try AgentSocketIO.writeFrame(responseData, to: connection)
        } catch {
            do {
                let responseData = try await service.failureResponseData(for: error)
                try AgentSocketIO.writeFrame(responseData, to: connection)
            } catch {
                return
            }
        }
    }
}
