import Foundation
import RupaCore

struct SceneBrowserRow: Identifiable {
    var id: SceneNodeID
    var depth: Int
}

struct SidebarAssetRow: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
}

enum InspectorBoolChoice: String, CaseIterable, Identifiable {
    case mixed = "Mixed"
    case on = "On"
    case off = "Off"

    var id: String {
        rawValue
    }
}

enum InspectorTransformComponent {
    case translationX
    case translationY
    case translationZ
    case scaleX
    case scaleY
    case scaleZ

    var matrixIndex: Int {
        switch self {
        case .translationX:
            12
        case .translationY:
            13
        case .translationZ:
            14
        case .scaleX:
            0
        case .scaleY:
            5
        case .scaleZ:
            10
        }
    }
}

enum InspectorMaterialChoice: Hashable, Identifiable {
    case mixed
    case none
    case material(MaterialID)

    var id: String {
        switch self {
        case .mixed:
            "mixed"
        case .none:
            "none"
        case .material(let id):
            id.description
        }
    }
}

struct InspectorVector3D: Equatable {
    var x: Double
    var y: Double
    var z: Double
}

struct InspectorObjectShape: Identifiable, Equatable {
    var id: SceneNodeID
    var featureID: FeatureID
    var typeID: ObjectTypeID?
    var definition: ObjectTypeDefinition?
    var properties: ObjectPropertySet
    var sourceCenter: InspectorVector3D
    var center: InspectorVector3D
    var size: InspectorVector3D
    var cylinder: InspectorCylinderShape?
}

struct InspectorSketchEntity: Equatable {
    var target: SelectionTarget
    var sourceFeatureID: FeatureID
    var entityID: SketchEntityID
    var sourceFeatureName: String?
    var entityKind: String
    var analysis: InspectorCurveAnalysis?
    var bridgeCurve: InspectorBridgeCurve?
    var joinedCurveSourceID: JoinedCurveSourceID?
    var joinedCurveGroupSourceID: JoinedCurveGroupSourceID?
    var joinedCurveGroupContinuity: SketchCurveJoinContinuity?
    var start: SketchEntitySummaryResult.Point?
    var end: SketchEntitySummaryResult.Point?
    var center: SketchEntitySummaryResult.Point?
    var controlPoints: [SketchEntitySummaryResult.Point] = []
    var smoothSplineControlPointIndexes: Set<Int> = []
    var tangentLineCandidates: [InspectorSketchLineCandidate] = []
    var tangentSplineEndpointCandidates: [InspectorSplineEndpointCandidate] = []
    var startTangentLineIDs: Set<SketchEntityID> = []
    var endTangentLineIDs: Set<SketchEntityID> = []
    var startTangentSplineEndpoints: Set<SketchSplineEndpointReference> = []
    var endTangentSplineEndpoints: Set<SketchSplineEndpointReference> = []
    var startSmoothSplineEndpoints: Set<SketchSplineEndpointReference> = []
    var endSmoothSplineEndpoints: Set<SketchSplineEndpointReference> = []
    var radius: Double?
    var startAngle: Double?
    var endAngle: Double?
}

struct InspectorBridgeCurve: Equatable {
    var sourceID: BridgeCurveSourceID
    var target: SelectionTarget
    var firstEndpoint: BridgeCurveEndpoint
    var secondEndpoint: BridgeCurveEndpoint
    var continuity: BridgeCurveContinuity
    var trimsSourceCurves: Bool
    var curvatureDisplay: CurveCurvatureDisplay?
    var firstParameter: Double
    var secondParameter: Double
    var firstTension: InspectorBridgeCurveTension
    var secondTension: InspectorBridgeCurveTension
}

struct InspectorBridgeCurveTension: Equatable {
    var first: Double
    var second: Double
    var third: Double
}

enum InspectorBridgeCurveEndpoint {
    case first
    case second
}

enum InspectorBridgeCurveTensionLevel {
    case first
    case second
    case third
}

