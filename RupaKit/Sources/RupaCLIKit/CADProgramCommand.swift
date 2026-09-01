import ArgumentParser
import Foundation
import RupaAgentProtocol

/// Sends one bounded structured semantic CAD program.
public struct CADProgramCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "program",
        abstract: "Execute one bounded structured semantic CAD program."
    )

    @Argument(help: "Path to the .rupa project.")
    public var file: String?

    @OptionGroup
    public var access: CADSemanticAccessOptions

    @Option(
        name: [.customLong("input"), .customLong("program")],
        help: "Bounded JSON program file or inline JSON value."
    )
    public var input: String?

    public init() {}

    public func run() async throws {
        try await CLIExitCode.run {
            let program = try buildProgram()
            let target = try access.target(file: file)
            let result = try await CLIService().executeProgram(
                target: target,
                program: program,
                dryRun: access.dryRun
            )
            try CLIOutput.write(response: result, asJSON: access.json)
        }
    }

    private func buildProgram() throws -> AgentSemanticProgramRequest {
        guard let input else {
            throw ValidationError("CAD program requires --input with one bounded JSON program document.")
        }
        return try CADSemanticInputReader.decode(
            AgentSemanticProgramRequest.self,
            source: input,
            label: "CAD program"
        )
    }
}
