import Foundation
import RupaCoreTypes

public enum WorkspaceScalePreset: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case microFabrication
    case precisionMechanical
    case productDesign
    case roomInterior
    case architecture
    case architectureImperial
    case sitePlanning
    case sitePlanningImperial

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .microFabrication:
            "Micro Fabrication"
        case .precisionMechanical:
            "Precision Mechanical"
        case .productDesign:
            "Product Design"
        case .roomInterior:
            "Room Interior"
        case .architecture:
            "Architecture"
        case .architectureImperial:
            "Architecture (ft)"
        case .sitePlanning:
            "Site Planning"
        case .sitePlanningImperial:
            "Site Planning (ft)"
        }
    }

    public var rulerConfiguration: RulerConfiguration {
        switch self {
        case .microFabrication:
            RulerConfiguration(
                displayUnit: .micrometer,
                minorTickMeters: 1.0e-6,
                majorTickMeters: 1.0e-5,
                visibleSpanMeters: 0.01
            )
        case .precisionMechanical:
            RulerConfiguration(
                displayUnit: .millimeter,
                minorTickMeters: 0.0001,
                majorTickMeters: 0.001,
                visibleSpanMeters: 1.0
            )
        case .productDesign:
            RulerConfiguration(
                displayUnit: .millimeter,
                minorTickMeters: 0.001,
                majorTickMeters: 0.01,
                visibleSpanMeters: 10.0
            )
        case .roomInterior:
            RulerConfiguration(
                displayUnit: .centimeter,
                minorTickMeters: 0.01,
                majorTickMeters: 0.1,
                visibleSpanMeters: 50.0
            )
        case .architecture:
            RulerConfiguration(
                displayUnit: .meter,
                minorTickMeters: 0.1,
                majorTickMeters: 1.0,
                visibleSpanMeters: 2_000.0
            )
        case .architectureImperial:
            RulerConfiguration(
                displayUnit: .foot,
                minorTickMeters: 0.3048,
                majorTickMeters: 3.048,
                visibleSpanMeters: 1_524.0
            )
        case .sitePlanning:
            RulerConfiguration(
                displayUnit: .meter,
                minorTickMeters: 10.0,
                majorTickMeters: 100.0,
                visibleSpanMeters: 100_000.0
            )
        case .sitePlanningImperial:
            RulerConfiguration(
                displayUnit: .foot,
                minorTickMeters: 30.48,
                majorTickMeters: 304.8,
                visibleSpanMeters: 100_000.0
            )
        }
    }

    public static func matching(
        _ ruler: RulerConfiguration,
        tolerance: Double = 1.0e-9
    ) -> WorkspaceScalePreset? {
        let normalized = ruler.normalizedForWorkspaceScale()
        return allCases.first { preset in
            let presetRuler = preset.rulerConfiguration.normalizedForWorkspaceScale()
            return presetRuler.displayUnit == normalized.displayUnit
                && approximatelyEqual(presetRuler.minorTickMeters, normalized.minorTickMeters, tolerance: tolerance)
                && approximatelyEqual(presetRuler.majorTickMeters, normalized.majorTickMeters, tolerance: tolerance)
                && approximatelyEqual(presetRuler.visibleSpanMeters, normalized.visibleSpanMeters, tolerance: tolerance)
        }
    }

    private static func approximatelyEqual(
        _ lhs: Double,
        _ rhs: Double,
        tolerance: Double
    ) -> Bool {
        let scale = max(1.0, max(abs(lhs), abs(rhs)))
        return abs(lhs - rhs) <= tolerance * scale
    }
}
