import Foundation
import RupaCore
import SwiftUI
import RupaViewportScene

struct ViewportActiveDrag: Equatable {
    var startLocation: CGPoint
    var currentLocation: CGPoint
    var kind: Kind
    var sketchPlane: SketchPlane? = nil

    enum Kind: Equatable {
        case creation(ViewportCanvasDragPreviewKind)
        case selection
    }

    var accessibilityIdentifier: String {
        switch kind {
        case .creation:
            "CanvasDragPlaceholder"
        case .selection:
            "CanvasSelectionRectangle"
        }
    }

    var accessibilityLabel: String {
        switch kind {
        case .creation(.rectangle):
            "Canvas drag placeholder"
        case .creation(.polygon):
            "Canvas polygon drag preview"
        case .creation(.arc):
            "Canvas arc drag preview"
        case .creation(.spline):
            "Canvas spline drag preview"
        case .selection:
            "Canvas selection rectangle"
        }
    }
}

struct ViewportProjectionTransition: Equatable {
    var id: UUID = UUID()
    var startBasis: ViewportProjectionBasis
    var targetBasis: ViewportProjectionBasis
    var startDate: Date
    var duration: TimeInterval

    func basis(at date: Date) -> ViewportProjectionBasis {
        let elapsed = max(date.timeIntervalSince(startDate), 0.0)
        let rawProgress = CGFloat(elapsed / max(duration, 1.0e-9))
        let progress = min(max(rawProgress, 0.0), 1.0)
        let easedProgress = progress * progress * (3.0 - 2.0 * progress)
        return ViewportProjectionBasis.interpolated(
            from: startBasis,
            to: targetBasis,
            progress: easedProgress
        )
    }
}

struct ViewportAffordanceDragState: Equatable {
    var target: ViewportAffordanceTarget
    var startPoint: CGPoint
    var baseEdits: [FeatureID: ViewportObjectEditState]
    var baseGroupEdit: ViewportObjectEditState?
}

struct ViewportSplineControlPointDragState: Equatable {
    var target: ViewportSplineControlPointHandleTarget
    var startPoint: CGPoint
    var viewportDelta: CGPoint
}

struct ViewportBridgeCurveEndpointDragState: Equatable {
    var target: ViewportBridgeCurveEndpointHandleTarget
    var startPoint: CGPoint
    var endpoint: BridgeCurveEndpoint
    var parameter: Double
    var projectedPoint: CGPoint
    var projectedTangentTip: CGPoint
}

struct ViewportSplineControlPointSlideDragState: Equatable {
    var target: ViewportSplineControlPointSlideHandleTarget
    var startPoint: CGPoint
    var distanceMeters: Double
}

struct ViewportPolySplineSurfaceVertexDragState: Equatable {
    var target: ViewportPolySplineSurfaceVertexHandleTarget
    var startPoint: CGPoint
    var delta: Point3D
}

struct ViewportSurfaceControlPointDragState: Equatable {
    var target: ViewportSurfaceControlPointHandleTarget
    var startPoint: CGPoint
    var delta: Point3D
}

struct ViewportSurfaceTrimEndpointDragState: Equatable {
    var target: ViewportSurfaceTrimEndpointHandleTarget
    var startPoint: CGPoint
    var delta: Point3D
}

struct ViewportSurfaceTrimControlPointDragState: Equatable {
    var target: ViewportSurfaceTrimControlPointHandleTarget
    var startPoint: CGPoint
    var delta: Point3D
}

struct ViewportPolySplineSurfaceVertexSlideDragState: Equatable {
    var target: ViewportPolySplineSurfaceVertexSlideHandleTarget
    var startPoint: CGPoint
    var distanceMeters: Double
}

struct ViewportSurfaceControlPointSlideDragState: Equatable {
    var target: ViewportSurfaceControlPointSlideHandleTarget
    var startPoint: CGPoint
    var distanceMeters: Double
}

struct ViewportSurfaceFrameDragState: Equatable {
    var target: ViewportSurfaceFrameHandleTarget
    var startPoint: CGPoint
    var distanceMeters: Double
}

struct ViewportRegionOffsetDragState: Equatable {
    var target: ViewportRegionOffsetHandleTarget
    var startPoint: CGPoint
    var distanceMeters: Double
}

struct ViewportEdgeOffsetDragState: Equatable {
    var target: ViewportEdgeOffsetHandleTarget
    var startPoint: CGPoint
    var distanceMeters: Double
}

