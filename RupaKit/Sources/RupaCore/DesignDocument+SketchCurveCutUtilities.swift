import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    func uniqueInteriorCutFractions(_ fractions: [Double]) -> [Double] {
        let tolerance = 1.0e-10
        return fractions
            .filter { fraction in
                fraction > tolerance && fraction < 1.0 - tolerance
            }
            .sorted()
            .reduce(into: [Double]()) { uniqueFractions, fraction in
                guard uniqueFractions.contains(where: { abs($0 - fraction) <= tolerance }) == false else {
                    return
                }
                uniqueFractions.append(fraction)
            }
    }

    func uniqueCutAngles(_ angles: [Double]) -> [Double] {
        let tolerance = 1.0e-10
        let fullCircle = Double.pi * 2.0
        var uniqueAngles = angles
            .map(normalizedCutAngle)
            .sorted()
            .reduce(into: [Double]()) { uniqueAngles, angle in
                guard uniqueAngles.contains(where: { abs($0 - angle) <= tolerance }) == false else {
                    return
                }
                uniqueAngles.append(angle)
            }
        if let first = uniqueAngles.first,
           let last = uniqueAngles.last,
           uniqueAngles.count > 1,
           fullCircle - last + first <= tolerance {
            uniqueAngles.removeLast()
        }
        return uniqueAngles
    }

    func normalizedCutAngle(_ angle: Double) -> Double {
        let fullCircle = Double.pi * 2.0
        // Remainder-based normalization stays O(1) for arbitrarily large angle
        // expressions; +/- 2*pi loops hang on huge-but-finite values.
        var normalized = angle.truncatingRemainder(dividingBy: fullCircle)
        if normalized < 0.0 {
            normalized += fullCircle
        }
        if fullCircle - normalized <= 1.0e-10 {
            return 0.0
        }
        return normalized
    }

    func cutCurveAngleIsOnArc(
        _ angle: Double,
        startAngle: Double,
        endAngle: Double
    ) -> Bool {
        normalizedAngleDelta(from: startAngle, to: angle) <=
            positiveArcSpan(startAngle: startAngle, endAngle: endAngle) + 1.0e-10
    }

    func cutCurveArcFraction(
        for angle: Double,
        on arc: CutCurveArc
    ) -> Double {
        normalizedAngleDelta(from: arc.startAngle, to: angle) /
            positiveArcSpan(startAngle: arc.startAngle, endAngle: arc.endAngle)
    }

    func normalizedAngleDelta(
        from startAngle: Double,
        to angle: Double
    ) -> Double {
        let fullCircle = Double.pi * 2.0
        var delta = angle - startAngle
        while delta < 0.0 {
            delta += fullCircle
        }
        while delta >= fullCircle {
            delta -= fullCircle
        }
        return delta
    }
}
