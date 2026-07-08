import ArgumentParser
import Foundation
import RupaAutomation

public struct BatchCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "batch",
        abstract: """
        Apply an AutomationBatch JSON file to a file or live document. Batch \
        execution is atomic: file mode saves only after every command succeeds, \
        and live/auto mode dispatches one app-session transaction that rolls \
        back document, selection, and undo history on failure.
        """
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Path to a JSON file containing an AutomationBatch object.")
    public var input: String

    public init() {}

    public func run() throws {
        let sessionID = try document.resolvedSessionID()
        try validateDryRunTarget(sessionID: sessionID)
        let batch = try decodedBatch()

        try CLIExitCode.run {
            let response = try CLIService().runBatch(
                target: try document.target(sessionID: sessionID),
                batch: batch,
                mode: document.mode,
                dryRun: document.dryRun,
                writePolicy: try document.writePolicy(sessionID: sessionID),
                forceFileEdit: document.forceFileEdit,
                client: document.agentClient(sessionID: sessionID)
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
            expectedGeneration: document.generation() ?? decoded.expectedGeneration
        )
    }

    private func validateDryRunTarget(sessionID: UUID?) throws {
        guard document.dryRun,
              (document.mode == .live || sessionID != nil) else {
            return
        }
        throw ValidationError("Dry-run is not supported for live document mutation.")
    }
}
