import ArgumentParser

@main
struct CADBenchmarkCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rupa-agent-cad-benchmark",
        abstract: "Exchange one activated CAD benchmark case with an external Agent.",
        subcommands: [
            CADBenchmarkRequestCommand.self,
            CADBenchmarkEvaluateCommand.self,
        ]
    )

    init() {}

    mutating func run() async throws {
        throw ValidationError("A subcommand is required.")
    }
}
