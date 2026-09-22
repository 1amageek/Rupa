import SwiftCAD

/// Pure lowering after the shared preparer resolves one current CAD subshape.
protocol TopologyEditOperation: Sendable {
    static var selectionKind: TopologySummaryResult.Entry.Kind { get }
    func featureOperation(sourceID: FeatureID, reference: StableSubshapeReference,
                          in document: DesignDocument) throws -> FeatureOperation
}
