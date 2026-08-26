import Foundation
import RupaAgentRuntime
import RupaAgentTransport
import RupaCore
import RupaDomainFoundation
import RupaKit

public enum AgentHostState: Equatable, Sendable {
    case stopped
    case starting
    case running(socketPath: String)
    case failed(message: String)
}

@MainActor
public final class AgentHost {
    public private(set) var state: AgentHostState

    private let controller: ProjectAgentCommandController
    private let listener: any AgentHostListening
    private let socketPath: AgentSocketPath
    private var lifecycleGeneration: Int

    public init(
        socketPath: AgentSocketPath = AgentSocketPath(),
        exportService: DocumentExportService = DocumentExportService(),
        domainRegistry: DomainRegistry = DomainRegistry()
    ) {
        self.socketPath = socketPath
        self.controller = ProjectAgentCommandController(
            domainRegistry: domainRegistry,
            exportExecutor: ProjectAgentExportExecutor(exportService: exportService)
        )
        self.listener = AgentSocketListener(
            handler: controller,
            socketPath: socketPath
        )
        self.state = .stopped
        self.lifecycleGeneration = 0
    }

    init(
        socketPath: AgentSocketPath,
        listener: any AgentHostListening,
        exportService: DocumentExportService = DocumentExportService(),
        domainRegistry: DomainRegistry = DomainRegistry()
    ) {
        self.socketPath = socketPath
        self.controller = ProjectAgentCommandController(
            domainRegistry: domainRegistry,
            exportExecutor: ProjectAgentExportExecutor(exportService: exportService)
        )
        self.listener = listener
        self.state = .stopped
        self.lifecycleGeneration = 0
    }

    public func start() async {
        switch state {
        case .starting, .running:
            return
        case .stopped, .failed:
            break
        }

        advanceLifecycleGeneration()
        let generation = lifecycleGeneration
        state = .starting
        do {
            try await listener.start()
            guard lifecycleGeneration == generation else {
                return
            }
            state = .running(socketPath: socketPath.value)
        } catch {
            guard lifecycleGeneration == generation else {
                return
            }
            state = .failed(message: error.localizedDescription)
        }
    }

    public func stop() async {
        guard state != .stopped else {
            return
        }

        advanceLifecycleGeneration()
        await listener.stop()
        state = .stopped
    }

    @discardableResult
    public func register(
        workspace: ProjectWorkspace,
        path: URL? = nil,
        id: UUID = UUID()
    ) async throws -> UUID {
        try await controller.register(workspace: workspace, path: path, id: id)
    }

    public func unregister(id: UUID) async {
        await controller.unregister(id: id)
    }

    private func advanceLifecycleGeneration() {
        if lifecycleGeneration == Int.max {
            lifecycleGeneration = 1
        } else {
            lifecycleGeneration += 1
        }
    }
}

protocol AgentHostListening: Sendable {
    func start() async throws
    func stop() async
}

extension AgentSocketListener: AgentHostListening {}
