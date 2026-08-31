import ArgumentParser
import Foundation
import RupaAutomation

public struct BatchCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "batch",
        abstract: """
        Apply an AutomationBatch JSON file to a live document. Batch \
        execution dispatches one app-session transaction that rolls \
        back document, selection, and undo history on failure.
        """
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Path to a JSON file containing an AutomationBatch object.")
    public var input: String

    public init() {}

    public func run() async throws {
        let sessionID = try document.resolvedSessionID()
        let batch = try decodedBatch()

        try await CLIExitCode.run {
            let response = try await CLIService().runBatch(
                target: document.target(sessionID: sessionID),
                batch: batch
            )
            try CLIOutput.write(response: response, asJSON: document.json)
        }
    }

    private func decodedBatch() throws -> AutomationBatch {
        let data = try Data(contentsOf: URL(fileURLWithPath: input))
        let decoded: AutomationBatch
        do {
            decoded = try JSONDecoder().decode(AutomationBatch.self, from: data)
        } catch {
            throw ValidationError("AutomationBatch JSON is invalid: \(error.localizedDescription)")
        }
        guard !decoded.commands.isEmpty else {
            throw ValidationError("AutomationBatch must contain at least one command.")
        }
        // The CLI --expected-generation flag overrides the batch file's own
        // value when provided; otherwise the file's value is used as-is.
        return AutomationBatch(
            commands: decoded.commands,
            expectedGeneration: document.generation() ?? decoded.expectedGeneration,
            expectedWorkspaceRevision: document.workspaceRevision()
                ?? decoded.expectedWorkspaceRevision
        )
    }
}
