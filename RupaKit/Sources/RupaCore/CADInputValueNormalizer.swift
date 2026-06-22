import Foundation
import SwiftCAD

public struct CADInputValueNormalizer: Sendable {
    public var lengthFractionDigits: Int
    public var angleRadianFractionDigits: Int
    public var angleDegreeFractionDigits: Int

    public init(
        lengthFractionDigits: Int,
        angleRadianFractionDigits: Int,
        angleDegreeFractionDigits: Int
    ) {
        precondition(lengthFractionDigits >= 0)
        precondition(angleRadianFractionDigits >= 0)
        precondition(angleDegreeFractionDigits >= 0)
        self.lengthFractionDigits = lengthFractionDigits
        self.angleRadianFractionDigits = angleRadianFractionDigits
        self.angleDegreeFractionDigits = angleDegreeFractionDigits
    }

    public static let standard = CADInputValueNormalizer(
        lengthFractionDigits: 12,
        angleRadianFractionDigits: 12,
        angleDegreeFractionDigits: 9
    )

    public func point(_ point: Point2D) -> Point2D {
        Point2D(
            x: lengthMeters(point.x),
            y: lengthMeters(point.y)
        )
    }

    public func lengthMeters(_ value: Double) -> Double {
        rounded(value, fractionDigits: lengthFractionDigits)
    }

    public func angleRadians(_ value: Double) -> Double {
        rounded(value, fractionDigits: angleRadianFractionDigits)
    }

    public func angleDegrees(_ value: Double) -> Double {
        rounded(value, fractionDigits: angleDegreeFractionDigits)
    }

    private func rounded(_ value: Double, fractionDigits: Int) -> Double {
        guard value.isFinite else {
            return value
        }
        let format = "%.\(fractionDigits)f"
        let formatted = String(
            format: format,
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
        let normalized = Double(formatted) ?? value
        return normalized == -0.0 ? 0.0 : normalized
    }
}
