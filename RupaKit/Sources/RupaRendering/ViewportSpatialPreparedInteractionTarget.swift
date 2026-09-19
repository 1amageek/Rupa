import Foundation
import RupaCore
import RupaViewportScene

/// Source-frame operation baselines. Projection and drag state belong to the
/// input owner, not to this camera-independent preparation value.
enum ViewportSpatialPreparedInteractionTarget: Sendable {
    struct Axis: Sendable {
        let origin: Point3D
        let direction: Vector3D
        let baseValue: Double
        let sourceUnitsPerWorldMetre: Double?

        init(origin: Point3D, direction: Vector3D, baseValue: Double,
             sourceUnitsPerWorldMetre: Double? = nil) {
            self.origin = origin
            self.direction = direction
            self.baseValue = baseValue
            self.sourceUnitsPerWorldMetre = sourceUnitsPerWorldMetre
        }
    }

    struct AffordanceBodyMember: Sendable {
        let occurrenceID: String
        let featureID: FeatureID
        let sceneNodeID: SceneNodeID?
        let modelTransform: Transform3D
        let edit: ViewportObjectEditState
        var placement: ViewportBodyPlacementBaseline? = nil
    }

    case sketchCurveHandle(ViewportSketchCurveHandleTarget)
    case sketchDimension(ViewportSketchDimensionTarget)
    case sketchPointHandle(ViewportSketchPointHandleTarget)
    case bridgeCurveEndpoint(handle: BridgeCurveEndpointHandle, modelTransform: Transform3D)
    case splineControlPoint(ViewportSplineControlPointHandleTarget)
    case splineControlPointSlide(featureID: FeatureID, entityID: SketchEntityID, target: SelectionTarget,
                                 controlPointIndexes: [Int], direction: SplineControlPointSlideDirection, axis: Axis)
    case polySplineSurfaceVertex(ViewportPolySplineSurfaceVertexHandleTarget)
    case polySplineSurfaceVertexSlide(targets: [SelectionTarget], direction: PolySplineSurfaceVertexSlideDirection, axis: Axis)
    case surfaceControlPoint(ViewportSurfaceControlPointHandleTarget)
    case surfaceControlPointSlide(targets: [SelectionReference], direction: PolySplineSurfaceVertexSlideDirection, axis: Axis)
    case surfaceTrimEndpoint(ViewportSurfaceTrimEndpointHandleTarget)
    case surfaceTrimControlPoint(ViewportSurfaceTrimControlPointHandleTarget)
    case surfaceFrame(targets: [SelectionReference], query: SurfaceFrameQuery, displayID: SurfaceFrameDisplayID,
                      axis: ViewportSurfaceFrameAxis, geometry: Axis)
    case regionOffset(featureID: FeatureID, componentID: SelectionComponentID, target: SelectionTarget, axis: Axis)
    case edgeOffset(featureID: FeatureID, edge: ViewportBodyEdge, target: SelectionTarget,
                    edgeStart: Point3D, edgeEnd: Point3D, axis: Axis)
    case slotWidth(featureID: FeatureID, entityID: SketchEntityID, target: SelectionTarget, axis: Axis)
    case sketchVertexOffset(featureID: FeatureID, entityID: SketchEntityID, target: SelectionTarget,
                            handle: SketchEntityPointHandle, axis: Axis)
    case patternArrayLinearAxis(ViewportPatternAffordanceSource.LinearAxisHandle)
    case independentCopyExtrudeDistance(ViewportPatternAffordanceSource.IndependentCopyExtrudeHandle)
    case independentCopyBodyDimension(ViewportPatternAffordanceSource.IndependentCopyDimensionHandle)
    case patternArrayRadialAngle(ViewportPatternAffordanceSource.RadialAngleHandle)
    case patternArrayCopyCount(ViewportPatternAffordanceSource.CopyCountHandle)
    case patternArrayCurveExtent(ViewportPatternAffordanceSource.CurveExtentHandle)
    case patternArrayCurvePathPoint(ViewportPatternAffordanceSource.CurvePathPointHandle)
    case patternArrayOutputMode(ViewportPatternAffordanceSource.OutputModeHandle)
    case constructionPlane(identity: ViewportConstructionPlaneHandleIdentity, origin: Point3D,
                           normal: Vector3D, normalEnd: Point3D, corners: [Point3D])
    case affordance(target: ViewportAffordanceTarget, members: [AffordanceBodyMember],
                    groupEdit: ViewportObjectEditState?, placement: ViewportBodyPlacementBaseline?)
    case objectTransform(action: ViewportAffordanceAction, members: [ViewportObjectTransformMember], bounds: ViewportObjectEditState)

