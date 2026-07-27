import Foundation
import Testing
import RupaCore
@testable import RupaAgent

@Test func agentMessageCodecRoundTripsDocumentLifecycleAndHistoryRequests() throws {
    let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let requests: [AgentRequest] = [
        .createDocument(name: "Created", outputPath: "/tmp/Created.rupa"),
        .openDocument(path: "/tmp/Created.rupa"),
        .closeDocument(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2),
            discardUnsavedChanges: false
        ),
        .resetDocument(
            sessionID: sessionID,
            name: "Reset",
            expectedGeneration: DocumentGeneration(2)
        ),
        .undo(sessionID: sessionID, expectedGeneration: DocumentGeneration(3)),
        .redo(sessionID: sessionID, expectedGeneration: DocumentGeneration(4)),
    ]
    let codec = AgentMessageCodec()

    for request in requests {
        let encoded = try codec.encode(request, id: request.methodName)
        let envelope = try codec.decodeRequestEnvelope(from: encoded)
        #expect(envelope.method == request.methodName)
        #expect(envelope.params == request)
    }
}

@Test func agentMessageCodecRoundTripsSessionOperationResponsesByMethod() throws {
    let summary = WorkspaceSessionSummary(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        path: "/tmp/Created.rupa",
        displayName: "Created",
        dirty: true,
        generation: DocumentGeneration(3),
        workspaceRevision: WorkspaceRevision(0)
    )
    let operations: [AgentSessionOperationResult.Operation] = [
        .create,
        .open,
        .close,
        .reset,
        .undo,
        .redo,
    ]
    let codec = AgentMessageCodec()

    for operation in operations {
        let response = AgentResponse.sessionOperation(
            AgentSessionOperationResult(
                operation: operation,
                session: summary,
                commandName: operation == .undo ? "undo.renameDocument" : nil,
                canUndo: true,
                canRedo: false
            )
        )
        let encoded = try codec.encode(response, id: operation.rawValue)
        let envelope = try codec.decodeResponseEnvelope(from: encoded)
        #expect(envelope.result == response)
        #expect(try envelope.decodedResponse() == response)
    }
}

@Test func sessionOperationResponseRejectsMismatchedMethod() throws {
    let response = AgentResponse.sessionOperation(
        AgentSessionOperationResult(
            operation: .undo,
            session: WorkspaceSessionSummary(
                id: UUID(),
                path: nil,
                displayName: "Untitled",
                dirty: true,
                generation: DocumentGeneration(1),
                workspaceRevision: WorkspaceRevision(0)
            ),
            canUndo: false,
            canRedo: true
        )
    )

    #expect(throws: EditorError.self) {
        try AgentMessageCodec().encode(
            response,
            id: "mismatch",
            method: "history.redo"
        )
    }
}
