import SwiftCAD

public protocol DrawingRadialDimensionResolving: Sendable {
    func resolve(_ measurement: MeasurementAnnotation,
        document: DesignDocument, evaluated: EvaluatedDocument,
        projection: DrawingOccurrenceProjection, options: DrawingGeometricPageOptions,
        usage: inout DrawingExchangeUsage) throws -> DrawingRadialDimensionMeasurement
}
