import Foundation
import SwiftCAD
import RupaCoreTypes

public struct MeasurementResult: Codable, Equatable, Sendable {
    public var scope: Scope
    public var displayUnit: LengthDisplayUnit
    public var counts: Counts
    public var bounds: Bounds?
    public var totals: Totals
    public var profiles: [Profile]
    public var solids: [Solid]
    public var sheets: [Sheet]
    public var diagnostics: [EditorDiagnostic]
    public var workspacePrecision: WorkspacePrecisionReport?
    public var workspaceScaleRecommendation: WorkspaceScaleRecommendation?

    public init(
        scope: Scope = .document,
        displayUnit: LengthDisplayUnit,
        counts: Counts = Counts(),
        bounds: Bounds? = nil,
        totals: Totals = Totals(),
        profiles: [Profile] = [],
        solids: [Solid] = [],
        sheets: [Sheet] = [],
        diagnostics: [EditorDiagnostic] = [],
        workspacePrecision: WorkspacePrecisionReport? = nil,
        workspaceScaleRecommendation: WorkspaceScaleRecommendation? = nil
    ) {
        self.scope = scope
        self.displayUnit = displayUnit
        self.counts = counts
        self.bounds = bounds
        self.totals = totals
        self.profiles = profiles
        self.solids = solids
        self.sheets = sheets
        self.diagnostics = diagnostics
        self.workspacePrecision = workspacePrecision
        self.workspaceScaleRecommendation = workspaceScaleRecommendation
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
        let sheetArea = formatted(totals.sheetAreaSquareMeters, exponent: 2)
        let provenance = totalsProvenance
        let profileAreaLabel = provenance.profileArea.isApproximate
            ? "profile area (approximate)"
            : "profile area"
        let sheetAreaLabel = provenance.sheetArea.isApproximate
            ? "sheet area (approximate)"
            : "sheet area"
        let solidVolumeLabel = provenance.solidVolume.isApproximate
            ? "solid volume (approximate)"
            : "solid volume"
        if let bounds {
            return "\(title): \(counts.sourceFeatures) source features, \(counts.solids) solids, \(counts.sheets) sheets, \(area) \(displayUnit.symbol)^2 \(profileAreaLabel), \(sheetArea) \(displayUnit.symbol)^2 \(sheetAreaLabel), \(volume) \(displayUnit.symbol)^3 \(solidVolumeLabel), \(bounds.formattedSize(in: displayUnit)) bounds."
        }
        return "\(title): \(counts.sourceFeatures) source features, \(counts.solids) solids, \(counts.sheets) sheets, \(area) \(displayUnit.symbol)^2 \(profileAreaLabel), \(sheetArea) \(displayUnit.symbol)^2 \(sheetAreaLabel), \(volume) \(displayUnit.symbol)^3 \(solidVolumeLabel)."
    }

    public var totalsProvenance: TotalsProvenance {
        TotalsProvenance(
            profileArea: MeasurementProvenance(methods: profiles.map(\.areaMethod)),
            sheetArea: MeasurementProvenance(methods: sheets.map(\.surfaceAreaMethod)),
            solidVolume: MeasurementProvenance(methods: solids.map(\.volumeMethod))
        )
    }

