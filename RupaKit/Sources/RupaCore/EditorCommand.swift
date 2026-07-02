import Foundation
import SwiftCAD
import RupaCoreTypes

public enum EditorCommand: Codable, Equatable, Sendable {
    case setDisplayUnit(LengthDisplayUnit)
    case setRulerConfiguration(RulerConfiguration)
    case setViewportGridSettings(ViewportGridSettings)
    case rebaseWorkspaceOrigin(translation: Vector3D)
    case renameDocument(name: String)
    case resetDocument(name: String)
    case replaceProductMetadata(ProductMetadata)
    case upsertParameter(name: String, expression: CADExpression, kind: QuantityKind)
    case renameParameter(currentName: String, newName: String)
    case deleteParameter(name: String)
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
    case setSceneNodeMaterial(id: SceneNodeID, materialID: MaterialID?)
    case setSceneNodeObjectProperty(id: SceneNodeID, propertyID: ObjectPropertyID, value: ObjectPropertyValue?)
    case setComponentInstanceVisibility(id: ComponentInstanceID, isVisible: Bool)
    case setComponentInstanceLock(id: ComponentInstanceID, isLocked: Bool)
    case setComponentInstanceTransform(id: ComponentInstanceID, localTransform: Transform3D)
    case createSectionPlane(name: String)
    case createConstructionPlane(name: String, plane: SketchPlane, activates: Bool)
    case createConstructionPlaneFromTarget(name: String, target: SelectionTarget, activates: Bool)
    case createConstructionPlaneFromTargets(
        name: String,
        targets: [SelectionTarget],
        viewNormal: Vector3D?,
        activates: Bool
    )
    case createViewAlignedConstructionPlane(
        name: String,
        origin: Point3D,
        viewNormal: Vector3D,
        activates: Bool
    )
    case setActiveConstructionPlane(id: ConstructionPlaneSourceID?)
    case renameConstructionPlane(id: ConstructionPlaneSourceID, name: String)
    case setConstructionPlane(id: ConstructionPlaneSourceID, plane: SketchPlane)
    case setCurveCurvatureDisplay(target: SelectionTarget, isVisible: Bool?, combScale: Double?)
    case setPointDisplay(target: SelectionTarget, isVisible: Bool?)
    case createSketch(name: String, sketch: Sketch, geometryRole: ObjectDescriptor.GeometryRole)
    case createLineSketch(name: String, plane: SketchPlane, start: SketchPoint, end: SketchPoint)
    case createCircleSketch(name: String, plane: SketchPlane, center: SketchPoint, radius: CADExpression)
    case createArcSketch(
        name: String,
        plane: SketchPlane,
        center: SketchPoint,
        radius: CADExpression,
        startAngle: CADExpression,
        endAngle: CADExpression
    )
    case createSplineSketch(name: String, plane: SketchPlane, spline: SketchSpline)
    case createRectangleSketch(name: String, plane: SketchPlane, width: CADExpression, height: CADExpression)
    case createPolygonSketch(
        name: String,
        plane: SketchPlane,
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
        plane: SketchPlane?,
        name: String?
    )
    case projectCurvesToGeneratedFace(
        targets: [SelectionTarget],
        face: SelectionTarget,
        name: String?
    )
    case projectBodyOutlinesToConstructionPlane(
        targets: [SelectionTarget],
        plane: SketchPlane?,
        name: String?
    )
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
    case createRectangleSketchFromCorners(
        name: String,
        plane: SketchPlane,
        firstCorner: SketchPoint,
        oppositeCorner: SketchPoint
    )
    case setExtrudeDistance(featureID: FeatureID, distance: CADExpression)
    case setCubeDimensions(
        featureID: FeatureID,
        sizeX: CADExpression,
        sizeY: CADExpression,
        sizeZ: CADExpression
    )
    case setCylinderDimensions(
        featureID: FeatureID,
        radius: CADExpression,
        sizeY: CADExpression
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
    case setSurfaceControlPointDisplay(
        target: SelectionReference,
        isVisible: Bool?
    )
    case setSurfaceFrameDisplay(
        query: SurfaceFrameQuery,
        isVisible: Bool?
    )
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
    case setSurfaceControlPointWeight(
        target: SelectionReference,
        weight: CADExpression
    )
    case setSurfaceKnotValue(
        target: SelectionReference,
        value: CADExpression
    )
    case insertSurfaceKnot(
        target: SelectionReference,
        value: CADExpression
    )
    case splitSurfaceSpan(
        target: SelectionReference,
        fraction: CADExpression
    )
    case setSurfaceKnotMultiplicity(
        target: SelectionReference,
        multiplicity: Int
    )
    case setSurfaceTrimDomain(
        target: SelectionReference,
        uLowerBound: CADExpression,
        uUpperBound: CADExpression,
        vLowerBound: CADExpression,
        vUpperBound: CADExpression
    )
    case setSurfaceTrimLoops(
        target: SelectionReference,
        trimLoops: [BSplineSurfaceTrimLoop]
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
    case insertSurfaceTrimKnot(
        target: SelectionReference,
        value: CADExpression
    )
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
        plane: SketchPlane,
        width: CADExpression,
        height: CADExpression,
        depth: CADExpression,
        direction: ExtrudeDirection
    )
    case createExtrudedRectangleFromCorners(
        name: String,
        plane: SketchPlane,
        firstCorner: SketchPoint,
        oppositeCorner: SketchPoint,
        depth: CADExpression,
        direction: ExtrudeDirection
    )
    case createExtrudedCircle(
        name: String,
        plane: SketchPlane,
        center: SketchPoint,
        radius: CADExpression,
        depth: CADExpression,
        direction: ExtrudeDirection
    )
    case validateDocument

    public var name: String {
        switch self {
        case .setDisplayUnit:
            "setDisplayUnit"
        case .setRulerConfiguration:
            "setRulerConfiguration"
        case .setViewportGridSettings:
            "setViewportGridSettings"
        case .rebaseWorkspaceOrigin:
            "rebaseWorkspaceOrigin"
        case .renameDocument:
            "renameDocument"
        case .resetDocument:
            "resetDocument"
        case .replaceProductMetadata:
            "replaceProductMetadata"
        case .upsertParameter:
            "upsertParameter"
        case .renameParameter:
            "renameParameter"
        case .deleteParameter:
            "deleteParameter"
        case .createComponentDefinition:
            "createComponentDefinition"
        case .createComponentInstance:
            "createComponentInstance"
        case .createPatternArray:
            "createPatternArray"
        case .updatePatternArray:
            "updatePatternArray"
        case .explodePatternArray:
            "explodePatternArray"
        case .setSceneNodeVisibility:
            "setSceneNodeVisibility"
        case .setSceneNodeLock:
            "setSceneNodeLock"
        case .setSceneNodeTransform:
            "setSceneNodeTransform"
        case .setSceneNodeMaterial:
            "setSceneNodeMaterial"
        case .setSceneNodeObjectProperty:
            "setSceneNodeObjectProperty"
        case .setComponentInstanceVisibility:
            "setComponentInstanceVisibility"
        case .setComponentInstanceLock:
            "setComponentInstanceLock"
        case .setComponentInstanceTransform:
            "setComponentInstanceTransform"
        case .createSectionPlane:
            "createSectionPlane"
        case .createConstructionPlane:
            "createConstructionPlane"
        case .createConstructionPlaneFromTarget:
            "createConstructionPlaneFromTarget"
        case .createConstructionPlaneFromTargets:
            "createConstructionPlaneFromTargets"
        case .createViewAlignedConstructionPlane:
            "createViewAlignedConstructionPlane"
        case .setActiveConstructionPlane:
            "setActiveConstructionPlane"
        case .renameConstructionPlane:
            "renameConstructionPlane"
        case .setConstructionPlane:
            "setConstructionPlane"
        case .setCurveCurvatureDisplay:
            "setCurveCurvatureDisplay"
        case .setPointDisplay:
            "setPointDisplay"
        case .createSketch:
            "createSketch"
        case .createLineSketch:
            "createLineSketch"
        case .createCircleSketch:
            "createCircleSketch"
        case .createArcSketch:
            "createArcSketch"
        case .createSplineSketch:
            "createSplineSketch"
        case .createRectangleSketch:
            "createRectangleSketch"
        case .createPolygonSketch:
            "createPolygonSketch"
        case .createFaceKnife:
            "createFaceKnife"
        case .projectSketchCurvesToConstructionPlane:
            "projectSketchCurvesToConstructionPlane"
        case .projectCurvesToGeneratedFace:
            "projectCurvesToGeneratedFace"
        case .projectBodyOutlinesToConstructionPlane:
            "projectBodyOutlinesToConstructionPlane"
        case .addSketchConstraint:
            "addSketchConstraint"
        case .removeSketchConstraint:
            "removeSketchConstraint"
        case .createBridgeCurve:
            "createBridgeCurve"
        case .setBridgeCurveParameters:
            "setBridgeCurveParameters"
        case .createRectangleSketchFromCorners:
            "createRectangleSketchFromCorners"
        case .setExtrudeDistance:
            "setExtrudeDistance"
        case .setCubeDimensions:
            "setCubeDimensions"
        case .setCylinderDimensions:
            "setCylinderDimensions"
        case .setObjectDimension:
            "setObjectDimension"
        case .addSelectionDimension:
            "addSelectionDimension"
        case .setSelectionDimensionTarget:
            "setSelectionDimensionTarget"
        case .applySelectionDimensionTarget:
            "applySelectionDimensionTarget"
        case .removeSelectionDimension:
            "removeSelectionDimension"
        case .offsetCurve:
            "offsetCurve"
        case .offsetRegions:
            "offsetRegions"
        case .offsetSketchVertex:
            "offsetSketchVertex"
        case .applySketchCornerTreatment:
            "applySketchCornerTreatment"
        case .createSlotSketch:
            "createSlotSketch"
        case .offsetBodyFace:
            "offsetBodyFace"
        case .deleteBodyFaces:
            "deleteBodyFaces"
        case .draftBodyFaces:
            "draftBodyFaces"
        case .chamferBodyEdges:
            "chamferBodyEdges"
        case .filletBodyEdges:
            "filletBodyEdges"
        case .moveBodyEdge:
            "moveBodyEdge"
        case .moveBodyVertex:
            "moveBodyVertex"
        case .moveSketchEntityPoint:
            "moveSketchEntityPoint"
        case .moveSketchSplineControlPoint:
            "moveSketchSplineControlPoint"
        case .alignSketchVertex:
            "alignSketchVertex"
        case .slideSketchSplineControlPoints:
            "slideSketchSplineControlPoints"
        case .insertSketchSplineControlPoint:
            "insertSketchSplineControlPoint"
        case .setSketchCircleParameters:
            "setSketchCircleParameters"
        case .setSketchArcParameters:
            "setSketchArcParameters"
        case .setSketchEntityDimension:
            "setSketchEntityDimension"
        case .convertSketchLineToArc:
            "convertSketchLineToArc"
        case .convertSketchLineToSpline:
            "convertSketchLineToSpline"
        case .reverseSketchCurve:
            "reverseSketchCurve"
        case .rebuildSketchCurve:
            "rebuildSketchCurve"
        case .extendSketchCurve:
            "extendSketchCurve"
        case .joinSketchCurves:
            "joinSketchCurves"
        case .unjoinSketchCurve:
            "unjoinSketchCurve"
        case .splitSketchCurve:
            "splitSketchCurve"
        case .trimSketchCurveSegment:
            "trimSketchCurveSegment"
        case .cutSketchCurve:
            "cutSketchCurve"
        case .extrudeProfile:
            "extrudeProfile"
        case .createRevolve:
            "createRevolve"
        case .createSweep:
            "createSweep"
        case .createLoft:
            "createLoft"
        case .createBoolean:
            "createBoolean"
        case .createBSplineSurface:
            "createBSplineSurface"
        case .createPolySplineSurface:
            "createPolySplineSurface"
        case .setSurfaceControlPointDisplay:
            "setSurfaceControlPointDisplay"
        case .setSurfaceFrameDisplay:
            "setSurfaceFrameDisplay"
        case .movePolySplineSurfaceVertex:
            "movePolySplineSurfaceVertex"
        case .moveSurfaceControlPoint:
            "moveSurfaceControlPoint"
        case .moveSurfaceControlPointsInFrame:
            "moveSurfaceControlPointsInFrame"
        case .setSurfaceControlPointWeight:
            "setSurfaceControlPointWeight"
        case .setSurfaceKnotValue:
            "setSurfaceKnotValue"
        case .insertSurfaceKnot:
            "insertSurfaceKnot"
        case .splitSurfaceSpan:
            "splitSurfaceSpan"
        case .setSurfaceKnotMultiplicity:
            "setSurfaceKnotMultiplicity"
        case .setSurfaceTrimDomain:
            "setSurfaceTrimDomain"
        case .setSurfaceTrimLoops:
            "setSurfaceTrimLoops"
        case .moveSurfaceTrimEndpoint:
            "moveSurfaceTrimEndpoint"
        case .moveSurfaceTrimControlPoint:
            "moveSurfaceTrimControlPoint"
        case .setSurfaceTrimControlPointWeight:
            "setSurfaceTrimControlPointWeight"
        case .insertSurfaceTrimKnot:
            "insertSurfaceTrimKnot"
        case .setSurfaceTrimKnotValue:
            "setSurfaceTrimKnotValue"
        case .setSurfaceTrimKnotMultiplicity:
            "setSurfaceTrimKnotMultiplicity"
        case .matchSurfaceBoundaryContinuity:
            "matchSurfaceBoundaryContinuity"
        case .slidePolySplineSurfaceVertices:
            "slidePolySplineSurfaceVertices"
        case .slideSurfaceControlPoints:
            "slideSurfaceControlPoints"
        case .createExtrudedRectangle:
            "createExtrudedRectangle"
        case .createExtrudedRectangleFromCorners:
            "createExtrudedRectangleFromCorners"
        case .createExtrudedCircle:
            "createExtrudedCircle"
        case .validateDocument:
            "validateDocument"
        }
    }

    public var mutatesDocument: Bool {
        switch self {
        case .setDisplayUnit,
             .setRulerConfiguration,
             .setViewportGridSettings,
             .rebaseWorkspaceOrigin,
             .renameDocument,
             .resetDocument,
             .replaceProductMetadata,
             .upsertParameter,
             .renameParameter,
             .deleteParameter,
             .createComponentDefinition,
             .createComponentInstance,
             .createPatternArray,
             .updatePatternArray,
             .explodePatternArray,
             .setSceneNodeVisibility,
             .setSceneNodeLock,
             .setSceneNodeTransform,
             .setSceneNodeMaterial,
             .setSceneNodeObjectProperty,
             .setComponentInstanceVisibility,
             .setComponentInstanceLock,
             .setComponentInstanceTransform,
             .createSectionPlane,
             .createConstructionPlane,
             .createConstructionPlaneFromTarget,
             .createConstructionPlaneFromTargets,
             .createViewAlignedConstructionPlane,
             .setActiveConstructionPlane,
             .renameConstructionPlane,
             .setConstructionPlane,
             .setCurveCurvatureDisplay,
             .setPointDisplay,
             .createSketch,
             .createLineSketch,
             .createCircleSketch,
             .createArcSketch,
             .createSplineSketch,
             .createRectangleSketch,
             .createPolygonSketch,
             .createFaceKnife,
             .projectSketchCurvesToConstructionPlane,
             .projectCurvesToGeneratedFace,
             .projectBodyOutlinesToConstructionPlane,
             .addSketchConstraint,
             .removeSketchConstraint,
             .createBridgeCurve,
             .setBridgeCurveParameters,
             .createRectangleSketchFromCorners,
             .setExtrudeDistance,
             .setCubeDimensions,
             .setCylinderDimensions,
             .setObjectDimension,
             .addSelectionDimension,
             .setSelectionDimensionTarget,
             .applySelectionDimensionTarget,
             .removeSelectionDimension,
             .offsetCurve,
             .offsetRegions,
             .offsetSketchVertex,
             .applySketchCornerTreatment,
             .createSlotSketch,
             .offsetBodyFace,
             .deleteBodyFaces,
             .draftBodyFaces,
             .chamferBodyEdges,
             .filletBodyEdges,
             .moveBodyEdge,
             .moveBodyVertex,
             .moveSketchEntityPoint,
             .moveSketchSplineControlPoint,
             .alignSketchVertex,
             .slideSketchSplineControlPoints,
             .insertSketchSplineControlPoint,
             .setSketchCircleParameters,
             .setSketchArcParameters,
             .setSketchEntityDimension,
             .convertSketchLineToArc,
             .convertSketchLineToSpline,
             .reverseSketchCurve,
             .rebuildSketchCurve,
             .extendSketchCurve,
             .joinSketchCurves,
             .unjoinSketchCurve,
             .splitSketchCurve,
             .trimSketchCurveSegment,
             .cutSketchCurve,
             .extrudeProfile,
             .createRevolve,
             .createSweep,
             .createLoft,
             .createBoolean,
             .createBSplineSurface,
             .createPolySplineSurface,
             .setSurfaceControlPointDisplay,
             .setSurfaceFrameDisplay,
             .movePolySplineSurfaceVertex,
             .moveSurfaceControlPoint,
             .moveSurfaceControlPointsInFrame,
             .setSurfaceControlPointWeight,
             .setSurfaceKnotValue,
             .insertSurfaceKnot,
             .splitSurfaceSpan,
             .setSurfaceKnotMultiplicity,
             .setSurfaceTrimDomain,
             .setSurfaceTrimLoops,
             .moveSurfaceTrimEndpoint,
             .moveSurfaceTrimControlPoint,
             .setSurfaceTrimControlPointWeight,
             .insertSurfaceTrimKnot,
             .setSurfaceTrimKnotValue,
             .setSurfaceTrimKnotMultiplicity,
             .matchSurfaceBoundaryContinuity,
             .slidePolySplineSurfaceVertices,
             .slideSurfaceControlPoints,
             .createExtrudedRectangle,
             .createExtrudedRectangleFromCorners,
             .createExtrudedCircle:
            true
        case .validateDocument:
            false
        }
    }
}
