import Foundation
import RupaAutomation
import RupaCore

enum CLIAutomationCommandRunner {
    static func run(
        document: CLIWriteDocumentOptions,
        command: AutomationCommand
    ) async throws {
        try await run(document: document) { _ in command }
    }

    static func run(
        document: CLIWriteDocumentOptions,
        command: (UUID?) async throws -> AutomationCommand
    ) async throws {
        let sessionID = try document.resolvedSessionID()
        try await CLIExitCode.run {
            let resolvedCommand = try await command(sessionID)
            let response = try await response(
                document: document,
                sessionID: sessionID,
                command: resolvedCommand
            )
            try CLIOutput.write(response: response, asJSON: document.json)
        }
    }

    static func response(
        document: CLIWriteDocumentOptions,
        command: AutomationCommand
    ) async throws -> CLIResponse {
        let sessionID = try document.resolvedSessionID()
        return try await response(
            document: document,
            sessionID: sessionID,
            command: command
        )
    }

    private static func response(
        document: CLIWriteDocumentOptions,
        sessionID: UUID?,
        command: AutomationCommand
    ) async throws -> CLIResponse {
        try await CLIService().applyAutomationCommand(
            target: document.target(sessionID: sessionID),
            command: command,
            expectedGeneration: document.generation(),
            expectedWorkspaceRevision: document.workspaceRevision()
        )
    }

    static func lengthUnit(
        unitName: String?,
        document: CLIWriteDocumentOptions,
        sessionID: UUID?
    ) async throws -> LengthDisplayUnit {
        try await CLILengthUnitResolver.resolve(
            unitName: unitName,
            document: document,
            sessionID: sessionID
        )
    }

    static func lengthExpression(
        value: Double,
        unit: LengthDisplayUnit,
        valueName: String
    ) throws -> CADExpression {
        try CLIExpressionParser.length(
            value: value,
            unit: unit,
            valueName: valueName
        )
    }

}
