import RupaCapabilities
import RupaCore
import RupaCoreTypes

public extension DomainCapabilityDescriptor {
    func capabilityDescriptor() throws -> CapabilityDescriptor {
        try validate()
        let descriptor = CapabilityDescriptor(
            id: CapabilityID(rawValue: id.rawValue),
            version: CapabilityVersion(major: 1, minor: 0, patch: 0),
            category: CapabilityCategoryID(rawValue: namespace.rawValue),
            name: name,
            summary: summary,
            effect: capabilityEffect,
            result: CapabilityResultDescriptor(
                kind: capabilityResultKind,
                maximumFidelity: resultFidelity?.rawValue
            ),
            targets: targetKinds.map {
                CapabilityTargetDescriptor(
                    id: $0.rawValue,
                    name: $0.rawValue,
                    summary: "Target kind \($0.rawValue)."
                )
            },
            parameters: try parameters.map { try $0.capabilityParameterDescriptor() },
            execution: CapabilityExecutionContract(
                supportsDryRun: supportsDryRun,
                supportsCancellation: supportsCancellation,
                reportsProgress: reportsProgress,
                determinism: capabilityDeterminism,
                requiresTransactionRevision: effect == .documentMutation,
                retrySafe: effect == .query && determinism == .deterministic
            ),
            availability: CapabilityAvailability(
                surfaces: [.swiftAPI, .ui, .cli, .agent, .mcp]
            ),
            knownErrorCodes: knownErrorCodes.map(\.rawValue),
            failureMode: failureMode
        )
        try descriptor.validate()
        return descriptor
    }

    private var capabilityEffect: CapabilityEffect {
        switch effect {
        case .query:
            return .query
        case .documentMutation:
            return .sourceMutation
        case .artifactGeneration:
            return .artifactGeneration
        case .export:
            return .export
        case .externalJob:
            return .externalJob
        }
    }

    private var capabilityResultKind: CapabilityResultKind {
        switch resultKind {
        case .semanticPayload:
            return .semanticPayload
        case .documentTransaction:
            return .sourceTransaction
        case .validationReport:
            return .validationReport
        case .artifactReference:
            return .artifactReference
        case .exportArtifact:
            return .exportArtifact
        case .externalJob:
            return .externalJob
        }
    }

    private var capabilityDeterminism: CapabilityDeterminism {
        switch determinism {
        case .deterministic:
            return .deterministic
        case .deterministicWithDeclaredEnvironment:
            return .deterministicWithDeclaredEnvironment
        case .nondeterministic:
            return .nondeterministic
        }
    }
}

private extension DomainCommandParameterDescriptor {
    func capabilityParameterDescriptor() throws -> CapabilityParameterDescriptor {
        let canonicalDefaultValue: CanonicalValue?
        if let defaultValue {
            canonicalDefaultValue = try Self.canonicalValue(defaultValue)
        } else {
            canonicalDefaultValue = nil
        }
        return CapabilityParameterDescriptor(
            id: id,
            payloadPath: payloadPath,
            label: label,
            summary: summary,
            group: group,
            kind: capabilityParameterKind,
            unit: capabilityParameterUnit,
            isRequired: isRequired,
            allowsNull: allowsNull,
            defaultValue: canonicalDefaultValue,
            minimumValue: minimumValue,
            maximumValue: maximumValue,
            choices: choices.map {
                CapabilityChoice(
                    value: $0.value,
                    label: $0.label,
                    summary: $0.summary
                )
            }
        )
    }

    private var capabilityParameterKind: CapabilityParameterKind {
        switch kind {
        case .text:
            return .text
        case .boolean:
            return .boolean
        case .integer:
            return .integer
        case .number:
            return .number
        case .length:
            return .length
        case .angle:
            return .angle
        case .choice:
            return .choice
        }
    }

    private var capabilityParameterUnit: CapabilityParameterUnit {
        switch unit {
        case .unitless:
            return .unitless
        case .meter:
            return .meter
        case .degree:
            return .degree
        }
    }

    private static func canonicalValue(_ value: SemanticJSONValue) throws -> CanonicalValue {
        let canonical: CanonicalValue
        switch value {
        case .object(let object):
            canonical = .object(try object.mapValues(Self.canonicalValue))
        case .array(let values):
            canonical = .array(try values.map(Self.canonicalValue))
        case .string(let string):
            canonical = .string(string)
        case .number(let number):
            canonical = .number(number)
        case .bool(let bool):
            canonical = .bool(bool)
        case .null:
            canonical = .null
        }
        try canonical.validate()
        return canonical
    }
}
