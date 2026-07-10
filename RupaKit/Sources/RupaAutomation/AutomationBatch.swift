import Foundation
import RupaCore

public struct AutomationBatch: Codable, Equatable, Sendable {
    public var commands: [AutomationCommand]
    public var expectedGeneration: DocumentGeneration?
    public var expectedWorkspaceRevision: WorkspaceRevision?

    public init(
        commands: [AutomationCommand],
        expectedGeneration: DocumentGeneration? = nil,
        expectedWorkspaceRevision: WorkspaceRevision? = nil
    ) {
        self.commands = commands
        self.expectedGeneration = expectedGeneration
        self.expectedWorkspaceRevision = expectedWorkspaceRevision
    }

    public func validatedEffect() throws -> AutomationCommandEffect {
        var mutationEffect: AutomationCommandEffect?
        var mutationIndex: Int?
        for (index, command) in commands.enumerated() {
            let commandEffect = command.effect
            guard commandEffect != .readOnly else {
                continue
            }
            guard let establishedEffect = mutationEffect else {
                mutationEffect = commandEffect
                mutationIndex = index
                continue
            }
            guard establishedEffect == commandEffect else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Automation batches cannot mix \(establishedEffect.rawValue) at index \(mutationIndex ?? 0) with \(commandEffect.rawValue) at index \(index)."
                )
            }
        }
        return mutationEffect ?? .readOnly
    }
}
