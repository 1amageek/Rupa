import SwiftCAD
import RupaCoreTypes

public struct CurveAnalysisResult: Codable, Equatable, Sendable {
    public struct Counts: Codable, Equatable, Sendable {
        public var curveCount: Int
        public var sampleCount: Int
        public var continuityJoinCount: Int

        public init(
            curveCount: Int = 0,
            sampleCount: Int = 0,
            continuityJoinCount: Int = 0
        ) {
            self.curveCount = curveCount
            self.sampleCount = sampleCount
            self.continuityJoinCount = continuityJoinCount
        }
    }

    public enum CurveKind: String, Codable, Equatable, Sendable {
        case line
        case circle
        case arc
        case spline
    }

    public enum ContinuityLevel: String, Codable, Equatable, Sendable {
        case disconnected
        case g0
        case g1
        case g2
    }

    public enum ContinuityJoinKind: String, Codable, Equatable, Sendable {
        case internalSplineKnot
        case constrainedEndpoint
    }

    public struct CurveEntry: Codable, Equatable, Sendable {
        public var sourceFeatureID: String
        public var sourceFeatureName: String?
        public var sceneNodeID: String?
        public var entityID: String
        public var curveKind: CurveKind
        public var selectionComponentID: String?
        public var samples: [CurveEvaluationSample]
        public var maxAbsCurvature: Double
        public var maxAbsCurvatureDisplayValue: Double
        public var approximateLength: Double
        public var approximateLengthDisplayValue: Double
        public var displayUnitSymbol: String
        public var pointDisplayScale: Double
        public var curvatureDisplayUnitSymbol: String
        public var curvatureDisplayScale: Double

        private enum CodingKeys: String, CodingKey {
            case sourceFeatureID
            case sourceFeatureName
            case sceneNodeID
            case entityID
            case curveKind
            case selectionComponentID
            case samples
            case maxAbsCurvature
            case maxAbsCurvatureDisplayValue
            case approximateLength
            case approximateLengthDisplayValue
            case displayUnitSymbol
            case pointDisplayScale
            case curvatureDisplayUnitSymbol
            case curvatureDisplayScale
        }

        public init(
            sourceFeatureID: String,
            sourceFeatureName: String?,
            sceneNodeID: String?,
            entityID: String,
            curveKind: CurveKind,
            selectionComponentID: String?,
            samples: [CurveEvaluationSample],
            maxAbsCurvature: Double,
            approximateLength: Double,
            maxAbsCurvatureDisplayValue: Double? = nil,
            approximateLengthDisplayValue: Double? = nil,
            displayUnitSymbol: String? = nil,
            pointDisplayScale: Double? = nil,
            curvatureDisplayUnitSymbol: String? = nil,
            curvatureDisplayScale: Double? = nil
        ) {
            self.sourceFeatureID = sourceFeatureID
            self.sourceFeatureName = sourceFeatureName
            self.sceneNodeID = sceneNodeID
            self.entityID = entityID
            self.curveKind = curveKind
            self.selectionComponentID = selectionComponentID
            self.samples = samples
            self.maxAbsCurvature = maxAbsCurvature
            self.maxAbsCurvatureDisplayValue = maxAbsCurvatureDisplayValue ?? maxAbsCurvature
            self.approximateLength = approximateLength
            self.approximateLengthDisplayValue = approximateLengthDisplayValue ?? approximateLength
            self.displayUnitSymbol = displayUnitSymbol ?? LengthDisplayUnit.meter.symbol
            self.pointDisplayScale = pointDisplayScale ?? 1.0
            self.curvatureDisplayUnitSymbol = curvatureDisplayUnitSymbol ?? "1/\(LengthDisplayUnit.meter.symbol)"
            self.curvatureDisplayScale = curvatureDisplayScale ?? 1.0
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let samples = try container.decode([CurveEvaluationSample].self, forKey: .samples)
            let maxAbsCurvature = try container.decode(Double.self, forKey: .maxAbsCurvature)
            let approximateLength = try container.decode(Double.self, forKey: .approximateLength)
            self.init(
                sourceFeatureID: try container.decode(String.self, forKey: .sourceFeatureID),
                sourceFeatureName: try container.decodeIfPresent(String.self, forKey: .sourceFeatureName),
                sceneNodeID: try container.decodeIfPresent(String.self, forKey: .sceneNodeID),
                entityID: try container.decode(String.self, forKey: .entityID),
                curveKind: try container.decode(CurveKind.self, forKey: .curveKind),
                selectionComponentID: try container.decodeIfPresent(
                    String.self,
                    forKey: .selectionComponentID
                ),
                samples: samples,
                maxAbsCurvature: maxAbsCurvature,
                approximateLength: approximateLength,
                maxAbsCurvatureDisplayValue: try container.decodeIfPresent(
                    Double.self,
                    forKey: .maxAbsCurvatureDisplayValue
                ),
                approximateLengthDisplayValue: try container.decodeIfPresent(
                    Double.self,
                    forKey: .approximateLengthDisplayValue
                ),
                displayUnitSymbol: try container.decodeIfPresent(
                    String.self,
                    forKey: .displayUnitSymbol
                ),
                pointDisplayScale: try container.decodeIfPresent(
                    Double.self,
                    forKey: .pointDisplayScale
                ),
                curvatureDisplayUnitSymbol: try container.decodeIfPresent(
                    String.self,
                    forKey: .curvatureDisplayUnitSymbol
                ),
                curvatureDisplayScale: try container.decodeIfPresent(
                    Double.self,
                    forKey: .curvatureDisplayScale
                )
            )
        }

