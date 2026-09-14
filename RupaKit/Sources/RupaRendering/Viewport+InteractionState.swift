import Foundation
import RupaCore
import SwiftUI
import RupaViewportScene

struct ViewportActiveDrag: Equatable {
    var startLocation: CGPoint
    var currentLocation: CGPoint
    var kind: Kind
    var sketchPlane: SketchPlane? = nil
    // Resolved at the input event boundary so native overlay preparation never
    // has to reinterpret screen coordinates with a later camera state.
    var modelDrag: ViewportModelDrag? = nil

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
        case .creation(.circle):
            "Canvas circle drag preview"
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

/// The prepared membership of a natively claimed transform affordance.
///
/// The overlay producer decides which selected bodies one transform gizmo
/// stands for, and emits that decision into the interaction record it
/// registers for the gizmo's handles. Re-deriving the grouping from the
/// selection when the drag starts would give the drawn gizmo and the drag two
/// owners: they disagree whenever one feature is selected through more than
/// one scene node, where the gizmo spans the group while the derivation
/// resolves a single body and the drag then matches no item at all. The claim
/// carries the producer's decision from the press through to the drag, so the
/// handle that was drawn is the handle that moves.
struct ViewportNativeAffordanceClaim {
    var target: ViewportAffordanceTarget
    var members: [ViewportSpatialPreparedInteractionTarget.AffordanceBodyMember]
    var groupEdit: ViewportObjectEditState?
}

struct ViewportConstructionPlaneHandlePlane: Equatable {
    var constructionPlaneID: ConstructionPlaneSourceID
    var sceneNodeID: SceneNodeID
    var origin: Point3D
    var normal: Vector3D
    var normalEnd: Point3D
    var corners: [Point3D]
    var projectedOrigin: CGPoint
    var projectedNormalEnd: CGPoint

    func target(
        handle: ViewportConstructionPlaneHandleKind
    ) -> ViewportConstructionPlaneHandleTarget {
        ViewportConstructionPlaneHandleTarget(
            constructionPlaneID: constructionPlaneID,
            sceneNodeID: sceneNodeID,
            handle: handle,
            origin: origin,
            normal: normal,
            normalEnd: normalEnd,
            corners: corners,
            projectedOrigin: projectedOrigin,
            projectedNormalEnd: projectedNormalEnd
        )
    }
}

struct ViewportConstructionPlaneHandleTarget: Equatable {
    var constructionPlaneID: ConstructionPlaneSourceID
    var sceneNodeID: SceneNodeID
    var handle: ViewportConstructionPlaneHandleKind
    var origin: Point3D
    var normal: Vector3D
    var normalEnd: Point3D
    var corners: [Point3D]
    var projectedOrigin: CGPoint
    var projectedNormalEnd: CGPoint

    var identity: ViewportConstructionPlaneHandleIdentity {
        ViewportConstructionPlaneHandleIdentity(
            constructionPlaneID: constructionPlaneID,
            sceneNodeID: sceneNodeID,
            handle: handle
        )
    }
}

struct ViewportConstructionPlaneHandleIdentity: Hashable, Sendable {
    var constructionPlaneID: ConstructionPlaneSourceID
    var sceneNodeID: SceneNodeID
    var handle: ViewportConstructionPlaneHandleKind
}

struct ViewportSketchCurveHandleTarget: Equatable, Sendable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var target: SelectionTarget
    var handle: ViewportSketchCurveHandleKind
    var sketchPlane: SketchPlane
    /// The handle's own point in the sketch display space the producer
    /// drew it in. The native world-point owner offsets it by the queried
    /// displacement rather than reading an absolute pointer position.
    var point: CGPoint
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

struct ViewportSketchCurveHandleIdentity: Equatable, Sendable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var handle: ViewportSketchCurveHandleKind
}

struct ViewportSketchDimensionTarget: Equatable, Sendable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var target: SelectionTarget
    var kind: SketchEntityDimensionKind
    var sketchPlane: SketchPlane
    /// The handle's own point in the sketch display space the producer
    /// drew it in.
    var point: CGPoint
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

struct ViewportSketchDimensionIdentity: Equatable, Sendable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var kind: SketchEntityDimensionKind
}

struct ViewportSketchPointHandleTarget: Equatable, Sendable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var target: SelectionTarget
    var handle: SketchEntityPointHandle
    var sketchPlane: SketchPlane
    /// The handle's own point in the sketch display space the producer
    /// drew it in.
    var point: CGPoint

    var identity: ViewportSketchPointHandleIdentity {
        ViewportSketchPointHandleIdentity(
            featureID: featureID,
            entityID: entityID,
            handle: handle
        )
    }
}

struct ViewportSketchPointHandleIdentity: Equatable, Sendable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var handle: SketchEntityPointHandle
}

