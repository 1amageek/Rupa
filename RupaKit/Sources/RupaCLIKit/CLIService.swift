import Foundation
import RupaAgentProtocol
import RupaAutomation
import RupaCore
import RupaDomainFoundation
import RupaProjectAccess

public struct CLIReadEnvelope: Sendable {
    public let response: AgentResponse
    public let state: AutomationResult

    public init(response: AgentResponse, state: AutomationResult) {
        self.response = response
        self.state = state
    }
}

public struct CLIAutomationMutationExecution: Sendable {
    public let result: AutomationResult
    public let dirty: Bool
    public let saved: Bool

    public var response: CLIResponse {
        CLIResponse(result: result, dirty: dirty, saved: saved)
    }
}

public struct CLIService {
    public init() {}

    @MainActor
    public func capabilities() async throws -> [String] {
        try await CLIProjectAccessRunner.capabilities().map(\.name)
    }

    @MainActor
    public func agentStatus() async throws -> CLIAgentStatusResponse {
        CLIAgentStatusResponse(status: try await CLIProjectAccessRunner.status())
    }

    @MainActor
    public func sessions() async throws -> CLISessionsResponse {
        CLISessionsResponse(sessions: try await CLIProjectAccessRunner.sessions())
    }

    @MainActor
    public func attach(target: CLIDocumentTarget) async throws -> CLIAttachResponse {
        guard target.fileURL != nil || target.sessionID != nil else {
            throw invalidCommand("Attach requires a .rupa project path or session ID.")
        }
        guard !(target.fileURL != nil && target.sessionID != nil) else {
            throw invalidCommand("Attach accepts either a .rupa project path or session ID, not both.")
        }

        let openSessions = try await CLIProjectAccessRunner.sessions()
        if let sessionID = target.sessionID {
            guard let session = openSessions.first(where: { $0.id == sessionID }) else {
                throw EditorError(
                    code: .sessionNotFound,
                    message: "No open Rupa session exists for \(sessionID.uuidString)."
                )
            }
            return CLIAttachResponse(session: session)
        }

        guard let url = target.fileURL else {
            throw invalidCommand("Attach requires a .rupa project path or session ID.")
        }
        _ = try ProjectAccessTarget.liveProject(url).validated()
        let requestedPath = canonicalPath(url)
        let matches = openSessions.filter { summary in
            guard let path = summary.path else {
                return false
            }
            return canonicalPath(URL(fileURLWithPath: path)) == requestedPath
        }
        guard matches.count <= 1 else {
            throw invalidCommand("Multiple open Rupa sessions match \(url.path).")
        }
        guard let session = matches.first else {
            throw EditorError(
                code: .sessionNotFound,
                message: "No open Rupa session matches \(url.path)."
            )
        }
        return CLIAttachResponse(session: session)
    }

    public func read(
        target: CLIDocumentTarget,
        expectedGeneration: DocumentGeneration? = nil,
        request: @escaping (UUID) -> AgentRequest
    ) async throws -> CLIReadEnvelope {
        try await CLIProjectAccessRunner.withSession(target: target) { session in
            let state = try await documentState(
                session: session,
                expectedGeneration: expectedGeneration
            )
            let response = try await session.send(request(session.sessionID))
            try Self.throwIfFailure(response)
            return CLIReadEnvelope(response: response, state: state)
        }
    }

    public func send(
        target: CLIDocumentTarget,
        request: @escaping (UUID) -> AgentRequest
    ) async throws -> AgentResponse {
        try await CLIProjectAccessRunner.withSession(target: target) { session in
            let response = try await session.send(request(session.sessionID))
            try Self.throwIfFailure(response)
            return response
        }
    }

    public func workspaceScale(
        target: CLIDocumentTarget,
        expectedGeneration: DocumentGeneration? = nil
    ) async throws -> WorkspaceScaleSnapshot {
        let state = try await withState(
            target: target,
            expectedGeneration: expectedGeneration
        )
        guard let scale = state.workspaceScale else {
            throw Self.unexpectedResponse("Document description did not include workspace scale.")
        }
        return scale
    }

