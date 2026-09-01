public struct SemanticOperationRegistry: Sendable {
    private struct Key: Hashable, Sendable {
        let operationID: DomainCapabilityID
        let version: SemanticOperationVersion
    }

    private let registrations: [Key: SemanticOperationRegistration]

    public init(registrations: [SemanticOperationRegistration]) throws {
        var indexed: [Key: SemanticOperationRegistration] = [:]
        for registration in registrations {
            try Self.validate(registration)
            let key = Key(
                operationID: registration.descriptor.operationID,
                version: registration.descriptor.version
            )
            guard indexed[key] == nil else {
                throw SemanticOperationRegistryError.duplicateOperation(
                    registration.descriptor.operationID,
                    registration.descriptor.version
                )
            }
            indexed[key] = registration
        }
        self.registrations = indexed
    }

    public func resolve(
        operationID: DomainCapabilityID,
        version: SemanticOperationVersion
    ) -> SemanticOperationRegistration? {
        registrations[Key(operationID: operationID, version: version)]
    }

    public func containsOperation(_ operationID: DomainCapabilityID) -> Bool {
        registrations.keys.contains { $0.operationID == operationID }
    }

    public var count: Int { registrations.count }

    /// Returns the immutable operation vocabulary in a stable wire order.
    ///
    /// Discovery and compilation must read this same registry snapshot. The
    /// registry remains the owner of descriptor validity; callers only receive
    /// value-type views and cannot register a second operation list.
    public func sortedDescriptors() -> [SemanticOperationDescriptor] {
        registrations.values.sorted { lhs, rhs in
            let leftID = lhs.descriptor.operationID.rawValue
            let rightID = rhs.descriptor.operationID.rawValue
            if leftID != rightID {
                return leftID < rightID
            }
            return lhs.descriptor.version < rhs.descriptor.version
        }.map(\.descriptor)
    }

    /// Verifies a product's required operation set without accepting a
    /// partial registry or an unplanned extra operation.
    public func validateOperations(
        _ expectedOperationIDs: [DomainCapabilityID],
        version: SemanticOperationVersion
    ) throws {
        let expected = Set(expectedOperationIDs.map {
            Key(operationID: $0, version: version)
        })
        let actual = Set(registrations.keys)
        if let missing = expected.subtracting(actual).sorted(by: Self.keyOrder).first {
            throw SemanticOperationRegistryError.missingOperation(
                missing.operationID,
                missing.version
            )
        }
        if let unexpected = actual.subtracting(expected).sorted(by: Self.keyOrder).first {
            throw SemanticOperationRegistryError.unexpectedOperation(
                unexpected.operationID,
                unexpected.version
            )
        }
    }

    private static func keyOrder(_ lhs: Key, _ rhs: Key) -> Bool {
        if lhs.operationID != rhs.operationID {
            return lhs.operationID.rawValue < rhs.operationID.rawValue
        }
        return lhs.version < rhs.version
    }

    private static func validate(_ registration: SemanticOperationRegistration) throws {
        let descriptor = registration.descriptor
        guard !descriptor.operationID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SemanticOperationRegistryError.invalidOperationID
        }
        guard registration.lowerer.operationID == descriptor.operationID,
              registration.lowerer.operationVersion == descriptor.version,
              registration.lowerer.resultEstimate == descriptor.resultEstimate else {
            if registration.lowerer.operationID == descriptor.operationID,
               registration.lowerer.operationVersion == descriptor.version {
                throw SemanticOperationRegistryError.lowererResultEstimateMismatch
            }
            throw SemanticOperationRegistryError.lowererIdentityMismatch
        }

        var inputIDs: Set<SemanticArgumentID> = []
        for input in descriptor.inputs {
            guard !input.id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SemanticOperationRegistryError.invalidInputID(input.id)
            }
            guard inputIDs.insert(input.id).inserted else {
                throw SemanticOperationRegistryError.duplicateInput(input.id)
            }
        }

        var outputIDs: Set<SemanticOutputID> = []
        var outputSelectors: Set<SemanticOutputSelector> = []
        for output in descriptor.outputs {
            guard !output.id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SemanticOperationRegistryError.invalidOutputID(output.id)
            }
            guard outputIDs.insert(output.id).inserted else {
                throw SemanticOperationRegistryError.duplicateOutput(output.id)
            }
            guard outputSelectors.insert(output.selector).inserted else {
                throw SemanticOperationRegistryError.duplicateOutputSelector(output.selector)
            }
            guard output.type == output.selector.type else {
                throw SemanticOperationRegistryError.outputSelectorKindMismatch(output.id)
            }
            guard output.selector.index >= 0 else {
                throw SemanticOperationRegistryError.negativeOutputIndex(output.id)
            }
        }

        guard descriptor.estimatedExpandedSourceWork > 0 || descriptor.outputs.isEmpty else {
            throw SemanticOperationRegistryError.invalidSourceWork
        }

        // Route, effect, and cost eligibility are invocation concerns. The
        // registry may describe non-source operations for discovery, while a
        // source compiler rejects them before invoking their lowerer.
    }
}
