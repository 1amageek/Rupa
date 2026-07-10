import Foundation
import RupaCore
import RupaCoreTypes

public struct DomainRegistry: Sendable {
    public let namespaces: [SemanticNamespaceID: DomainNamespaceRegistration]
    public let capabilityDescriptors: [DomainCapabilityID: DomainCapabilityDescriptor]
    private let decoders: [SemanticNamespaceID: any DomainPayloadDecoder]
    private let validators: [SemanticNamespaceID: any DomainValidator]
    private let commandLowerings: [DomainCapabilityID: any DomainCommandLowering]
    private let projectionRepairProviders: [SemanticNamespaceID: any DomainProjectionRepairProvider]
    private let simulationAdapters: [SemanticNamespaceID: any DomainSimulationAdapter]

    public init() {
        self.namespaces = [:]
        self.capabilityDescriptors = [:]
        self.decoders = [:]
        self.validators = [:]
        self.commandLowerings = [:]
        self.projectionRepairProviders = [:]
        self.simulationAdapters = [:]
    }

    public init(
        namespaces: [DomainNamespaceRegistration] = [],
        capabilityDescriptors: [DomainCapabilityDescriptor] = [],
        decoders: [any DomainPayloadDecoder] = [],
        validators: [any DomainValidator] = [],
        commandLowerings: [any DomainCommandLowering] = [],
        projectionRepairProviders: [any DomainProjectionRepairProvider] = [],
        simulationAdapters: [any DomainSimulationAdapter] = []
    ) throws {
        self.namespaces = try Self.indexNamespaces(namespaces)
        self.capabilityDescriptors = try Self.indexCapabilities(
            capabilityDescriptors,
            namespaces: self.namespaces
        )
        self.decoders = try Self.indexDecoders(
            decoders,
            namespaces: self.namespaces
        )
        self.validators = try Self.indexValidators(
            validators,
            namespaces: self.namespaces
        )
        self.commandLowerings = try Self.indexCommandLowerings(
            commandLowerings,
            capabilities: self.capabilityDescriptors
        )
        try Self.validateCapabilityLoweringCoverage(
            capabilities: self.capabilityDescriptors,
            commandLowerings: self.commandLowerings
        )
        self.projectionRepairProviders = try Self.indexProjectionRepairProviders(
            projectionRepairProviders,
            namespaces: self.namespaces
        )
        self.simulationAdapters = try Self.indexSimulationAdapters(
            simulationAdapters,
            namespaces: self.namespaces
        )
    }

    public static func merged(_ registries: [DomainRegistry]) throws -> DomainRegistry {
        var namespaces: [SemanticNamespaceID: DomainNamespaceRegistration] = [:]
        var capabilityDescriptors: [DomainCapabilityID: DomainCapabilityDescriptor] = [:]
        var decoders: [SemanticNamespaceID: any DomainPayloadDecoder] = [:]
        var validators: [SemanticNamespaceID: any DomainValidator] = [:]
        var commandLowerings: [DomainCapabilityID: any DomainCommandLowering] = [:]
        var projectionRepairProviders: [SemanticNamespaceID: any DomainProjectionRepairProvider] = [:]
        var simulationAdapters: [SemanticNamespaceID: any DomainSimulationAdapter] = [:]

        for registry in registries {
            try merge(
                registry.namespaces,
                into: &namespaces,
                duplicateMessage: { "Duplicate domain namespace \($0.rawValue)." }
            )
            try merge(
                registry.capabilityDescriptors,
                into: &capabilityDescriptors,
                duplicateMessage: { "Duplicate domain capability \($0.rawValue)." }
            )
            try merge(
                registry.decoders,
                into: &decoders,
                duplicateMessage: { "Duplicate payload decoder for namespace \($0.rawValue)." }
            )
            try merge(
                registry.validators,
                into: &validators,
                duplicateMessage: { "Duplicate validator for namespace \($0.rawValue)." }
            )
            try merge(
                registry.commandLowerings,
                into: &commandLowerings,
                duplicateMessage: { "Duplicate command lowering for capability \($0.rawValue)." }
            )
            try merge(
                registry.projectionRepairProviders,
                into: &projectionRepairProviders,
                duplicateMessage: { "Duplicate projection repair provider for namespace \($0.rawValue)." }
            )
            try merge(
                registry.simulationAdapters,
                into: &simulationAdapters,
                duplicateMessage: { "Duplicate simulation adapter for namespace \($0.rawValue)." }
            )
        }

        try validateCapabilityLoweringCoverage(
            capabilities: capabilityDescriptors,
            commandLowerings: commandLowerings
        )

        return DomainRegistry(
            namespaces: namespaces,
            capabilityDescriptors: capabilityDescriptors,
            decoders: decoders,
            validators: validators,
            commandLowerings: commandLowerings,
            projectionRepairProviders: projectionRepairProviders,
            simulationAdapters: simulationAdapters
        )
    }

