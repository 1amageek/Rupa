import Foundation
import RupaAutomation
import RupaCore
import RupaCoreTypes

public struct ProjectSourceTransaction: Sendable {
    private let storage: ProjectSourceTransactionStorage

    public var name: String {
        switch storage {
        case .commands(let name, _, _, _),
             .automation(let name, _, _, _),
             .preparedProgram(let name, _):
            name
        }
    }

    public var mutation: ProjectSourceMutation {
        switch storage {
        case .commands(_, let commands, _, _):
            .commands(commands)
        case .automation(_, let automation, _, _):
            .automation(automation)
        case .preparedProgram(_, let mutation):
            .preparedProgram(mutation)
        }
    }

    /// Geometry-source commands run in array order after all CAD editor commands.
    public var geometrySourceCommands: [GeometrySourceCommand] {
        switch storage {
        case .commands(_, _, let commands, _),
             .automation(_, _, let commands, _):
            commands
        case .preparedProgram:
            []
        }
    }

    public var expectedProjectID: ProjectID {
        switch storage {
        case .commands(_, _, _, let authority),
             .automation(_, _, _, let authority):
            authority.projectID
        case .preparedProgram(_, let mutation):
            mutation.authority.projectID
        }
    }

    public var expectedTransactionRevision: DocumentTransactionRevision {
        switch storage {
        case .commands(_, _, _, let authority),
             .automation(_, _, _, let authority):
            authority.transactionRevision
        case .preparedProgram(_, let mutation):
            mutation.authority.transactionRevision
        }
    }

    public var expectedPublicationSequence: UInt64 {
        switch storage {
        case .commands(_, _, _, let authority),
             .automation(_, _, _, let authority):
            authority.publicationSequence
        case .preparedProgram(_, let mutation):
            mutation.authority.publicationSequence
        }
    }

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
        self.storage = .commands(
            name: name,
            commands: resolvedCommands,
            geometrySourceCommands: geometrySourceCommands,
            authority: ProjectLegacySourceAuthority(
                projectID: expectedProjectID,
                transactionRevision: expectedTransactionRevision,
                publicationSequence: expectedPublicationSequence
            )
        )
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
        self.storage = .commands(
            name: name,
            commands: resolvedCommands,
            geometrySourceCommands: geometrySourceCommands,
            authority: ProjectLegacySourceAuthority(
                projectID: expectedProjectID,
                transactionRevision: expectedTransactionRevision,
                publicationSequence: expectedPublicationSequence
            )
        )
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
        self.storage = .automation(
            name: name,
            automation: automation,
            geometrySourceCommands: geometrySourceCommands,
            authority: ProjectLegacySourceAuthority(
                projectID: expectedProjectID,
                transactionRevision: expectedTransactionRevision,
                publicationSequence: expectedPublicationSequence
            )
        )
    }

    public init(
        name: String,
        preparedProgram: PreparedAutomationProgram,
        authority: ProjectAuthorityCoordinate,
        resultLimit: ProjectPreparedProgramResultLimit
    ) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "Project source transaction names must not be empty."
            )
        }
        guard !preparedProgram.steps.isEmpty else {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "Prepared source programs must contain at least one step."
            )
        }
        self.storage = .preparedProgram(
            name: name,
            mutation:
            ProjectPreparedProgramMutation(
                program: preparedProgram,
                authority: authority,
                resultLimit: resultLimit
            )
        )
    }

    public var commands: [EditorCommand] {
        guard case .commands(let commands) = mutation else {
            return []
        }
        return commands.map(\.command)
    }
}

private struct ProjectLegacySourceAuthority: Sendable {
    let projectID: ProjectID
    let transactionRevision: DocumentTransactionRevision
    let publicationSequence: UInt64
}

private enum ProjectSourceTransactionStorage: Sendable {
    case commands(
        name: String,
        commands: [ContextResolvedEditorCommand],
        geometrySourceCommands: [GeometrySourceCommand],
        authority: ProjectLegacySourceAuthority
    )
    case automation(
        name: String,
        automation: PreparedAutomationBatch,
        geometrySourceCommands: [GeometrySourceCommand],
        authority: ProjectLegacySourceAuthority
    )
    case preparedProgram(
        name: String,
        mutation: ProjectPreparedProgramMutation
    )
}
