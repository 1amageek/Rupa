import ArgumentParser
import Foundation
import RupaAgentProtocol
import RupaAutomation
import RupaCore
import RupaCoreTypes
import RupaProjectAccess
import Testing
@testable import RupaCLIKit

@Test(.timeLimit(.minutes(1)))
func lineCommandParsesImplicitUnitAndRunsThroughOneOutputAuthority() async throws {
    let inputURL = URL(fileURLWithPath: "/tmp/line-input.rupa")
    let outputURL = URL(fileURLWithPath: "/tmp/line-output.rupa")
    let session = StubProjectAccessSession(
        steps: [
            .response(.command(stubAutomationResult(
                message: "Described.",
                effect: .readOnly,
                generation: DocumentGeneration(3),
                sourceDirty: false,
                didMutate: false,
                workspaceScale: stubWorkspaceScale(displayUnit: .millimeter)
            ))),
            .response(.command(stubAutomationResult(
                message: "Line created.",
                generation: DocumentGeneration(4)
            ))),
        ]
    )
    let opener = StubProjectAccessOpener(session: session)
    let observer = await makeStubProjectAccessObserver()
    let command = try LineSketchCommand.parse([
        inputURL.path,
        "--mode", "file",
        "--expected-generation", "3",
        "--output", outputURL.path,
        "--name", "API Line",
        "--start-x", "1",
        "--start-y", "2",
        "--end-x", "3",
        "--end-y", "4",
        "--json",
    ])

    try await withStubProjectAccess(opener: opener, observer: observer) {
        try await command.run()
    }

    #expect(await opener.recordedTargets() == [
        .closedProject(input: inputURL, output: outputURL),
    ])
    #expect(await session.recordedSaveGenerations() == [DocumentGeneration(4)])
    #expect(await session.recordedFinishCount() == 1)
    let requests = await session.recordedRequests()
    #expect(requests.count == 2)
    guard case .execute(_, .describeDocument, let describedGeneration, _) = requests[0] else {
        Issue.record("The line command must resolve its implicit unit from the project state.")
        return
    }
    #expect(describedGeneration == DocumentGeneration(3))
    guard case .execute(_, let projectedCommand, let mutationGeneration, _) = requests[1] else {
        Issue.record("The line command must emit one source mutation request.")
        return
    }
    #expect(mutationGeneration == DocumentGeneration(3))
    #expect(projectedCommand == .createLineSketch(
        name: "API Line",
        plane: nil,
        start: SketchPoint(
            x: .constant(.length(1, unit: .millimeter)),
            y: .constant(.length(2, unit: .millimeter))
        ),
        end: SketchPoint(
            x: .constant(.length(3, unit: .millimeter)),
            y: .constant(.length(4, unit: .millimeter))
        )
    ))
}

@Test(.timeLimit(.minutes(1)))
func parameterListCommandParsesAndProjectsOneReadRequest() async throws {
    let projectURL = URL(fileURLWithPath: "/tmp/read.rupa")
    let generation = DocumentGeneration(7)
    let session = StubProjectAccessSession(
        steps: [
            .response(.parameters(ParameterListResult(
                message: "0 parameters.",
                generation: generation,
                dirty: false,
                parameters: [],
                diagnostics: []
            ))),
        ]
    )
    let opener = StubProjectAccessOpener(session: session)
    let observer = await makeStubProjectAccessObserver()
    let command = try ListParameterCommand.parse([
        projectURL.path,
        "--mode", "file",
        "--expected-generation", String(generation.value),
        "--json",
    ])

    try await withStubProjectAccess(opener: opener, observer: observer) {
        try await command.run()
    }

    #expect(await opener.recordedTargets() == [
        .closedProject(input: projectURL, output: nil),
    ])
    #expect(await session.recordedSaveGenerations().isEmpty)
    let requests = await session.recordedRequests()
    #expect(requests.count == 1)
    guard case .parameters(_, let expectedGeneration) = requests[0] else {
        Issue.record("The parameter list command must emit a read request.")
        return
    }
    #expect(expectedGeneration == generation)
}

