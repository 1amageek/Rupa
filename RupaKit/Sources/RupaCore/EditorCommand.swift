import Foundation
import SwiftCAD
import RupaCoreTypes

public indirect enum EditorCommand: Codable, Equatable, Sendable {
    case createSavedView(SavedView)
    case updateSavedView(SavedView)
    case removeSavedView(id: SavedViewID)
    /// Records the plane Section Analysis's Previous option restores.
    case setSectionAnalysisPlane(SketchPlane?)
    case addMeasurementAnnotation(MeasurementAnnotation)
    case rebaseWorkspaceOrigin(translation: Vector3D)
    case renameDocument(name: String)
    case renameSceneNode(id: SceneNodeID, name: String)
    case renameComponentInstance(id: ComponentInstanceID, name: String)
    case moveSceneNodes(
        ids: [SceneNodeID],
        parentID: SceneNodeID?,
        beforeSiblingID: SceneNodeID?
    )
    case resetDocument(name: String)
    case replaceProductMetadata(ProductMetadata)
    case applySemanticExtensionMutations([SemanticExtensionMutation])
    case applyNamespacedSemanticExtensionMutations(
        namespace: SemanticNamespaceID,
        mutations: [SemanticExtensionMutation]
    )
    case upsertParameter(name: String, expression: CADExpression, kind: QuantityKind)
    case renameParameter(currentName: String, newName: String)
    case deleteParameter(name: String)
    case setFeatureSuppression(featureID: FeatureID, isSuppressed: Bool)
    case reorderFeatureGraph(featureIDs: [FeatureID])
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
    /// Arrays the objects `rootSceneNodeIDs` in one step, reading the distribution in their
    /// parent's frame; the objects become the array's component definition.
    case createPatternArrayFromSceneNodes(
        name: String,
        rootSceneNodeIDs: [SceneNodeID],
        distribution: PatternArrayDistribution,
        outputMode: PatternArrayOutputMode
    )
    case setSceneNodeVisibility(id: SceneNodeID, isVisible: Bool)
    case setSceneNodeLock(id: SceneNodeID, isLocked: Bool)
    case setSceneNodeTransform(id: SceneNodeID, localTransform: Transform3D)
    /// Collects `memberIDs` under a new group node without moving any of them.
    case groupSceneNodes(name: String, memberIDs: [SceneNodeID], origin: Point3D?)
    /// Dissolves a group, handing its members back to the group's parent where they stand.
    case ungroupSceneNode(id: SceneNodeID)
    /// Removes `ids` and everything that cannot outlive them, or nothing at all.
    case deleteSceneNodes(ids: [SceneNodeID])
    /// Moves `ids` together as one body, `worldDelta` being the motion in world space; with
    /// `compensatingInstances`, instances of a moved component definition stay in place.
    case transformSceneNodes(ids: [SceneNodeID], worldDelta: Transform3D, compensatingInstances: Bool)
    /// Mirror the selected objects across a world plane with the dialog's options.
    case mirrorSceneNodes(ids: [SceneNodeID], plane: SceneMirrorPlane, options: SceneMirrorOptions)
    /// Copies `ids` in place as independent siblings; the copies are the generated scene nodes.
    case duplicateSceneNodes(ids: [SceneNodeID])
    /// Realize Instances: each component instance node becomes an independent copy of its definition.
    case realizeComponentInstances(sceneNodeIDs: [SceneNodeID])
    /// Places `ids` once per world-space placement of the selection, as independent copies or as
    /// instances of the selection's component definition; copies may be combined with the body
    /// they were placed on.
    case placeSceneNodes(
        ids: [SceneNodeID],
        placements: [Transform3D],
        output: SceneNodePlacementOutput,
        boolean: SceneNodePlacementBoolean?
    )
    /// Inserts one copy of a transported fragment per world-space placement.
    case pasteSceneFragment(SceneFragment, placements: [Transform3D], boolean: SceneNodePlacementBoolean?)
    case setSceneNodeMaterial(id: SceneNodeID, materialID: MaterialID?)
    case setTopologyMaterialBinding(
        target: SelectionTarget,
        materialID: MaterialID?,
        process: TopologyMaterialBinding.Process?
    )
    /// Applies one appearance component to the material `id` names, creating and
    /// assigning a material when the node names none.
    case setSceneNodeAppearance(id: SceneNodeID, edit: MaterialComponentEdit)
    /// Set Material: the objects the selection reaches share one material, a library one when named.
    case assignMaterial(ids: [SceneNodeID], materialID: MaterialID?)
    /// Fork Material: the objects the selection reaches take a new copy of their appearance.
    case forkMaterial(ids: [SceneNodeID])
    /// Remove Material: the objects the selection reaches and their faces return to the default.
    case removeMaterial(ids: [SceneNodeID])
    case editMaterial(id: MaterialID, edit: MaterialComponentEdit)
    case createMaterial(name: String)
    case renameMaterial(id: MaterialID, name: String)
    case deleteMaterial(id: MaterialID)
    case setSceneNodeObjectProperty(id: SceneNodeID, propertyID: PropertyID, value: ObjectPropertyValue?)
    case setComponentInstanceVisibility(id: ComponentInstanceID, isVisible: Bool)
    case setComponentInstanceLock(id: ComponentInstanceID, isLocked: Bool)
    case setComponentInstanceTransform(id: ComponentInstanceID, localTransform: Transform3D)
    case createSectionPlane(name: String)
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
    case renameConstructionPlane(id: ConstructionPlaneSourceID, name: String)
    case setConstructionPlane(id: ConstructionPlaneSourceID, plane: SketchPlane)
    case appendFeatureGraph(FeatureGraphTransaction)
    case createSketch(name: String, sketch: Sketch, geometryRole: ObjectDescriptor.GeometryRole)
    case createSemanticSketch(
        name: String,
        plan: SketchCreationPlan,
        geometryRole: ObjectDescriptor.GeometryRole
    )
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
    case createSpatialPath(name: String, path: SpatialPathFeature)
    case editSpatialPath(featureID: FeatureID, edit: SpatialPathEdit)
    case convertSketchToSpatialPath(featureID: FeatureID)
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
        plane: SketchPlane,
        name: String?
    )
    case projectCurvesToGeneratedFace(
        targets: [SelectionTarget],
        face: SelectionTarget,
        name: String?
    )
    case createProjectedCurve(
        name: String,
        source: CurveOutputReference,
        planeOrigin: Point3D,
        planeNormal: Vector3D,
        direction: Vector3D?
    )
    case projectBodyOutlinesToConstructionPlane(
        targets: [SelectionTarget],
        plane: SketchPlane,
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
    case setExtrudeExtents(featureID: FeatureID, start: CADExpression, end: CADExpression)
    case setExtrudeDistance(featureID: FeatureID, distance: CADExpression)
    case setFeatureLength(featureID: FeatureID, expression: CADExpression)
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
    /// Fillet Vertex on several selected curve ends, each corner once, as one step.
    case applySketchCornerTreatments(vertices: [SelectionTarget], distance: CADExpression, treatment: SketchCornerTreatment)
    case createSlotSketch(target: SelectionTarget, width: CADExpression)
    case offsetBodyFace(target: SelectionTarget, distance: CADExpression)
    case deleteBodyFaces(targets: [SelectionTarget])
    case draftBodyFaces(targets: [SelectionTarget], neutralTarget: SelectionTarget, angle: CADExpression)
    case chamferBodyEdges(targets: [SelectionTarget], distance: CADExpression)
    case createBodyEdgeTreatment(name: String, target: SelectionTarget, treatment: BodyEdgeTreatment)
    case createSheetSurfaceEdit(name: String, target: SelectionTarget, edit: SheetSurfaceEdit)
    case createSurfaceFill(name: String, target: SelectionTarget)
    case createBoundaryBridge(
        name: String,
        first: SelectionTarget,
        second: SelectionTarget,
        reverseSecondBoundary: Bool
    )
    case createBodyShell(name: String, target: SelectionTarget, thickness: CADExpression)
    case filletBodyEdges(targets: [SelectionTarget], radius: CADExpression, segmentCount: Int)
    case moveBodyEdge(target: SelectionTarget, deltaX: CADExpression, deltaY: CADExpression)
    /// Move Edges: moves edges of one body by `distance` along `direction` in the body's frame,
    /// through the kernel's edge move.
    case moveBodyEdges(targets: [SelectionTarget], direction: Vector3D, distance: CADExpression)
    /// Move Faces: moves planar faces of one body through the kernel's face move.
    case moveBodyFaces(targets: [SelectionTarget], direction: Vector3D, distance: CADExpression)
    /// Move Vertices: moves vertices of one body through the kernel's vertex move.
    case moveBodyVertices(targets: [SelectionTarget], direction: Vector3D, distance: CADExpression)
    /// Rotate or Scale Edges, Faces or Vertices: moves them together by one motion in their body's
    /// frame through the kernel's topology transform.
    case transformBodyTopology(kind: BodyTopologyMoveKind, targets: [SelectionTarget], motion: TopologyMotion)
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
    /// Insert Knot: a control point inserted at the spline's point nearest `point`, in its sketch's
    /// plane coordinates.
    case insertSketchSplineControlPointAtPoint(target: SelectionTarget, point: Point2D)
    /// Delete Redundant Topology: the spline's joints one cubic spans are removed, keeping its shape.
    case deleteRedundantSketchSplineJoints(target: SelectionTarget)
    /// Raise Curve Degree: each target line or spline one degree higher, the same curve.
    case raiseSketchCurveDegree(targets: [SelectionTarget])
    /// Convert Vertex: an interior vertex a spline passes through becomes an ordinary control point.
    case convertSketchSplineVertex(target: SelectionTarget)
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
    /// Dependent Curve Extend: the target end extends in `shape` until it meets `limit`.
    case extendSketchCurveToCurve(target: SelectionTarget, limit: SelectionTarget, shape: ExtendCurveShape)
    /// Bridge Curve between two ends on curves or edges that need not share a sketch.
    case createBridgeCurveBetweenEnds(
        first: SpatialBridgeEnd, second: SpatialBridgeEnd, continuity: BridgeCurveContinuity,
        tensions: SpatialBridgeTensions = SpatialBridgeTensions()
    )
    /// Project Curve Curve: where two sketch curves' extrusions meet.
    case projectCurveIntersection(first: SelectionTarget, second: SelectionTarget)
    /// Project Body Body: the curves where two bodies meet.
    case projectBodyIntersection(first: SelectionTarget, second: SelectionTarget)
    /// Create Outline: the bodies' silhouette along the plane's normal, left on the bodies as 3D curves.
    case createBodyOutlines(targets: [SelectionTarget], plane: SketchPlane)
    /// Project Curve Body along a direction onto one face (both ways when bidirectional).
    case projectCurvesAlongDirection(targets: [SelectionTarget], face: SelectionTarget, direction: Vector3D, bidirectional: Bool)
    /// Deform Curve: sketch curves carried from a reference face onto a target face as spatial paths.
    case deformCurves(targets: [SelectionTarget], referenceFace: SelectionTarget, targetFace: SelectionTarget, options: CurveDeformationOptions)
    /// Align on two curves: the second curve's nearest end aligned with the first's.
    case alignSketchCurveEnds(first: SelectionTarget, second: SelectionTarget, options: SketchVertexAlignmentOptions)
    /// Complete Edge: extends a sketch curve's open ends to the nearest curve its extension meets.
    case completeSketchCurve(target: SelectionTarget)
    /// Subdivide: splits every span of a sketch spline at its middle.
    case subdivideSketchSpline(target: SelectionTarget)
    /// Subdivide: raises a B-spline surface's degree and adds a span in each direction.
    case subdivideSurface(target: SelectionTarget)
    case joinSketchCurves(
        target: SelectionTarget,
        adjacentTarget: SelectionTarget,
        continuity: SketchCurveJoinContinuity = .g0
    )
    /// Join Curves on two or more curves: their meeting free ends become joints of one joined curve.
    case joinSketchCurveChain(targets: [SelectionTarget], continuity: SketchCurveJoinContinuity = .g0)
    case unjoinSketchCurve(target: SelectionTarget)
    case splitSketchCurve(target: SelectionTarget, fraction: CADExpression)
    case trimSketchCurveSegment(target: SelectionTarget)
    /// Trim: removes the segment of the curve holding the point nearest `point`, in its sketch's
    /// plane coordinates, bounded by its ends, its crossings with the sketch's other curves and a
    /// spline's span joints.
    case trimSketchCurve(target: SelectionTarget, point: Point2D)
    /// Split Segment: inserts a vertex into the curve at its point nearest `point`, in its sketch's
    /// plane coordinates.
    case splitSketchCurveAtPoint(target: SelectionTarget, point: Point2D)
    case cutSketchCurve(target: SelectionTarget, cutter: SelectionTarget, options: CutCurveOptions)
    /// Cut Curve's dialog: every target cut wherever a cutter crosses it, as one step.
    case cutSketchCurves(targets: [SelectionTarget], cutters: [SelectionTarget], options: CutCurveOptions)
    case createExtrusion(name: String, source: ExtrudeFeature)
    case setExtrusion(featureID: FeatureID, source: ExtrudeFeature)
    case extrudeProfile(name: String, profile: ProfileReference, distance: CADExpression, direction: ExtrudeDirection, resultKind: ExtrudeResultKind = .solid)
    case extrudeSection(name: String, section: SectionReference, distance: CADExpression, startDistance: CADExpression? = nil, direction: ExtrudeDirection, resultKind: ExtrudeResultKind)
    case createRevolve(name: String, profile: ProfileReference, axis: RevolveAxis, angle: CADExpression)
    case revolveSection(name: String, section: SectionReference, axis: RevolveAxis, angle: CADExpression, resultKind: BodyKind)
    case createSweep(
        name: String,
        sections: [SectionReference],
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
    case setLoft(featureID: FeatureID, loft: LoftFeature)
    case createBoolean(
        name: String,
        targets: [BooleanTargetReference],
        tools: [BooleanToolReference],
        operation: BooleanOperation,
        keepTools: Bool,
        targetMaterial: BooleanMaterial = .default,
        toolMaterial: BooleanMaterial = .default
    )
    case cut(name: String, targets: [SceneNodeID], cutters: [CutCutter], options: CutOptions)
    case duplicateBodyFaces(name: String, targets: [SelectionTarget])
    case createConstrainedSurface(name: String, source: ConstrainedSurfaceFeature)
    case setConstrainedSurface(featureID: FeatureID, source: ConstrainedSurfaceFeature)
    case createBSplineSurface(
        name: String,
        surface: BSplineSurface3D
    )
    case createPolySplineSurface(
        name: String,
        sourceMesh: Mesh,
        options: PolySplineOptions
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
    /// Move Control Point with proportional falloff and mirror; the last target of each surface
    /// is its active control point.
    case moveSurfaceControlPointsProportionally(
        targets: [SelectionReference],
        deltaX: CADExpression,
        deltaY: CADExpression,
        deltaZ: CADExpression,
        options: SurfaceControlPointMoveOptions
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
    case createAnalyticSphere(name: String, center: Point3D, radius: Double)
    case validateDocument

    public var name: String {
        switch self {
        case .createSavedView:
            "createSavedView"
        case .updateSavedView:
            "updateSavedView"
        case .removeSavedView:
            "removeSavedView"
        case .setSectionAnalysisPlane:
            "setSectionAnalysisPlane"
        case .addMeasurementAnnotation:
            "addMeasurementAnnotation"
        case .rebaseWorkspaceOrigin:
            "rebaseWorkspaceOrigin"
        case .renameDocument:
            "renameDocument"
        case .renameSceneNode:
            "renameSceneNode"
        case .renameComponentInstance:
            "renameComponentInstance"
        case .moveSceneNodes:
            "moveSceneNodes"
        case .resetDocument:
            "resetDocument"
        case .replaceProductMetadata:
            "replaceProductMetadata"
        case .applySemanticExtensionMutations:
            "applySemanticExtensionMutations"
        case .applyNamespacedSemanticExtensionMutations:
            "applyNamespacedSemanticExtensionMutations"
        case .upsertParameter:
            "upsertParameter"
        case .renameParameter:
            "renameParameter"
        case .deleteParameter:
            "deleteParameter"
        case .setFeatureSuppression:
            "setFeatureSuppression"
        case .reorderFeatureGraph:
            "reorderFeatureGraph"
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
        case .createPatternArrayFromSceneNodes:
            "createPatternArrayFromSceneNodes"
        case .setSceneNodeVisibility:
            "setSceneNodeVisibility"
        case .setSceneNodeLock:
            "setSceneNodeLock"
        case .setSceneNodeTransform:
            "setSceneNodeTransform"
        case .groupSceneNodes:
            "groupSceneNodes"
        case .ungroupSceneNode:
            "ungroupSceneNode"
        case .deleteSceneNodes:
            "deleteSceneNodes"
        case .transformSceneNodes:
            "transformSceneNodes"
        case .mirrorSceneNodes:
            "mirrorSceneNodes"
        case .assignMaterial:
            "assignMaterial"
        case .forkMaterial:
            "forkMaterial"
        case .removeMaterial:
            "removeMaterial"
        case .editMaterial:
            "editMaterial"
        case .createMaterial:
            "createMaterial"
        case .renameMaterial:
            "renameMaterial"
        case .deleteMaterial:
            "deleteMaterial"
        case .duplicateSceneNodes:
            "duplicateSceneNodes"
        case .realizeComponentInstances:
            "realizeComponentInstances"
        case .placeSceneNodes:
            "placeSceneNodes"
        case .pasteSceneFragment:
            "pasteSceneFragment"
        case .setSceneNodeMaterial:
            "setSceneNodeMaterial"
        case .setTopologyMaterialBinding:
            "setTopologyMaterialBinding"
        case .setSceneNodeAppearance:
            "setSceneNodeAppearance"
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
        case .renameConstructionPlane:
            "renameConstructionPlane"
        case .setConstructionPlane:
            "setConstructionPlane"
        case .appendFeatureGraph:
            "appendFeatureGraph"
        case .createSketch:
            "createSketch"
        case .createSemanticSketch:
            "createSemanticSketch"
        case .createLineSketch:
            "createLineSketch"
        case .createCircleSketch:
            "createCircleSketch"
        case .createArcSketch:
            "createArcSketch"
        case .createSplineSketch:
            "createSplineSketch"
        case .createSpatialPath:
            "createSpatialPath"
        case .editSpatialPath:
            "editSpatialPath"
        case .convertSketchToSpatialPath:
            "convertSketchToSpatialPath"
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
        case .createProjectedCurve:
            "createProjectedCurve"
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
        case .setExtrudeExtents:
            "setExtrudeExtents"
        case .setExtrudeDistance:
            "setExtrudeDistance"
        case .setFeatureLength:
            "setFeatureLength"
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
        case .applySketchCornerTreatments:
            "applySketchCornerTreatments"
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
        case .createBodyEdgeTreatment:
            "createBodyEdgeTreatment"
        case .createSheetSurfaceEdit:
            "createSheetSurfaceEdit"
        case .createSurfaceFill:
            "createSurfaceFill"
        case .createBoundaryBridge:
            "createBoundaryBridge"
        case .createBodyShell:
            "createBodyShell"
        case .filletBodyEdges:
            "filletBodyEdges"
        case .moveBodyEdge:
            "moveBodyEdge"
        case .moveBodyEdges:
            "moveBodyEdges"
        case .moveBodyFaces:
            "moveBodyFaces"
        case .moveBodyVertices:
            "moveBodyVertices"
        case .transformBodyTopology:
            "transformBodyTopology"
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
        case .extendSketchCurveToCurve:
            "extendSketchCurveToCurve"
        case .deformCurves:
            "deformCurves"
        case .projectCurvesAlongDirection:
            "projectCurvesAlongDirection"
        case .createBodyOutlines:
            "createBodyOutlines"
        case .projectBodyIntersection:
            "projectBodyIntersection"
        case .projectCurveIntersection:
            "projectCurveIntersection"
        case .createBridgeCurveBetweenEnds:
            "createBridgeCurveBetweenEnds"
        case .alignSketchCurveEnds:
            "alignSketchCurveEnds"
        case .extendSketchCurve:
            "extendSketchCurve"
        case .completeSketchCurve:
            "completeSketchCurve"
        case .subdivideSketchSpline:
            "subdivideSketchSpline"
        case .subdivideSurface:
            "subdivideSurface"
        case .joinSketchCurves:
            "joinSketchCurves"
        case .joinSketchCurveChain:
            "joinSketchCurveChain"
        case .unjoinSketchCurve:
            "unjoinSketchCurve"
        case .splitSketchCurve:
            "splitSketchCurve"
        case .trimSketchCurveSegment:
            "trimSketchCurveSegment"
        case .trimSketchCurve:
            "trimSketchCurve"
        case .splitSketchCurveAtPoint:
            "splitSketchCurveAtPoint"
        case .insertSketchSplineControlPointAtPoint:
            "insertSketchSplineControlPointAtPoint"
        case .deleteRedundantSketchSplineJoints:
            "deleteRedundantSketchSplineJoints"
        case .raiseSketchCurveDegree:
            "raiseSketchCurveDegree"
        case .convertSketchSplineVertex:
            "convertSketchSplineVertex"
        case .cutSketchCurve:
            "cutSketchCurve"
        case .cutSketchCurves:
            "cutSketchCurves"
        case .createExtrusion:
            "createExtrusion"
        case .setExtrusion:
            "setExtrusion"
        case .extrudeProfile:
            "extrudeProfile"
        case .extrudeSection:
            "extrudeSection"
        case .createRevolve:
            "createRevolve"
        case .revolveSection:
            "revolveSection"
        case .createSweep:
            "createSweep"
        case .createLoft:
            "createLoft"
        case .setLoft:
            "setLoft"
        case .createBoolean:
            "createBoolean"
        case .cut:
            "cut"
        case .duplicateBodyFaces:
            "duplicateBodyFaces"
        case .createConstrainedSurface:
            "createConstrainedSurface"
        case .setConstrainedSurface:
            "setConstrainedSurface"
        case .createBSplineSurface:
            "createBSplineSurface"
        case .createPolySplineSurface:
            "createPolySplineSurface"
        case .movePolySplineSurfaceVertex:
            "movePolySplineSurfaceVertex"
        case .moveSurfaceControlPoint:
            "moveSurfaceControlPoint"
        case .moveSurfaceControlPointsInFrame:
            "moveSurfaceControlPointsInFrame"
        case .moveSurfaceControlPointsProportionally:
            "moveSurfaceControlPointsProportionally"
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
        case .createAnalyticSphere:
            "createAnalyticSphere"
        case .validateDocument:
            "validateDocument"
        }
    }

    public var mutatesDocument: Bool {
        switch self {
        case .createSavedView,
             .updateSavedView,
             .removeSavedView,
             .setSectionAnalysisPlane,
             .addMeasurementAnnotation,
             .rebaseWorkspaceOrigin,
             .renameDocument,
             .renameSceneNode,
             .renameComponentInstance,
             .moveSceneNodes,
             .resetDocument,
             .replaceProductMetadata,
             .applySemanticExtensionMutations,
             .applyNamespacedSemanticExtensionMutations,
             .upsertParameter,
             .renameParameter,
             .deleteParameter,
             .setFeatureSuppression,
             .reorderFeatureGraph,
             .createComponentDefinition,
             .createComponentInstance,
             .createPatternArray,
             .updatePatternArray,
             .explodePatternArray,
             .createPatternArrayFromSceneNodes,
             .setSceneNodeVisibility,
             .setSceneNodeLock,
             .setSceneNodeTransform,
             .groupSceneNodes,
             .ungroupSceneNode,
             .deleteSceneNodes,
             .transformSceneNodes,
             .mirrorSceneNodes,
             .assignMaterial,
             .forkMaterial,
             .removeMaterial,
             .editMaterial,
             .createMaterial,
             .renameMaterial,
             .deleteMaterial,
             .duplicateSceneNodes,
             .realizeComponentInstances,
             .placeSceneNodes,
             .pasteSceneFragment,
             .setSceneNodeMaterial,
             .setTopologyMaterialBinding,
             .setSceneNodeAppearance,
             .setSceneNodeObjectProperty,
             .setComponentInstanceVisibility,
             .setComponentInstanceLock,
             .setComponentInstanceTransform,
             .createSectionPlane,
             .createConstructionPlane,
             .createConstructionPlaneFromTarget,
             .createConstructionPlaneFromTargets,
             .createViewAlignedConstructionPlane,
             .renameConstructionPlane,
             .setConstructionPlane,
             .appendFeatureGraph,
             .createSketch,
             .createSemanticSketch,
             .createLineSketch,
             .createCircleSketch,
             .createArcSketch,
             .createSplineSketch,
             .createSpatialPath,
             .editSpatialPath,
             .convertSketchToSpatialPath,
             .createRectangleSketch,
             .createPolygonSketch,
             .createFaceKnife,
             .projectSketchCurvesToConstructionPlane,
             .projectCurvesToGeneratedFace,
             .createProjectedCurve,
             .projectBodyOutlinesToConstructionPlane,
             .addSketchConstraint,
             .removeSketchConstraint,
             .createBridgeCurve,
             .setBridgeCurveParameters,
             .createRectangleSketchFromCorners,
             .setExtrudeExtents,
             .setExtrudeDistance,
             .setFeatureLength,
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
             .applySketchCornerTreatments,
             .createSlotSketch,
             .offsetBodyFace,
             .deleteBodyFaces,
             .draftBodyFaces,
             .chamferBodyEdges,
             .createBodyEdgeTreatment,
             .createSheetSurfaceEdit,
             .createSurfaceFill,
             .createBoundaryBridge,
             .createBodyShell,
             .filletBodyEdges,
             .moveBodyEdge,
             .moveBodyEdges,
             .moveBodyFaces,
             .moveBodyVertices,
             .transformBodyTopology,
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
             .extendSketchCurveToCurve,
             .deformCurves,
             .projectCurvesAlongDirection,
             .createBodyOutlines,
             .projectBodyIntersection,
             .projectCurveIntersection,
             .createBridgeCurveBetweenEnds,
             .alignSketchCurveEnds,
             .completeSketchCurve,
             .subdivideSketchSpline,
             .subdivideSurface,
             .joinSketchCurves,
             .joinSketchCurveChain,
             .unjoinSketchCurve,
             .splitSketchCurve,
             .trimSketchCurveSegment,
             .trimSketchCurve,
             .splitSketchCurveAtPoint,
             .insertSketchSplineControlPointAtPoint,
             .deleteRedundantSketchSplineJoints,
             .raiseSketchCurveDegree,
             .convertSketchSplineVertex,
             .cutSketchCurve,
             .cutSketchCurves,
             .createExtrusion,
             .setExtrusion,
             .extrudeProfile,
             .extrudeSection,
             .createRevolve,
             .revolveSection,
             .createSweep,
             .createLoft,
             .setLoft,
             .createBoolean,
             .cut,
             .duplicateBodyFaces,
             .createConstrainedSurface,
             .setConstrainedSurface,
             .createBSplineSurface,
             .createPolySplineSurface,
             .movePolySplineSurfaceVertex,
             .moveSurfaceControlPoint,
             .moveSurfaceControlPointsInFrame,
             .moveSurfaceControlPointsProportionally,
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
             .createExtrudedCircle,
             .createAnalyticSphere:
            true
        case .validateDocument:
            false
        }
    }
}
