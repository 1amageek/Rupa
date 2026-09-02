import RupaAgentProtocol
import RupaCore

/// Projects a committed semantic receipt without exposing lowered automation
/// commands to benchmark code.
struct CADSemanticExecutionEvidence: Sendable {
    let receipt: AgentSemanticCommitReceipt

    var commandCount: Int { receipt.telemetry.execution.commandCount }

    var diagnostics: [String] { receipt.diagnostics.map(\.message) }

    static func committedReceipt(from response: AgentResponse?) -> AgentSemanticCommitReceipt? {
        guard case .programExecution(.success(.committed(let receipt))) = response else {
            return nil
        }
        return receipt
    }

    func bindings(for step: CADSemanticProgramPlan.Step) -> [AgentSemanticOutputBinding] {
        step.outputs.compactMap { reference in
            receipt.outputs.first(where: { $0.output == reference })
        }
    }

    func bindings(forNode node: String) -> [AgentSemanticOutputBinding] {
        receipt.outputs.filter { $0.output.node == node }
    }

    func nodeNamesInOrder() -> [String] {
        var seen = Set<String>()
        return receipt.outputs.compactMap { binding in
            seen.insert(binding.output.node).inserted ? binding.output.node : nil
        }
    }

    func featureID(
        forNode node: String,
        preferredOutputs: [String] = []
    ) -> String? {
        let values = bindings(forNode: node)
        for name in preferredOutputs {
            guard let binding = values.first(where: { $0.output.output == name }) else { continue }
            if let id = featureID(from: binding.value) { return id }
        }
        return values.compactMap { featureID(from: $0.value) }.first
    }

    func sceneNodeID(
        forNode node: String,
        preferredOutputs: [String] = []
    ) -> String? {
        let values = bindings(forNode: node)
        for name in preferredOutputs {
            guard let binding = values.first(where: { $0.output.output == name }) else { continue }
            if let id = sceneNodeID(from: binding.value) { return id }
        }
        return values.compactMap { sceneNodeID(from: $0.value) }.first
    }

    func typedSceneNodeID(
        forNode node: String,
        preferredOutputs: [String] = []
    ) -> SceneNodeID? {
        let values = bindings(forNode: node)
        for name in preferredOutputs {
            guard let binding = values.first(where: { $0.output.output == name }) else { continue }
            if let id = typedSceneNodeID(from: binding.value) { return id }
        }
        return values.compactMap { typedSceneNodeID(from: $0.value) }.first
    }

    func stepResult(
        node: String,
        operation: String,
        index: Int,
        primaryOutputs: [String] = []
    ) -> CADCandidateStepResult {
        let primaryFeatureID = featureID(forNode: node, preferredOutputs: primaryOutputs)
        return CADCandidateStepResult(
            stepIndex: index,
            operation: operation,
            status: .published,
            primaryFeatureID: primaryFeatureID,
            createdFeatureIDs: orderedFeatureIDs(
                in: bindings(forNode: node),
                primaryFeatureID: primaryFeatureID
            ),
            diagnostics: diagnostics
        )
    }

    func featureID(
        for step: CADSemanticProgramPlan.Step,
        preferredOutputs: [String] = []
    ) -> String? {
        let values = bindings(for: step)
        for name in preferredOutputs {
            guard let binding = values.first(where: { $0.output.output == name }) else { continue }
            if let id = featureID(from: binding.value) { return id }
        }
        return values.compactMap { featureID(from: $0.value) }.first
    }

    func sceneNodeID(
        for step: CADSemanticProgramPlan.Step,
        preferredOutputs: [String] = []
    ) -> String? {
        let values = bindings(for: step)
        for name in preferredOutputs {
            guard let binding = values.first(where: { $0.output.output == name }) else { continue }
            if let id = sceneNodeID(from: binding.value) { return id }
        }
        return values.compactMap { sceneNodeID(from: $0.value) }.first
    }

    func stepResult(
        _ step: CADSemanticProgramPlan.Step,
        index: Int,
        primaryOutputs: [String] = []
    ) -> CADCandidateStepResult {
        let primaryFeatureID = featureID(for: step, preferredOutputs: primaryOutputs)
        return CADCandidateStepResult(
            stepIndex: index,
            operation: step.operationID.rawValue,
            status: .published,
            primaryFeatureID: primaryFeatureID,
            createdFeatureIDs: orderedFeatureIDs(
                in: bindings(for: step),
                primaryFeatureID: primaryFeatureID
            ),
            diagnostics: diagnostics
        )
    }

    private func orderedFeatureIDs(
        in bindings: [AgentSemanticOutputBinding],
        primaryFeatureID: String?
    ) -> [String] {
        let featureIDs = bindings.compactMap { featureID(from: $0.value) }
        guard let primaryFeatureID else { return featureIDs }
        return featureIDs.filter { $0 != primaryFeatureID } + [primaryFeatureID]
    }

    private func featureID(from value: AgentSemanticOutputBinding.Value) -> String? {
        switch value {
        case .feature(let id): String(describing: id)
        case .body(let featureID, _, _): String(describing: featureID)
        default: nil
        }
    }

    private func sceneNodeID(from value: AgentSemanticOutputBinding.Value) -> String? {
        guard case .sceneNode(let id) = value else { return nil }
        return String(describing: id)
    }

    private func typedSceneNodeID(from value: AgentSemanticOutputBinding.Value) -> SceneNodeID? {
        guard case .sceneNode(let id) = value else { return nil }
        return id
    }
}
