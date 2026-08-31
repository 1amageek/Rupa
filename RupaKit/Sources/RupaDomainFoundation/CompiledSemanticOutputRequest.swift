import RupaAutomation

public struct CompiledSemanticOutputRequest: Sendable, Equatable {
    public let source: SemanticOutputReference
    public let preparedSlot: PreparedAutomationSlotID

    init(
        source: SemanticOutputReference,
        preparedSlot: PreparedAutomationSlotID
    ) {
        self.source = source
        self.preparedSlot = preparedSlot
    }
}
