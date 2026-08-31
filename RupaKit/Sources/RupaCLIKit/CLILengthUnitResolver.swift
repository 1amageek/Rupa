import ArgumentParser
import Foundation
import RupaAgentProtocol
import RupaCore

enum CLILengthUnitResolver {
    static func resolve(
        unitName: String?,
        document: CLIWriteDocumentOptions,
        sessionID: UUID?
    ) async throws -> LengthDisplayUnit {
        return try await resolve(
            unitName: unitName,
            target: document.target(sessionID: sessionID),
            expectedGeneration: document.generation()
        )
    }

    static func resolve(
        unit: LengthDisplayUnit?,
        document: CLIWriteDocumentOptions,
        sessionID: UUID?
    ) async throws -> LengthDisplayUnit {
        guard let unit else {
            return try await resolve(
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
        expectedGeneration: DocumentGeneration?
    ) async throws -> LengthDisplayUnit {
        if let unitName {
            guard let unit = LengthDisplayUnit(rawValue: unitName) else {
                throw ValidationError("Length unit must be a supported Rupa display unit.")
            }
            return unit
        }

        return try await CLIService().workspaceScale(
            target: target,
            expectedGeneration: expectedGeneration
        ).displayUnit
    }
}
