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
        let writePolicy = try document.writePolicy(sessionID: sessionID)
        return try await resolve(
            unitName: unitName,
            target: try document.target(sessionID: sessionID),
            mode: document.mode,
            expectedGeneration: document.generation(),
            outputURL: writePolicy.outputURL
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
        mode: CLIEditMode,
        expectedGeneration: DocumentGeneration?,
        outputURL: URL?
    ) async throws -> LengthDisplayUnit {
        if let unitName {
            guard let unit = LengthDisplayUnit(rawValue: unitName) else {
                throw ValidationError("Length unit must be a supported Rupa display unit.")
            }
            return unit
        }

        return try await CLIService().workspaceScale(
            target: target,
            mode: mode,
            expectedGeneration: expectedGeneration,
            outputURL: outputURL
        ).displayUnit
    }
}
