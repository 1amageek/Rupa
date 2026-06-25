import ArgumentParser
import RupaAutomation
import RupaCore

enum CLIAutomationCommandRunner {
    static func run(
        document: CLIWriteDocumentOptions,
        command: AutomationCommand
    ) throws {
        let sessionID = try document.resolvedSessionID()

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

    static func lengthExpression(
        value: Double,
        unitName: String,
        valueName: String
    ) throws -> CADExpression {
        guard let unit = LengthDisplayUnit(rawValue: unitName) else {
            throw ValidationError("\(valueName) unit must be a supported Rupa display unit.")
        }
        return try CLIExpressionParser.length(value: value, unit: unit, valueName: valueName)
    }
}
