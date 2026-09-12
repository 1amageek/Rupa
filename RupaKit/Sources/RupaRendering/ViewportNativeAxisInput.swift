import Foundation
import RupaCore
import RupaViewportScene

/// Retains one prepared world-axis operation and converts native camera query
/// deltas into the existing public callback payloads.
struct ViewportNativeAxisInput: Sendable {
    enum Commit: Equatable, Sendable {
        case splineControlPointSlide(ViewportSplineControlPointSlideDragTarget)
        case polySplineSurfaceVertexSlide(ViewportPolySplineSurfaceVertexSlideDragTarget)
        case surfaceControlPointSlide(ViewportSurfaceControlPointSlideDragTarget)
        case surfaceFrame(ViewportSurfaceFrameDragTarget)
        case regionOffset(ViewportRegionOffsetDragTarget)
        case edgeOffset(ViewportEdgeOffsetDragTarget)
        case slotWidth(ViewportSlotWidthDragTarget)
        case sketchVertexOffset(ViewportSketchVertexOffsetDragTarget)
        case patternArrayLinearAxis(ViewportPatternArrayLinearAxisDragTarget)
        case independentCopyExtrudeDistance(ViewportIndependentCopyExtrudeDistanceDragTarget)
        case independentCopyBodyDimension(ViewportIndependentCopyBodyDimensionDragTarget)
        case polySplineSurfaceVertex(ViewportPolySplineSurfaceVertexDragTarget)
        case surfaceControlPoint(ViewportSurfaceControlPointDragTarget)
    }

    let record: ViewportSpatialInteractionRecord
    let axis: ViewportSpatialPreparedInteractionTarget.Axis
    let sourceUnitsPerWorldMetre: Double
    /// The model-space direction the two surface handle routes move along.
    ///
    /// Those two commit a displacement rather than a measured quantity, so the
    /// axis value alone does not name what moved. Every other route leaves
    /// this empty.
    let handleLocalDirection: Vector3D?

    init?(record: ViewportSpatialInteractionRecord) throws {
        let axis: ViewportSpatialPreparedInteractionTarget.Axis
        var handleLocalDirection: Vector3D?
        switch record.target {
        case .splineControlPointSlide(_, _, _, _, _, let value):
            axis = value
        case .polySplineSurfaceVertexSlide(_, _, let value):
            axis = value
        case .surfaceControlPointSlide(_, _, let value):
            axis = value
        case .surfaceFrame(_, _, _, _, let value):
            axis = value
        case .regionOffset(_, _, _, let value):
            axis = value
        case .edgeOffset(_, _, _, _, _, let value):
            axis = value
        case .slotWidth(_, _, _, let value):
            axis = value
        case .sketchVertexOffset(_, _, _, _, let value):
            axis = value
        case .patternArrayLinearAxis(let value):
            axis = try Self.patternAxis(origin: value.basePoint, direction: value.direction, value: value.distanceMeters)
        case .independentCopyExtrudeDistance(let value):
            axis = try Self.patternAxis(origin: value.basePoint, direction: value.axis, value: value.distanceMeters)
        case .independentCopyBodyDimension(let value):
            axis = try Self.patternAxis(origin: value.basePoint, direction: value.axis, value: value.valueMeters)
        case .polySplineSurfaceVertex(let value):
            // The planar handle of this route moves in a plane, so it belongs
            // to the world-point owner rather than to this one.
            guard let localDirection = value.dragMode.localDirection else { return nil }
            handleLocalDirection = localDirection
            axis = try Self.handleAxis(localPoint: value.point, localDirection: localDirection,
                                       modelTransform: value.modelTransform)
        case .surfaceControlPoint(let value):
            guard let localDirection = value.dragMode.localDirection else { return nil }
            handleLocalDirection = localDirection
            axis = try Self.handleAxis(localPoint: value.point, localDirection: localDirection,
                                       modelTransform: value.modelTransform)
        default:
            return nil
        }

        guard axis.origin.x.isFinite,
              axis.origin.y.isFinite,
              axis.origin.z.isFinite,
              axis.direction.x.isFinite,
              axis.direction.y.isFinite,
              axis.direction.z.isFinite,
              axis.baseValue.isFinite else {
            throw RealityViewportSpatialBatch.invalid("The prepared world axis is not finite.")
        }
        let length = Self.length(axis.direction)
        guard length.isFinite, length > 1.0e-12 else {
            throw RealityViewportSpatialBatch.invalid("The prepared world axis is degenerate.")
        }
        let sourceUnitsPerWorldMetre = try axis.sourceUnitsPerWorldMetre ?? Self.sourceUnitsPerWorldMetre(
            for: axis.direction,
            in: record.modelTransform
        )
        guard sourceUnitsPerWorldMetre.isFinite, sourceUnitsPerWorldMetre > 0 else {
            throw RealityViewportSpatialBatch.invalid("The prepared source-axis scale is invalid.")
        }
        self.record = record
        self.axis = axis
        self.sourceUnitsPerWorldMetre = sourceUnitsPerWorldMetre
        self.handleLocalDirection = handleLocalDirection
    }

