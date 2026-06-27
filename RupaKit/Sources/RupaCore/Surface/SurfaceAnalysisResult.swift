import RupaCoreTypes
public struct SurfaceAnalysisResult: Codable, Equatable, Sendable {
    public struct Counts: Codable, Equatable, Sendable {
        public var bSplineFaceCount: Int
        public var sampleCount: Int
        public var uCurvatureCombCount: Int
        public var vCurvatureCombCount: Int
        public var trimBoundaryCount: Int
        public var innerTrimBoundaryCount: Int
        public var openTrimBoundaryCount: Int
        public var trimBoundaryEdgeCount: Int

        public init(
            bSplineFaceCount: Int = 0,
            sampleCount: Int = 0,
            uCurvatureCombCount: Int = 0,
            vCurvatureCombCount: Int = 0,
            trimBoundaryCount: Int = 0,
            innerTrimBoundaryCount: Int = 0,
            openTrimBoundaryCount: Int = 0,
            trimBoundaryEdgeCount: Int = 0
        ) {
            self.bSplineFaceCount = bSplineFaceCount
            self.sampleCount = sampleCount
            self.uCurvatureCombCount = uCurvatureCombCount
            self.vCurvatureCombCount = vCurvatureCombCount
            self.trimBoundaryCount = trimBoundaryCount
            self.innerTrimBoundaryCount = innerTrimBoundaryCount
            self.openTrimBoundaryCount = openTrimBoundaryCount
            self.trimBoundaryEdgeCount = trimBoundaryEdgeCount
        }
    }

    public enum Direction: String, Codable, Equatable, Sendable {
        case u
        case v
    }

    public struct Point: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var z: Double

