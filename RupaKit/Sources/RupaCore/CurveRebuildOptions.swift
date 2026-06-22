import Foundation
import SwiftCAD

public struct CurveRebuildOptions: Codable, Equatable, Sendable {
    public enum Method: Codable, Equatable, Sendable {
        case refit(tolerance: CADExpression, keepsCorners: Bool)
        case points(controlPointCount: Int)
        case explicitControl(degree: Int, spanCount: Int, weight: Double)
    }

    public var method: Method

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
