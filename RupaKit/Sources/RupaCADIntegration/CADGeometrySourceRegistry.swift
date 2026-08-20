/// An immutable registry of CAD sources available to one provider transaction.
public struct CADGeometrySourceRegistry: CADGeometrySourceResolving {
    private let sourcesByID: [String: CADGeometryEvaluationSource]

    public init(source: CADGeometryEvaluationSource) {
        self.sourcesByID = [source.sourceID: source]
    }

    public init(sources: [CADGeometryEvaluationSource]) throws {
        var sourcesByID: [String: CADGeometryEvaluationSource] = [:]
        sourcesByID.reserveCapacity(sources.count)
        for source in sources {
            guard sourcesByID.updateValue(source, forKey: source.sourceID) == nil else {
                throw CADIntegrationError(
                    code: .duplicateSource,
                    message: "CAD source IDs must be unique: \(source.sourceID)."
                )
            }
        }
        self.sourcesByID = sourcesByID
    }

    public func source(for sourceID: String) throws -> CADGeometryEvaluationSource {
        guard let source = sourcesByID[sourceID] else {
            throw CADIntegrationError(
                code: .sourceUnavailable,
                message: "No CAD source is registered for \(sourceID)."
            )
        }
        return source
    }
}
