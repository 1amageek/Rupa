import Foundation
import RupaCore

public struct AutomationBatch: Codable, Equatable, Sendable {
    public var commands: [AutomationCommand]
    public var expectedGeneration: DocumentGeneration?

    public init(
        commands: [AutomationCommand],
        expectedGeneration: DocumentGeneration? = nil
    ) {
        self.commands = commands
        self.expectedGeneration = expectedGeneration
    }
}
