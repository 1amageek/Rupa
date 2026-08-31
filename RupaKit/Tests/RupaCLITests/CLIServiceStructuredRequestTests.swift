import Foundation
import RupaAgentProtocol
import RupaAutomation
import RupaCore
import RupaCoreTypes
import RupaDomainFoundation
import RupaProjectAccess
import Testing
@testable import RupaCLIKit

@Test(.timeLimit(.minutes(1)))
func batchRequestUsesOneProjectAccessTransactionAndOneSave() async throws {
    let projectURL = URL(fileURLWithPath: "/tmp/batch.rupa")
    let batch = AutomationBatch(
        commands: [
            .renameDocument(name: "Batch Result"),
        ],
        expectedGeneration: DocumentGeneration(5)
    )
    let result = stubAutomationResult(
        message: "Renamed.",
        generation: DocumentGeneration(6)
    )
    let session = StubProjectAccessSession(
        steps: [
            .response(.batch(AgentBatchResult(
                results: [result],
                generation: result.generation,
                workspaceRevision: result.workspaceRevision,
                dirty: true,
                metrics: .empty
            ))),
        ]
    )
    let opener = StubProjectAccessOpener(session: session)
    let observer = await makeStubProjectAccessObserver()

    try await withStubProjectAccess(opener: opener, observer: observer) {
        let response = try await CLIService().runBatch(
            target: CLIDocumentTarget(fileURL: projectURL),
            batch: batch,
            mode: .file
        )
        #expect(response.saved)
        #expect(response.generation == 6)
        #expect(response.results == [result])
    }

    #expect(await opener.recordedTargets() == [
        .closedProject(input: projectURL, output: nil),
    ])
    #expect(await session.recordedSaveGenerations() == [DocumentGeneration(6)])
    let requests = await session.recordedRequests()
    #expect(requests.count == 1)
    guard case .executeBatch(_, let projectedBatch) = requests[0] else {
        Issue.record("Batch execution must be projected as one Agent batch request.")
        return
    }
    #expect(projectedBatch == batch)
}

@Test(.timeLimit(.minutes(1)))
func domainRequestPreservesTypedPayloadAndSavesOnlyItsCommittedGeneration() async throws {
    let projectURL = URL(fileURLWithPath: "/tmp/domain.rupa")
    let request = DomainCommandRequest(
        capabilityID: DomainCapabilityID(rawValue: "architecture.rename"),
        namespace: SemanticNamespaceID(rawValue: "architecture"),
        payload: .object(["name": .string("Domain Result")]),
        expectedGeneration: DocumentGeneration(2)
    )
    let result = DomainExecutionResult(
        capabilityID: request.capabilityID,
        namespace: request.namespace,
        message: "Domain command completed.",
        baseGeneration: DocumentGeneration(2),
        generation: DocumentGeneration(3),
        proposedGeneration: DocumentGeneration(3),
        didMutate: true,
        wouldMutate: true,
        dryRun: false,
        payload: request.payload
    )
    let session = StubProjectAccessSession(
        steps: [.response(.domainExecution(result))]
    )
    let opener = StubProjectAccessOpener(session: session)
    let observer = await makeStubProjectAccessObserver()

    try await withStubProjectAccess(opener: opener, observer: observer) {
        let response = try await CLIService().executeDomain(
            target: CLIDocumentTarget(fileURL: projectURL),
            request: request,
            mode: .file
        )
        #expect(response.saved)
        #expect(response.capabilityID == request.capabilityID)
        #expect(response.payload == request.payload)
    }

    #expect(await session.recordedSaveGenerations() == [DocumentGeneration(3)])
    let requests = await session.recordedRequests()
    #expect(requests.count == 1)
    guard case .executeDomain(_, let projectedRequest) = requests[0] else {
        Issue.record("Domain execution must remain a typed Agent domain request.")
        return
    }
    #expect(projectedRequest == request)
}

@Test(.timeLimit(.minutes(1)))
func exportRequestUsesProjectAccessAndNeverInvokesProjectSave() async throws {
    let projectURL = URL(fileURLWithPath: "/tmp/export.rupa")
    let outputURL = URL(fileURLWithPath: "/tmp/export.stl")
    let generation = DocumentGeneration(4)
    let options = ExportOptions(
        presetName: "Mesh",
        destinationPolicy: .overwrite
    )
    let session = StubProjectAccessSession(
        steps: [
            .response(.export(ExportResult(
                message: "Exported.",
                format: .stl,
                outputPath: outputURL.path,
                byteCount: 128,
                generation: generation,
                presetName: "Mesh",
                diagnostics: []
            ))),
            .response(.command(stubAutomationResult(
                message: "Described.",
                effect: .readOnly,
                generation: generation,
                sourceDirty: true,
                didMutate: false
            ))),
        ]
    )
    let opener = StubProjectAccessOpener(session: session)
    let observer = await makeStubProjectAccessObserver()

    try await withStubProjectAccess(opener: opener, observer: observer) {
        let response = try await CLIService().exportDocument(
            target: CLIDocumentTarget(fileURL: projectURL),
            outputURL: outputURL,
            mode: .live,
            expectedGeneration: generation,
            options: options
        )
        #expect(response.outputPath == outputURL.path)
        #expect(response.byteCount == 128)
        #expect(response.dirty)
    }

    #expect(await opener.recordedTargets() == [.liveProject(projectURL)])
    #expect(await session.recordedSaveGenerations().isEmpty)
    let requests = await session.recordedRequests()
    #expect(requests.count == 2)
    guard case .export(_, let path, let expected, let projectedOptions, false) = requests[0] else {
        Issue.record("Export must be projected as one Agent export request.")
        return
    }
    #expect(path == outputURL.path)
    #expect(expected == generation)
    #expect(projectedOptions == options)
    guard case .execute(_, .describeDocument, generation, _) = requests[1] else {
        Issue.record("Export response must read the resulting project state through the same session.")
        return
    }
    #expect(generation == DocumentGeneration(4))
}
