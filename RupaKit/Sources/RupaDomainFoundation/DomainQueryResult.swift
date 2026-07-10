import Foundation
import RupaCore

public struct DomainQueryResult: Equatable, Sendable {
    public var message: String
    public var diagnostics: [EditorDiagnostic]
    public var validationFindings: [ValidationFinding]
    public var validationRegions: [ValidationRegionReference]
    public var payload: SemanticJSONValue?

    public init(
        message: String,
        diagnostics: [EditorDiagnostic] = [],
        validationFindings: [ValidationFinding] = [],
        validationRegions: [ValidationRegionReference] = [],
        payload: SemanticJSONValue? = nil
    ) {
        self.message = message
        self.diagnostics = diagnostics
        self.validationFindings = validationFindings
        self.validationRegions = validationRegions
        self.payload = payload
    }

    public func validate() throws {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainRegistryError(
                code: .invalidRegistration,
                message: "Domain query results must contain a message."
            )
        }
        for finding in validationFindings {
            try finding.validate()
        }
        for region in validationRegions {
            try region.validate()
        }
        if let payload {
            try payload.validate()
        }
    }
}
