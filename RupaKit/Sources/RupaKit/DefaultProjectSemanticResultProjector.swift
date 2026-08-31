import RupaAutomation
import RupaCore
import RupaDomainFoundation
import RupaProject
import SwiftCAD

public struct DefaultProjectSemanticResultProjector: ProjectSemanticResultProjecting, Sendable {
    public init() {}

    public func project(
        plan: ProjectResultProjectionPlan,
        receipt: PreparedAutomationExecutionReceipt,
        state: ProjectStateSnapshot
    ) throws -> [ProjectSemanticOutputBinding] {
        var bindingsBySlot: [PreparedAutomationSlotID: PreparedAutomationOutputBinding] = [:]
        for binding in receipt.outputBindings {
            guard bindingsBySlot.updateValue(binding, forKey: binding.slotID) == nil else {
                throw ProjectSemanticProgramError(
                    code: .requestedOutputMismatch,
                    message: "The prepared execution returned a duplicate output slot."
                )
            }
        }

        return try plan.requestedOutputs.map { requested in
            guard let binding = bindingsBySlot[requested.preparedSlot] else {
                throw ProjectSemanticProgramError(
                    code: .requestedOutputMissing,
                    message: "The prepared execution omitted a requested output slot."
                )
            }
            return ProjectSemanticOutputBinding(
                output: requested.source,
                value: try value(
                    for: requested.source.kind,
                    identity: binding.identity,
                    state: state
                )
            )
        }
    }

    private func value(
        for kind: SemanticValueType,
        identity: PreparedAutomationIdentity,
        state: ProjectStateSnapshot
    ) throws -> ProjectSemanticOutputBinding.Value {
        switch (kind, identity) {
        case (.feature, .feature(let id)):
            return .feature(id)
        case (
            .sourceBody(let expectedRole),
            .sourceBody(let featureID, let actualRole)
        ) where expectedRole == actualRole:
            return .body(
                featureID: featureID,
                role: actualRole,
                evaluatedBodyID: try evaluatedBodyID(
                    featureID: featureID,
                    sourceRole: actualRole,
                    state: state
                )
            )
        case (.sceneNode, .sceneNode(let id)):
            return .sceneNode(id)
        case (.componentDefinition, .componentDefinition(let id)):
            return .componentDefinition(id)
        case (.componentInstance, .componentInstance(let id)):
            return .componentInstance(id)
        case (.patternArraySource, .patternArraySource(let id)):
            return .patternArraySource(id)
        default:
            throw ProjectSemanticProgramError(
                code: .requestedOutputMismatch,
                message: "The prepared execution output kind does not match the compiled request."
            )
        }
    }

    private func evaluatedBodyID(
        featureID: FeatureID,
        sourceRole: SourceBodyOutputRole,
        state: ProjectStateSnapshot
    ) throws -> BodyID {
        let expectedPort: FeaturePort
        switch sourceRole {
        case .body:
            expectedPort = .body
        case .sheet:
            expectedPort = .sheet
        }
        guard state.document.cadDocument.designGraph.nodes[featureID]?.outputs.contains(
            where: { $0.role == expectedPort }
        ) == true,
              let evaluation = state.cadInteraction,
              evaluation.generation == state.documentGeneration else {
            throw bodyUnavailable()
        }

        let candidates = evaluation.evaluatedDocument.subshapes.entries
            .sorted { $0.key < $1.key }
            .compactMap { subshapeID, reference -> BodyID? in
                guard subshapeID.featureID == featureID,
                      subshapeID.role == GeneratedSubshapeRole.body.rawValue,
                      case .body(let bodyID) = reference else {
                    return nil
                }
                return bodyID
            }
        guard candidates.count == 1,
              let bodyID = candidates.first else {
            throw bodyUnavailable()
        }
        return bodyID
    }

    private func bodyUnavailable() -> ProjectSemanticProgramError {
        ProjectSemanticProgramError(
            code: .evaluatedBodyUnavailable,
            message: "The requested source body does not resolve to exactly one body in the committed evaluation."
        )
    }
}