struct ViewportSlotWidthDragState: Equatable {
    var target: ViewportSlotWidthHandleTarget
    var startPoint: CGPoint
    var widthMeters: Double
}

struct ViewportPatternArrayLinearAxisDragState: Equatable {
    var target: ViewportPatternArrayLinearAxisHandleTarget
    var startPoint: CGPoint
    var distanceMeters: Double
}

struct ViewportIndependentCopyExtrudeDistanceDragState: Equatable {
    var target: ViewportIndependentCopyExtrudeDistanceHandleTarget
    var startPoint: CGPoint
    var distanceMeters: Double
}

struct ViewportIndependentCopyBodyDimensionDragState: Equatable {
    var target: ViewportIndependentCopyBodyDimensionHandleTarget
    var startPoint: CGPoint
    var valueMeters: Double
}

struct ViewportPatternArrayRadialAngleDragState: Equatable {
    var target: ViewportPatternArrayRadialAngleHandleTarget
    var startPoint: CGPoint
    var angleRadians: Double
}

struct ViewportPatternArrayCopyCountDragState: Equatable {
    var target: ViewportPatternArrayCopyCountHandleTarget
    var startPoint: CGPoint
    var copyCount: Int
}

struct ViewportPatternArrayCurveExtentDragState: Equatable {
    var target: ViewportPatternArrayCurveExtentHandleTarget
    var startPoint: CGPoint
    var distanceMeters: Double
}

struct ViewportPatternArrayCurvePathPointDragState: Equatable {
    var target: ViewportPatternArrayCurvePathPointHandleTarget
    var startPoint: CGPoint
    var point: Point3D
}

struct ViewportSketchVertexOffsetDragState: Equatable {
    var target: ViewportSketchVertexOffsetHandleTarget
    var startPoint: CGPoint
    var distanceMeters: Double
}

struct ViewportSketchCurveHandleDragState: Equatable {
    var target: ViewportSketchCurveHandleTarget
    var startPoint: CGPoint
    var radiusMeters: Double?
    var startAngleRadians: Double?
    var endAngleRadians: Double?
}

struct ViewportSketchCurveHandleCandidate: Equatable {
    var handle: ViewportSketchCurveHandleKind
    var point: CGPoint
    var center: CGPoint
    var radiusMeters: Double
    var startAngleRadians: Double?
    var endAngleRadians: Double?
}

struct ViewportSketchCurveHandleTarget: Equatable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var target: SelectionTarget
    var handle: ViewportSketchCurveHandleKind
    var sketchPlane: SketchPlane
    var center: CGPoint
    var radiusMeters: Double
    var startAngleRadians: Double?
    var endAngleRadians: Double?

    var identity: ViewportSketchCurveHandleIdentity {
        ViewportSketchCurveHandleIdentity(
            featureID: featureID,
            entityID: entityID,
            handle: handle
        )
    }
}

struct ViewportSketchCurveHandleIdentity: Equatable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var handle: ViewportSketchCurveHandleKind
}

struct ViewportSketchDimensionDragState: Equatable {
    var target: ViewportSketchDimensionTarget
    var startPoint: CGPoint
    var value: Double
}

struct ViewportSketchDimensionCandidate: Equatable {
    var kind: SketchEntityDimensionKind
    var rect: CGRect
    var baselineValue: Double
    var start: CGPoint?
    var end: CGPoint?
    var center: CGPoint?
    var radiusMeters: Double?
    var startAngleRadians: Double?
    var endAngleRadians: Double?
}

struct ViewportSketchDimensionTarget: Equatable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var target: SelectionTarget
    var kind: SketchEntityDimensionKind
    var sketchPlane: SketchPlane
    var baselineValue: Double
    var start: CGPoint?
    var end: CGPoint?
    var center: CGPoint?
    var radiusMeters: Double?
    var startAngleRadians: Double?
    var endAngleRadians: Double?

    var identity: ViewportSketchDimensionIdentity {
        ViewportSketchDimensionIdentity(
            featureID: featureID,
            entityID: entityID,
            kind: kind
        )
    }
}

struct ViewportSketchDimensionIdentity: Equatable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var kind: SketchEntityDimensionKind
}

struct ViewportSketchPointHandleDragState: Equatable {
    var target: ViewportSketchPointHandleTarget
    var startPoint: CGPoint
    var viewportDelta: CGPoint
}