        public func displayed(in unit: LengthDisplayUnit) -> CurveEntry {
            CurveEntry(
                sourceFeatureID: sourceFeatureID,
                sourceFeatureName: sourceFeatureName,
                sceneNodeID: sceneNodeID,
                entityID: entityID,
                curveKind: curveKind,
                selectionComponentID: selectionComponentID,
                samples: samples,
                maxAbsCurvature: maxAbsCurvature,
                approximateLength: approximateLength,
                maxAbsCurvatureDisplayValue: maxAbsCurvature * unit.metersPerUnit,
                approximateLengthDisplayValue: unit.value(fromMeters: approximateLength),
                displayUnitSymbol: unit.symbol,
                pointDisplayScale: unit.value(fromMeters: 1.0),
                curvatureDisplayUnitSymbol: "1/\(unit.symbol)",
                curvatureDisplayScale: unit.metersPerUnit
            )
        }
    }

    public struct ContinuityJoin: Codable, Equatable, Sendable {
        public var sourceFeatureID: String
        public var joinKind: ContinuityJoinKind
        public var firstEntityID: String
        public var firstReference: String
        public var firstParameter: Double
        public var secondEntityID: String
        public var secondReference: String
        public var secondParameter: Double
        public var constraintKinds: [String]
        public var requiredContinuity: ContinuityLevel?
        public var continuity: ContinuityLevel
        public var positionGap: Double
        public var positionGapDisplayValue: Double
        public var tangentAngle: Double?
        public var tangentAngleDegrees: Double?
        public var curvatureGap: Double?
        public var curvatureGapDisplayValue: Double?
        public var displayUnitSymbol: String
        public var curvatureDisplayUnitSymbol: String

        private enum CodingKeys: String, CodingKey {
            case sourceFeatureID
            case joinKind
            case firstEntityID
            case firstReference
            case firstParameter
            case secondEntityID
            case secondReference
            case secondParameter
            case constraintKinds
            case requiredContinuity
            case continuity
            case positionGap
            case positionGapDisplayValue
            case tangentAngle
            case tangentAngleDegrees
            case curvatureGap
            case curvatureGapDisplayValue
            case displayUnitSymbol
            case curvatureDisplayUnitSymbol
        }

