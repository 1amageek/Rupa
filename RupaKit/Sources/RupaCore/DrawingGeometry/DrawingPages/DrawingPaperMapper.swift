import SwiftCAD

/// One explicit paper law with outward rounding admission shared by all page primitives.
struct DrawingPaperMapper {
    let options: DrawingGeometricPageOptions

    func map(_ point: Point2D, sourceError: Double = 0) throws -> Point2D {
        func coordinate(_ value: Double, translation: Double) throws -> (value: Double, error: Double) {
            guard value.isFinite else { throw invalid("Original drawing coordinate is nonfinite.") }
            let product = value * options.pointsPerMeter, mapped = product + translation
            let lower = (product.nextDown + translation).nextDown
            let upper = (product.nextUp + translation).nextUp
            let error = max(abs(mapped - lower), abs(upper - mapped)).nextUp
            guard mapped.isFinite, lower.isFinite, upper.isFinite, error.isFinite else {
                throw invalid("Paper coordinate law exceeds finite precision.")
            }
            return (mapped, error)
        }
        guard sourceError.isFinite, sourceError >= 0 else { throw invalid("Original point projection error is invalid.") }
        let x = try coordinate(point.x, translation: options.translation.x)
        let y = try coordinate(point.y, translation: options.translation.y)
        let mappedSourceError = sourceError == 0 ? 0 : (sourceError * options.pointsPerMeter).nextUp
        let coordinateError = (x.error + y.error).nextUp
        let error = sourceError == 0 ? coordinateError : (coordinateError + mappedSourceError).nextUp
        guard error.isFinite, error <= (options.maximumCurveDeviation / 2).nextDown else {
            throw invalid("Paper rounding exceeds the caller's original drawing deviation.")
        }
        return Point2D(x: x.value, y: y.value)
    }

    private func invalid(_ message: String) -> EditorError {
        EditorError(code: .evaluationFailed, message: message)
    }
}