struct ViewportSketchPointHandleTarget: Equatable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var target: SelectionTarget
    var handle: SketchEntityPointHandle
    var sketchPlane: SketchPlane

    var identity: ViewportSketchPointHandleIdentity {
        ViewportSketchPointHandleIdentity(
            featureID: featureID,
            entityID: entityID,
            handle: handle
        )
    }
}

struct ViewportSketchPointHandleIdentity: Equatable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var handle: SketchEntityPointHandle
}

struct ViewportSplineControlPointHandleTarget: Equatable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var target: SelectionTarget
    var controlPointIndex: Int
    var sketchPlane: SketchPlane

    var identity: ViewportSplineControlPointIdentity {
        ViewportSplineControlPointIdentity(
            featureID: featureID,
            entityID: entityID,
            controlPointIndex: controlPointIndex
        )
    }
}

struct ViewportSplineControlPointIdentity: Equatable, Hashable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var controlPointIndex: Int
}

struct ViewportSplineControlPointGroup: Equatable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var target: SelectionTarget
    var controlPointIndexes: [Int]
}

struct ViewportSplineControlPointGroupKey: Equatable, Hashable {
    var featureID: FeatureID
    var entityID: SketchEntityID
}

struct ViewportSplineControlPointSlideAffordanceCandidate: Equatable {
    var target: ViewportSplineControlPointSlideHandleTarget
    var geometry: ViewportSplineControlPointSlideAffordanceGeometry
}

struct ViewportSplineControlPointSlideHandleTarget: Equatable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var target: SelectionTarget
    var controlPointIndexes: [Int]
    var direction: SplineControlPointSlideDirection
    var geometry: ViewportSplineControlPointSlideAffordanceGeometry

    var identity: ViewportSplineControlPointSlideHandleIdentity {
        ViewportSplineControlPointSlideHandleIdentity(
            featureID: featureID,
            entityID: entityID,
            controlPointIndexes: controlPointIndexes,
            direction: direction
        )
    }
}

struct ViewportSplineControlPointSlideHandleIdentity: Equatable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var controlPointIndexes: [Int]
    var direction: SplineControlPointSlideDirection
}

struct ViewportPolySplineSurfaceVertexSlideAffordanceCandidate: Equatable {
    var target: ViewportPolySplineSurfaceVertexSlideHandleTarget
    var geometry: ViewportPolySplineSurfaceVertexSlideAffordanceGeometry
}

struct ViewportSurfaceControlPointSlideAffordanceCandidate: Equatable {
    var target: ViewportSurfaceControlPointSlideHandleTarget
    var geometry: ViewportPolySplineSurfaceVertexSlideAffordanceGeometry
}

struct ViewportSurfaceFrameAffordanceCandidate: Equatable {
    var target: ViewportSurfaceFrameHandleTarget
    var geometry: ViewportSurfaceFrameAxisAffordanceGeometry
}

struct ViewportPolySplineSurfaceVertexSlideHandleTarget: Equatable {
    var targets: [SelectionTarget]
    var direction: PolySplineSurfaceVertexSlideDirection
    var geometry: ViewportPolySplineSurfaceVertexSlideAffordanceGeometry

    var identity: ViewportPolySplineSurfaceVertexSlideHandleIdentity {
        ViewportPolySplineSurfaceVertexSlideHandleIdentity(
            targets: targets,
            direction: direction
        )
    }
}

struct ViewportPolySplineSurfaceVertexSlideHandleIdentity: Equatable {
    var targets: [SelectionTarget]
    var direction: PolySplineSurfaceVertexSlideDirection
}

struct ViewportSurfaceControlPointSlideHandleTarget: Equatable {
    var targets: [SelectionReference]
    var direction: PolySplineSurfaceVertexSlideDirection
    var geometry: ViewportPolySplineSurfaceVertexSlideAffordanceGeometry

    var identity: ViewportSurfaceControlPointSlideHandleIdentity {
        ViewportSurfaceControlPointSlideHandleIdentity(
            targets: targets,
            direction: direction
        )
    }
}

struct ViewportSurfaceControlPointSlideHandleIdentity: Equatable {
    var targets: [SelectionReference]
    var direction: PolySplineSurfaceVertexSlideDirection
}

struct ViewportSurfaceFrameHandleTarget: Equatable {
    var targets: [SelectionReference]
    var query: SurfaceFrameQuery
    var displayID: SurfaceFrameDisplayID
    var axis: ViewportSurfaceFrameAxis
    var geometry: ViewportSurfaceFrameAxisAffordanceGeometry