@Test(.timeLimit(.minutes(1)))
func displayUnitCommandParsesAndProjectsOneWorkspaceMutation() async throws {
    let projectURL = URL(fileURLWithPath: "/tmp/workspace.rupa")
    let generation = DocumentGeneration(3)
    let workspaceRevision = WorkspaceRevision(4)
    let session = StubProjectAccessSession(
        steps: [
            .response(.command(stubAutomationResult(
                message: "Display unit updated.",
                effect: .workspaceMutation,
                generation: generation,
                sourceDirty: false,
                workspaceRevision: WorkspaceRevision(5),
                workspaceScale: stubWorkspaceScale(displayUnit: .centimeter)
            ))),
        ]
    )
    let opener = StubProjectAccessOpener(session: session)
    let observer = await makeStubProjectAccessObserver()
    let command = try SetDisplayUnitCommand.parse([
        projectURL.path,
        "centimeter",
        "--mode", "live",
        "--expected-generation", String(generation.value),
        "--expected-workspace-revision", String(workspaceRevision.value),
        "--json",
    ])

    try await withStubProjectAccess(opener: opener, observer: observer) {
        try await command.run()
    }

    #expect(await opener.recordedTargets() == [.liveProject(projectURL)])
    #expect(await session.recordedSaveGenerations().isEmpty)
    let requests = await session.recordedRequests()
    #expect(requests.count == 1)
    guard case .execute(
        _,
        .setDisplayUnit(.centimeter),
        let expectedGeneration,
        let expectedWorkspaceRevision
    ) = requests[0] else {
        Issue.record("The display unit command must emit one workspace mutation.")
        return
    }
    #expect(expectedGeneration == generation)
    #expect(expectedWorkspaceRevision == workspaceRevision)
}

@Test(.timeLimit(.minutes(1)))
func batchCommandParsesJSONAndRunsOneAtomicFileRequest() async throws {
    let projectURL = URL(fileURLWithPath: "/tmp/command-batch.rupa")
    let fixtureDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("rupa-cli-batch-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: fixtureDirectory,
        withIntermediateDirectories: true
    )
    defer {
        do {
            try FileManager.default.removeItem(at: fixtureDirectory)
        } catch {
            Issue.record("Failed to remove CLI batch fixture: \(error)")
        }
    }
    let batchURL = fixtureDirectory.appendingPathComponent("batch.json")
    let batch = AutomationBatch(
        commands: [.renameDocument(name: "Batch")],
        expectedGeneration: DocumentGeneration(5)
    )
    try JSONEncoder().encode(batch).write(to: batchURL)

    let result = stubAutomationResult(
        message: "Batch complete.",
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
    let command = try BatchCommand.parse([
        projectURL.path,
        "--mode", "file",
        "--input", batchURL.path,
        "--json",
    ])

    try await withStubProjectAccess(opener: opener, observer: observer) {
        try await command.run()
    }

    #expect(await session.recordedSaveGenerations() == [DocumentGeneration(6)])
    let requests = await session.recordedRequests()
    #expect(requests.count == 1)
    guard case .executeBatch(_, let projectedBatch) = requests[0] else {
        Issue.record("The batch command must emit one atomic batch request.")
        return
    }
    #expect(projectedBatch == batch)
}

@Test(.timeLimit(.minutes(1)))
func explicitSaveCommandParsesAndUsesSessionSaveAPI() async throws {
    let projectURL = URL(fileURLWithPath: "/tmp/command-save.rupa")
    let generation = DocumentGeneration(9)
    let session = StubProjectAccessSession(steps: [])
    let opener = StubProjectAccessOpener(session: session)
    let observer = await makeStubProjectAccessObserver()
    let command = try SaveDocument.parse([
        projectURL.path,
        "--mode", "live",
        "--expected-generation", String(generation.value),
        "--json",
    ])

    try await withStubProjectAccess(opener: opener, observer: observer) {
        try await command.run()
    }

    #expect(await opener.recordedTargets() == [.liveProject(projectURL)])
    #expect(await session.recordedRequests().isEmpty)
    #expect(await session.recordedSaveGenerations() == [generation])
    #expect(await session.recordedFinishCount() == 1)
}

@Test(.timeLimit(.minutes(1)))
func exportCommandParsesAndProjectsExportWithoutProjectSave() async throws {
    let projectURL = URL(fileURLWithPath: "/tmp/command-export.rupa")
    let outputURL = URL(fileURLWithPath: "/tmp/command-export.stl")
    let generation = DocumentGeneration(4)
    let session = StubProjectAccessSession(
        steps: [
            .response(.export(ExportResult(
                message: "Exported.",
                format: .stl,
                outputPath: outputURL.path,
                byteCount: 256,
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
    let command = try ExportDocument.parse([
        projectURL.path,
        "--mode", "live",
        "--expected-generation", String(generation.value),
        "--output", outputURL.path,
        "--preset", "Mesh",
        "--destination-policy", "overwrite",
        "--json",
    ])

    try await withStubProjectAccess(opener: opener, observer: observer) {
        try await command.run()
    }

    #expect(await opener.recordedTargets() == [.liveProject(projectURL)])
    #expect(await session.recordedSaveGenerations().isEmpty)
    let requests = await session.recordedRequests()
    #expect(requests.count == 2)
    guard case .export(_, let outputPath, let expectedGeneration, let options, false) = requests[0] else {
        Issue.record("The export command must emit one export request.")
        return
    }
    #expect(outputPath == outputURL.path)
    #expect(expectedGeneration == generation)
    #expect(options.presetName == "Mesh")
    #expect(options.destinationPolicy == .overwrite)
}