    var spatialIdentity: ViewportSpatialHandleIdentity {
        get throws {
            switch self {
            case .sketchCurveHandle(let value): .sketchCurveHandle(value.identity)
            case .sketchDimension(let value): .sketchDimension(value.identity)
            case .sketchPointHandle(let value): .sketchPointHandle(value.identity)
            case .bridgeCurveEndpoint(let value, _):
                .bridgeCurveEndpoint(.init(sourceID: value.sourceID, role: value.role))
            case .splineControlPoint(let value): .splineControlPoint(value.identity)
            case .splineControlPointSlide(let featureID, let entityID, _, let indexes, let direction, _):
                .splineControlPointSlide(.init(featureID: featureID, entityID: entityID,
                                              controlPointIndexes: indexes, direction: direction))
            case .polySplineSurfaceVertex(let value):
                .polySplineSurfaceVertex(featureID: value.featureID, componentID: value.componentID,
                                         role: .init(value.dragMode))
            case .polySplineSurfaceVertexSlide(let targets, let direction, _):
                .polySplineSurfaceVertexSlide(.init(targets: targets, direction: direction))
            case .surfaceControlPoint(let value):
                .surfaceControlPoint(.init(value.target), role: .init(value.dragMode))
            case .surfaceControlPointSlide(let targets, let direction, _):
                .surfaceControlPointSlide(try ViewportSpatialReferenceAddress.project(targets), direction: direction)
            case .surfaceTrimEndpoint(let value): .surfaceTrimEndpoint(.init(value.target), endpoint: value.endpoint)
            case .surfaceTrimControlPoint(let value): .surfaceTrimControlPoint(.init(value.target), index: value.controlPointIndex)
            case .surfaceFrame(let targets, _, let displayID, let axis, _):
                .surfaceFrame(try ViewportSpatialReferenceAddress.project(targets), displayID: displayID, axis: axis)
            case .regionOffset(let featureID, let componentID, _, _):
                .regionOffset(.init(featureID: featureID, componentID: componentID))
            case .edgeOffset(let featureID, let edge, _, _, _, _): .edgeOffset(.init(featureID: featureID, edge: edge))
            case .slotWidth(let featureID, let entityID, _, _): .slotWidth(.init(featureID: featureID, entityID: entityID))
            case .sketchVertexOffset(let featureID, let entityID, _, let handle, _):
                .sketchVertexOffset(.init(featureID: featureID, entityID: entityID, handle: handle))
            case .patternArrayLinearAxis(let value): .patternArrayLinearAxis(.init(sourceID: value.sourceID, axisSlot: value.axisSlot))
            case .independentCopyExtrudeDistance(let value):
                .independentCopyExtrudeDistance(.init(sourceID: value.sourceID, outputIndex: value.outputIndex, featureID: value.featureID))
            case .independentCopyBodyDimension(let value):
                .independentCopyBodyDimension(.init(sourceID: value.sourceID, outputIndex: value.outputIndex,
                                                   featureID: value.featureID, kind: value.kind))
            case .patternArrayRadialAngle(let value): .patternArrayRadialAngle(.init(sourceID: value.sourceID))
            case .patternArrayCopyCount(let value): .patternArrayCopyCount(.init(sourceID: value.sourceID, slot: value.slot))
            case .patternArrayCurveExtent(let value): .patternArrayCurveExtent(.init(sourceID: value.sourceID))
            case .patternArrayCurvePathPoint(let value):
                .patternArrayCurvePathPoint(.init(sourceID: value.sourceID, pointIndex: value.pointIndex))
            case .patternArrayOutputMode(let value): .patternArrayOutputMode(.init(sourceID: value.sourceID))
            case .constructionPlane(let identity, _, _, _, _): .constructionPlane(identity)
            case .affordance(let target, _, _, _): .affordance(target)
            case .objectTransform(let action, let members, _):
                .objectTransform(nodes: members.map(\.sceneNodeID), action: action)
            }
        }
    }
}
