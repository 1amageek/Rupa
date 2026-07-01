import Foundation
import RupaAutomation
import RupaCore

enum CLIAutomationCommandRunner {
    static func run(
        document: CLIWriteDocumentOptions,
        command: AutomationCommand
    ) throws {
        let sessionID = try document.resolvedSessionID()
        try run(
            document: document,
            sessionID: sessionID,
            command: command
        )
    }

    static func run(
        document: CLIWriteDocumentOptions,
        command: (UUID?) throws -> AutomationCommand
    ) throws {
        let sessionID = try document.resolvedSessionID()
        let resolvedCommand = try command(sessionID)
        try run(
            document: document,
            sessionID: sessionID,
            command: resolvedCommand
        )
    }

    private static func run(
        document: CLIWriteDocumentOptions,
        sessionID: UUID?,
        command: AutomationCommand
    ) throws {
        try CLIExitCode.run {
            let response = try CLIService().applyAutomationCommand(
                target: document.target(sessionID: sessionID),
                command: command,
                mode: document.mode,
                expectedGeneration: document.generation(),
                dryRun: document.dryRun,
                forceFileEdit: document.forceFileEdit,
                client: document.agentClient(sessionID: sessionID)
            )
            try CLIOutput.write(response: response, asJSON: document.json)
        }
    }

    static func lengthUnit(
        unitName: String?,
        document: CLIWriteDocumentOptions,
        sessionID: UUID?
    ) throws -> LengthDisplayUnit {
        try CLILengthUnitResolver.resolve(
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
