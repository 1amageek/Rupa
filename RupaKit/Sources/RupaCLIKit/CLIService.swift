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
public struct CLIService {
    public init() {}

    @MainActor
    public func capabilityDescriptors() async throws -> [AgentCapabilityDescriptor] {
        try await CLIProjectAccessRunner.capabilities()
    }

    @MainActor
    public func capabilities() async throws -> [String] {
        try await capabilityDescriptors().map(\.name)
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

    public func executeTypedMutationRequest(
        target: CLIDocumentTarget,
        request: @escaping (UUID) -> AgentRequest
    ) async throws -> CLIResponse {
        try await CLIProjectAccessRunner.withSession(target: target) { session in
            let result = try Self.typedMutationResult(
                from: try await session.send(request(session.sessionID))
            )
            return CLIResponse(result: result, dirty: result.sourceDirty, saved: false)
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
            .describeDocument(
                sessionID: session.sessionID,
                expectedGeneration: expectedGeneration
            )
        )
        return try Self.documentDescriptionResult(from: response)
    }

    private static func documentDescriptionResult(from response: AgentResponse) throws -> AutomationResult {
        switch response {
        case .documentDescription(let result):
            result
        case .failure(let error):
            throw error
        case .committedMutation(let outcome):
            throw CLICommittedMutationError(outcome: outcome)
        default:
            throw unexpectedResponse("Document description returned an unexpected response.")
        }
    }

    private static func typedMutationResult(from response: AgentResponse) throws -> AutomationResult {
        switch response {
        case .parameterExpression(let result),
             .objectDimensionExpression(let result),
             .sketchEntityDimensionExpression(let result),
             .selectionDimensionTargetExpression(let result),
             .surfaceFrameDisplay(let result),
             .polySplineSurfaceVertex(let result):
            result
        case .failure(let error):
            throw error
        case .committedMutation(let outcome):
            throw CLICommittedMutationError(outcome: outcome)
        default:
            throw unexpectedResponse("Typed mutation request returned an unexpected response.")
        }
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