    /// The model-space displacement an axis value stands for, for the two
    /// surface handle routes. Every other route has no displacement to state
    /// and answers with nothing.
    func localDelta(for value: Double) -> Vector3D? {
        guard let direction = handleLocalDirection, value.isFinite else { return nil }
        let delta = Vector3D(x: direction.x * value, y: direction.y * value,
                             z: direction.z * value)
        guard delta.isFinite else { return nil }
        return delta
    }

    func value(forWorldDelta worldDelta: Double) throws -> Double {
        guard worldDelta.isFinite else {
            throw RealityViewportSpatialBatch.invalid("The native world-axis delta is not finite.")
        }
        let sourceDelta = worldDelta * sourceUnitsPerWorldMetre
        guard sourceDelta.isFinite else {
            throw RealityViewportSpatialBatch.invalid("The native source-axis delta is not finite.")
        }

        switch record.target {
        case .splineControlPointSlide, .polySplineSurfaceVertexSlide,
             .surfaceControlPointSlide, .surfaceFrame, .regionOffset,
             .polySplineSurfaceVertex, .surfaceControlPoint:
            return sourceDelta
        case .edgeOffset, .sketchVertexOffset:
            return try Self.positiveValue(axis.baseValue, adding: sourceDelta)
        case .slotWidth:
            let scaledDelta = sourceDelta * 2.0
            guard scaledDelta.isFinite else {
                throw RealityViewportSpatialBatch.invalid("The native slot-width delta is not finite.")
            }
            return try Self.positiveValue(axis.baseValue, adding: scaledDelta)
        case .patternArrayLinearAxis, .independentCopyExtrudeDistance, .independentCopyBodyDimension:
            let result = axis.baseValue + sourceDelta
            guard result.isFinite else {
                throw RealityViewportSpatialBatch.invalid("The native pattern-axis value overflowed.")
            }
            return max(result, PatternArrayDistancePolicy.standard.minimumLinearDistanceMeters)
        default:
            throw RealityViewportSpatialBatch.invalid("The prepared record is not a world-axis operation.")
        }
    }

