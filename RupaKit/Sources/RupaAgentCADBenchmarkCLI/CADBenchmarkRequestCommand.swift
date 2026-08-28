import ArgumentParser

struct CADBenchmarkRequestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "request",
        abstract: "Emit the public context for one activated benchmark case."
    )

    @Argument(help: "Activated benchmark case ID.")
    var caseID: String

    init() {}

    mutating func run() async throws {
        let execution = await CADBenchmarkCLIService().request(rawCaseID: caseID)
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
