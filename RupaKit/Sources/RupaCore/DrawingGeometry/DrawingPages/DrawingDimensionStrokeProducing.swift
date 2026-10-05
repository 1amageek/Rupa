import SwiftCAD

public protocol DrawingDimensionStrokeProducing: Sendable {
    func paths(annotation: DrawingProjectionResult.Annotation, layout: DrawingDimensionLayout,
               options: DrawingGeometricPageOptions, usage: inout DrawingExchangeUsage) throws -> [DrawingPagePath]
    func paths(annotation: DrawingProjectionResult.Annotation, layout: DrawingDimensionLayout,
               options: DrawingGeometricPageOptions, radialMeasurement: DrawingRadialDimensionMeasurement?,
               frame: OrthographicProjectionFrame, usage: inout DrawingExchangeUsage) throws -> [DrawingPagePath]
}

extension DrawingDimensionStrokeProducing {
    // FIXME(INCOMPLETE_IMPLEMENTATION): External custom dimension producers must
    // bind actual radial source receipts before this production entry can publish
    // their strokes. The default never discards original circular provenance.
    public func paths(annotation: DrawingProjectionResult.Annotation, layout: DrawingDimensionLayout,
        options: DrawingGeometricPageOptions, radialMeasurement: DrawingRadialDimensionMeasurement?,
        frame: OrthographicProjectionFrame, usage: inout DrawingExchangeUsage) throws -> [DrawingPagePath] {
        guard radialMeasurement == nil else {
            throw EditorError(code: .commandInvalid, message: "Custom dimension producer must preserve the original radial source.")
        }
        return try paths(annotation: annotation, layout: layout, options: options, usage: &usage)
    }
}