    private func formatted(_ metersValue: Double, exponent: Int) -> String {
        MeasurementDisplayNumberText.valueString(
            fromMetersValue: metersValue,
            unit: displayUnit,
            exponent: exponent
        )
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
        public var sheets: Int

        public init(
            sourceFeatures: Int = 0,
            sketches: Int = 0,
            sketchPrimitives: Int = 0,
            profiles: Int = 0,
            solids: Int = 0,
            sheets: Int = 0
        ) {
            self.sourceFeatures = sourceFeatures
            self.sketches = sketches
            self.sketchPrimitives = sketchPrimitives
            self.profiles = profiles
            self.solids = solids
            self.sheets = sheets
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

        public var center: Point3D {
            Point3D(
                x: (minX + maxX) * 0.5,
                y: (minY + maxY) * 0.5,
                z: (minZ + maxZ) * 0.5
            )
        }

        public var maximumAbsoluteCoordinate: Double {
            [
                minX,
                minY,
                minZ,
                maxX,
                maxY,
                maxZ,
            ].map(abs).max() ?? 0.0
        }

        public var maximumSpan: Double {
            max(abs(sizeX), abs(sizeY), abs(sizeZ))
        }

        public var maximumDistanceFromOrigin: Double {
            [
                hypot(hypot(minX, minY), minZ),
                hypot(hypot(minX, minY), maxZ),
                hypot(hypot(minX, maxY), minZ),
                hypot(hypot(minX, maxY), maxZ),
                hypot(hypot(maxX, minY), minZ),
                hypot(hypot(maxX, minY), maxZ),
                hypot(hypot(maxX, maxY), minZ),
                hypot(hypot(maxX, maxY), maxZ),
            ].max() ?? 0.0
        }

        public func formattedSize(in unit: LengthDisplayUnit) -> String {
            if unit == .foot {
                let x = LengthDisplayText.lengthString(fromMeters: sizeX, unit: unit)
                let y = LengthDisplayText.lengthString(fromMeters: sizeY, unit: unit)
                let z = LengthDisplayText.lengthString(fromMeters: sizeZ, unit: unit)
                return "\(x) x \(y) x \(z)"
            }
            let x = LengthDisplayText.readableLengthString(fromMeters: sizeX, preferredUnit: unit)
            let y = LengthDisplayText.readableLengthString(fromMeters: sizeY, preferredUnit: unit)
            let z = LengthDisplayText.readableLengthString(fromMeters: sizeZ, preferredUnit: unit)
            return "\(x) x \(y) x \(z)"
        }
    }

    enum MeasurementMethod: String, Codable, Equatable, Hashable, Sendable {
        /// Closed-form evaluation from authored parametric inputs.
        case analytic
        /// Exact or certified evaluation from B-rep topology and geometry.
        case exactBRep
        /// Approximation computed from samples of an exact or authored curve.
        case sampledCurve
        /// Approximation computed from the evaluated display tessellation.
        case tessellatedMesh
        /// A persisted legacy value whose original method was not recorded.
        case legacyUnspecified

        public var isApproximate: Bool {
            switch self {
            case .analytic, .exactBRep:
                false
            case .sampledCurve, .tessellatedMesh, .legacyUnspecified:
                true
            }
        }
    }

    struct MeasurementProvenance: Equatable, Sendable {
        public let methods: [MeasurementMethod]

        public init(methods: [MeasurementMethod]) {
            self.methods = Array(Set(methods)).sorted { $0.rawValue < $1.rawValue }
        }

        public var isApproximate: Bool {
            methods.contains { $0.isApproximate }
        }
    }

    struct TotalsProvenance: Equatable, Sendable {
        public let profileArea: MeasurementProvenance
        public let sheetArea: MeasurementProvenance
        public let solidVolume: MeasurementProvenance

        public init(
            profileArea: MeasurementProvenance,
            sheetArea: MeasurementProvenance,
            solidVolume: MeasurementProvenance
        ) {
            self.profileArea = profileArea
            self.sheetArea = sheetArea
            self.solidVolume = solidVolume
        }
    }

    /// A measurement value and the provenance required to interpret it.
    struct Measured<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
        public let value: Value
        public let method: MeasurementMethod

        public init(value: Value, method: MeasurementMethod) {
            self.value = value
            self.method = method
        }

        private enum CodingKeys: String, CodingKey {
            case value
            case method
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try container.validateOnlyExpectedKeys([.value, .method], in: decoder)
            value = try container.decode(Value.self, forKey: .value)
            method = try container.decode(MeasurementMethod.self, forKey: .method)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(value, forKey: .value)
            try container.encode(method, forKey: .method)
        }
    }

    struct Totals: Codable, Equatable, Sendable {
        public var profileAreaSquareMeters: Double
        public var sheetAreaSquareMeters: Double
        public var solidVolumeCubicMeters: Double

        public init(
            profileAreaSquareMeters: Double = 0.0,
            sheetAreaSquareMeters: Double = 0.0,
            solidVolumeCubicMeters: Double = 0.0
        ) {
            self.profileAreaSquareMeters = profileAreaSquareMeters
            self.sheetAreaSquareMeters = sheetAreaSquareMeters
            self.solidVolumeCubicMeters = solidVolumeCubicMeters
        }
    }