    func commit(value: Double) throws -> Commit? {
        guard value.isFinite else {
            throw RealityViewportSpatialBatch.invalid("The native interaction value is not finite.")
        }

        switch record.target {
        case .patternArrayLinearAxis, .independentCopyExtrudeDistance, .independentCopyBodyDimension:
            guard value >= PatternArrayDistancePolicy.standard.minimumLinearDistanceMeters else {
                throw RealityViewportSpatialBatch.invalid("The native pattern-axis value is below its minimum.")
            }
            guard abs(value - axis.baseValue) > 1.0e-12 else { return nil }
        default: break
        }

        switch record.target {
        case .splineControlPointSlide(
            _, _, let target, let controlPointIndexes, let direction, _
        ):
            guard abs(value) > 1.0e-12 else { return nil }
            return .splineControlPointSlide(.init(
                target: target,
                controlPointIndexes: controlPointIndexes,
                direction: direction,
                distance: value
            ))

        case .polySplineSurfaceVertexSlide(let targets, let direction, _):
            guard abs(value) > 1.0e-12 else { return nil }
            return .polySplineSurfaceVertexSlide(.init(
                targets: targets,
                direction: direction,
                distance: value
            ))

        case .surfaceControlPointSlide(let targets, let direction, _):
            guard abs(value) > 1.0e-12 else { return nil }
            return .surfaceControlPointSlide(.init(
                targets: targets,
                direction: direction,
                distance: value
            ))

        case .surfaceFrame(let targets, let query, _, let axis, _):
            guard abs(value) > 1.0e-12 else { return nil }
            return .surfaceFrame(.init(
                targets: targets,
                query: query,
                axis: axis,
                distance: value
            ))

        case .regionOffset(_, _, let target, _):
            guard abs(value) > 1.0e-12 else { return nil }
            return .regionOffset(.init(target: target, distance: value))

        case .edgeOffset(_, _, let target, _, _, _):
            guard value > 0.0 else {
                throw RealityViewportSpatialBatch.invalid("The edge-offset value is not positive.")
            }
            guard abs(value - axis.baseValue) > 1.0e-12 else { return nil }
            return .edgeOffset(.init(target: target, distance: value))

        case .slotWidth(_, _, let target, _):
            guard value > 0.0 else {
                throw RealityViewportSpatialBatch.invalid("The slot-width value is not positive.")
            }
            guard abs(value - axis.baseValue) > 1.0e-12 else { return nil }
            return .slotWidth(.init(target: target, width: value))

        case .sketchVertexOffset(_, _, let target, let handle, _):
            guard value > 0.0 else {
                throw RealityViewportSpatialBatch.invalid("The sketch-vertex offset is not positive.")
            }
            guard abs(value - axis.baseValue) > 1.0e-12 else { return nil }
            return .sketchVertexOffset(.init(target: target, handle: handle, distance: value))

        case .polySplineSurfaceVertex(let handle):
            guard let delta = localDelta(for: value) else {
                throw RealityViewportSpatialBatch.invalid(
                    "The axis-mode surface handle has no local drag direction."
                )
            }
            guard Self.moves(delta) else { return nil }
            return .polySplineSurfaceVertex(.init(
                target: handle.target,
                deltaX: delta.x, deltaY: delta.y, deltaZ: delta.z
            ))

        case .surfaceControlPoint(let handle):
            guard let delta = localDelta(for: value) else {
                throw RealityViewportSpatialBatch.invalid(
                    "The axis-mode surface handle has no local drag direction."
                )
            }
            guard Self.moves(delta) else { return nil }
            return .surfaceControlPoint(.init(
                target: handle.target,
                deltaX: delta.x, deltaY: delta.y, deltaZ: delta.z
            ))

        case .patternArrayLinearAxis(let target):
            return .patternArrayLinearAxis(.init(sourceID: target.sourceID, axisSlot: target.axisSlot, distance: value))

        case .independentCopyExtrudeDistance(let target):
            return .independentCopyExtrudeDistance(.init(
                sourceID: target.sourceID, outputIndex: target.outputIndex,
                outputSceneNodeID: target.outputSceneNodeID, featureID: target.featureID,
                distance: try sourcePatternValue(fromWorldValue: value)
            ))

        case .independentCopyBodyDimension(let target):
            return .independentCopyBodyDimension(.init(
                sourceID: target.sourceID, outputIndex: target.outputIndex,
                outputSceneNodeID: target.outputSceneNodeID, featureID: target.featureID, kind: target.kind,
                value: try sourcePatternValue(fromWorldValue: value)
            ))

        default:
            throw RealityViewportSpatialBatch.invalid("The prepared record is not a world-axis operation.")
        }
    }