    var identity: ViewportSurfaceFrameHandleIdentity {
        ViewportSurfaceFrameHandleIdentity(
            targets: targets,
            displayID: displayID,
            axis: axis
        )
    }
}

struct ViewportSurfaceFrameHandleIdentity: Equatable {
    var targets: [SelectionReference]
    var displayID: SurfaceFrameDisplayID
    var axis: ViewportSurfaceFrameAxis
}

struct ViewportPolySplineSurfaceVertexHandleTarget: Equatable {
    var featureID: FeatureID
    var target: SelectionTarget
    var componentID: SelectionComponentID
    var point: Point3D
    var modelTransform: Transform3D
    var dragMode: ViewportPolySplineSurfaceVertexDragMode

    var geometry: ViewportPlanarHandleDragGeometry {
        ViewportPlanarHandleDragGeometry(
            localPoint: point,
            modelTransform: modelTransform
        )
    }
}

struct ViewportSurfaceControlPointHandleTarget: Equatable {
    var featureID: FeatureID
    var target: SelectionReference
    var point: Point3D
    var modelTransform: Transform3D
    var dragMode: ViewportPolySplineSurfaceVertexDragMode

    var identity: ViewportSurfaceControlPointHandleIdentity {
        ViewportSurfaceControlPointHandleIdentity(target: target)
    }

    var geometry: ViewportPlanarHandleDragGeometry {
        ViewportPlanarHandleDragGeometry(
            localPoint: point,
            modelTransform: modelTransform
        )
    }
}

struct ViewportSurfaceControlPointHandleIdentity: Equatable {
    var target: SelectionReference
}

struct ViewportSurfaceTrimEndpointHandleTarget: Equatable {
    var featureID: FeatureID
    var target: SelectionReference
    var endpoint: SurfaceTrimEndpoint
    var point: Point3D
    var u: Double
    var v: Double
    var tangentU: Vector3D
    var tangentV: Vector3D
    var modelTransform: Transform3D

    var identity: ViewportSurfaceTrimEndpointHandleIdentity {
        ViewportSurfaceTrimEndpointHandleIdentity(target: target, endpoint: endpoint)
    }

    var geometry: ViewportPlanarHandleDragGeometry {
        ViewportPlanarHandleDragGeometry(
            localPoint: point,
            modelTransform: modelTransform
        )
    }
}

struct ViewportSurfaceTrimEndpointHandleIdentity: Equatable {
    var target: SelectionReference
    var endpoint: SurfaceTrimEndpoint
}

struct ViewportSurfaceTrimControlPointHandleTarget: Equatable {
    var featureID: FeatureID
    var target: SelectionReference
    var controlPointIndex: Int
    var point: Point3D
    var u: Double
    var v: Double
    var tangentU: Vector3D
    var tangentV: Vector3D
    var modelTransform: Transform3D

    var identity: ViewportSurfaceTrimControlPointHandleIdentity {
        ViewportSurfaceTrimControlPointHandleIdentity(
            target: target,
            controlPointIndex: controlPointIndex
        )
    }

    var geometry: ViewportPlanarHandleDragGeometry {
        ViewportPlanarHandleDragGeometry(
            localPoint: point,
            modelTransform: modelTransform
        )
    }
}

struct ViewportSurfaceTrimControlPointHandleIdentity: Equatable {
    var target: SelectionReference
    var controlPointIndex: Int
}

struct ViewportPolySplineSurfaceVertexLocalAxisHit: Equatable {
    var axis: ViewportPolySplineSurfaceVertexLocalAxis
    var direction: Vector3D
}

enum ViewportPolySplineSurfaceVertexLocalAxis: CaseIterable, Equatable {
    case u
    case v
    case normal

    var slideDirection: PolySplineSurfaceVertexSlideDirection {
        switch self {
        case .u:
            .positiveU
        case .v:
            .positiveV
        case .normal:
            .normal
        }
    }

    var color: Color {
        switch self {
        case .u:
            ViewportTheme.surfaceAnalysisU
        case .v:
            ViewportTheme.surfaceAnalysisV
        case .normal:
            ViewportTheme.surfaceEdit
        }
    }
}

enum ViewportPolySplineSurfaceVertexDragMode: Equatable {
    case planar
    case axis(ViewportCoordinateAxis)
    case localAxis(ViewportPolySplineSurfaceVertexLocalAxis, direction: Vector3D)

    var axis: ViewportCoordinateAxis? {
        switch self {
        case .planar:
            nil
        case .localAxis(_, direction: _):
            nil
        case .axis(let axis):
            axis
        }
    }

