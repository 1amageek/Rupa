import SwiftCAD

public protocol DrawingGeometricPageComposing: Sendable {
    func compose(_ projection: DrawingOccurrenceProjection,
                 annotations: DrawingGeometricAnnotations,
                 document: DesignDocument, evaluated: EvaluatedDocument,
                 options: DrawingGeometricPageOptions,
                 usage: inout DrawingExchangeUsage) throws -> DrawingGeometricPage
    func compose(_ projection: DrawingOccurrenceProjection,
                 annotations: DrawingGeometricAnnotations, sections: DrawingOccurrenceSections,
                 contributions: [DrawingSectionPageContribution],
                 document: DesignDocument, evaluated: EvaluatedDocument,
                 options: DrawingGeometricPageOptions,
                 usage: inout DrawingExchangeUsage) throws -> DrawingGeometricPage
}
