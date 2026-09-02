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
            )))
        ]
    )
    let opener = StubProjectAccessOpener(session: session)
    let observer = await makeStubProjectAccessObserver()
    let command = try ListParameterCommand.parse([
        projectURL.path,
        "--expected-generation", String(generation.value),
        "--json",
    ])

    try await withStubProjectAccess(opener: opener, observer: observer) {
        try await command.run()
    }

    #expect(await opener.recordedTargets() == [.liveProject(projectURL)])
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
func explicitSaveCommandParsesAndUsesSessionSaveAPI() async throws {
    let projectURL = URL(fileURLWithPath: "/tmp/command-save.rupa")
    let generation = DocumentGeneration(9)
    let session = StubProjectAccessSession(steps: [])
    let opener = StubProjectAccessOpener(session: session)
    let observer = await makeStubProjectAccessObserver()
    let command = try SaveDocument.parse([
        projectURL.path,
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
            .response(.documentDescription(stubAutomationResult(
                message: "Described.",
                effect: .readOnly,
                generation: generation,
                sourceDirty: true,
                didMutate: false
            )))
        ]
    )
    let opener = StubProjectAccessOpener(session: session)
    let observer = await makeStubProjectAccessObserver()
    let command = try ExportDocument.parse([
        projectURL.path,
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
    guard case .describeDocument(_, let describedGeneration) = requests[1] else {
        Issue.record("The export command must read the resulting project state through the same session.")
        return
    }
    #expect(describedGeneration == generation)
}

@Test(.timeLimit(.minutes(1)))
func removedRawCommandsAreNotRegistered() throws {
    for arguments in [
        ["batch"],
        ["command", "apply"],
        ["model"],
        ["sketch"],
        ["feature"],
        ["plane"],
        ["view"],
    ] {
        do {
            _ = try CLICommand.parseAsRoot(arguments)
            Issue.record("Removed raw command was still registered: \(arguments.joined(separator: " "))")
        } catch {
            // Rejection is part of the typed-only public syntax contract.
        }
    }
}
