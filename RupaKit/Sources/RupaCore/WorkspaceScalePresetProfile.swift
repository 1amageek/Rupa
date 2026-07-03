import RupaCoreTypes

public struct WorkspaceScalePresetProfile: Codable, Equatable, Sendable {
    public enum Category: String, Codable, Equatable, Sendable {
        case microScale
        case mechanical
        case product
        case interior
        case building
        case urban
        case site
        case regional
    }

    public let preset: WorkspaceScalePreset
    public let title: String
    public let category: Category
    public let useCaseTitle: String
    public let displayUnit: LengthDisplayUnit
    public let displayUnitSymbol: String
    public let minorTickMeters: Double
    public let majorTickMeters: Double
    public let visibleSpanMeters: Double
    public let comfortableModelSpanLowerMeters: Double
    public let comfortableModelSpanUpperMeters: Double
    public let minorTickTitle: String
    public let majorTickTitle: String
    public let visibleSpanTitle: String
    public let comfortableModelSpanTitle: String
    public let agentGuidance: String

    public init(preset: WorkspaceScalePreset) {
        let ruler = preset.rulerConfiguration.normalizedForWorkspaceScale()
        let visibleSpan = ruler.visibleSpanMeters
        let lower = visibleSpan * WorkspaceScalePreset.minimumComfortableModelSpanRatio
        let upper = visibleSpan * WorkspaceScalePreset.maximumComfortableModelSpanRatio
        self.preset = preset
        self.title = preset.title
        self.category = preset.scaleCategory
        self.useCaseTitle = preset.useCaseTitle
        self.displayUnit = ruler.displayUnit
        self.displayUnitSymbol = ruler.displayUnit.symbol
        self.minorTickMeters = ruler.minorTickMeters
        self.majorTickMeters = ruler.majorTickMeters
        self.visibleSpanMeters = visibleSpan
        self.comfortableModelSpanLowerMeters = lower
        self.comfortableModelSpanUpperMeters = upper
        self.minorTickTitle = Self.lengthTitle(
            ruler.minorTickMeters,
            preferredUnit: ruler.displayUnit
        )
        self.majorTickTitle = Self.lengthTitle(
            ruler.majorTickMeters,
            preferredUnit: ruler.displayUnit
        )
        self.visibleSpanTitle = Self.lengthTitle(visibleSpan, preferredUnit: ruler.displayUnit)
        self.comfortableModelSpanTitle = Self.comfortableModelSpanTitle(
            lowerMeters: lower,
            upperMeters: upper,
            preferredUnit: ruler.displayUnit
        )
        self.agentGuidance = [
            "\(preset.rawValue): \(preset.title)",
            preset.useCaseTitle,
            "visible span \(self.visibleSpanTitle)",
            "comfortable model span \(self.comfortableModelSpanTitle)",
            "minor grid \(self.minorTickTitle)",
            "major grid \(self.majorTickTitle).",
        ].joined(separator: ", ")
    }

    public var menuTitle: String {
        "\(title) · \(visibleSpanTitle)"
    }

    public var summary: String {
        "\(title), \(useCaseTitle), unit \(displayUnitSymbol), minor \(minorTickTitle), major \(majorTickTitle), visible \(visibleSpanTitle), comfortable model span \(comfortableModelSpanTitle)."
    }

    private static func lengthTitle(
        _ meters: Double,
        preferredUnit: LengthDisplayUnit
    ) -> String {
        let unit = preferredUnit.readableUnit(forMeters: meters)
        return LengthDisplayText.lengthString(
            fromMeters: meters,
            unit: unit,
            usesArchitecturalFeet: true
        )
    }

    private static func comfortableModelSpanTitle(
        lowerMeters: Double,
        upperMeters: Double,
        preferredUnit: LengthDisplayUnit
    ) -> String {
        "\(lengthTitle(lowerMeters, preferredUnit: preferredUnit)) to \(lengthTitle(upperMeters, preferredUnit: preferredUnit))"
    }
}

public extension WorkspaceScalePreset {
    static var minimumComfortableModelSpanRatio: Double {
        0.01
    }

    static var maximumComfortableModelSpanRatio: Double {
        0.80
    }

    static var profiles: [WorkspaceScalePresetProfile] {
        allCases.map(\.profile)
    }

    var profile: WorkspaceScalePresetProfile {
        WorkspaceScalePresetProfile(preset: self)
    }

    var scaleCategory: WorkspaceScalePresetProfile.Category {
        switch self {
        case .microFabrication:
            .microScale
        case .precisionMechanical:
            .mechanical
        case .productDesign:
            .product
        case .roomInterior:
            .interior
        case .architecture, .architectureImperial:
            .building
        case .urbanPlanning:
            .urban
        case .sitePlanning, .sitePlanningImperial:
            .site
        case .regionalPlanning:
            .regional
        }
    }

    var useCaseTitle: String {
        switch self {
        case .microFabrication:
            "MEMS, watch-scale, and sub-millimeter fabrication"
        case .precisionMechanical:
            "precision parts, fasteners, and small mechanisms"
        case .productDesign:
            "desktop products, fixtures, and printable objects"
        case .roomInterior:
            "rooms, furniture layouts, and interior assemblies"
        case .architecture:
            "buildings, levels, rooms, and architectural components"
        case .architectureImperial:
            "building-scale work using feet and architectural notation"
        case .urbanPlanning:
            "urban districts, campuses, streetscape, and large site coordination"
        case .sitePlanning:
            "site, campus, and civil-scale coordination"
        case .regionalPlanning:
            "regional context, infrastructure corridors, and kilometer-scale terrain"
        case .sitePlanningImperial:
            "site and civil-scale work using feet"
        }
    }
}