    private init(
        namespaces: [SemanticNamespaceID: DomainNamespaceRegistration],
        capabilityDescriptors: [DomainCapabilityID: DomainCapabilityDescriptor],
        decoders: [SemanticNamespaceID: any DomainPayloadDecoder],
        validators: [SemanticNamespaceID: any DomainValidator],
        commandLowerings: [DomainCapabilityID: any DomainCommandLowering],
        projectionRepairProviders: [SemanticNamespaceID: any DomainProjectionRepairProvider],
        simulationAdapters: [SemanticNamespaceID: any DomainSimulationAdapter]
    ) {
        self.namespaces = namespaces
        self.capabilityDescriptors = capabilityDescriptors
        self.decoders = decoders
        self.validators = validators
        self.commandLowerings = commandLowerings
        self.projectionRepairProviders = projectionRepairProviders
        self.simulationAdapters = simulationAdapters
    }

    public func namespaceRegistration(for namespace: SemanticNamespaceID) -> DomainNamespaceRegistration? {
        namespaces[namespace]
    }

    public func capabilityDescriptor(for id: DomainCapabilityID) -> DomainCapabilityDescriptor? {
        capabilityDescriptors[id]
    }

    public func sortedCapabilityDescriptors() -> [DomainCapabilityDescriptor] {
        capabilityDescriptors.values.sorted { lhs, rhs in
            lhs.id.rawValue < rhs.id.rawValue
        }
    }

    public func ownershipResolver() -> DomainOwnershipResolver {
        DomainOwnershipResolver(registry: self)
    }

    public func resolveOwnership(
        for envelope: SemanticExtensionEnvelope,
        semanticEntityID: SemanticEntityID,
        in document: DesignDocument,
        generation: DocumentGeneration
    ) throws -> DomainOwnershipResolution {
        try ownershipResolver().resolve(
            envelope: envelope,
            semanticEntityID: semanticEntityID,
            in: document,
            generation: generation
        )
    }

    public func decode(_ envelope: SemanticExtensionEnvelope) throws -> DomainPayloadDecodingResult {
        guard let decoder = decoders[envelope.namespace] else {
            throw DomainRegistryError(
                code: .missingNamespace,
                message: "No domain payload decoder is registered for namespace \(envelope.namespace.rawValue)."
            )
        }
        return try decoder.decode(envelope)
    }

    public func validate(
        envelope: SemanticExtensionEnvelope,
        in document: DesignDocument
    ) throws -> [EditorDiagnostic] {
        guard let validator = validators[envelope.namespace] else {
            return []
        }
        return try validator.validate(envelope: envelope, in: document)
    }

    public func lower(_ request: DomainCommandRequest) throws -> DomainCommandPlan {
        guard let lowering = commandLowerings[request.capabilityID] else {
            throw DomainRegistryError(
                code: .missingCommandLowering,
                message: "No domain command lowering is registered for capability \(request.capabilityID.rawValue)."
            )
        }
        guard capabilityDescriptors[request.capabilityID]?.namespace == request.namespace else {
            throw DomainRegistryError(
                code: .invalidRegistration,
                message: "Domain command request namespace does not match the capability namespace."
            )
        }
        return try lowering.lower(request)
    }