struct InspectorCurveAnalysis: Equatable {
    var sampleCount: Int
    var approximateLength: Double
    var maxAbsCurvature: Double
    var continuityJoins: [InspectorCurveContinuityJoin]
}

struct InspectorCurveContinuityJoin: Identifiable, Equatable {
    var id: String
    var joinKind: CurveAnalysisResult.ContinuityJoinKind
    var requiredContinuity: CurveAnalysisResult.ContinuityLevel?
    var actualContinuity: CurveAnalysisResult.ContinuityLevel
    var positionGap: Double
    var tangentAngle: Double?
    var curvatureGap: Double?
    var constraintKinds: [String]
    var firstReference: String
    var secondReference: String
}

struct InspectorSurfaceContinuity: Equatable {
    var bSplineFaceCount: Int
    var sharedEdgeCount: Int
    var g0AdjacencyCount: Int
    var g1AdjacencyCount: Int
    var g2AdjacencyCount: Int
    var unresolvedG2AdjacencyCount: Int
    var adjacencies: [InspectorSurfaceAdjacency]
    var diagnostics: [EditorDiagnostic]
}

struct InspectorSurfaceAdjacency: Identifiable, Equatable {
    var id: String
    var edgePersistentNames: [String]
    var firstFacePersistentName: String?
    var secondFacePersistentName: String?
    var continuity: RupaCore.SurfaceContinuityResult.ContinuityLevel
    var positionGap: Double
    var normalAngle: Double?
    var curvatureGap: Double?
    var requiresCurvatureContinuitySolve: Bool
}

struct InspectorSurfaceAnalysis: Equatable {
    var bSplineFaceCount: Int
    var sampleCount: Int
    var uCurvatureCombCount: Int
    var vCurvatureCombCount: Int
    var trimBoundaryCount: Int
    var innerTrimBoundaryCount: Int
    var openTrimBoundaryCount: Int
    var trimBoundaryEdgeCount: Int
    var faces: [InspectorSurfaceFaceAnalysis]
    var diagnostics: [EditorDiagnostic]
}

struct InspectorSurfaceFaceAnalysis: Identifiable, Equatable {
    var id: String
    var facePersistentNames: [String]
    var uDegree: Int
    var vDegree: Int
    var uControlPointCount: Int
    var vControlPointCount: Int
    var sampleCount: Int
    var trimBoundaryCount: Int
    var innerTrimBoundaryCount: Int
    var openTrimBoundaryCount: Int
    var trimBoundaryEdgeCount: Int
    var trimBoundaryLength: Double
    var maxUNormalChangePerLength: Double
    var maxVNormalChangePerLength: Double
    var maxNormalAngle: Double
    var maxAbsUNormalCurvature: Double
    var maxAbsVNormalCurvature: Double
    var maxAbsPrincipalCurvature: Double
    var maxAbsGaussianCurvature: Double
    var minimumPrincipalDirection: SurfaceAnalysisResult.Vector?
    var maximumPrincipalDirection: SurfaceAnalysisResult.Vector?
}

struct InspectorSketchLineCandidate: Identifiable, Equatable {
    var id: SketchEntityID
    var start: SketchEntitySummaryResult.Point
    var end: SketchEntitySummaryResult.Point
}

struct InspectorSplineEndpointCandidate: Identifiable, Equatable {
    var splineID: SketchEntityID
    var endpoint: SketchSplineEndpoint
    var point: SketchEntitySummaryResult.Point
    var tangent: SketchEntitySummaryResult.Point

    var id: String {
        "\(splineID.description):\(endpoint.rawValue)"
    }

    var reference: SketchSplineEndpointReference {
        SketchSplineEndpointReference(splineID: splineID, endpoint: endpoint)
    }
}

struct InspectorCylinderShape: Equatable {
    var topRadius: Double
    var bottomRadius: Double
    var sideSegments: Int
    var verticalSegments: Int
    var angleDegrees: Double
    var hasCaps: Bool
    var hollow: Double
    var cornerRadius: Double
    var cornerSideSegments: Int
}

enum InspectorObjectAxis: Equatable {
    case x
    case y
    case z
}
