import Foundation

/// A batch whose effect and initial state coordinates were validated together.
public struct PreparedAutomationBatch: Sendable {
    public let batch: AutomationBatch
    public let effect: AutomationCommandEffect

    init(
        batch: AutomationBatch,
        effect: AutomationCommandEffect
    ) {
        self.batch = batch
        self.effect = effect
    }
}