    public func applyAutomationCommand(
        target: CLIDocumentTarget,
        command: AutomationCommand,
        expectedGeneration: DocumentGeneration? = nil,
        expectedWorkspaceRevision: WorkspaceRevision? = nil
    ) async throws -> CLIResponse {
        try await executeAutomationMutationCommand(
            command,
            target: target,
            expectedGeneration: expectedGeneration,
            expectedWorkspaceRevision: expectedWorkspaceRevision
        ).response
    }

    public func executeAutomationMutationCommand(
        _ command: AutomationCommand,
        target: CLIDocumentTarget,
        expectedGeneration: DocumentGeneration?,
        expectedWorkspaceRevision: WorkspaceRevision? = nil
    ) async throws -> CLIAutomationMutationExecution {
        return try await CLIProjectAccessRunner.withSession(target: target) { session in
            let preconditions = try await commandPreconditions(
                command: command,
                session: session,
                expectedGeneration: expectedGeneration,
                expectedWorkspaceRevision: expectedWorkspaceRevision
            )
            let response = try await session.send(
                .execute(
                    sessionID: session.sessionID,
                    command: command,
                    expectedGeneration: preconditions.generation,
                    expectedWorkspaceRevision: preconditions.workspaceRevision
                )
            )
            let result = try Self.commandResult(from: response)
            return CLIAutomationMutationExecution(
                result: result,
                dirty: result.sourceDirty,
                saved: false
            )
        }
    }

    public func executeCommandMutationRequest(
        target: CLIDocumentTarget,
        expectedGeneration: DocumentGeneration?,
        request: @escaping (UUID) -> AgentRequest
    ) async throws -> CLIResponse {
        return try await CLIProjectAccessRunner.withSession(target: target) { session in
            let response = try await session.send(request(session.sessionID))
            let result = try Self.commandResult(from: response)
            return CLIResponse(
                result: result,
                dirty: result.sourceDirty,
                saved: false
            )
        }
    }

    public func executeDomain(
        target: CLIDocumentTarget,
        request: DomainCommandRequest
    ) async throws -> CLIDomainExecutionResponse {
        return try await CLIProjectAccessRunner.withSession(target: target) { session in
            let response = try await session.send(
                .executeDomain(sessionID: session.sessionID, request: request)
            )
            let result = try Self.domainResult(from: response)
            return CLIDomainExecutionResponse(
                result: result,
                dirty: result.didMutate,
                saved: false
            )
        }
    }

    public func runBatch(
        target: CLIDocumentTarget,
        batch: AutomationBatch
    ) async throws -> CLIBatchResponse {
        return try await CLIProjectAccessRunner.withSession(target: target) { session in
            let effectiveBatch = try await batchWithPreconditions(batch, session: session)
            let response = try await session.send(
                .executeBatch(sessionID: session.sessionID, batch: effectiveBatch)
            )
            let result = try Self.batchResult(from: response)
            return CLIBatchResponse(
                results: result.results,
                generation: result.generation,
                workspaceRevision: result.workspaceRevision,
                dirty: result.dirty,
                saved: false,
                metrics: result.metrics
            )
        }
    }

    public func saveDocument(
        target: CLIDocumentTarget,
        expectedGeneration: DocumentGeneration? = nil
    ) async throws -> CLISaveResponse {
        try await CLIProjectAccessRunner.withSession(target: target) { session in
            CLISaveResponse(
                result: try await session.save(expectedGeneration: expectedGeneration)
            )
        }
    }

    public func exportDocument(
        target: CLIDocumentTarget,
        outputURL: URL,
        expectedGeneration: DocumentGeneration? = nil,
        options: ExportOptions = ExportOptions(),
        dryRun: Bool = false
    ) async throws -> CLIExportResponse {
        try await CLIProjectAccessRunner.withSession(target: target) { session in
            let response = try await session.send(
                .export(
                    sessionID: session.sessionID,
                    outputPath: outputURL.path,
                    expectedGeneration: expectedGeneration,
                    options: options,
                    dryRun: dryRun
                )
            )
            switch response {
            case .export(let result):
                let state = try await documentState(
                    session: session,
                    expectedGeneration: result.generation
                )
                return CLIExportResponse(result: result, dirty: state.sourceDirty)
            case .failure(let error):
                throw error
            case .committedMutation(let outcome):
                throw CLICommittedMutationError(outcome: outcome)
            default:
                throw Self.unexpectedResponse("Export request returned an unexpected response.")
            }
        }
    }

