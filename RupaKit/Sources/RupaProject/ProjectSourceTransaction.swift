import Foundation
import RupaAutomation
import RupaCore
import RupaCoreTypes

public struct ProjectSourceTransaction: Sendable {
    public let name: String
    public let mutation: ProjectSourceMutation
    /// Geometry-source commands run in array order after all CAD editor commands.
    public let geometrySourceCommands: [GeometrySourceCommand]
    public let expectedProjectID: ProjectID
    public let expectedTransactionRevision: DocumentTransactionRevision
    public let expectedPublicationSequence: UInt64

    public init(
        name: String,
        commands: [EditorCommand] = [],
        geometrySourceCommands: [GeometrySourceCommand] = [],
        expectedProjectID: ProjectID,
        expectedTransactionRevision: DocumentTransactionRevision,
        expectedPublicationSequence: UInt64
    ) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "Project source transaction names must not be empty."
            )
        }
        let resolvedCommands: [ContextResolvedEditorCommand]
        do {
            resolvedCommands = try commands.map { command in
                try ContextResolvedEditorCommand(validating: command)
            }
        } catch let error as EditorError {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: error.message
            )
        }
        guard (!resolvedCommands.isEmpty || !geometrySourceCommands.isEmpty),
              resolvedCommands.allSatisfy({ $0.command.mutatesDocument }) else {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "Project source transactions require source-mutating commands."
            )
        }
        self.name = name
        self.mutation = .commands(resolvedCommands)
        self.geometrySourceCommands = geometrySourceCommands
        self.expectedProjectID = expectedProjectID
        self.expectedTransactionRevision = expectedTransactionRevision
        self.expectedPublicationSequence = expectedPublicationSequence
    }

    public init(
        name: String,
        resolvedCommands: [ContextResolvedEditorCommand],
        geometrySourceCommands: [GeometrySourceCommand] = [],
        expectedProjectID: ProjectID,
        expectedTransactionRevision: DocumentTransactionRevision,
        expectedPublicationSequence: UInt64
    ) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "Project source transaction names must not be empty."
            )
        }
        guard (!resolvedCommands.isEmpty || !geometrySourceCommands.isEmpty),
              resolvedCommands.allSatisfy({ $0.command.mutatesDocument }) else {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "Project source transactions require source-mutating commands."
            )
        }
        self.name = name
        self.mutation = .commands(resolvedCommands)
        self.geometrySourceCommands = geometrySourceCommands
        self.expectedProjectID = expectedProjectID
        self.expectedTransactionRevision = expectedTransactionRevision
        self.expectedPublicationSequence = expectedPublicationSequence
    }

    public init(
        name: String,
        automation: PreparedAutomationBatch,
        geometrySourceCommands: [GeometrySourceCommand] = [],
        expectedProjectID: ProjectID,
        expectedTransactionRevision: DocumentTransactionRevision,
        expectedPublicationSequence: UInt64
    ) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "Project source transaction names must not be empty."
            )
        }
        guard automation.effect == .sourceMutation else {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "Project source Automation transactions require a source-mutation batch."
            )
        }
        self.name = name
        self.mutation = .automation(automation)
        self.geometrySourceCommands = geometrySourceCommands
        self.expectedProjectID = expectedProjectID
        self.expectedTransactionRevision = expectedTransactionRevision
        self.expectedPublicationSequence = expectedPublicationSequence
    }

    public var commands: [EditorCommand] {
        guard case .commands(let commands) = mutation else {
            return []
        }
        return commands.map(\.command)
    }
}
