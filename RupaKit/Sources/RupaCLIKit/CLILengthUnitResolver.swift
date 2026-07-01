import ArgumentParser
import Foundation
import RupaAgentProtocol
import RupaCore

enum CLILengthUnitResolver {
    static func resolve(
        unitName: String?,
        document: CLIWriteDocumentOptions,
        sessionID: UUID?
    ) throws -> LengthDisplayUnit {
        try resolve(
            unitName: unitName,
            target: document.target(sessionID: sessionID),
            mode: document.mode,
            expectedGeneration: document.generation(),
            forceFileEdit: document.forceFileEdit,
            client: document.agentClient(sessionID: sessionID)
        )
    }

    static func resolve(
        unit: LengthDisplayUnit?,
        document: CLIWriteDocumentOptions,
        sessionID: UUID?
    ) throws -> LengthDisplayUnit {
        guard let unit else {
            return try resolve(
                unitName: nil,
                document: document,
                sessionID: sessionID
            )
        }
        return unit
    }

    static func resolve(
        unitName: String?,
        target: CLIDocumentTarget,
        mode: CLIEditMode,
        expectedGeneration: DocumentGeneration?,
        forceFileEdit: Bool,
        client: AgentClientProtocol?
    ) throws -> LengthDisplayUnit {
        if let unitName {
            guard let unit = LengthDisplayUnit(rawValue: unitName) else {
                throw ValidationError("Length unit must be a supported Rupa display unit.")
            }
            return unit
        }

        return try CLIService().workspaceScale(
            target: target,
            mode: mode,
            expectedGeneration: expectedGeneration,
            forceFileEdit: forceFileEdit,
            client: client
        ).displayUnit
    }
}
