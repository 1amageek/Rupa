import SwiftCAD

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
        public var approximateLength: Double

        public init(
            sourceFeatureID: String,
            sourceFeatureName: String?,
            sceneNodeID: String?,
            entityID: String,
            curveKind: CurveKind,
            selectionComponentID: String?,
            samples: [CurveEvaluationSample],
            maxAbsCurvature: Double,
            approximateLength: Double
        ) {
            self.sourceFeatureID = sourceFeatureID
            self.sourceFeatureName = sourceFeatureName
            self.sceneNodeID = sceneNodeID
            self.entityID = entityID
            self.curveKind = curveKind
            self.selectionComponentID = selectionComponentID
            self.samples = samples
            self.maxAbsCurvature = maxAbsCurvature
            self.approximateLength = approximateLength
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
        public var tangentAngle: Double?
        public var curvatureGap: Double?

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
            curvatureGap: Double?
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
            self.tangentAngle = tangentAngle
            self.curvatureGap = curvatureGap
        }
    }

    public var displayUnit: LengthDisplayUnit
    public var counts: Counts
    public var curves: [CurveEntry]
    public var continuityJoins: [ContinuityJoin]
    public var diagnostics: [EditorDiagnostic]

    public init(
        displayUnit: LengthDisplayUnit,
        counts: Counts = Counts(),
        curves: [CurveEntry] = [],
        continuityJoins: [ContinuityJoin] = [],
        diagnostics: [EditorDiagnostic] = []
    ) {
        self.displayUnit = displayUnit
        self.counts = counts
        self.curves = curves
        self.continuityJoins = continuityJoins
        self.diagnostics = diagnostics
    }
}
