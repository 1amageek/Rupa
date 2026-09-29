import Foundation
import SwiftCAD

public struct CurveRebuildOptions: Codable, Equatable, Sendable {
    public enum Method: Codable, Equatable, Sendable {
        case refit(tolerance: CADExpression, keepsCorners: Bool)
        case points(controlPointCount: Int)
        case explicitControl(degree: Int, spanCount: Int, weight: Double)
    }

    public var method: Method

    /// The degrees Explicit Control builds: every degree a sketch spline stores.
    public static let explicitControlDegrees: ClosedRange<Int> = 1...SketchSpline.maximumDegree

    /// The control point counts Points builds: a cubic's four up to the most a Swift-CAD fit takes.
    public static let pointCounts: ClosedRange<Int> = 4...SketchSplineLeastSquaresFit.maximumControlPointCount

    /// The span counts Explicit Control builds at `degree`: spans + degree control points, up to
    /// the most a Swift-CAD fit takes.
    public static func explicitControlSpanCounts(degree: Int) -> ClosedRange<Int> {
        1...(SketchSplineLeastSquaresFit.maximumControlPointCount - degree)
    }

    /// Refuses counts, degrees and weights outside what the method builds, before any of them is
    /// used, so no input from any caller reaches the rebuild's arithmetic out of range.
    public func validate(owner: String) throws {
        switch method {
        case .points(let controlPointCount):
            guard Self.pointCounts.contains(controlPointCount) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) Points takes \(Self.pointCounts.lowerBound) to \(Self.pointCounts.upperBound) control points."
                )
            }
        case .refit:
            break
        case .explicitControl(let degree, let spanCount, let weight):
            guard Self.explicitControlDegrees.contains(degree) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) Explicit Control degree must be between \(Self.explicitControlDegrees.lowerBound) and \(Self.explicitControlDegrees.upperBound)."
                )
            }
            let spans = Self.explicitControlSpanCounts(degree: degree)
            guard spans.contains(spanCount) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) Explicit Control at degree \(degree) takes \(spans.lowerBound) to \(spans.upperBound) spans."
                )
            }
            guard weight.isFinite, weight >= 0.0, weight <= 1.0 else {
                throw EditorError(code: .commandInvalid, message: "\(owner) Explicit Control weight must be between 0 and 1.")
            }
        }
    }

    public init(method: Method) {
        self.method = method
    }

    public static func points(controlPointCount: Int) -> CurveRebuildOptions {
        CurveRebuildOptions(method: .points(controlPointCount: controlPointCount))
    }

    public static func refit(
        tolerance: CADExpression,
        keepsCorners: Bool
    ) -> CurveRebuildOptions {
        CurveRebuildOptions(
            method: .refit(
                tolerance: tolerance,
                keepsCorners: keepsCorners
            )
        )
    }

    public static func explicitControl(
        degree: Int,
        spanCount: Int,
        weight: Double
    ) -> CurveRebuildOptions {
        CurveRebuildOptions(
            method: .explicitControl(
                degree: degree,
                spanCount: spanCount,
                weight: weight
            )
        )
    }
}
