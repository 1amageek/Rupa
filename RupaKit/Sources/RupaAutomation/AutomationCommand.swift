import Foundation
import RupaCore

public enum AutomationCommand: Codable, Equatable, Sendable {
    case describeDocument
    case setDisplayUnit(LengthDisplayUnit)
    case renameDocument(name: String)
    case upsertParameter(name: String, expression: CADExpression, kind: QuantityKind)
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
    case setComponentInstanceVisibility(id: ComponentInstanceID, isVisible: Bool)
    case setComponentInstanceLock(id: ComponentInstanceID, isLocked: Bool)
    case setComponentInstanceTransform(id: ComponentInstanceID, localTransform: Transform3D)
    case createSectionPlane(name: String)
    case describeConstructionPlanes
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
    case chamferBodyEdges(targets: [SelectionTarget], distance: CADExpression)
    case filletBodyEdges(targets: [SelectionTarget], radius: CADExpression, segmentCount: Int)
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
    case createPolySplineSurface(
        name: String,
        sourceMesh: Mesh,
        options: PolySplineOptions
    )
    case setSurfaceControlPointDisplay(target: SelectionReference, isVisible: Bool?)
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

    public var editorCommand: EditorCommand? {
        switch self {
        case .describeDocument:
            nil
        case .setDisplayUnit(let unit):
            .setDisplayUnit(unit)
        case .renameDocument(let name):
            .renameDocument(name: name)
        case .upsertParameter(let name, let expression, let kind):
            .upsertParameter(
                name: name,
                expression: expression,
                kind: kind
            )
        case .deleteParameter(let name):
            .deleteParameter(name: name)
        case .createComponentDefinition(let name, let rootSceneNodeIDs):
            .createComponentDefinition(
                name: name,
                rootSceneNodeIDs: rootSceneNodeIDs
            )
        case .createComponentInstance(let name, let definitionID, let localTransform):
            .createComponentInstance(
                name: name,
                definitionID: definitionID,
                localTransform: localTransform
            )
        case .createPatternArray(let name, let definitionID, let distribution, let outputMode):
            .createPatternArray(
                name: name,
                definitionID: definitionID,
                distribution: distribution,
                outputMode: outputMode
            )
        case .updatePatternArray(let id, let name, let definitionID, let distribution, let outputMode):
            .updatePatternArray(
                id: id,
                name: name,
                definitionID: definitionID,
                distribution: distribution,
                outputMode: outputMode
            )
        case .explodePatternArray(let id):
            .explodePatternArray(id: id)
        case .setSceneNodeVisibility(let id, let isVisible):
            .setSceneNodeVisibility(id: id, isVisible: isVisible)
        case .setSceneNodeLock(let id, let isLocked):
            .setSceneNodeLock(id: id, isLocked: isLocked)
        case .setSceneNodeTransform(let id, let localTransform):
            .setSceneNodeTransform(
                id: id,
                localTransform: localTransform
            )
        case .setComponentInstanceVisibility(let id, let isVisible):
            .setComponentInstanceVisibility(id: id, isVisible: isVisible)
        case .setComponentInstanceLock(let id, let isLocked):
            .setComponentInstanceLock(id: id, isLocked: isLocked)
        case .setComponentInstanceTransform(let id, let localTransform):
            .setComponentInstanceTransform(
                id: id,
                localTransform: localTransform
            )
        case .createSectionPlane(let name):
            .createSectionPlane(name: name)
        case .describeConstructionPlanes:
            nil
        case .createConstructionPlane(let name, let plane, let activates):
            .createConstructionPlane(
                name: name,
                plane: plane,
                activates: activates
            )
        case .createConstructionPlaneFromTarget(let name, let target, let activates):
            .createConstructionPlaneFromTarget(
                name: name,
                target: target,
                activates: activates
            )
        case .createConstructionPlaneFromTargets(let name, let targets, let viewNormal, let activates):
            .createConstructionPlaneFromTargets(
                name: name,
                targets: targets,
                viewNormal: viewNormal,
                activates: activates
            )
        case .createViewAlignedConstructionPlane(let name, let origin, let viewNormal, let activates):
            .createViewAlignedConstructionPlane(
                name: name,
                origin: origin,
                viewNormal: viewNormal,
                activates: activates
            )
        case .setActiveConstructionPlane(let id):
            .setActiveConstructionPlane(id: id)
        case .renameConstructionPlane(let id, let name):
            .renameConstructionPlane(id: id, name: name)
        case .setCurveCurvatureDisplay(let target, let isVisible, let combScale):
            .setCurveCurvatureDisplay(
                target: target,
                isVisible: isVisible,
                combScale: combScale
            )
        case .setPointDisplay(let target, let isVisible):
            .setPointDisplay(target: target, isVisible: isVisible)
        case .createSketch(let name, let sketch, let geometryRole):
            .createSketch(
                name: name,
                sketch: sketch,
                geometryRole: geometryRole
            )
        case .createLineSketch(let name, let plane, let start, let end):
            .createLineSketch(
                name: name,
                plane: plane,
                start: start,
                end: end
            )
        case .createCircleSketch(let name, let plane, let center, let radius):
            .createCircleSketch(
                name: name,
                plane: plane,
                center: center,
                radius: radius
            )
        case .createArcSketch(let name, let plane, let center, let radius, let startAngle, let endAngle):
            .createArcSketch(
                name: name,
                plane: plane,
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle
            )
        case .createSplineSketch(let name, let plane, let spline):
            .createSplineSketch(
                name: name,
                plane: plane,
                spline: spline
            )
        case .createRectangleSketch(let name, let plane, let width, let height):
            .createRectangleSketch(
                name: name,
                plane: plane,
                width: width,
                height: height
            )
        case .createPolygonSketch(
            let name,
            let plane,
            let center,
            let radius,
            let sides,
            let sizingMode,
            let inclinationMode,
            let rotationAngle
        ):
            .createPolygonSketch(
                name: name,
                plane: plane,
                center: center,
                radius: radius,
                sides: sides,
                sizingMode: sizingMode,
                inclinationMode: inclinationMode,
                rotationAngle: rotationAngle
            )
        case .createFaceKnife(let name, let target, let loop):
            .createFaceKnife(
                name: name,
                target: target,
                loop: loop
            )
        case .setObjectDimension(let target, let kind, let value):
            .setObjectDimension(
                target: target,
                kind: kind,
                value: value
            )
        case .addSelectionDimension(let name, let kind, let first, let second, let target):
            .addSelectionDimension(
                name: name,
                kind: kind,
                first: first,
                second: second,
                target: target
            )
        case .removeSelectionDimension(let id):
            .removeSelectionDimension(id: id)
        case .addSketchConstraint(let featureID, let constraint):
            .addSketchConstraint(
                featureID: featureID,
                constraint: constraint
            )
        case .removeSketchConstraint(let featureID, let constraint):
            .removeSketchConstraint(
                featureID: featureID,
                constraint: constraint
            )
        case .createBridgeCurve(let featureID, let firstEndpoint, let secondEndpoint, let continuity, let trimsSourceCurves):
            .createBridgeCurve(
                featureID: featureID,
                firstEndpoint: firstEndpoint,
                secondEndpoint: secondEndpoint,
                continuity: continuity,
                trimsSourceCurves: trimsSourceCurves
            )
        case .setBridgeCurveParameters(let sourceID, let firstEndpoint, let secondEndpoint, let continuity, let trimsSourceCurves):
            .setBridgeCurveParameters(
                sourceID: sourceID,
                firstEndpoint: firstEndpoint,
                secondEndpoint: secondEndpoint,
                continuity: continuity,
                trimsSourceCurves: trimsSourceCurves
            )
        case .offsetCurve(let target, let distance, let options, let vertexHandle):
            .offsetCurve(
                target: target,
                distance: distance,
                options: options,
                vertexHandle: vertexHandle
            )
        case .offsetRegions(let targets, let distance, let options, let combinesRegions):
            .offsetRegions(
                targets: targets,
                distance: distance,
                options: options,
                combinesRegions: combinesRegions
            )
        case .offsetSketchVertex(let target, let handle, let distance):
            .offsetSketchVertex(
                target: target,
                handle: handle,
                distance: distance
            )
        case .applySketchCornerTreatment(let target, let adjacentTarget, let distance, let treatment):
            .applySketchCornerTreatment(
                target: target,
                adjacentTarget: adjacentTarget,
                distance: distance,
                treatment: treatment
            )
        case .createSlotSketch(let target, let width):
            .createSlotSketch(
                target: target,
                width: width
            )
        case .offsetBodyFace(let target, let distance):
            .offsetBodyFace(
                target: target,
                distance: distance
            )
        case .chamferBodyEdges(let targets, let distance):
            .chamferBodyEdges(
                targets: targets,
                distance: distance
            )
        case .filletBodyEdges(let targets, let radius, let segmentCount):
            .filletBodyEdges(
                targets: targets,
                radius: radius,
                segmentCount: segmentCount
            )
        case .moveBodyVertex(let target, let deltaX, let deltaY):
            .moveBodyVertex(
                target: target,
                deltaX: deltaX,
                deltaY: deltaY
            )
        case .moveSketchEntityPoint(let target, let handle, let deltaX, let deltaY):
            .moveSketchEntityPoint(
                target: target,
                handle: handle,
                deltaX: deltaX,
                deltaY: deltaY
            )
        case .moveSketchSplineControlPoint(let target, let controlPointIndex, let deltaX, let deltaY):
            .moveSketchSplineControlPoint(
                target: target,
                controlPointIndex: controlPointIndex,
                deltaX: deltaX,
                deltaY: deltaY
            )
        case .slideSketchSplineControlPoints(let target, let controlPointIndexes, let direction, let distance):
            .slideSketchSplineControlPoints(
                target: target,
                controlPointIndexes: controlPointIndexes,
                direction: direction,
                distance: distance
            )
        case .insertSketchSplineControlPoint(let target, let fraction):
            .insertSketchSplineControlPoint(
                target: target,
                fraction: fraction
            )
        case .setSketchCircleParameters(let target, let center, let radius):
            .setSketchCircleParameters(
                target: target,
                center: center,
                radius: radius
            )
        case .setSketchArcParameters(let target, let center, let radius, let startAngle, let endAngle):
            .setSketchArcParameters(
                target: target,
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle
            )
        case .setSketchEntityDimension(let target, let kind, let value):
            .setSketchEntityDimension(
                target: target,
                kind: kind,
                value: value
            )
        case .convertSketchLineToArc(let target, let sagitta):
            .convertSketchLineToArc(
                target: target,
                sagitta: sagitta
            )
        case .convertSketchLineToSpline(let target):
            .convertSketchLineToSpline(target: target)
        case .reverseSketchCurve(let target):
            .reverseSketchCurve(target: target)
        case .rebuildSketchCurve(let target, let options):
            .rebuildSketchCurve(target: target, options: options)
        case .extendSketchCurve(let target, let distance, let shape):
            .extendSketchCurve(
                target: target,
                distance: distance,
                shape: shape
            )
        case .splitSketchCurve(let target, let fraction):
            .splitSketchCurve(target: target, fraction: fraction)
        case .trimSketchCurveSegment(let target):
            .trimSketchCurveSegment(target: target)
        case .cutSketchCurve(let target, let cutter, let options):
            .cutSketchCurve(target: target, cutter: cutter, options: options)
        case .extrudeProfile(let name, let profile, let distance, let direction):
            .extrudeProfile(
                name: name,
                profile: profile,
                distance: distance,
                direction: direction
            )
        case .setExtrudeDistance(let featureID, let distance):
            .setExtrudeDistance(
                featureID: featureID,
                distance: distance
            )
        case .setCubeDimensions(let featureID, let sizeX, let sizeY, let sizeZ):
            .setCubeDimensions(
                featureID: featureID,
                sizeX: sizeX,
                sizeY: sizeY,
                sizeZ: sizeZ
            )
        case .setCylinderDimensions(let featureID, let radius, let sizeY):
            .setCylinderDimensions(
                featureID: featureID,
                radius: radius,
                sizeY: sizeY
            )
        case .createRevolve(let name, let profile, let axis, let angle):
            .createRevolve(
                name: name,
                profile: profile,
                axis: axis,
                angle: angle
            )
        case .createSweep(let name, let sections, let path, let guides, let targets, let options):
            .createSweep(
                name: name,
                sections: sections,
                path: path,
                guides: guides,
                targets: targets,
                options: options
            )
        case .createPolySplineSurface(let name, let sourceMesh, let options):
            .createPolySplineSurface(
                name: name,
                sourceMesh: sourceMesh,
                options: options
            )
        case .setSurfaceControlPointDisplay(let target, let isVisible):
            .setSurfaceControlPointDisplay(target: target, isVisible: isVisible)
        case .movePolySplineSurfaceVertex(let target, let deltaX, let deltaY, let deltaZ):
            .movePolySplineSurfaceVertex(
                target: target,
                deltaX: deltaX,
                deltaY: deltaY,
                deltaZ: deltaZ
            )
        case .moveSurfaceControlPoint(let target, let deltaX, let deltaY, let deltaZ):
            .moveSurfaceControlPoint(
                target: target,
                deltaX: deltaX,
                deltaY: deltaY,
                deltaZ: deltaZ
            )
        case .slidePolySplineSurfaceVertices(let targets, let direction, let distance):
            .slidePolySplineSurfaceVertices(
                targets: targets,
                direction: direction,
                distance: distance
            )
        case .slideSurfaceControlPoints(let targets, let direction, let distance):
            .slideSurfaceControlPoints(
                targets: targets,
                direction: direction,
                distance: distance
            )
        case .createExtrudedRectangle(let name, let plane, let width, let height, let depth, let direction):
            .createExtrudedRectangle(
                name: name,
                plane: plane,
                width: width,
                height: height,
                depth: depth,
                direction: direction
            )
        case .createExtrudedRectangleFromCorners(
            let name,
            let plane,
            let firstCorner,
            let oppositeCorner,
            let depth,
            let direction
        ):
            .createExtrudedRectangleFromCorners(
                name: name,
                plane: plane,
                firstCorner: firstCorner,
                oppositeCorner: oppositeCorner,
                depth: depth,
                direction: direction
            )
        case .createExtrudedCircle(let name, let plane, let center, let radius, let depth, let direction):
            .createExtrudedCircle(
                name: name,
                plane: plane,
                center: center,
                radius: radius,
                depth: depth,
                direction: direction
            )
        case .validateDocument:
            .validateDocument
        }
    }
}
