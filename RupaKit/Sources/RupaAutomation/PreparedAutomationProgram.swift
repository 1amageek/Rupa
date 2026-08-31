/// An immutable, ordered source program prepared by an upstream compiler.
public struct PreparedAutomationProgram: Sendable {
    public let steps: [PreparedAutomationStep]
    public let limits: PreparedAutomationLimitPolicy
    public let estimatedInputSlotCount: Int
    public let estimatedOutputSlotCount: Int
    public let estimatedCommandCount: Int
    public let estimatedGeneratedSourceWork: UInt64

    public init(
        steps: [PreparedAutomationStep],
        limits: PreparedAutomationLimitPolicy
    ) throws {
        try Self.validateLimits(limits)

        var outputProducers: [PreparedAutomationSlotID: Int] = [:]
        var inputSlotCount = 0
        var outputSlotCount = 0
        var estimatedWork: UInt64 = 0

        for (stepIndex, step) in steps.enumerated() {
            guard step.estimatedGeneratedSourceWork > 0 || step.outputs.isEmpty else {
                throw PreparedAutomationPlanError.invalidStepWork(stepIndex: stepIndex)
            }

            var inputIDs: Set<PreparedAutomationSlotID> = []
            for input in step.inputs {
                guard !input.id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw PreparedAutomationPlanError.invalidSlotIdentifier(input.id)
                }
                guard inputIDs.insert(input.id).inserted else {
                    throw PreparedAutomationPlanError.duplicateInputSlot(
                        stepIndex: stepIndex,
                        slotID: input.id
                    )
                }
                inputSlotCount = try Self.adding(
                    inputSlotCount,
                    1,
                    error: .countOverflow
                )

                if case .existing(let identity) = input.reference,
                   identity.kind != input.expectedKind {
                    throw PreparedAutomationPlanError.inputKindMismatch(
                        stepIndex: stepIndex,
                        slotID: input.id,
                        expected: input.expectedKind,
                        actual: identity.kind
                    )
                }
            }

            var outputIDs: Set<PreparedAutomationSlotID> = []
            var outputSelectors: Set<PreparedAutomationOutputSelector> = []
            for output in step.outputs {
                guard !output.id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw PreparedAutomationPlanError.invalidSlotIdentifier(output.id)
                }
                guard outputIDs.insert(output.id).inserted else {
                    throw PreparedAutomationPlanError.duplicateOutputSlot(
                        stepIndex: stepIndex,
                        slotID: output.id
                    )
                }
                guard outputSelectors.insert(output.selector).inserted else {
                    throw PreparedAutomationPlanError.duplicateOutputSelector(
                        stepIndex: stepIndex,
                        selector: output.selector
                    )
                }
                guard output.selector.index >= 0 else {
                    throw PreparedAutomationPlanError.negativeOutputIndex(
                        stepIndex: stepIndex,
                        selector: output.selector
                    )
                }
                guard outputProducers[output.id] == nil else {
                    throw PreparedAutomationPlanError.duplicateOutputProducer(output.id)
                }
                outputProducers[output.id] = stepIndex
                outputSlotCount = try Self.adding(
                    outputSlotCount,
                    1,
                    error: .countOverflow
                )
            }

            estimatedWork = try Self.adding(
                estimatedWork,
                step.estimatedGeneratedSourceWork,
                error: .countOverflow
            )
        }

        for (stepIndex, step) in steps.enumerated() {
            for input in step.inputs {
                guard case .local(let outputID) = input.reference else {
                    continue
                }
                guard let producerStepIndex = outputProducers[outputID] else {
                    throw PreparedAutomationPlanError.missingLocalOutput(
                        stepIndex: stepIndex,
                        slotID: outputID
                    )
                }
                guard producerStepIndex < stepIndex else {
                    throw PreparedAutomationPlanError.forwardLocalReference(
                        stepIndex: stepIndex,
                        slotID: outputID,
                        producerStepIndex: producerStepIndex
                    )
                }
                let producer = steps[producerStepIndex].outputs.first {
                    $0.id == outputID
                }
                guard let producer,
                      producer.kind == input.expectedKind else {
                    throw PreparedAutomationPlanError.inputKindMismatch(
                        stepIndex: stepIndex,
                        slotID: input.id,
                        expected: input.expectedKind,
                        actual: producer?.kind ?? input.expectedKind
                    )
                }
            }
        }

        let commandCount = steps.count
        try Self.validateEstimate(
            metric: .steps,
            estimated: UInt64(commandCount),
            maximum: limits.maximumStepCount
        )
        try Self.validateEstimate(
            metric: .inputSlots,
            estimated: UInt64(inputSlotCount),
            maximum: limits.maximumInputSlotCount
        )
        try Self.validateEstimate(
            metric: .outputSlots,
            estimated: UInt64(outputSlotCount),
            maximum: limits.maximumOutputSlotCount
        )
        try Self.validateEstimate(
            metric: .commands,
            estimated: UInt64(commandCount),
            maximum: limits.maximumCommandCount
        )
        guard estimatedWork <= limits.maximumGeneratedSourceWork else {
            throw PreparedAutomationPlanError.estimateExceedsLimit(
                metric: .generatedSourceWork,
                estimated: estimatedWork,
                maximum: limits.maximumGeneratedSourceWork
            )
        }

        self.steps = steps
        self.limits = limits
        self.estimatedInputSlotCount = inputSlotCount
        self.estimatedOutputSlotCount = outputSlotCount
        self.estimatedCommandCount = commandCount
        self.estimatedGeneratedSourceWork = estimatedWork
    }

    private static func validateLimits(_ limits: PreparedAutomationLimitPolicy) throws {
        guard limits.maximumStepCount >= 0 else {
            throw PreparedAutomationPlanError.invalidLimit(.steps)
        }
        guard limits.maximumInputSlotCount >= 0 else {
            throw PreparedAutomationPlanError.invalidLimit(.inputSlots)
        }
        guard limits.maximumOutputSlotCount >= 0 else {
            throw PreparedAutomationPlanError.invalidLimit(.outputSlots)
        }
        guard limits.maximumCommandCount >= 0 else {
            throw PreparedAutomationPlanError.invalidLimit(.commands)
        }
    }

    private static func validateEstimate(
        metric: PreparedAutomationLimitMetric,
        estimated: UInt64,
        maximum: Int
    ) throws {
        guard estimated <= UInt64(maximum) else {
            throw PreparedAutomationPlanError.estimateExceedsLimit(
                metric: metric,
                estimated: estimated,
                maximum: UInt64(maximum)
            )
        }
    }

    private static func adding(
        _ lhs: Int,
        _ rhs: Int,
        error: PreparedAutomationPlanError
    ) throws -> Int {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else {
            throw error
        }
        return value
    }

    private static func adding(
        _ lhs: UInt64,
        _ rhs: UInt64,
        error: PreparedAutomationPlanError
    ) throws -> UInt64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else {
            throw error
        }
        return value
    }
}
