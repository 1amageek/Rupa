import RupaCoreTypes
public struct SurfaceFrameResult: Codable, Equatable, Sendable {
    public struct Frame: Codable, Equatable, Sendable {
        public var faceID: String
        public var facePersistentNames: [String]
        public var sourceFeatureID: String?
        public var sceneNodeID: String?
        public var u: Double
        public var v: Double
        public var uDomain: SurfaceAnalysisResult.ParameterRange
        public var vDomain: SurfaceAnalysisResult.ParameterRange
        public var position: SurfaceAnalysisResult.Point
        public var tangentU: SurfaceAnalysisResult.Vector
        public var tangentV: SurfaceAnalysisResult.Vector
        public var uAxis: SurfaceAnalysisResult.Vector
        public var vAxis: SurfaceAnalysisResult.Vector
        public var normal: SurfaceAnalysisResult.Vector
        public var handedness: Double
        public var normalCurvatureU: Double
        public var normalCurvatureV: Double
        public var meanCurvature: Double
        public var gaussianCurvature: Double
        public var minimumPrincipalCurvature: Double
        public var maximumPrincipalCurvature: Double
        public var minimumPrincipalDirection: SurfaceAnalysisResult.Vector
        public var maximumPrincipalDirection: SurfaceAnalysisResult.Vector

        public init(
            faceID: String,
            facePersistentNames: [String] = [],
            sourceFeatureID: String? = nil,
            sceneNodeID: String? = nil,
            u: Double,
            v: Double,
            uDomain: SurfaceAnalysisResult.ParameterRange,
            vDomain: SurfaceAnalysisResult.ParameterRange,
            position: SurfaceAnalysisResult.Point,
            tangentU: SurfaceAnalysisResult.Vector,
            tangentV: SurfaceAnalysisResult.Vector,
            uAxis: SurfaceAnalysisResult.Vector,
            vAxis: SurfaceAnalysisResult.Vector,
            normal: SurfaceAnalysisResult.Vector,
            handedness: Double,
            normalCurvatureU: Double,
            normalCurvatureV: Double,
            meanCurvature: Double,
            gaussianCurvature: Double,
            minimumPrincipalCurvature: Double,
            maximumPrincipalCurvature: Double,
            minimumPrincipalDirection: SurfaceAnalysisResult.Vector,
            maximumPrincipalDirection: SurfaceAnalysisResult.Vector
        ) {
            self.faceID = faceID
            self.facePersistentNames = facePersistentNames
            self.sourceFeatureID = sourceFeatureID
            self.sceneNodeID = sceneNodeID
            self.u = u
            self.v = v
            self.uDomain = uDomain
            self.vDomain = vDomain
            self.position = position
            self.tangentU = tangentU
            self.tangentV = tangentV
            self.uAxis = uAxis
            self.vAxis = vAxis
            self.normal = normal
            self.handedness = handedness
            self.normalCurvatureU = normalCurvatureU
            self.normalCurvatureV = normalCurvatureV
            self.meanCurvature = meanCurvature
            self.gaussianCurvature = gaussianCurvature
            self.minimumPrincipalCurvature = minimumPrincipalCurvature
            self.maximumPrincipalCurvature = maximumPrincipalCurvature
            self.minimumPrincipalDirection = minimumPrincipalDirection
            self.maximumPrincipalDirection = maximumPrincipalDirection
        }
    }

    public var displayUnit: LengthDisplayUnit
    public var frames: [Frame]
    public var diagnostics: [EditorDiagnostic]

    public init(
        displayUnit: LengthDisplayUnit,
        frames: [Frame] = [],
        diagnostics: [EditorDiagnostic] = []
    ) {
        self.displayUnit = displayUnit
        self.frames = frames
        self.diagnostics = diagnostics
    }
}
