import Foundation
import RupaCore
import RupaCoreTypes

public struct ProjectSourceTransaction: Sendable {
    public let name: String
    public let commands: [EditorCommand]
    public let expectedTransactionRevision: DocumentTransactionRevision

    public init(
        name: String,
        commands: [EditorCommand],
        expectedTransactionRevision: DocumentTransactionRevision
    ) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "Project source transaction names must not be empty."
            )
        }
        guard !commands.isEmpty, commands.allSatisfy(\.mutatesDocument) else {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "Project source transactions require source-mutating editor commands."
            )
        }
        self.name = name
        self.commands = commands
        self.expectedTransactionRevision = expectedTransactionRevision
    }
}