    /// The world axis a model-space handle direction traces through a handle's
    /// own placement.
    ///
    /// The base value is zero because these handles commit a displacement
    /// rather than a measured quantity, and the source scale is left to the
    /// common path so one rule converts world metres back into model units.
    private static func handleAxis(
        localPoint: Point3D,
        localDirection: Vector3D,
        modelTransform: Transform3D
    ) throws -> ViewportSpatialPreparedInteractionTarget.Axis {
        let origin = modelTransform.viewportTransformedPoint(localPoint)
        let direction = modelTransform.viewportTransformedVector(localDirection)
        guard origin.isFinite, direction.isFinite else {
            throw RealityViewportSpatialBatch.invalid(
                "The surface handle has no finite world axis."
            )
        }
        return .init(origin: origin, direction: direction, baseValue: 0)
    }

    /// Whether a model-space displacement is larger than numerical noise on any
    /// component. A drag that moves nothing commits nothing.
    private static func moves(_ delta: Vector3D) -> Bool {
        abs(delta.x) > 1.0e-12 || abs(delta.y) > 1.0e-12 || abs(delta.z) > 1.0e-12
    }

    private static func patternAxis(origin: Point3D, direction: Vector3D, value: Double) throws -> ViewportSpatialPreparedInteractionTarget.Axis {
        guard value.isFinite, value > 0 else {
            throw RealityViewportSpatialBatch.invalid("The prepared pattern-axis value is not positive and finite.")
        }
        // Pattern handles already own world coordinates and world-metre values.
        // Only independent-copy callback payloads convert back to source units.
        return .init(origin: origin, direction: direction,
                     baseValue: max(value, PatternArrayDistancePolicy.standard.minimumLinearDistanceMeters),
                     sourceUnitsPerWorldMetre: 1)
    }

    private func sourcePatternValue(fromWorldValue value: Double) throws -> Double {
        let result = value / Self.length(axis.direction)
        guard result.isFinite, result > 0 else {
            throw RealityViewportSpatialBatch.invalid("The independent-copy source value is not positive and finite.")
        }
        return result
    }

    private static func length(_ value: Vector3D) -> Double {
        (value.x * value.x + value.y * value.y + value.z * value.z).squareRoot()
    }

    static func sourceUnitsPerWorldMetre(
        for worldDirection: Vector3D,
        in modelTransform: Transform3D
    ) throws -> Double {
        let worldLength = length(worldDirection)
        guard worldLength.isFinite, worldLength > 1.0e-12 else {
            throw RealityViewportSpatialBatch.invalid("The world axis is degenerate.")
        }
        let worldUnit = Vector3D(
            x: worldDirection.x / worldLength,
            y: worldDirection.y / worldLength,
            z: worldDirection.z / worldLength
        )
        guard let localDirection = modelTransform.viewportInverseTransformedVector(worldUnit) else {
            throw RealityViewportSpatialBatch.invalid("The model transform cannot invert the world axis.")
        }
        let sourceUnitsPerWorldMetre = length(localDirection)
        guard sourceUnitsPerWorldMetre.isFinite, sourceUnitsPerWorldMetre > 1.0e-12 else {
            throw RealityViewportSpatialBatch.invalid("The model transform has no finite source-axis scale.")
        }
        return sourceUnitsPerWorldMetre
    }

    static func commonSourceScale(_ scales: [Double]) throws -> Double {
        guard let firstScale = scales.first, firstScale.isFinite, firstScale > 0 else {
            throw RealityViewportSpatialBatch.invalid("A grouped world axis has no source members.")
        }
        for scale in scales.dropFirst() {
            let tolerance = max(abs(firstScale), abs(scale), 1.0) * 1.0e-12
            guard scale.isFinite, scale > 0, abs(scale - firstScale) <= tolerance else {
                throw RealityViewportSpatialBatch.invalid(
                    "Grouped world-axis members have incompatible source-axis scales."
                )
            }
        }
        return firstScale
    }

    private static func positiveValue(_ base: Double, adding delta: Double) throws -> Double {
        let result = base + delta
        guard result.isFinite else {
            throw RealityViewportSpatialBatch.invalid("The native interaction value overflowed.")
        }
        return max(result, 1.0e-9)
    }
}
