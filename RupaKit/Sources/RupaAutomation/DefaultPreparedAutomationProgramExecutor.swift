import Foundation
import RupaCore

/// Executes prepared source steps without creating or publishing a transaction.
public struct DefaultPreparedAutomationProgramExecutor: PreparedAutomationProgramExecuting, Sendable {
    public init() {}

    public func execute(
        _ program: PreparedAutomationProgram,
        in stagedSession: EditorSession
    ) throws -> PreparedAutomationExecutionReceipt {
        guard stagedSession.hasActiveSourceCommandGroup else {
            throw PreparedAutomationExecutionError.inactiveSourceCommandGroup
        }

        var slotValues: [PreparedAutomationSlotID: PreparedAutomationIdentity] = [:]
        var stepReceipts: [PreparedAutomationStepReceipt] = []
        var outputBindings: [PreparedAutomationOutputBinding] = []
        var diagnostics: [EditorDiagnostic] = []
        var generatedIdentityCount = 0
        var generatedSourceWork: UInt64 = 0

        for (stepIndex, step) in program.steps.enumerated() {
            try checkCancellation()

            let inputs = try resolveInputs(
                step.inputs,
                stepIndex: stepIndex,
                slotValues: slotValues,
                in: stagedSession.document
            )
            let resolvedCommand: ContextResolvedEditorCommand
            do {
                resolvedCommand = try step.commandBuilder.build(from: inputs)
            } catch let error as PreparedAutomationExecutionError {
                throw error
            } catch let error as EditorError {
                throw PreparedAutomationExecutionError.commandBuildFailed(
                    stepIndex: stepIndex,
                    commandName: step.commandBuilder.name,
                    code: error.code,
                    message: error.message
                )
            } catch {
                throw PreparedAutomationExecutionError.commandBuildFailed(
                    stepIndex: stepIndex,
                    commandName: step.commandBuilder.name,
                    code: nil,
                    message: String(describing: error)
                )
            }

            guard PreparedAutomationSourceCommandValidation.isAcceptedSourceCommand(
                resolvedCommand.command
            ) else {
                throw PreparedAutomationExecutionError.sourceCommandRejected(
                    stepIndex: stepIndex,
                    commandName: resolvedCommand.command.name
                )
            }

            let result: CommandExecutionResult
            do {
                result = try stagedSession.execute(resolvedCommand)
            } catch let error as EditorError {
                throw PreparedAutomationExecutionError.coreCommandFailed(
                    stepIndex: stepIndex,
                    commandName: resolvedCommand.command.name,
                    code: error.code,
                    message: error.message
                )
            } catch {
                throw PreparedAutomationExecutionError.coreCommandFailed(
                    stepIndex: stepIndex,
                    commandName: resolvedCommand.command.name,
                    code: nil,
                    message: String(describing: error)
                )
            }

            try checkCancellation()
            let delta = result.generatedIdentities
            let stepGeneratedIdentities = try allIdentities(
                from: delta,
                stepIndex: stepIndex
            )
            let stepGeneratedWork = UInt64(stepGeneratedIdentities.count)
            let (nextWork, overflow) = generatedSourceWork.addingReportingOverflow(
                stepGeneratedWork
            )
            guard !overflow else {
                throw PreparedAutomationExecutionError.generatedWorkOverflow(stepIndex: stepIndex)
            }
            guard nextWork <= program.limits.maximumGeneratedSourceWork else {
                throw PreparedAutomationExecutionError.generatedSourceWorkExceeded(
                    stepIndex: stepIndex,
                    measured: nextWork,
                    maximum: program.limits.maximumGeneratedSourceWork
                )
            }

            let stepBindings = try bind(
                step.outputs,
                to: delta,
                stepIndex: stepIndex,
                slotValues: &slotValues
            )
            generatedSourceWork = nextWork
            generatedIdentityCount += stepGeneratedIdentities.count
            outputBindings.append(contentsOf: stepBindings)
            diagnostics.append(contentsOf: result.diagnostics)
            stepReceipts.append(
                PreparedAutomationStepReceipt(
                    stepIndex: stepIndex,
                    commandName: resolvedCommand.command.name,
                    generatedIdentities: delta,
                    outputBindings: stepBindings
                )
            )
        }

        let telemetry = PreparedAutomationExecutionTelemetry(
            stepCount: program.steps.count,
            commandCount: program.steps.count,
            inputSlotCount: program.estimatedInputSlotCount,
            outputSlotCount: program.estimatedOutputSlotCount,
            generatedIdentityCount: generatedIdentityCount,
            generatedSourceWork: generatedSourceWork
        )
        return PreparedAutomationExecutionReceipt(
            stepReceipts: stepReceipts,
            outputBindings: outputBindings,
            diagnostics: EditorDiagnostic.stableMerged([diagnostics]),
            telemetry: telemetry
        )
    }

