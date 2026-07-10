import RupaCore
import RupaDomainFoundation

struct WorkspaceDomainCommandDraft: Equatable, Sendable {
    var values: [String: SemanticJSONValue]

    init(descriptor: DomainCapabilityDescriptor) {
        self.values = DomainCommandPayloadBuilder().defaultValues(for: descriptor)
    }

    func hasExplicitValue(for parameterID: String) -> Bool {
        guard let value = values[parameterID] else {
            return false
        }
        return value != .null
    }

    mutating func setValue(
        _ value: SemanticJSONValue,
        for parameterID: String
    ) {
        values[parameterID] = value
    }

    mutating func unsetValue(for parameterID: String) {
        values.removeValue(forKey: parameterID)
    }

    func request(
        descriptor: DomainCapabilityDescriptor,
        generation: DocumentGeneration,
        dryRun: Bool
    ) throws -> DomainCommandRequest {
        DomainCommandRequest(
            capabilityID: descriptor.id,
            namespace: descriptor.namespace,
            payload: try DomainCommandPayloadBuilder().payload(
                for: descriptor,
                values: values
            ),
            expectedGeneration: generation,
            dryRun: dryRun
        )
    }
}