    public func repairProjection(_ request: DomainProjectionRepairRequest) throws -> DomainCommandPlan {
        guard let provider = projectionRepairProviders[request.envelope.namespace] else {
            throw DomainRegistryError(
                code: .missingProjectionRepairProvider,
                message: "No domain projection repair provider is registered for namespace \(request.envelope.namespace.rawValue)."
            )
        }
        return try provider.repairProjection(request)
    }

    public func prepareSimulation(_ request: DomainSimulationRequest) throws -> DomainSimulationPlan {
        guard let adapter = simulationAdapters[request.namespace] else {
            throw DomainRegistryError(
                code: .missingSimulationAdapter,
                message: "No domain simulation adapter is registered for namespace \(request.namespace.rawValue)."
            )
        }
        let plan = try adapter.prepareSimulation(request)
        try plan.validate()
        return plan
    }

    private static func indexNamespaces(
        _ registrations: [DomainNamespaceRegistration]
    ) throws -> [SemanticNamespaceID: DomainNamespaceRegistration] {
        var result: [SemanticNamespaceID: DomainNamespaceRegistration] = [:]
        for registration in registrations {
            try registration.validate()
            guard result[registration.namespace] == nil else {
                throw DomainRegistryError(
                    code: .duplicateNamespace,
                    message: "Domain namespace \(registration.namespace.rawValue) is registered more than once."
                )
            }
            result[registration.namespace] = registration
        }
        return result
    }

    private static func indexCapabilities(
        _ descriptors: [DomainCapabilityDescriptor],
        namespaces: [SemanticNamespaceID: DomainNamespaceRegistration]
    ) throws -> [DomainCapabilityID: DomainCapabilityDescriptor] {
        var result: [DomainCapabilityID: DomainCapabilityDescriptor] = [:]
        for descriptor in descriptors {
            try descriptor.validate()
            guard namespaces[descriptor.namespace] != nil else {
                throw DomainRegistryError(
                    code: .missingNamespace,
                    message: "Domain capability \(descriptor.id.rawValue) references an unregistered namespace."
                )
            }
            guard result[descriptor.id] == nil else {
                throw DomainRegistryError(
                    code: .duplicateCapability,
                    message: "Domain capability \(descriptor.id.rawValue) is registered more than once."
                )
            }
            result[descriptor.id] = descriptor
        }
        return result
    }

    private static func merge<Key: Hashable, Value>(
        _ source: [Key: Value],
        into destination: inout [Key: Value],
        duplicateMessage: (Key) -> String
    ) throws {
        for (key, value) in source {
            guard destination[key] == nil else {
                throw DomainRegistryError(
                    code: .invalidRegistration,
                    message: duplicateMessage(key)
                )
            }
            destination[key] = value
        }
    }

    private static func indexDecoders(
        _ decoders: [any DomainPayloadDecoder],
        namespaces: [SemanticNamespaceID: DomainNamespaceRegistration]
    ) throws -> [SemanticNamespaceID: any DomainPayloadDecoder] {
        var result: [SemanticNamespaceID: any DomainPayloadDecoder] = [:]
        for decoder in decoders {
            try decoder.namespace.validate()
            guard namespaces[decoder.namespace] != nil else {
                throw DomainRegistryError(
                    code: .missingNamespace,
                    message: "Domain payload decoder references an unregistered namespace."
                )
            }
            guard result[decoder.namespace] == nil else {
                throw DomainRegistryError(
                    code: .duplicateDecoder,
                    message: "Domain payload decoder for namespace \(decoder.namespace.rawValue) is registered more than once."
                )
            }
            result[decoder.namespace] = decoder
        }
        return result
    }