    private func resolveInputs(
        _ slots: [PreparedAutomationInputSlot],
        stepIndex: Int,
        slotValues: [PreparedAutomationSlotID: PreparedAutomationIdentity],
        in document: DesignDocument
    ) throws -> PreparedAutomationResolvedInputs {
        var values: [PreparedAutomationSlotID: PreparedAutomationIdentity] = [:]
        for slot in slots {
            let identity: PreparedAutomationIdentity
            switch slot.reference {
            case .existing(let existing):
                guard existing.exists(in: document) else {
                    throw PreparedAutomationExecutionError.inputUnavailable(
                        stepIndex: stepIndex,
                        slotID: slot.id,
                        identity: existing
                    )
                }
                identity = existing
            case .local(let outputID):
                guard let local = slotValues[outputID] else {
                    throw PreparedAutomationExecutionError.localInputUnavailable(
                        stepIndex: stepIndex,
                        slotID: slot.id
                    )
                }
                identity = local
            }
            guard identity.kind == slot.expectedKind else {
                throw PreparedAutomationExecutionError.inputKindMismatch(
                    stepIndex: stepIndex,
                    slotID: slot.id,
                    expected: slot.expectedKind,
                    actual: identity.kind
                )
            }
            values[slot.id] = identity
        }
        return PreparedAutomationResolvedInputs(values: values)
    }

    private func allIdentities(
        from delta: CommandGeneratedIdentityDelta,
        stepIndex: Int
    ) throws -> [PreparedAutomationIdentity] {
        var identities: [PreparedAutomationIdentity] = []
        identities.reserveCapacity(
            delta.featureIDs.count
                + delta.sourceBodyOutputs.count
                + delta.sceneNodeIDs.count
                + delta.componentDefinitionIDs.count
                + delta.componentInstanceIDs.count
                + delta.patternArraySourceIDs.count
        )
        identities.append(contentsOf: delta.featureIDs.map(PreparedAutomationIdentity.init))
        identities.append(contentsOf: delta.sourceBodyOutputs.map(PreparedAutomationIdentity.init))
        identities.append(contentsOf: delta.sceneNodeIDs.map(PreparedAutomationIdentity.init))
        identities.append(contentsOf: delta.componentDefinitionIDs.map(PreparedAutomationIdentity.init))
        identities.append(contentsOf: delta.componentInstanceIDs.map(PreparedAutomationIdentity.init))
        identities.append(contentsOf: delta.patternArraySourceIDs.map(PreparedAutomationIdentity.init))

        var seen: Set<PreparedAutomationIdentity> = []
        for identity in identities {
            guard seen.insert(identity).inserted else {
                throw PreparedAutomationExecutionError.duplicateGeneratedIdentity(
                    stepIndex: stepIndex,
                    identity: identity
                )
            }
        }
        return identities
    }

    private func bind(
        _ outputs: [PreparedAutomationOutputSlot],
        to delta: CommandGeneratedIdentityDelta,
        stepIndex: Int,
        slotValues: inout [PreparedAutomationSlotID: PreparedAutomationIdentity]
    ) throws -> [PreparedAutomationOutputBinding] {
        var bindings: [PreparedAutomationOutputBinding] = []
        for output in outputs {
            guard let identity = identity(for: output.selector, from: delta) else {
                throw PreparedAutomationExecutionError.generatedIdentityMissing(
                    stepIndex: stepIndex,
                    selector: output.selector
                )
            }
            guard identity.kind == output.kind else {
                throw PreparedAutomationExecutionError.inputKindMismatch(
                    stepIndex: stepIndex,
                    slotID: output.id,
                    expected: output.kind,
                    actual: identity.kind
                )
            }
            guard slotValues[output.id] == nil else {
                throw PreparedAutomationExecutionError.duplicateGeneratedIdentity(
                    stepIndex: stepIndex,
                    identity: identity
                )
            }
            slotValues[output.id] = identity
            bindings.append(
                PreparedAutomationOutputBinding(
                    slotID: output.id,
                    kind: output.kind,
                    identity: identity
                )
            )
        }

        return bindings
    }

    private func identity(
        for selector: PreparedAutomationOutputSelector,
        from delta: CommandGeneratedIdentityDelta
    ) -> PreparedAutomationIdentity? {
        switch selector {
        case .feature(let index):
            guard delta.featureIDs.indices.contains(index) else { return nil }
            return .feature(delta.featureIDs[index])
        case .sourceBody(let role, let index):
            let matches = delta.sourceBodyOutputs.filter { $0.role == role }
            guard matches.indices.contains(index) else { return nil }
            return .sourceBody(featureID: matches[index].featureID, role: role)
        case .sceneNode(let index):
            guard delta.sceneNodeIDs.indices.contains(index) else { return nil }
            return .sceneNode(delta.sceneNodeIDs[index])
        case .componentDefinition(let index):
            guard delta.componentDefinitionIDs.indices.contains(index) else { return nil }
            return .componentDefinition(delta.componentDefinitionIDs[index])
        case .componentInstance(let index):
            guard delta.componentInstanceIDs.indices.contains(index) else { return nil }
            return .componentInstance(delta.componentInstanceIDs[index])
        case .patternArraySource(let index):
            guard delta.patternArraySourceIDs.indices.contains(index) else { return nil }
            return .patternArraySource(delta.patternArraySourceIDs[index])
        }
    }

    private func checkCancellation() throws {
        do {
            try Task.checkCancellation()
        } catch {
            throw PreparedAutomationExecutionError.cancelled
        }
    }
}
