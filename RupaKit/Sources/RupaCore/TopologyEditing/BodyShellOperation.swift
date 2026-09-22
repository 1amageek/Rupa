import SwiftCAD

struct BodyShellOperation: TopologyEditOperation {
    let thickness: CADExpression

    static var selectionKind: TopologySummaryResult.Entry.Kind { .face }

    func featureOperation(sourceID: FeatureID, reference: StableSubshapeReference,
                          in document: DesignDocument) throws -> FeatureOperation {
        .shell(.init(target: .init(featureID: sourceID), removedFaces: [reference], thickness: thickness))
    }
}