    private static func indexValidators(
        _ validators: [any DomainValidator],
        namespaces: [SemanticNamespaceID: DomainNamespaceRegistration]
    ) throws -> [SemanticNamespaceID: any DomainValidator] {
        var result: [SemanticNamespaceID: any DomainValidator] = [:]
        for validator in validators {
            try validator.namespace.validate()
            guard namespaces[validator.namespace] != nil else {
                throw DomainRegistryError(
                    code: .missingNamespace,
                    message: "Domain validator references an unregistered namespace."
                )
            }
            guard result[validator.namespace] == nil else {
                throw DomainRegistryError(
                    code: .duplicateValidator,
                    message: "Domain validator for namespace \(validator.namespace.rawValue) is registered more than once."
                )
            }
            result[validator.namespace] = validator
        }
        return result
    }

    private static func indexCommandLowerings(
        _ lowerings: [any DomainCommandLowering],
        capabilities: [DomainCapabilityID: DomainCapabilityDescriptor]
    ) throws -> [DomainCapabilityID: any DomainCommandLowering] {
        var result: [DomainCapabilityID: any DomainCommandLowering] = [:]
        for lowering in lowerings {
            try lowering.capabilityID.validate()
            guard capabilities[lowering.capabilityID] != nil else {
                throw DomainRegistryError(
                    code: .missingCapability,
                    message: "Domain command lowering references an unregistered capability."
                )
            }
            guard result[lowering.capabilityID] == nil else {
                throw DomainRegistryError(
                    code: .duplicateCommandLowering,
                    message: "Domain command lowering for capability \(lowering.capabilityID.rawValue) is registered more than once."
                )
            }
            result[lowering.capabilityID] = lowering
        }
        return result
    }

    private static func validateCapabilityLoweringCoverage(
        capabilities: [DomainCapabilityID: DomainCapabilityDescriptor],
        commandLowerings: [DomainCapabilityID: any DomainCommandLowering]
    ) throws {
        let missingCapabilityIDs = capabilities.keys
            .filter { commandLowerings[$0] == nil }
            .sorted { $0.rawValue < $1.rawValue }
        guard missingCapabilityIDs.isEmpty else {
            throw DomainRegistryError(
                code: .missingCommandLowering,
                message: "Domain capabilities must each register one command lowering. Missing lowering(s): \(missingCapabilityIDs.map(\.rawValue).joined(separator: ", "))."
            )
        }
    }

    private static func indexProjectionRepairProviders(
        _ providers: [any DomainProjectionRepairProvider],
        namespaces: [SemanticNamespaceID: DomainNamespaceRegistration]
    ) throws -> [SemanticNamespaceID: any DomainProjectionRepairProvider] {
        var result: [SemanticNamespaceID: any DomainProjectionRepairProvider] = [:]
        for provider in providers {
            try provider.namespace.validate()
            guard namespaces[provider.namespace] != nil else {
                throw DomainRegistryError(
                    code: .missingNamespace,
                    message: "Domain projection repair provider references an unregistered namespace."
                )
            }
            guard result[provider.namespace] == nil else {
                throw DomainRegistryError(
                    code: .duplicateProjectionRepairProvider,
                    message: "Domain projection repair provider for namespace \(provider.namespace.rawValue) is registered more than once."
                )
            }
            result[provider.namespace] = provider
        }
        return result
    }

    private static func indexSimulationAdapters(
        _ adapters: [any DomainSimulationAdapter],
        namespaces: [SemanticNamespaceID: DomainNamespaceRegistration]
    ) throws -> [SemanticNamespaceID: any DomainSimulationAdapter] {
        var result: [SemanticNamespaceID: any DomainSimulationAdapter] = [:]
        for adapter in adapters {
            try adapter.namespace.validate()
            guard namespaces[adapter.namespace] != nil else {
                throw DomainRegistryError(
                    code: .missingNamespace,
                    message: "Domain simulation adapter references an unregistered namespace."
                )
            }
            guard result[adapter.namespace] == nil else {
                throw DomainRegistryError(
                    code: .duplicateSimulationAdapter,
                    message: "Domain simulation adapter for namespace \(adapter.namespace.rawValue) is registered more than once."
                )
            }
            result[adapter.namespace] = adapter
        }
        return result
    }
}
