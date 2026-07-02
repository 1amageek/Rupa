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
        if let bounds {
            return "\(title): \(counts.sourceFeatures) source features, \(counts.solids) solids, \(counts.sheets) sheets, \(area) \(displayUnit.symbol)^2 profile area, \(sheetArea) \(displayUnit.symbol)^2 sheet area, \(volume) \(displayUnit.symbol)^3 solid volume, \(bounds.formattedSize(in: displayUnit)) bounds."
        }
        return "\(title): \(counts.sourceFeatures) source features, \(counts.solids) solids, \(counts.sheets) sheets, \(area) \(displayUnit.symbol)^2 profile area, \(sheetArea) \(displayUnit.symbol)^2 sheet area, \(volume) \(displayUnit.symbol)^3 solid volume."
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
        public var volumeCubicMeters: Double
        public var surfaceAreaSquareMeters: Double?
        public var bounds: Bounds

        public init(
            featureID: String,
            featureName: String?,
            sourceFeatureID: String,
            sourceFeatureName: String?,
            linearDimensions: [LinearDimension],
            volumeCubicMeters: Double,
            surfaceAreaSquareMeters: Double? = nil,
            bounds: Bounds
        ) {
            self.featureID = featureID
            self.featureName = featureName
            self.sourceFeatureID = sourceFeatureID
            self.sourceFeatureName = sourceFeatureName
            self.linearDimensions = linearDimensions
            self.volumeCubicMeters = volumeCubicMeters
            self.surfaceAreaSquareMeters = surfaceAreaSquareMeters
            self.bounds = bounds
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
        public var surfaceAreaSquareMeters: Double
        public var bounds: Bounds

        public init(
            featureID: String,
            featureName: String?,
            sourceFeatureID: String,
            sourceFeatureName: String?,
            linearDimensions: [LinearDimension],
            surfaceAreaSquareMeters: Double,
            bounds: Bounds
        ) {
            self.featureID = featureID
            self.featureName = featureName
            self.sourceFeatureID = sourceFeatureID
            self.sourceFeatureName = sourceFeatureName
            self.linearDimensions = linearDimensions
            self.surfaceAreaSquareMeters = surfaceAreaSquareMeters
            self.bounds = bounds
        }
    }
}
