/// Accepted ceilings enforced before and during prepared execution.
public struct PreparedAutomationLimitPolicy: Sendable, Equatable, Hashable {
    public let maximumStepCount: Int
    public let maximumInputSlotCount: Int
    public let maximumOutputSlotCount: Int
    public let maximumCommandCount: Int
    public let maximumGeneratedSourceWork: UInt64

    public init(
        maximumStepCount: Int,
        maximumInputSlotCount: Int,
        maximumOutputSlotCount: Int,
        maximumCommandCount: Int,
        maximumGeneratedSourceWork: UInt64
    ) {
        self.maximumStepCount = maximumStepCount
        self.maximumInputSlotCount = maximumInputSlotCount
        self.maximumOutputSlotCount = maximumOutputSlotCount
        self.maximumCommandCount = maximumCommandCount
        self.maximumGeneratedSourceWork = maximumGeneratedSourceWork
    }
}
