import SwiftCAD

public typealias AngleUnit = SwiftCAD.AngleUnit
public typealias CADExpression = SwiftCAD.CADExpression
public typealias CADAgentMeasurementQuery = SwiftCAD.CADAgentMeasurementQuery
public typealias CADAgentMeasurementQueryResult = SwiftCAD.CADAgentMeasurementQueryResult
public typealias CADPipeline = SwiftCAD.CADPipeline
public typealias CADBRepModel = SwiftCAD.BRepModel
public typealias CADFace = SwiftCAD.Face
public typealias CADProfile = SwiftCAD.Profile
public typealias BSplineSurface3D = SwiftCAD.BSplineSurface3D
public typealias BSplineCurve2D = SwiftCAD.BSplineCurve2D
public typealias BSplineSurfaceTrimEdge = SwiftCAD.BSplineSurfaceTrimEdge
public typealias BSplineSurfaceTrimLoop = SwiftCAD.BSplineSurfaceTrimLoop
public typealias BodyID = SwiftCAD.BodyID
public typealias BooleanFeature = SwiftCAD.BooleanFeature
public typealias BooleanOperation = SwiftCAD.BooleanOperation
public typealias BooleanTargetReference = SwiftCAD.BooleanTargetReference
public typealias BooleanToolReference = SwiftCAD.BooleanToolReference
public typealias CurveEvaluationSample = SwiftCAD.CurveEvaluationSample
public typealias EdgeID = SwiftCAD.EdgeID
public typealias EvaluatedDocument = SwiftCAD.EvaluatedDocument
public typealias ExtrudeDirection = SwiftCAD.ExtrudeDirection
public typealias ExtrudeFeature = SwiftCAD.ExtrudeFeature
public typealias FaceID = SwiftCAD.FaceID
public typealias FeatureNode = SwiftCAD.FeatureNode
public typealias FeatureOperation = SwiftCAD.FeatureOperation
public typealias FeatureID = SwiftCAD.FeatureID
public typealias LoopID = SwiftCAD.LoopID
public typealias MaterialID = SwiftCAD.MaterialID
public typealias Matrix4x4 = SwiftCAD.Matrix4x4
public typealias Mesh = SwiftCAD.Mesh
public typealias ParameterTable = SwiftCAD.ParameterTable
public typealias PersistentName = SwiftCAD.PersistentName
public typealias Point2D = SwiftCAD.Point2D
public typealias Point3D = SwiftCAD.Point3D
public typealias PolySplineMeshAnalysisResult = SwiftCAD.PolySplineMeshAnalysisResult
public typealias PolySplineOptions = SwiftCAD.PolySplineOptions
public typealias ProfileReference = SwiftCAD.ProfileReference
public typealias Quantity = SwiftCAD.Quantity
public typealias QuantityKind = SwiftCAD.QuantityKind
public typealias RevolveAxis = SwiftCAD.RevolveAxis
public typealias RevolveFeature = SwiftCAD.RevolveFeature
public typealias SelectionDimensionEvaluation = SwiftCAD.SelectionDimensionEvaluation
public typealias SelectionDimensionID = SwiftCAD.SelectionDimensionID
public typealias SelectionDimensionKind = SwiftCAD.SelectionDimensionKind
public typealias SelectionReference = SwiftCAD.SelectionReference
public typealias SelectionMeasurementPoint = SwiftCAD.SelectionMeasurementPoint
public typealias SelectionDistanceMeasurement = SwiftCAD.SelectionDistanceMeasurement
public typealias SelectionAngleMeasurement = SwiftCAD.SelectionAngleMeasurement
public typealias SketchConstraint = SwiftCAD.SketchConstraint
public typealias Sketch = SwiftCAD.Sketch
public typealias SketchArc = SwiftCAD.SketchArc
public typealias SketchCircle = SwiftCAD.SketchCircle
public typealias SketchEntity = SwiftCAD.SketchEntity
public typealias SketchEntityID = SwiftCAD.SketchEntityID
public typealias SketchLine = SwiftCAD.SketchLine
public typealias SketchPlane = SwiftCAD.SketchPlane
public typealias SketchPoint = SwiftCAD.SketchPoint
public typealias SketchReference = SwiftCAD.SketchReference
public typealias SketchSpline = SwiftCAD.SketchSpline
public typealias SketchSplineEndpoint = SwiftCAD.SketchSplineEndpoint
public typealias SketchSplineEndpointReference = SwiftCAD.SketchSplineEndpointReference
public typealias SketchCurveSampler = SwiftCAD.SketchCurveSampler
public typealias SweepFeature = SwiftCAD.SweepFeature
public typealias SweepCurveSectionReference = SwiftCAD.SweepCurveSectionReference
public typealias SweepGuideReference = SwiftCAD.SweepGuideReference
public typealias SweepOptions = SwiftCAD.SweepOptions
public typealias SweepPathReference = SwiftCAD.SweepPathReference
public typealias SweepSectionReference = SwiftCAD.SweepSectionReference
public typealias SweepTargetReference = SwiftCAD.SweepTargetReference
public typealias SweepAlignment = SwiftCAD.SweepAlignment
public typealias SweepBooleanOperation = SwiftCAD.SweepBooleanOperation
public typealias SweepCornerStyle = SwiftCAD.SweepCornerStyle
public typealias SweepGuideMethod = SwiftCAD.SweepGuideMethod
public typealias SweepResultKind = SwiftCAD.SweepResultKind
public typealias SweepEvaluationPlanResult = SwiftCAD.SweepEvaluationPlanResult
public typealias SweepEvaluationPlanService = SwiftCAD.SweepEvaluationPlanService
public typealias SweepEvaluationPreflightCheck = SwiftCAD.SweepEvaluationPreflightCheck
public typealias SurfaceControlPointReference = SwiftCAD.SurfaceControlPointReference
public typealias SurfaceParameter = SwiftCAD.SurfaceParameter
public typealias SurfaceParameterCurve = SwiftCAD.SurfaceParameterCurve
public typealias SurfaceParameterReference = SwiftCAD.SurfaceParameterReference
public typealias SurfaceReference = SwiftCAD.SurfaceReference
public typealias SurfaceSubobjectReference = SwiftCAD.SurfaceSubobjectReference
public typealias SurfaceTrimKnotReference = SwiftCAD.SurfaceTrimKnotReference
public typealias SurfaceTrimReference = SwiftCAD.SurfaceTrimReference
public typealias SurfaceTrimSpanReference = SwiftCAD.SurfaceTrimSpanReference
public typealias TopologyReference = SwiftCAD.TopologyReference
public typealias Transform3D = SwiftCAD.Transform3D
public typealias Vector3D = SwiftCAD.Vector3D
public typealias VertexID = SwiftCAD.VertexID

public enum SurfaceTrimEndpoint: String, Codable, CaseIterable, Equatable, Sendable {
    case start
    case end
}

public extension SketchPlane {
    static var defaultWorkspacePlane: SketchPlane {
        .xy
    }
}