        public init(x: Double, y: Double, z: Double) {
            self.x = x
            self.y = y
            self.z = z
        }
    }

    public struct Vector: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var z: Double

        public init(x: Double, y: Double, z: Double) {
            self.x = x
            self.y = y
            self.z = z
        }
    }

    public struct ParameterRange: Codable, Equatable, Sendable {
        public var lowerBound: Double
        public var upperBound: Double

        public init(lowerBound: Double, upperBound: Double) {
            self.lowerBound = lowerBound
            self.upperBound = upperBound
        }
    }

    public struct Sample: Codable, Equatable, Sendable {
        public var u: Double
        public var v: Double
        public var position: Point
        public var normal: Vector
        public var tangentU: Vector
        public var tangentV: Vector
        public var normalCurvatureU: Double
        public var normalCurvatureV: Double
        public var meanCurvature: Double
        public var gaussianCurvature: Double
        public var minimumPrincipalCurvature: Double
        public var maximumPrincipalCurvature: Double
        public var minimumPrincipalDirection: Vector
        public var maximumPrincipalDirection: Vector

        public init(
            u: Double,
            v: Double,
            position: Point,
            normal: Vector,
            tangentU: Vector,
            tangentV: Vector,
            normalCurvatureU: Double,
            normalCurvatureV: Double,
            meanCurvature: Double,
            gaussianCurvature: Double,
            minimumPrincipalCurvature: Double,
            maximumPrincipalCurvature: Double,
            minimumPrincipalDirection: Vector,
            maximumPrincipalDirection: Vector
        ) {
            self.u = u
            self.v = v
            self.position = position
            self.normal = normal
            self.tangentU = tangentU
            self.tangentV = tangentV
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

    public struct CurvatureCombSample: Codable, Equatable, Sendable {
        public var direction: Direction
        public var u: Double
        public var v: Double
        public var position: Point
        public var normal: Vector
        public var neighborDistance: Double
        public var normalAngle: Double
        public var normalChangePerLength: Double
        public var normalCurvature: Double

        public init(
            direction: Direction,
            u: Double,
            v: Double,
            position: Point,
            normal: Vector,
            neighborDistance: Double,
            normalAngle: Double,
            normalChangePerLength: Double,
            normalCurvature: Double
        ) {
            self.direction = direction
            self.u = u
            self.v = v
            self.position = position
            self.normal = normal
            self.neighborDistance = neighborDistance
            self.normalAngle = normalAngle
            self.normalChangePerLength = normalChangePerLength
            self.normalCurvature = normalCurvature
        }
    }

    public enum TrimBoundaryRole: String, Codable, Equatable, Sendable {
        case outer
        case inner
    }

    public struct TrimBoundary: Codable, Equatable, Sendable {
        public var loopID: String
        public var role: TrimBoundaryRole
        public var points: [Point]
        public var edgePersistentNames: [String]
        public var edgeCount: Int
        public var vertexCount: Int
        public var isClosed: Bool
        public var estimatedLength: Double

        public init(
            loopID: String,
            role: TrimBoundaryRole,
            points: [Point] = [],
            edgePersistentNames: [String] = [],
            edgeCount: Int,
            vertexCount: Int,
            isClosed: Bool,
            estimatedLength: Double
        ) {
            self.loopID = loopID
            self.role = role
            self.points = points
            self.edgePersistentNames = edgePersistentNames
            self.edgeCount = edgeCount
            self.vertexCount = vertexCount
            self.isClosed = isClosed
            self.estimatedLength = estimatedLength
        }
    }

    public struct FaceAnalysis: Codable, Equatable, Sendable {
        public var faceID: String
        public var facePersistentNames: [String]
        public var edgePersistentNames: [String]
        public var trimBoundaries: [TrimBoundary]
        public var sourceFeatureID: String?
        public var sceneNodeID: String?
        public var uDegree: Int
        public var vDegree: Int
        public var uControlPointCount: Int
        public var vControlPointCount: Int
        public var uDomain: ParameterRange
        public var vDomain: ParameterRange
        public var samples: [Sample]
        public var curvatureCombs: [CurvatureCombSample]
        public var maxUNormalChangePerLength: Double
        public var maxVNormalChangePerLength: Double
        public var maxNormalAngle: Double
        public var maxAbsUNormalCurvature: Double
        public var maxAbsVNormalCurvature: Double
        public var maxAbsPrincipalCurvature: Double
        public var maxAbsGaussianCurvature: Double

        public init(
            faceID: String,
            facePersistentNames: [String] = [],
            edgePersistentNames: [String] = [],
            trimBoundaries: [TrimBoundary] = [],
            sourceFeatureID: String? = nil,
            sceneNodeID: String? = nil,
            uDegree: Int,
            vDegree: Int,
            uControlPointCount: Int,
            vControlPointCount: Int,
            uDomain: ParameterRange,
            vDomain: ParameterRange,
            samples: [Sample],
            curvatureCombs: [CurvatureCombSample],
            maxUNormalChangePerLength: Double,
            maxVNormalChangePerLength: Double,
            maxNormalAngle: Double,
            maxAbsUNormalCurvature: Double,
            maxAbsVNormalCurvature: Double,
            maxAbsPrincipalCurvature: Double,
            maxAbsGaussianCurvature: Double
        ) {
            self.faceID = faceID
            self.facePersistentNames = facePersistentNames
            self.edgePersistentNames = edgePersistentNames
            self.trimBoundaries = trimBoundaries
            self.sourceFeatureID = sourceFeatureID
            self.sceneNodeID = sceneNodeID
            self.uDegree = uDegree
            self.vDegree = vDegree
            self.uControlPointCount = uControlPointCount
            self.vControlPointCount = vControlPointCount
            self.uDomain = uDomain
            self.vDomain = vDomain
            self.samples = samples
            self.curvatureCombs = curvatureCombs
            self.maxUNormalChangePerLength = maxUNormalChangePerLength
            self.maxVNormalChangePerLength = maxVNormalChangePerLength
            self.maxNormalAngle = maxNormalAngle
            self.maxAbsUNormalCurvature = maxAbsUNormalCurvature
            self.maxAbsVNormalCurvature = maxAbsVNormalCurvature
            self.maxAbsPrincipalCurvature = maxAbsPrincipalCurvature
            self.maxAbsGaussianCurvature = maxAbsGaussianCurvature
        }
    }

    public var displayUnit: LengthDisplayUnit
    public var counts: Counts
    public var faces: [FaceAnalysis]
    public var diagnostics: [EditorDiagnostic]

    public init(
        displayUnit: LengthDisplayUnit,
        counts: Counts = Counts(),
        faces: [FaceAnalysis] = [],
        diagnostics: [EditorDiagnostic] = []
    ) {
        self.displayUnit = displayUnit
        self.counts = counts
        self.faces = faces
        self.diagnostics = diagnostics
    }
}