        public init(
            sourceFeatureID: String,
            joinKind: ContinuityJoinKind,
            firstEntityID: String,
            firstReference: String,
            firstParameter: Double,
            secondEntityID: String,
            secondReference: String,
            secondParameter: Double,
            constraintKinds: [String],
            requiredContinuity: ContinuityLevel?,
            continuity: ContinuityLevel,
            positionGap: Double,
            tangentAngle: Double?,
            curvatureGap: Double?,
            positionGapDisplayValue: Double? = nil,
            tangentAngleDegrees: Double? = nil,
            curvatureGapDisplayValue: Double? = nil,
            displayUnitSymbol: String? = nil,
            curvatureDisplayUnitSymbol: String? = nil
        ) {
            self.sourceFeatureID = sourceFeatureID
            self.joinKind = joinKind
            self.firstEntityID = firstEntityID
            self.firstReference = firstReference
            self.firstParameter = firstParameter
            self.secondEntityID = secondEntityID
            self.secondReference = secondReference
            self.secondParameter = secondParameter
            self.constraintKinds = constraintKinds
            self.requiredContinuity = requiredContinuity
            self.continuity = continuity
            self.positionGap = positionGap
            self.positionGapDisplayValue = positionGapDisplayValue ?? positionGap
            self.tangentAngle = tangentAngle
            self.tangentAngleDegrees = tangentAngleDegrees ?? tangentAngle.map {
                $0 * 180.0 / Double.pi
            }
            self.curvatureGap = curvatureGap
            self.curvatureGapDisplayValue = curvatureGapDisplayValue ?? curvatureGap
            self.displayUnitSymbol = displayUnitSymbol ?? LengthDisplayUnit.meter.symbol
            self.curvatureDisplayUnitSymbol = curvatureDisplayUnitSymbol ?? "1/\(LengthDisplayUnit.meter.symbol)"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let positionGap = try container.decode(Double.self, forKey: .positionGap)
            let tangentAngle = try container.decodeIfPresent(Double.self, forKey: .tangentAngle)
            let curvatureGap = try container.decodeIfPresent(Double.self, forKey: .curvatureGap)
            self.init(
                sourceFeatureID: try container.decode(String.self, forKey: .sourceFeatureID),
                joinKind: try container.decode(ContinuityJoinKind.self, forKey: .joinKind),
                firstEntityID: try container.decode(String.self, forKey: .firstEntityID),
                firstReference: try container.decode(String.self, forKey: .firstReference),
                firstParameter: try container.decode(Double.self, forKey: .firstParameter),
                secondEntityID: try container.decode(String.self, forKey: .secondEntityID),
                secondReference: try container.decode(String.self, forKey: .secondReference),
                secondParameter: try container.decode(Double.self, forKey: .secondParameter),
                constraintKinds: try container.decode([String].self, forKey: .constraintKinds),
                requiredContinuity: try container.decodeIfPresent(
                    ContinuityLevel.self,
                    forKey: .requiredContinuity
                ),
                continuity: try container.decode(ContinuityLevel.self, forKey: .continuity),
                positionGap: positionGap,
                tangentAngle: tangentAngle,
                curvatureGap: curvatureGap,
                positionGapDisplayValue: try container.decodeIfPresent(
                    Double.self,
                    forKey: .positionGapDisplayValue
                ),
                tangentAngleDegrees: try container.decodeIfPresent(
                    Double.self,
                    forKey: .tangentAngleDegrees
                ),
                curvatureGapDisplayValue: try container.decodeIfPresent(
                    Double.self,
                    forKey: .curvatureGapDisplayValue
                ),
                displayUnitSymbol: try container.decodeIfPresent(
                    String.self,
                    forKey: .displayUnitSymbol
                ),
                curvatureDisplayUnitSymbol: try container.decodeIfPresent(
                    String.self,
                    forKey: .curvatureDisplayUnitSymbol
                )
            )
        }

        public func displayed(in unit: LengthDisplayUnit) -> ContinuityJoin {
            ContinuityJoin(
                sourceFeatureID: sourceFeatureID,
                joinKind: joinKind,
                firstEntityID: firstEntityID,
                firstReference: firstReference,
                firstParameter: firstParameter,
                secondEntityID: secondEntityID,
                secondReference: secondReference,
                secondParameter: secondParameter,
                constraintKinds: constraintKinds,
                requiredContinuity: requiredContinuity,
                continuity: continuity,
                positionGap: positionGap,
                tangentAngle: tangentAngle,
                curvatureGap: curvatureGap,
                positionGapDisplayValue: unit.value(fromMeters: positionGap),
                tangentAngleDegrees: tangentAngle.map { $0 * 180.0 / Double.pi },
                curvatureGapDisplayValue: curvatureGap.map { $0 * unit.metersPerUnit },
                displayUnitSymbol: unit.symbol,
                curvatureDisplayUnitSymbol: "1/\(unit.symbol)"
            )
        }
    }

    public var displayUnit: LengthDisplayUnit
    public var displayUnitSymbol: String
    public var counts: Counts
    public var curves: [CurveEntry]
    public var continuityJoins: [ContinuityJoin]
    public var diagnostics: [EditorDiagnostic]

    private enum CodingKeys: String, CodingKey {
        case displayUnit
        case displayUnitSymbol
        case counts
        case curves
        case continuityJoins
        case diagnostics
    }

    public init(
        displayUnit: LengthDisplayUnit,
        counts: Counts = Counts(),
        curves: [CurveEntry] = [],
        continuityJoins: [ContinuityJoin] = [],
        diagnostics: [EditorDiagnostic] = []
    ) {
        self.displayUnit = displayUnit
        self.displayUnitSymbol = displayUnit.symbol
        self.counts = counts
        self.curves = curves.map { $0.displayed(in: displayUnit) }
        self.continuityJoins = continuityJoins.map { $0.displayed(in: displayUnit) }
        self.diagnostics = diagnostics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let displayUnit = try container.decode(LengthDisplayUnit.self, forKey: .displayUnit)
        self.init(
            displayUnit: displayUnit,
            counts: try container.decode(Counts.self, forKey: .counts),
            curves: try container.decode([CurveEntry].self, forKey: .curves),
            continuityJoins: try container.decode(
                [ContinuityJoin].self,
                forKey: .continuityJoins
            ),
            diagnostics: try container.decodeIfPresent(
                [EditorDiagnostic].self,
                forKey: .diagnostics
            ) ?? []
        )
    }
}
