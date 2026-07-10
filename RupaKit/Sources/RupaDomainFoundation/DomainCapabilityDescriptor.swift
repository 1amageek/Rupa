import Foundation
import RupaCore

public struct DomainCapabilityDescriptor: Codable, Equatable, Sendable {
    public var id: DomainCapabilityID
    public var namespace: SemanticNamespaceID
    public var name: String
    public var summary: String
    public var effect: DomainCapabilityEffect
    public var resultKind: DomainCapabilityResultKind
    public var supportsDryRun: Bool
    public var supportsCancellation: Bool
    public var reportsProgress: Bool
    public var determinism: DomainCapabilityDeterminism
    public var resultFidelity: ValidationFidelity?
    public var targetKinds: [DomainCapabilityTargetKind]
    public var parameters: [DomainCommandParameterDescriptor]
    public var knownErrorCodes: [DomainCapabilityErrorCode]
    public var failureMode: String

    public init(
        id: DomainCapabilityID,
        namespace: SemanticNamespaceID,
        name: String,
        summary: String,
        effect: DomainCapabilityEffect,
        resultKind: DomainCapabilityResultKind,
        supportsDryRun: Bool,
        supportsCancellation: Bool = false,
        reportsProgress: Bool = false,
        determinism: DomainCapabilityDeterminism = .deterministic,
        resultFidelity: ValidationFidelity? = nil,
        targetKinds: [DomainCapabilityTargetKind] = [],
        parameters: [DomainCommandParameterDescriptor] = [],
        knownErrorCodes: [DomainCapabilityErrorCode] = ["commandInvalid"],
        failureMode: String
    ) {
        self.id = id
        self.namespace = namespace
        self.name = name
        self.summary = summary
        self.effect = effect
        self.resultKind = resultKind
        self.supportsDryRun = supportsDryRun
        self.supportsCancellation = supportsCancellation
        self.reportsProgress = reportsProgress
        self.determinism = determinism
        self.resultFidelity = resultFidelity
        self.targetKinds = targetKinds
        self.parameters = parameters
        self.knownErrorCodes = knownErrorCodes
        self.failureMode = failureMode
    }

    public var mutatesDocument: Bool {
        effect == .documentMutation
    }

    public func validate() throws {
        try id.validate()
        try namespace.validate()
        guard id.rawValue.hasPrefix("\(namespace.rawValue)."),
              id.rawValue.count > namespace.rawValue.count + 1 else {
            throw DomainRegistryError(
                code: .invalidRegistration,
                message: "Domain capability IDs must be qualified by their namespace."
            )
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainRegistryError(
                code: .invalidRegistration,
                message: "Domain capability names must not be empty."
            )
        }
        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainRegistryError(
                code: .invalidRegistration,
                message: "Domain capability summaries must not be empty."
            )
        }
        guard !failureMode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainRegistryError(
                code: .invalidRegistration,
                message: "Domain capability failure modes must not be empty."
            )
        }
        for targetKind in targetKinds {
            try targetKind.validate()
        }
        guard Set(targetKinds).count == targetKinds.count else {
            throw DomainRegistryError(
                code: .invalidRegistration,
                message: "Domain capability target kinds must be unique."
            )
        }
        for errorCode in knownErrorCodes {
            try errorCode.validate()
        }
        guard !knownErrorCodes.isEmpty,
              Set(knownErrorCodes).count == knownErrorCodes.count else {
            throw DomainRegistryError(
                code: .invalidRegistration,
                message: "Domain capabilities must declare unique known error codes."
            )
        }
        try validateEffectContract()
        try validateParameters()
    }

    private func validateEffectContract() throws {
        let validResultKinds: Set<DomainCapabilityResultKind>
        switch effect {
        case .query:
            validResultKinds = [.semanticPayload, .validationReport, .artifactReference]
        case .documentMutation:
            validResultKinds = [.documentTransaction]
        case .artifactGeneration:
            validResultKinds = [.artifactReference]
        case .export:
            validResultKinds = [.exportArtifact]
        case .externalJob:
            validResultKinds = [.externalJob]
        }
        guard validResultKinds.contains(resultKind) else {
            throw DomainRegistryError(
                code: .invalidRegistration,
                message: "Domain capability effect and result kind are incompatible."
            )
        }
        if resultKind == .validationReport, resultFidelity == nil {
            throw DomainRegistryError(
                code: .invalidRegistration,
                message: "Validation-report capabilities must declare their maximum result fidelity."
            )
        }
    }

    private func validateParameters() throws {
        for parameter in parameters {
            try parameter.validate()
        }
        guard Set(parameters.map(\.id)).count == parameters.count else {
            throw DomainRegistryError(
                code: .invalidRegistration,
                message: "Domain capability \(id.rawValue) must not contain duplicate parameter IDs."
            )
        }

        for index in parameters.indices {
            for otherIndex in parameters.indices where otherIndex > index {
                let path = parameters[index].payloadPath
                let otherPath = parameters[otherIndex].payloadPath
                guard !Self.isPrefix(path, of: otherPath),
                      !Self.isPrefix(otherPath, of: path) else {
                    throw DomainRegistryError(
                        code: .invalidRegistration,
                        message: "Domain capability \(id.rawValue) contains conflicting parameter payload paths."
                    )
                }
            }
        }
    }

    private static func isPrefix(_ prefix: [String], of path: [String]) -> Bool {
        guard prefix.count <= path.count else {
            return false
        }
        return zip(prefix, path).allSatisfy { $0 == $1 }
    }
}
