import Foundation
import RupaCore
import RupaCoreTypes

public struct ProjectSourceTransaction: Sendable {
    public let name: String
    /// CAD editor commands run in array order before any geometry-source command.
    public let commands: [EditorCommand]
    /// Geometry-source commands run in array order after all CAD editor commands.
    public let geometrySourceCommands: [GeometrySourceCommand]
    public let expectedTransactionRevision: DocumentTransactionRevision

    public init(
        name: String,
        commands: [EditorCommand] = [],
        geometrySourceCommands: [GeometrySourceCommand] = [],
        expectedTransactionRevision: DocumentTransactionRevision
    ) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "Project source transaction names must not be empty."
            )
        }
        guard (!commands.isEmpty || !geometrySourceCommands.isEmpty),
              commands.allSatisfy(\.mutatesDocument) else {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "Project source transactions require source-mutating commands."
            )
        }
        self.name = name
        self.commands = commands
        self.geometrySourceCommands = geometrySourceCommands
        self.expectedTransactionRevision = expectedTransactionRevision
    }
}
