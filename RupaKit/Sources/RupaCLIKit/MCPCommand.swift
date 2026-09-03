import ArgumentParser
import RupaMCP

public struct MCPCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Serve Rupa project tools over MCP stdio."
    )

    public init() {}

    public func run() async throws {
        try await RupaMCPServer(access: CLIRupaMCPAccess()).run()
    }
}
