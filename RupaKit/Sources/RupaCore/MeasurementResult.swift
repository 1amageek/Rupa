import Foundation

public struct MeasurementResult: Codable, Equatable, Sendable {
    public var scope: Scope
    public var displayUnit: LengthDisplayUnit
    public var counts: Counts
    public var bounds: Bounds?
    public var totals: Totals
    public var profiles: [Profile]
    public var solids: [Solid]
    public var diagnostics: [EditorDiagnostic]

    public init(
        scope: Scope = .document,
        displayUnit: LengthDisplayUnit,
        counts: Counts = Counts(),
        bounds: Bounds? = nil,
        totals: Totals = Totals(),
        profiles: [Profile] = [],
        solids: [Solid] = [],
        diagnostics: [EditorDiagnostic] = []
    ) {
        self.scope = scope
        self.displayUnit = displayUnit
        self.counts = counts
        self.bounds = bounds
        self.totals = totals
        self.profiles = profiles
        self.solids = solids
        self.diagnostics = diagnostics
    }

    public var message: String {
        let title = switch scope {
        case .document:
            "Measurement summary"
        case .selection:
            "Selection measurement"
        }
        let volume = formatted(totals.solidVolumeCubicMeters, exponent: 3)
        let area = formatted(totals.profileAreaSquareMeters, exponent: 2)
        if let bounds {
            return "\(title): \(counts.sourceFeatures) source features, \(counts.solids) solids, \(area) \(displayUnit.symbol)^2 profile area, \(volume) \(displayUnit.symbol)^3 solid volume, \(bounds.formattedSize(in: displayUnit)) bounds."
        }
        return "\(title): \(counts.sourceFeatures) source features, \(counts.solids) solids, \(area) \(displayUnit.symbol)^2 profile area, \(volume) \(displayUnit.symbol)^3 solid volume."
    }

    private func formatted(_ metersValue: Double, exponent: Int) -> String {
        let divisor = pow(displayUnit.metersPerUnit, Double(exponent))
        let displayValue = metersValue / divisor
        return String(format: "%.6g", displayValue)
    }
}

public extension MeasurementResult {
    enum Scope: String, Codable, Sendable {
        case document
        case selection
    }

    struct Counts: Codable, Equatable, Sendable {
        public var sourceFeatures: Int
        public var sketches: Int
        public var sketchPrimitives: Int
        public var profiles: Int
        public var solids: Int

        public init(
            sourceFeatures: Int = 0,
            sketches: Int = 0,
            sketchPrimitives: Int = 0,
            profiles: Int = 0,
            solids: Int = 0
        ) {
            self.sourceFeatures = sourceFeatures
            self.sketches = sketches
            self.sketchPrimitives = sketchPrimitives
            self.profiles = profiles
            self.solids = solids
        }
    }

    struct Bounds: Codable, Equatable, Sendable {
        public var minX: Double
        public var minY: Double
        public var minZ: Double
        public var maxX: Double
        public var maxY: Double
        public var maxZ: Double

        public init(
            minX: Double,
            minY: Double,
            minZ: Double,
            maxX: Double,
            maxY: Double,
            maxZ: Double
        ) {
            self.minX = minX
            self.minY = minY
            self.minZ = minZ
            self.maxX = maxX
            self.maxY = maxY
            self.maxZ = maxZ
        }

        public var sizeX: Double {
            maxX - minX
        }

        public var sizeY: Double {
            maxY - minY
        }

        public var sizeZ: Double {
            maxZ - minZ
        }

        public func formattedSize(in unit: LengthDisplayUnit) -> String {
            let x = unit.value(fromMeters: sizeX)
            let y = unit.value(fromMeters: sizeY)
            let z = unit.value(fromMeters: sizeZ)
            return String(format: "%.6g x %.6g x %.6g %@", x, y, z, unit.symbol)
        }
    }

    struct Totals: Codable, Equatable, Sendable {
        public var profileAreaSquareMeters: Double
        public var solidVolumeCubicMeters: Double

        public init(
            profileAreaSquareMeters: Double = 0.0,
            solidVolumeCubicMeters: Double = 0.0
        ) {
            self.profileAreaSquareMeters = profileAreaSquareMeters
            self.solidVolumeCubicMeters = solidVolumeCubicMeters
        }
    }

    struct Profile: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case lineLoop
            case circle
        }

        public var featureID: String
        public var featureName: String?
        public var kind: Kind
        public var areaSquareMeters: Double
        public var bounds: Bounds

        public init(
            featureID: String,
            featureName: String?,
            kind: Kind,
            areaSquareMeters: Double,
            bounds: Bounds
        ) {
            self.featureID = featureID
            self.featureName = featureName
            self.kind = kind
            self.areaSquareMeters = areaSquareMeters
            self.bounds = bounds
        }
    }

    struct Solid: Codable, Equatable, Sendable {
        public var featureID: String
        public var featureName: String?
        public var sourceFeatureID: String
        public var sourceFeatureName: String?
        public var heightMeters: Double
        public var volumeCubicMeters: Double
        public var bounds: Bounds

        public init(
            featureID: String,
            featureName: String?,
            sourceFeatureID: String,
            sourceFeatureName: String?,
            heightMeters: Double,
            volumeCubicMeters: Double,
            bounds: Bounds
        ) {
            self.featureID = featureID
            self.featureName = featureName
            self.sourceFeatureID = sourceFeatureID
            self.sourceFeatureName = sourceFeatureName
            self.heightMeters = heightMeters
            self.volumeCubicMeters = volumeCubicMeters
            self.bounds = bounds
        }
    }
}