    struct Profile: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case lineLoop
            case curveLoop
            case circle
        }

        public var featureID: String
        public var featureName: String?
        public var kind: Kind
        public var area: Measured<Double>
        public var measuredBounds: Measured<Bounds>

        public var areaSquareMeters: Double {
            area.value
        }

        public var areaMethod: MeasurementMethod {
            area.method
        }

        public var bounds: Bounds {
            measuredBounds.value
        }

        public var boundsMethod: MeasurementMethod {
            measuredBounds.method
        }

        public init(
            featureID: String,
            featureName: String?,
            kind: Kind,
            area: Measured<Double>,
            bounds: Measured<Bounds>
        ) {
            self.featureID = featureID
            self.featureName = featureName
            self.kind = kind
            self.area = area
            self.measuredBounds = bounds
        }

        private enum CodingKeys: String, CodingKey {
            case featureID
            case featureName
            case kind
            case area
            case measuredBounds
            case areaSquareMeters
            case bounds
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try container.validateOnlyExpectedKeys(
                [.featureID, .featureName, .kind, .area, .measuredBounds, .areaSquareMeters, .bounds],
                in: decoder
            )
            let usesCanonicalMeasurements = container.contains(.area)
                || container.contains(.measuredBounds)
            let usesLegacyMeasurements = container.contains(.areaSquareMeters)
                || container.contains(.bounds)
            guard usesCanonicalMeasurements == false || usesLegacyMeasurements == false else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Profile measurements cannot mix canonical measured values with legacy fields."
                    )
                )
            }
            featureID = try container.decode(String.self, forKey: .featureID)
            featureName = try container.decodeIfPresent(String.self, forKey: .featureName)
            kind = try container.decode(Kind.self, forKey: .kind)
            if usesCanonicalMeasurements {
                area = try container.decode(Measured<Double>.self, forKey: .area)
                measuredBounds = try container.decode(Measured<Bounds>.self, forKey: .measuredBounds)
            } else {
                area = Measured(
                    value: try container.decode(Double.self, forKey: .areaSquareMeters),
                    method: .legacyUnspecified
                )
                measuredBounds = Measured(
                    value: try container.decode(Bounds.self, forKey: .bounds),
                    method: .legacyUnspecified
                )
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(featureID, forKey: .featureID)
            try container.encodeIfPresent(featureName, forKey: .featureName)
            try container.encode(kind, forKey: .kind)
            try container.encode(area, forKey: .area)
            try container.encode(measuredBounds, forKey: .measuredBounds)
        }
    }

    struct Solid: Codable, Equatable, Sendable {
        public struct LinearDimension: Codable, Equatable, Sendable {
            public enum Kind: String, Codable, Sendable {
                case extrusionHeight
                case sweepNormalHeight
                case sweepPathLength
            }

            public var kind: Kind
            public var meters: Double

            public init(kind: Kind, meters: Double) {
                self.kind = kind
                self.meters = meters
            }
        }

        public var featureID: String
        public var featureName: String?
        public var sourceFeatureID: String
        public var sourceFeatureName: String?
        public var linearDimensions: [LinearDimension]
        public var volume: Measured<Double>
        public var surfaceArea: Measured<Double>?
        public var measuredBounds: Measured<Bounds>

        public var volumeCubicMeters: Double {
            volume.value
        }

        public var volumeMethod: MeasurementMethod {
            volume.method
        }

        public var surfaceAreaSquareMeters: Double? {
            surfaceArea?.value
        }

        public var surfaceAreaMethod: MeasurementMethod? {
            surfaceArea?.method
        }

        public var bounds: Bounds {
            measuredBounds.value
        }

        public var boundsMethod: MeasurementMethod {
            measuredBounds.method
        }

        public init(
            featureID: String,
            featureName: String?,
            sourceFeatureID: String,
            sourceFeatureName: String?,
            linearDimensions: [LinearDimension],
            volume: Measured<Double>,
            surfaceArea: Measured<Double>? = nil,
            bounds: Measured<Bounds>
        ) {
            self.featureID = featureID
            self.featureName = featureName
            self.sourceFeatureID = sourceFeatureID
            self.sourceFeatureName = sourceFeatureName
            self.linearDimensions = linearDimensions
            self.volume = volume
            self.surfaceArea = surfaceArea
            self.measuredBounds = bounds
        }

        private enum CodingKeys: String, CodingKey {
            case featureID
            case featureName
            case sourceFeatureID
            case sourceFeatureName
            case linearDimensions
            case volume
            case surfaceArea
            case measuredBounds
            case volumeCubicMeters
            case volumeMethod
            case surfaceAreaSquareMeters
            case surfaceAreaMethod
            case bounds
            case boundsMethod
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try container.validateOnlyExpectedKeys(
                [
                    .featureID,
                    .featureName,
                    .sourceFeatureID,
                    .sourceFeatureName,
                    .linearDimensions,
                    .volume,
                    .surfaceArea,
                    .measuredBounds,
                    .volumeCubicMeters,
                    .volumeMethod,
                    .surfaceAreaSquareMeters,
                    .surfaceAreaMethod,
                    .bounds,
                    .boundsMethod,
                ],
                in: decoder
            )
            let usesCanonicalMeasurements = container.contains(.volume)
                || container.contains(.surfaceArea)
                || container.contains(.measuredBounds)
            let usesLegacyMeasurements = container.contains(.volumeCubicMeters)
                || container.contains(.volumeMethod)
                || container.contains(.surfaceAreaSquareMeters)
                || container.contains(.surfaceAreaMethod)
                || container.contains(.bounds)
                || container.contains(.boundsMethod)
            guard usesCanonicalMeasurements == false || usesLegacyMeasurements == false else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Solid measurements cannot mix canonical measured values with legacy parallel fields."
                    )
                )
            }
            featureID = try container.decode(String.self, forKey: .featureID)
            featureName = try container.decodeIfPresent(String.self, forKey: .featureName)
            sourceFeatureID = try container.decode(String.self, forKey: .sourceFeatureID)
            sourceFeatureName = try container.decodeIfPresent(String.self, forKey: .sourceFeatureName)
            linearDimensions = try container.decode([LinearDimension].self, forKey: .linearDimensions)
            if usesCanonicalMeasurements {
                volume = try container.decode(Measured<Double>.self, forKey: .volume)
            } else {
                volume = Measured(
                    value: try container.decode(Double.self, forKey: .volumeCubicMeters),
                    method: try container.decodeIfPresent(
                        MeasurementMethod.self,
                        forKey: .volumeMethod
                    ) ?? .legacyUnspecified
                )
            }
            if usesCanonicalMeasurements {
                surfaceArea = try container.decodeIfPresent(
                    Measured<Double>.self,
                    forKey: .surfaceArea
                )
            } else if let value = try container.decodeIfPresent(
                Double.self,
                forKey: .surfaceAreaSquareMeters
            ) {
                surfaceArea = Measured(
                    value: value,
                    method: try container.decodeIfPresent(
                        MeasurementMethod.self,
                        forKey: .surfaceAreaMethod
                    ) ?? .legacyUnspecified
                )
            } else {
                surfaceArea = nil
            }
            if usesCanonicalMeasurements {
                measuredBounds = try container.decode(
                    Measured<Bounds>.self,
                    forKey: .measuredBounds
                )
            } else {
                measuredBounds = Measured(
                    value: try container.decode(Bounds.self, forKey: .bounds),
                    method: try container.decodeIfPresent(
                        MeasurementMethod.self,
                        forKey: .boundsMethod
                    ) ?? .legacyUnspecified
                )
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(featureID, forKey: .featureID)
            try container.encodeIfPresent(featureName, forKey: .featureName)
            try container.encode(sourceFeatureID, forKey: .sourceFeatureID)
            try container.encodeIfPresent(sourceFeatureName, forKey: .sourceFeatureName)
            try container.encode(linearDimensions, forKey: .linearDimensions)
            try container.encode(volume, forKey: .volume)
            try container.encodeIfPresent(surfaceArea, forKey: .surfaceArea)
            try container.encode(measuredBounds, forKey: .measuredBounds)
        }
    }

    struct Sheet: Codable, Equatable, Sendable {
        public struct LinearDimension: Codable, Equatable, Sendable {
            public enum Kind: String, Codable, Sendable {
                case sweepPathLength
            }

            public var kind: Kind
            public var meters: Double

            public init(kind: Kind, meters: Double) {
                self.kind = kind
                self.meters = meters
            }
        }

        public var featureID: String
        public var featureName: String?
        public var sourceFeatureID: String
        public var sourceFeatureName: String?
        public var linearDimensions: [LinearDimension]
        public var surfaceArea: Measured<Double>
        public var measuredBounds: Measured<Bounds>

        public var surfaceAreaSquareMeters: Double {
            surfaceArea.value
        }

        public var surfaceAreaMethod: MeasurementMethod {
            surfaceArea.method
        }

        public var bounds: Bounds {
            measuredBounds.value
        }

        public var boundsMethod: MeasurementMethod {
            measuredBounds.method
        }

        public init(
            featureID: String,
            featureName: String?,
            sourceFeatureID: String,
            sourceFeatureName: String?,
            linearDimensions: [LinearDimension],
            surfaceArea: Measured<Double>,
            bounds: Measured<Bounds>
        ) {
            self.featureID = featureID
            self.featureName = featureName
            self.sourceFeatureID = sourceFeatureID
            self.sourceFeatureName = sourceFeatureName
            self.linearDimensions = linearDimensions
            self.surfaceArea = surfaceArea
            self.measuredBounds = bounds
        }

        private enum CodingKeys: String, CodingKey {
            case featureID
            case featureName
            case sourceFeatureID
            case sourceFeatureName
            case linearDimensions
            case surfaceArea
            case measuredBounds
            case surfaceAreaSquareMeters
            case bounds
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try container.validateOnlyExpectedKeys(
                [
                    .featureID,
                    .featureName,
                    .sourceFeatureID,
                    .sourceFeatureName,
                    .linearDimensions,
                    .surfaceArea,
                    .measuredBounds,
                    .surfaceAreaSquareMeters,
                    .bounds,
                ],
                in: decoder
            )
            let usesCanonicalMeasurements = container.contains(.surfaceArea)
                || container.contains(.measuredBounds)
            let usesLegacyMeasurements = container.contains(.surfaceAreaSquareMeters)
                || container.contains(.bounds)
            guard usesCanonicalMeasurements == false || usesLegacyMeasurements == false else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Sheet measurements cannot mix canonical measured values with legacy fields."
                    )
                )
            }
            featureID = try container.decode(String.self, forKey: .featureID)
            featureName = try container.decodeIfPresent(String.self, forKey: .featureName)
            sourceFeatureID = try container.decode(String.self, forKey: .sourceFeatureID)
            sourceFeatureName = try container.decodeIfPresent(String.self, forKey: .sourceFeatureName)
            linearDimensions = try container.decode([LinearDimension].self, forKey: .linearDimensions)
            if usesCanonicalMeasurements {
                surfaceArea = try container.decode(Measured<Double>.self, forKey: .surfaceArea)
                measuredBounds = try container.decode(Measured<Bounds>.self, forKey: .measuredBounds)
            } else {
                surfaceArea = Measured(
                    value: try container.decode(Double.self, forKey: .surfaceAreaSquareMeters),
                    method: .legacyUnspecified
                )
                measuredBounds = Measured(
                    value: try container.decode(Bounds.self, forKey: .bounds),
                    method: .legacyUnspecified
                )
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(featureID, forKey: .featureID)
            try container.encodeIfPresent(featureName, forKey: .featureName)
            try container.encode(sourceFeatureID, forKey: .sourceFeatureID)
            try container.encodeIfPresent(sourceFeatureName, forKey: .sourceFeatureName)
            try container.encode(linearDimensions, forKey: .linearDimensions)
            try container.encode(surfaceArea, forKey: .surfaceArea)
            try container.encode(measuredBounds, forKey: .measuredBounds)
        }
    }
}
