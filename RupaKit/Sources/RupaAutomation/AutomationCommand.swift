import Foundation
import RupaCore

public indirect enum AutomationCommand: Codable, Equatable, Sendable {
    case describeDocument
    case setDisplayUnit(LengthDisplayUnit)
    case setRulerConfiguration(RulerConfiguration)
    case setWorkspaceScalePreset(WorkspaceScalePreset)
    case fitWorkspaceScaleToModel
    case setViewportGridSettings(ViewportGridSettings)
    case describeSavedViews
    case createSavedView(SavedView)
    case updateSavedView(SavedView)
    case removeSavedView(id: SavedViewID)
    case generateDrawingProjection(query: DrawingProjectionQuery)
    case generateDrawingProjectionFromView(
        savedView: SavedView,
        toleranceMeters: Double?,
        maximumStrokeCount: Int
    )
    case rebaseWorkspaceOrigin(translation: Vector3D)
    case renameDocument(name: String)
    case upsertParameter(name: String, expression: CADExpression, kind: QuantityKind)
    case renameParameter(currentName: String, newName: String)
    case deleteParameter(name: String)
    case setFeatureSuppression(featureID: FeatureID, isSuppressed: Bool)
    case createComponentDefinition(name: String, rootSceneNodeIDs: [SceneNodeID])
    case createComponentInstance(
        name: String,
        definitionID: ComponentDefinitionID,
        localTransform: Transform3D
    )
    case createPatternArray(
        name: String,
        definitionID: ComponentDefinitionID,
        distribution: PatternArrayDistribution,
        outputMode: PatternArrayOutputMode
    )
    case updatePatternArray(
        id: PatternArraySourceID,
        name: String?,
        definitionID: ComponentDefinitionID?,
        distribution: PatternArrayDistribution?,
        outputMode: PatternArrayOutputMode?
    )
    case explodePatternArray(id: PatternArraySourceID)
    case setSceneNodeVisibility(id: SceneNodeID, isVisible: Bool)
    case setSceneNodeLock(id: SceneNodeID, isLocked: Bool)
    case setSceneNodeTransform(id: SceneNodeID, localTransform: Transform3D)
    case setComponentInstanceVisibility(id: ComponentInstanceID, isVisible: Bool)
    case setComponentInstanceLock(id: ComponentInstanceID, isLocked: Bool)
    case setComponentInstanceTransform(id: ComponentInstanceID, localTransform: Transform3D)
    case createSectionPlane(name: String)
    case analyzeSection(query: SectionAnalysisQuery)
    case describeConstructionPlanes
    case createConstructionPlane(name: String, plane: SketchPlane)
    case createConstructionPlaneFromTarget(name: String, target: SelectionTarget)
    case createConstructionPlaneFromTargets(
        name: String,
        targets: [SelectionTarget],
        viewNormal: Vector3D?
    )
    case createViewAlignedConstructionPlane(
        name: String,
        origin: Point3D,
        viewNormal: Vector3D
    )
    case setActiveConstructionPlane(id: ConstructionPlaneSourceID?)
    case renameConstructionPlane(id: ConstructionPlaneSourceID, name: String)
    case setConstructionPlane(id: ConstructionPlaneSourceID, plane: SketchPlane)
    case appendFeatureGraph(FeatureGraphTransaction)
    case setCurveCurvatureDisplay(target: SelectionTarget, isVisible: Bool?, combScale: Double?)
    case setPointDisplay(target: SelectionTarget, isVisible: Bool?)
    case createSketch(name: String, sketch: Sketch, geometryRole: ObjectDescriptor.GeometryRole)
    case createLineSketch(name: String, plane: SketchPlaneReference?, start: SketchPoint, end: SketchPoint)
    case createCircleSketch(name: String, plane: SketchPlaneReference?, center: SketchPoint, radius: CADExpression)
    case createArcSketch(
        name: String,
        plane: SketchPlaneReference?,
        center: SketchPoint,
        radius: CADExpression,
        startAngle: CADExpression,
        endAngle: CADExpression
    )
    case createSplineSketch(name: String, plane: SketchPlaneReference?, spline: SketchSpline)
    case createRectangleSketch(name: String, plane: SketchPlaneReference?, width: CADExpression, height: CADExpression)
    case createPolygonSketch(
        name: String,
        plane: SketchPlaneReference?,
        center: SketchPoint,
        radius: CADExpression,
        sides: Int,
        sizingMode: PolygonSizingMode,
        inclinationMode: PolygonInclinationMode,
        rotationAngle: CADExpression
    )
    case createFaceKnife(name: String, target: SelectionTarget, loop: [Point3D])
    case projectSketchCurvesToConstructionPlane(
        targets: [SelectionTarget],
        plane: SketchPlaneReference?,
        name: String?
    )
    case projectCurvesToGeneratedFace(
        targets: [SelectionTarget],
        face: SelectionTarget,
        name: String?
    )
    case projectBodyOutlinesToConstructionPlane(
        targets: [SelectionTarget],
        plane: SketchPlaneReference?,
        name: String?
    )
    case setObjectDimension(
        target: SelectionTarget,
        kind: ObjectDimensionKind,
        value: CADExpression
    )
    case addSelectionDimension(
        name: String?,
        kind: SelectionDimensionKind,
        first: SelectionTarget,
        second: SelectionTarget,
        target: CADExpression
    )
    case setSelectionDimensionTarget(
        id: SelectionDimensionID,
        target: CADExpression
    )
    case applySelectionDimensionTarget(id: SelectionDimensionID)
    case removeSelectionDimension(id: SelectionDimensionID)
    case addSketchConstraint(featureID: FeatureID, constraint: SketchConstraint)
    case removeSketchConstraint(featureID: FeatureID, constraint: SketchConstraint)
    case createBridgeCurve(
        featureID: FeatureID,
        firstEndpoint: BridgeCurveEndpoint,
        secondEndpoint: BridgeCurveEndpoint,
        continuity: BridgeCurveContinuity,
        trimsSourceCurves: Bool = false
    )
    case setBridgeCurveParameters(
        sourceID: BridgeCurveSourceID,
        firstEndpoint: BridgeCurveEndpoint?,
        secondEndpoint: BridgeCurveEndpoint?,
        continuity: BridgeCurveContinuity?,
        trimsSourceCurves: Bool? = nil
    )
    case offsetCurve(
        target: SelectionTarget,
        distance: CADExpression,
        options: OffsetCurveOptions,
        vertexHandle: SketchEntityPointHandle?
    )
    case offsetRegions(
        targets: [SelectionTarget],
        distance: CADExpression,
        options: OffsetCurveOptions,
        combinesRegions: Bool
    )
    case offsetSketchVertex(target: SelectionTarget, handle: SketchEntityPointHandle, distance: CADExpression)
    case applySketchCornerTreatment(
        target: SelectionTarget,
        adjacentTarget: SelectionTarget?,
        distance: CADExpression,
        treatment: SketchCornerTreatment
    )
    case createSlotSketch(target: SelectionTarget, width: CADExpression)
    case offsetBodyFace(target: SelectionTarget, distance: CADExpression)
    case deleteBodyFaces(targets: [SelectionTarget])
    case draftBodyFaces(targets: [SelectionTarget], neutralTarget: SelectionTarget, angle: CADExpression)
    case chamferBodyEdges(targets: [SelectionTarget], distance: CADExpression)
    case filletBodyEdges(targets: [SelectionTarget], radius: CADExpression, segmentCount: Int)
    case moveBodyEdge(target: SelectionTarget, deltaX: CADExpression, deltaY: CADExpression)
    case moveBodyVertex(target: SelectionTarget, deltaX: CADExpression, deltaY: CADExpression)
    case moveSketchEntityPoint(
        target: SelectionTarget,
        handle: SketchEntityPointHandle,
        deltaX: CADExpression,
        deltaY: CADExpression
    )
    case moveSketchSplineControlPoint(
        target: SelectionTarget,
        controlPointIndex: Int,
        deltaX: CADExpression,
        deltaY: CADExpression
    )
    case alignSketchVertex(
        target: SelectionTarget,
        reference: SelectionTarget,
        options: SketchVertexAlignmentOptions
    )
    case slideSketchSplineControlPoints(
        target: SelectionTarget,
        controlPointIndexes: [Int],
        direction: SplineControlPointSlideDirection,
        distance: CADExpression
    )
    case insertSketchSplineControlPoint(target: SelectionTarget, fraction: CADExpression)
    case setSketchCircleParameters(
        target: SelectionTarget,
        center: SketchPoint?,
        radius: CADExpression?
    )
    case setSketchArcParameters(
        target: SelectionTarget,
        center: SketchPoint?,
        radius: CADExpression?,
        startAngle: CADExpression?,
        endAngle: CADExpression?
    )
    case setSketchEntityDimension(
        target: SelectionTarget,
        kind: SketchEntityDimensionKind,
        value: CADExpression
    )
    case convertSketchLineToArc(
        target: SelectionTarget,
        sagitta: CADExpression
    )
    case convertSketchLineToSpline(target: SelectionTarget)
    case reverseSketchCurve(target: SelectionTarget)
    case rebuildSketchCurve(target: SelectionTarget, options: CurveRebuildOptions)
    case extendSketchCurve(target: SelectionTarget, distance: CADExpression, shape: ExtendCurveShape)
    case joinSketchCurves(
        target: SelectionTarget,
        adjacentTarget: SelectionTarget,
        continuity: SketchCurveJoinContinuity = .g0
    )
    case unjoinSketchCurve(target: SelectionTarget)
    case splitSketchCurve(target: SelectionTarget, fraction: CADExpression)
    case trimSketchCurveSegment(target: SelectionTarget)
    case cutSketchCurve(target: SelectionTarget, cutter: SelectionTarget, options: CutCurveOptions)
    case extrudeProfile(name: String, profile: ProfileReference, distance: CADExpression, direction: ExtrudeDirection)
    case setExtrudeDistance(featureID: FeatureID, distance: CADExpression)
    case setCubeDimensions(featureID: FeatureID, sizeX: CADExpression, sizeY: CADExpression, sizeZ: CADExpression)
    case setCylinderDimensions(featureID: FeatureID, radius: CADExpression, sizeY: CADExpression)
    case createRevolve(name: String, profile: ProfileReference, axis: RevolveAxis, angle: CADExpression)
    case createSweep(
        name: String,
        sections: [SweepSectionReference],
        path: SweepPathReference,
        guides: [SweepGuideReference],
        targets: [SweepTargetReference],
        options: SweepOptions
    )
    case createLoft(
        name: String,
        sections: [LoftSectionReference],
        guides: [LoftGuideReference] = [],
        options: LoftOptions
    )
    case createBoolean(
        name: String,
        targets: [BooleanTargetReference],
        tool: BooleanToolReference,
        operation: BooleanOperation,
        keepTools: Bool
    )
    case createBSplineSurface(
        name: String,
        surface: BSplineSurface3D
    )
    case createPolySplineSurface(
        name: String,
        sourceMesh: Mesh,
        options: PolySplineOptions
    )
    case setSurfaceControlPointDisplay(target: SelectionReference, isVisible: Bool?)
    case setSurfaceFrameDisplay(query: SurfaceFrameQuery, isVisible: Bool?)
    case movePolySplineSurfaceVertex(
        target: SelectionTarget,
        deltaX: CADExpression,
        deltaY: CADExpression,
        deltaZ: CADExpression
    )
    case moveSurfaceControlPoint(
        target: SelectionReference,
        deltaX: CADExpression,
        deltaY: CADExpression,
        deltaZ: CADExpression
    )
    case moveSurfaceControlPointsInFrame(
        targets: [SelectionReference],
        frame: SurfaceFrameQuery,
        uDistance: CADExpression,
        vDistance: CADExpression,
        normalDistance: CADExpression
    )
    case setSurfaceControlPointWeight(target: SelectionReference, weight: CADExpression)
    case setSurfaceKnotValue(target: SelectionReference, value: CADExpression)
    case insertSurfaceKnot(target: SelectionReference, value: CADExpression)
    case splitSurfaceSpan(target: SelectionReference, fraction: CADExpression)
    case setSurfaceKnotMultiplicity(target: SelectionReference, multiplicity: Int)
    case setSurfaceTrimDomain(
        target: SelectionReference,
        uLowerBound: CADExpression,
        uUpperBound: CADExpression,
        vLowerBound: CADExpression,
        vUpperBound: CADExpression
    )
    case setSurfaceTrimLoops(
        target: SelectionReference,
        trimLoops: [SurfaceTrimLoop]
    )
    case moveSurfaceTrimEndpoint(
        target: SelectionReference,
        endpoint: SurfaceTrimEndpoint,
        u: CADExpression,
        v: CADExpression
    )
    case moveSurfaceTrimControlPoint(
        target: SelectionReference,
        controlPointIndex: Int,
        u: CADExpression,
        v: CADExpression
    )
    case setSurfaceTrimControlPointWeight(
        target: SelectionReference,
        controlPointIndex: Int,
        weight: CADExpression
    )
    case insertSurfaceTrimKnot(target: SelectionReference, value: CADExpression)
    case setSurfaceTrimKnotValue(
        target: SelectionReference,
        knotIndex: Int,
        value: CADExpression
    )
    case setSurfaceTrimKnotMultiplicity(
        target: SelectionReference,
        knotIndex: Int,
        multiplicity: Int
    )
    case matchSurfaceBoundaryContinuity(
        target: SelectionReference,
        reference: SelectionReference,
        level: SurfaceBoundaryContinuityLevel,
        matchSide: SurfaceBoundaryMatchSide = .automatic,
        referenceDirection: SurfaceBoundaryReferenceDirection = .automatic
    )
    case slidePolySplineSurfaceVertices(
        targets: [SelectionTarget],
        direction: PolySplineSurfaceVertexSlideDirection,
        distance: CADExpression
    )
    case slideSurfaceControlPoints(
        targets: [SelectionReference],
        direction: PolySplineSurfaceVertexSlideDirection,
        distance: CADExpression
    )
    case createExtrudedRectangle(
        name: String,
        plane: SketchPlaneReference?,
        width: CADExpression,
        height: CADExpression,
        depth: CADExpression,
        direction: ExtrudeDirection
    )
    case createExtrudedRectangleFromCorners(
        name: String,
        plane: SketchPlaneReference?,
        firstCorner: SketchPoint,
        oppositeCorner: SketchPoint,
        depth: CADExpression,
        direction: ExtrudeDirection
    )
    case createExtrudedCircle(
        name: String,
        plane: SketchPlaneReference?,
        center: SketchPoint,
        radius: CADExpression,
        depth: CADExpression,
        direction: ExtrudeDirection
    )
    case validateDocument

}
