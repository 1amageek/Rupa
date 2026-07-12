import Foundation
import RupaCoreTypes

public struct CapabilityDescriptor: Codable, Equatable, Sendable {
    public var id: CapabilityID
    public var version: CapabilityVersion
    public var category: CapabilityCategoryID
    public var name: String
    public var summary: String
    public var effect: CapabilityEffect
    public var result: CapabilityResultDescriptor
    public var targets: [CapabilityTargetDescriptor]
    public var parameters: [CapabilityParameterDescriptor]
    public var execution: CapabilityExecutionContract
    public var availability: CapabilityAvailability
    public var knownErrorCodes: [String]
    public var failureMode: String

    public init(
        id: CapabilityID,
        version: CapabilityVersion,
        category: CapabilityCategoryID,
        name: String,
        summary: String,
        effect: CapabilityEffect,
        result: CapabilityResultDescriptor,
        targets: [CapabilityTargetDescriptor] = [],
        parameters: [CapabilityParameterDescriptor] = [],
        execution: CapabilityExecutionContract,
        availability: CapabilityAvailability,
        knownErrorCodes: [String] = ["command.invalid"],
        failureMode: String
    ) {
        self.id = id
        self.version = version
        self.category = category
        self.name = name
        self.summary = summary
        self.effect = effect
        self.result = result
        self.targets = targets
        self.parameters = parameters
        self.execution = execution
        self.availability = availability
        self.knownErrorCodes = knownErrorCodes
        self.failureMode = failureMode
    }

    public func validate() throws {
        do {
            try id.validate()
            try category.validate()
            try result.validate()
            try availability.validate()
        } catch let error as CapabilityRegistryError {
            throw error
        } catch let error as EditorError {
            throw CapabilityRegistryError(code: .invalidDescriptor, message: error.message)
        }

        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw invalid("Capability names must not be empty.")
        }
        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw invalid("Capability summaries must not be empty.")
        }
        guard !failureMode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw invalid("Capability failure modes must not be empty.")
        }
        for target in targets {
            try target.validate()
        }
        guard Set(targets.map(\.id)).count == targets.count else {
            throw invalid("Capability targets must be unique.")
        }
        for parameter in parameters {
            try parameter.validate()
        }
        guard Set(parameters.map(\.id)).count == parameters.count else {
            throw invalid("Capability (id.rawValue) must not contain duplicate parameter IDs.")
        }
        for errorCode in knownErrorCodes {
            guard !errorCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw invalid("Capability known error codes must not be empty.")
            }
        }
        guard !knownErrorCodes.isEmpty,
              Set(knownErrorCodes).count == knownErrorCodes.count else {
            throw invalid("Capability known error codes must be unique and non-empty.")
        }
        try validateParameterPaths()
        try validateEffectContract()
    }

    private func validateParameterPaths() throws {
        for index in parameters.indices {
            for otherIndex in parameters.indices where otherIndex > index {
                let path = parameters[index].payloadPath
                let otherPath = parameters[otherIndex].payloadPath
                guard !Self.isPrefix(path, of: otherPath),
                      !Self.isPrefix(otherPath, of: path) else {
                    throw invalid("Capability (id.rawValue) contains conflicting parameter payload paths.")
                }
            }
        }
    }

    private func validateEffectContract() throws {
        let validResultKinds: Set<CapabilityResultKind>
        switch effect {
        case .query:
            validResultKinds = [.semanticPayload, .validationReport, .artifactReference]
        case .sourceMutation:
            validResultKinds = [.sourceTransaction]
        case .workspaceMutation:
            validResultKinds = [.workspaceTransaction]
        case .artifactGeneration:
            validResultKinds = [.artifactReference]
        case .export:
            validResultKinds = [.exportArtifact]
        case .externalJob:
            validResultKinds = [.externalJob]
        case .decisionRecording:
            validResultKinds = [.semanticPayload, .sourceTransaction]
        }
        guard validResultKinds.contains(result.kind) else {
            throw invalid("Capability effect and result kind are incompatible.")
        }
    }

    private func invalid(_ message: String) -> CapabilityRegistryError {
        CapabilityRegistryError(code: .invalidDescriptor, message: message)
    }

    private static func isPrefix(_ prefix: [String], of path: [String]) -> Bool {
        guard prefix.count <= path.count else {
            return false
        }
        return zip(prefix, path).allSatisfy { $0 == $1 }
    }
}
