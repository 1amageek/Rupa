import ArgumentParser

struct CADBenchmarkEvaluateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "evaluate",
        abstract: "Evaluate one candidate response from a bounded local file or standard input."
    )

    @Option(name: .customLong("response"), help: "Response JSON file path, or - for standard input.")
    var responsePath: String

    init() {}

    mutating func run() async throws {
        let execution = await CADBenchmarkCLIService().evaluate(responsePath: responsePath)
        do {
            try CADBenchmarkCLIOutput.write(execution.output)
        } catch {
            throw ExitCode(CADBenchmarkCLIExitCode.software.rawValue)
        }
        guard execution.exitCode != .success else {
            return
        }
        throw ExitCode(execution.exitCode.rawValue)
    }
}