struct ViewportSplineControlPointHandleTarget: Equatable, Sendable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var target: SelectionTarget
    var controlPointIndex: Int
    var sketchPlane: SketchPlane
    /// The handle's own point in the sketch display space the producer
    /// drew it in.
    var point: CGPoint

    var identity: ViewportSplineControlPointIdentity {
        ViewportSplineControlPointIdentity(
            featureID: featureID,
            entityID: entityID,
            controlPointIndex: controlPointIndex
        )
    }
}

struct ViewportSplineControlPointIdentity: Equatable, Hashable, Sendable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var controlPointIndex: Int
}

struct ViewportSplineControlPointSlideHandleIdentity: Equatable, Sendable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var controlPointIndexes: [Int]
    var direction: SplineControlPointSlideDirection
}

struct ViewportPolySplineSurfaceVertexSlideHandleIdentity: Equatable, Sendable {
    var targets: [SelectionTarget]
    var direction: PolySplineSurfaceVertexSlideDirection
}

struct ViewportPolySplineSurfaceVertexHandleTarget: Equatable, Sendable {
    var featureID: FeatureID
    var target: SelectionTarget
    var componentID: SelectionComponentID
    var point: Point3D
    var modelTransform: Transform3D
    var dragMode: ViewportPolySplineSurfaceVertexDragMode
}

struct ViewportSurfaceControlPointHandleTarget: Equatable, Sendable {
    var featureID: FeatureID
    var target: SelectionReference
    var point: Point3D
    var modelTransform: Transform3D
    var dragMode: ViewportPolySplineSurfaceVertexDragMode

    var identity: ViewportSurfaceControlPointHandleIdentity {
        ViewportSurfaceControlPointHandleIdentity(target: target)
    }
}

struct ViewportSurfaceControlPointHandleIdentity: Equatable, Sendable {
    var target: SelectionReference
}

struct ViewportSurfaceTrimEndpointHandleTarget: Equatable, Sendable {
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
}

struct ViewportSurfaceTrimEndpointHandleIdentity: Equatable, Sendable {
    var target: SelectionReference
    var endpoint: SurfaceTrimEndpoint
}

struct ViewportSurfaceTrimControlPointHandleTarget: Equatable, Sendable {
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
}

struct ViewportSurfaceTrimControlPointHandleIdentity: Equatable, Sendable {
    var target: SelectionReference
    var controlPointIndex: Int
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

extension ViewportCoordinateAxis {
    /// The unit vector this axis names, stated in whichever space the caller's
    /// own values are stated in. Owning it here keeps the world, model and
    /// handle routes from each carrying their own copy of the mapping.
    var unitVector: Vector3D {
        switch self {
        case .x: .unitX
        case .y: .unitY
        case .z: .unitZ
        }
    }
}

enum ViewportPolySplineSurfaceVertexDragMode: Equatable, Sendable {
    case planar
    case axis(ViewportCoordinateAxis)
    case localAxis(ViewportPolySplineSurfaceVertexLocalAxis, direction: Vector3D)

    /// The single model-space direction this drag mode moves the handle along.
    ///
    /// The planar mode has none because it moves within a plane rather than
    /// along a line, which is what separates the axis input owner from the
    /// world-point one for these two routes.
    var localDirection: Vector3D? {
        switch self {
        case .planar:
            nil
        case .axis(let axis):
            axis.unitVector
        case .localAxis(_, let direction):
            direction
        }
    }

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

struct ViewportRegionOffsetHandleIdentity: Equatable, Sendable {
    var featureID: FeatureID
    var componentID: SelectionComponentID
}

struct ViewportEdgeOffsetHandleIdentity: Equatable, Sendable {
    var featureID: FeatureID
    var edge: ViewportBodyEdge
}

struct ViewportSlotWidthHandleIdentity: Equatable, Sendable {
    var featureID: FeatureID
    var entityID: SketchEntityID
}

struct ViewportSketchVertexOffsetHandleIdentity: Equatable, Sendable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var handle: SketchEntityPointHandle
}

struct ViewportAffordanceTarget: Equatable, Sendable {
    var featureID: FeatureID
    var selectionTarget: SelectionTarget?
    var action: ViewportAffordanceAction

    init(
        featureID: FeatureID,
        selectionTarget: SelectionTarget? = nil,
        action: ViewportAffordanceAction
    ) {
        self.featureID = featureID
        self.selectionTarget = selectionTarget
        self.action = action
    }
}

/// The interaction target a press or hover claim carries.
///
/// The prepared native record is the only producer, and its `.affordance` case
/// is the only claim that reaches this type. Every other case that once lived
/// here was reachable solely through the removed legacy projected selectors,
/// so a new case belongs here only once a native owner produces it.
enum ViewportInteractionTarget: Equatable {
    case affordance(ViewportAffordanceTarget)
}

enum ViewportAffordanceAction: Equatable, Sendable {
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
