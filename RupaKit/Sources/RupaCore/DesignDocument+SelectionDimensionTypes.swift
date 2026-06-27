import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    var selectionDimensionEndpointTolerance: Double {
        1.0e-8
    }

    enum SelectionDimensionLineEndpointRole: Equatable, Sendable {
        case start
        case end
    }

    enum SelectionDimensionCurveEndpointRole: Equatable, Sendable {
        case start
        case end
    }

    enum SelectionDimensionSourceApplication: Sendable {
        case lineLength(SelectionDimensionSourceLineContext)
        case circularRadius(SelectionDimensionSourceCircularContext)
        case lineRelativeAngle(SelectionDimensionSourceLineAngleContext)
        case arcSpanAngle(SelectionDimensionSourceArcAngleContext)
        case sourcePointDistance(SelectionDimensionSourcePointDistanceContext)
        case sourcePointLineDistance(SelectionDimensionSourcePointLineDistanceContext)
        case objectFaceDistance(SelectionDimensionObjectFaceDistanceContext)
    }

    struct SelectionDimensionSourceLineContext: Sendable {
        var featureID: FeatureID
        var entityID: SketchEntityID
        var curve: CurveOutputReference
        var target: SelectionTarget
        var firstRole: SelectionDimensionLineEndpointRole
        var secondRole: SelectionDimensionLineEndpointRole
    }

    struct SelectionDimensionSourceCircularContext: Sendable {
        var featureID: FeatureID
        var entityID: SketchEntityID
        var curve: CurveOutputReference
        var target: SelectionTarget
    }

    struct SelectionDimensionSourceLineAngleContext: Sendable {
        var featureID: FeatureID
        var entityID: SketchEntityID
        var curve: CurveOutputReference
        var target: SelectionTarget
        var currentAngle: Double
        var referenceAngle: Double
    }

    struct SelectionDimensionSourceArcAngleContext: Sendable {
        var featureID: FeatureID
        var entityID: SketchEntityID
        var curve: CurveOutputReference
        var target: SelectionTarget
        var firstRole: SelectionDimensionCurveEndpointRole
        var secondRole: SelectionDimensionCurveEndpointRole
    }

    struct SelectionDimensionSourcePointDistanceContext: Sendable {
        var first: SelectionDimensionSourcePointContext
        var second: SelectionDimensionSourcePointContext
    }

    struct SelectionDimensionSourcePointLineDistanceContext: Sendable {
        var point: SelectionDimensionSourcePointContext
        var line: SelectionDimensionSourceLineDistanceLineContext
        var pointIsFirst: Bool
    }

    struct SelectionDimensionSourceLineDistanceLineContext: Sendable {
        var featureID: FeatureID
        var entityID: SketchEntityID
        var curve: CurveOutputReference
        var plane: SketchPlane
        var target: SelectionTarget
    }

    struct SelectionDimensionSourceLineDistanceGeometry: Sendable {
        var start: Point2D
        var end: Point2D
        var length: Double
    }

    struct SelectionDimensionObjectFaceDistanceContext: Sendable {
        var target: SelectionTarget
        var kind: ObjectDimensionKind
    }

    struct SelectionDimensionSourceLineProjection: Sendable {
        var closest: Point2D
        var deltaX: Double
        var deltaY: Double
        var lineUnitX: Double
        var lineUnitY: Double
    }

    struct SelectionDimensionSourcePointMovePlan: Sendable {
        var moving: SelectionDimensionSourcePointContext
        var anchor: SelectionDimensionSourcePointContext
    }

    enum SelectionDimensionSourcePointRole: Equatable, Sendable {
        case handle(SketchEntityPointHandle)
        case splineControlPoint(Int)
    }

    struct SelectionDimensionSourcePointContext: Sendable {
        var featureID: FeatureID
        var entityID: SketchEntityID
        var curve: CurveOutputReference?
        var plane: SketchPlane
        var target: SelectionTarget
        var role: SelectionDimensionSourcePointRole
    }

    struct SourceLineAngleContext: Sendable {
        var featureID: FeatureID
        var entityID: SketchEntityID
        var plane: SketchPlane
        var target: SelectionTarget
        var angle: Double
    }
}
