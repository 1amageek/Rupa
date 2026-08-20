import Foundation

/// Owns provider identity validation and immutable provider lookup.
public struct GeometrySourceEvaluationProviderRegistry: Sendable {
    private let providers: [String: any GeometrySourceEvaluationProvider]

    static var meshSourceOnly: Self {
        let provider = MeshSourceEvaluationProvider()
        return Self(indexedProviders: [provider.providerID: provider])
    }

    private init(indexedProviders: [String: any GeometrySourceEvaluationProvider]) {
        self.providers = indexedProviders
    }

    public init(providers: [any GeometrySourceEvaluationProvider]) throws {
        var indexed: [String: any GeometrySourceEvaluationProvider] = [:]
        indexed.reserveCapacity(providers.count)

        for provider in providers {
            let providerID = provider.providerID
            guard !providerID.isEmpty,
                  providerID == providerID.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw EvaluationError(
                    code: .invalidProvider,
                    message: "Geometry evaluation provider IDs must be non-empty and must not have surrounding whitespace."
                )
            }
            guard indexed[providerID] == nil else {
                throw EvaluationError(
                    code: .duplicateProvider,
                    message: "Geometry evaluation provider \(providerID) is registered more than once."
                )
            }
            indexed[providerID] = provider
        }

        self.providers = indexed
    }

    package func provider(
        identifiedBy providerID: String
    ) throws -> any GeometrySourceEvaluationProvider {
        guard let provider = providers[providerID] else {
            throw EvaluationError(
                code: .providerNotRegistered,
                message: "No geometry evaluation provider is registered for \(providerID)."
            )
        }
        return provider
    }
}