    var color: Color {
        switch self {
        case .planar:
            ViewportTheme.surfaceEdit
        case .axis(let axis):
            axis.color
        case .localAxis(let localAxis, direction: _):
            localAxis.color
        }
    }

    func isHighlighted(axis candidate: ViewportCoordinateAxis) -> Bool {
        guard case .axis(let axis) = self else {
            return false
        }
        return axis == candidate
    }

    func isHighlighted(localAxis candidate: ViewportPolySplineSurfaceVertexLocalAxis) -> Bool {
        guard case .localAxis(let localAxis, direction: _) = self else {
            return false
        }
        return localAxis == candidate
    }
}

struct ViewportRegionOffsetAffordanceCandidate: Equatable {
    var target: ViewportRegionOffsetHandleTarget
    var geometry: ViewportRegionOffsetAffordanceGeometry
}

struct ViewportRegionOffsetHandleTarget: Equatable {
    var featureID: FeatureID
    var componentID: SelectionComponentID
    var target: SelectionTarget
    var geometry: ViewportRegionOffsetAffordanceGeometry

    var identity: ViewportRegionOffsetHandleIdentity {
        ViewportRegionOffsetHandleIdentity(
            featureID: featureID,
            componentID: componentID
        )
    }
}

struct ViewportRegionOffsetHandleIdentity: Equatable {
    var featureID: FeatureID
    var componentID: SelectionComponentID
}

struct ViewportEdgeOffsetAffordanceCandidate: Equatable {
    var target: ViewportEdgeOffsetHandleTarget
    var geometry: ViewportEdgeOffsetAffordanceGeometry
}

struct ViewportEdgeOffsetHandleTarget: Equatable {
    var featureID: FeatureID
    var edge: ViewportBodyEdge
    var target: SelectionTarget
    var geometry: ViewportEdgeOffsetAffordanceGeometry

    var identity: ViewportEdgeOffsetHandleIdentity {
        ViewportEdgeOffsetHandleIdentity(
            featureID: featureID,
            edge: edge
        )
    }
}

struct ViewportEdgeOffsetHandleIdentity: Equatable {
    var featureID: FeatureID
    var edge: ViewportBodyEdge
}

struct ViewportSlotWidthAffordanceCandidate: Equatable {
    var target: ViewportSlotWidthHandleTarget
    var geometry: ViewportSlotWidthAffordanceGeometry
}

struct ViewportSlotWidthHandleTarget: Equatable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var target: SelectionTarget
    var geometry: ViewportSlotWidthAffordanceGeometry

    var identity: ViewportSlotWidthHandleIdentity {
        ViewportSlotWidthHandleIdentity(
            featureID: featureID,
            entityID: entityID
        )
    }
}

struct ViewportSlotWidthHandleIdentity: Equatable {
    var featureID: FeatureID
    var entityID: SketchEntityID
}

struct ViewportSketchVertexOffsetAffordanceCandidate: Equatable {
    var target: ViewportSketchVertexOffsetHandleTarget
    var geometry: ViewportSketchVertexOffsetAffordanceGeometry
}

struct ViewportSketchVertexOffsetHandleTarget: Equatable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var target: SelectionTarget
    var handle: SketchEntityPointHandle
    var geometry: ViewportSketchVertexOffsetAffordanceGeometry

    var identity: ViewportSketchVertexOffsetHandleIdentity {
        ViewportSketchVertexOffsetHandleIdentity(
            featureID: featureID,
            entityID: entityID,
            handle: handle
        )
    }
}

struct ViewportSketchVertexOffsetHandleIdentity: Equatable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var handle: SketchEntityPointHandle
}

struct ViewportAffordanceTarget: Equatable {
    var featureID: FeatureID
    var action: ViewportAffordanceAction
}

enum ViewportAffordanceAction: Equatable {
    case translate(ViewportCoordinateAxis)
    case oneSidedScale(ViewportCoordinateAxis)
    case centerScale(ViewportCoordinateAxis)
    case rotate(ViewportCoordinateAxis)
    case vertexMove(ViewportBodyVertex)
    case profileCornerMove(SelectionTarget, ViewportBodyVertex)
    case profileFaceMove(SelectionTarget, ViewportBodyFace)
    case profileEdgeChamfer(SelectionTarget, ViewportBodyEdge)
    case profileEdgeFillet(SelectionTarget, ViewportBodyEdge)
    case faceMove(ViewportBodyFace)
}