    private func withState(
        target: CLIDocumentTarget,
        expectedGeneration: DocumentGeneration?
    ) async throws -> AutomationResult {
        try await CLIProjectAccessRunner.withSession(target: target) { session in
            try await documentState(session: session, expectedGeneration: expectedGeneration)
        }
    }

    private func documentState(
        session: any ProjectAccessSession,
        expectedGeneration: DocumentGeneration?
    ) async throws -> AutomationResult {
        let response = try await session.send(
            .execute(
                sessionID: session.sessionID,
                command: .describeDocument,
                expectedGeneration: expectedGeneration
            )
        )
        return try Self.commandResult(from: response)
    }

    private func commandPreconditions(
        command: AutomationCommand,
        session: any ProjectAccessSession,
        expectedGeneration: DocumentGeneration?,
        expectedWorkspaceRevision: WorkspaceRevision?
    ) async throws -> (generation: DocumentGeneration, workspaceRevision: WorkspaceRevision?) {
        let requiresWorkspaceRevision = command.effect == .workspaceMutation
        if let expectedGeneration,
           !requiresWorkspaceRevision || expectedWorkspaceRevision != nil {
            return (expectedGeneration, expectedWorkspaceRevision)
        }
        let state = try await documentState(
            session: session,
            expectedGeneration: expectedGeneration
        )
        return (
            expectedGeneration ?? state.generation,
            requiresWorkspaceRevision
                ? expectedWorkspaceRevision ?? state.workspaceRevision
                : expectedWorkspaceRevision
        )
    }

    private func batchWithPreconditions(
        _ batch: AutomationBatch,
        session: any ProjectAccessSession
    ) async throws -> AutomationBatch {
        let effect = try batch.validatedEffect()
        let requiresWorkspaceRevision = effect == .workspaceMutation
        if batch.expectedGeneration != nil,
           !requiresWorkspaceRevision || batch.expectedWorkspaceRevision != nil {
            return batch
        }
        let state = try await documentState(
            session: session,
            expectedGeneration: batch.expectedGeneration
        )
        return AutomationBatch(
            commands: batch.commands,
            expectedGeneration: batch.expectedGeneration ?? state.generation,
            expectedWorkspaceRevision: requiresWorkspaceRevision
                ? batch.expectedWorkspaceRevision ?? state.workspaceRevision
                : batch.expectedWorkspaceRevision
        )
    }

    private static func throwIfFailure(_ response: AgentResponse) throws {
        switch response {
        case .failure(let error):
            throw error
        case .committedMutation(let outcome):
            throw CLICommittedMutationError(outcome: outcome)
        default:
            return
        }
    }

    private static func commandResult(from response: AgentResponse) throws -> AutomationResult {
        switch response {
        case .command(let result):
            result
        case .failure(let error):
            throw error
        case .committedMutation(let outcome):
            throw CLICommittedMutationError(outcome: outcome)
        default:
            throw unexpectedResponse("Command request returned an unexpected response.")
        }
    }

    private static func batchResult(from response: AgentResponse) throws -> AgentBatchResult {
        switch response {
        case .batch(let result):
            result
        case .failure(let error):
            throw error
        case .committedMutation(let outcome):
            throw CLICommittedMutationError(outcome: outcome)
        default:
            throw unexpectedResponse("Batch request returned an unexpected response.")
        }
    }

    private static func domainResult(from response: AgentResponse) throws -> DomainExecutionResult {
        switch response {
        case .domainExecution(let result):
            result
        case .failure(let error):
            throw error
        case .committedMutation(let outcome):
            throw CLICommittedMutationError(outcome: outcome)
        default:
            throw unexpectedResponse("Domain request returned an unexpected response.")
        }
    }

    private static func unexpectedResponse(_ message: String) -> EditorError {
        EditorError(code: .commandFailed, message: message)
    }

    private func invalidCommand(_ message: String) -> EditorError {
        EditorError(code: .commandInvalid, message: message)
    }

    private func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
