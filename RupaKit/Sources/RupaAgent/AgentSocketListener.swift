import Darwin
import Foundation
import RupaCore

public actor AgentSocketListener {
    private let socketPath: AgentSocketPath
    private let service: AgentSocketService
    private var listenDescriptor: Int32?
    private var acceptTask: Task<Void, Never>?

    public init(
        controller: sending AgentCommandController,
        socketPath: AgentSocketPath = AgentSocketPath()
    ) {
        self.socketPath = socketPath
        self.service = AgentSocketService(controller: controller)
    }

    public init(
        mainActorBridge: MainActorAgentBridge,
        socketPath: AgentSocketPath = AgentSocketPath()
    ) {
        self.socketPath = socketPath
        self.service = AgentSocketService(mainActorBridge: mainActorBridge)
    }

    public var path: String {
        socketPath.value
    }

    public var isRunning: Bool {
        listenDescriptor != nil
    }

    public func start() async throws {
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
            let socketService = service
            acceptTask = Task.detached {
                await Self.runAcceptLoop(
                    descriptor: descriptor,
                    service: socketService
                )
            }
        } catch {
            Darwin.close(descriptor)
            removeSocketFile()
            throw error
        }
    }

    public func stop() async {
        let descriptor = listenDescriptor
        let task = acceptTask
        listenDescriptor = nil
        acceptTask = nil

        task?.cancel()
        if let descriptor {
            Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
        }
        removeSocketFile()
        await service.setSocketPath(nil)
        await task?.value
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

        let isActive = try AgentSocketAddress.withUnixAddress(path: socketPath.value) { address, length in
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

    private nonisolated static func runAcceptLoop(
        descriptor: Int32,
        service: AgentSocketService
    ) async {
        while !Task.isCancelled {
            let connection = Darwin.accept(descriptor, nil, nil)
            if connection >= 0 {
                await handle(connection: connection, service: service)
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
        defer {
            Darwin.close(connection)
        }

        do {
            let requestData = try AgentSocketIO.readAll(from: connection)
            let responseData = await service.responseData(for: requestData)
            try AgentSocketIO.writeAll(responseData, to: connection)
        } catch {
            let responseData = await service.failureResponseData(for: error)
            do {
                try AgentSocketIO.writeAll(responseData, to: connection)
            } catch {
                return
            }
        }
    }
}

public actor AgentSocketService {
    private enum Handler {
        case controller(AgentCommandController)
        case mainActorBridge(MainActorAgentBridge)
    }

    private let handler: Handler
    private let codec: AgentMessageCodec

    public init(
        controller: sending AgentCommandController,
        codec: AgentMessageCodec = AgentMessageCodec()
    ) {
        self.handler = .controller(controller)
        self.codec = codec
    }

    public init(
        mainActorBridge: MainActorAgentBridge,
        codec: AgentMessageCodec = AgentMessageCodec()
    ) {
        self.handler = .mainActorBridge(mainActorBridge)
        self.codec = codec
    }

    public func setSocketPath(_ path: String?) async {
        switch handler {
        case .controller(let controller):
            controller.socketPath = path
        case .mainActorBridge(let bridge):
            await bridge.setSocketPath(path)
        }
    }

    public func responseData(for requestData: Data) async -> Data {
        do {
            let requestEnvelope = try codec.decodeRequestEnvelope(from: requestData)
            let response = await response(for: requestEnvelope.params)
            return try codec.encode(
                response,
                id: requestEnvelope.id,
                method: requestEnvelope.method
            )
        } catch {
            return failureResponseData(for: error)
        }
    }

    public func failureResponseData(for error: Error) -> Data {
        let response: AgentResponse
        if let error = error as? EditorError {
            response = .failure(error)
        } else {
            response = .failure(
                EditorError(
                    code: .commandInvalid,
                    message: error.localizedDescription
                )
            )
        }

        do {
            return try codec.encode(response, id: nil)
        } catch {
            return Data()
        }
    }

    private func response(for request: AgentRequest) async -> AgentResponse {
        switch handler {
        case .controller(let controller):
            controller.handle(request)
        case .mainActorBridge(let bridge):
            await bridge.handle(request)
        }
    }
}
