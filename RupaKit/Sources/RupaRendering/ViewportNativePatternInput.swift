import CoreGraphics
import Foundation
import RupaCore
import RupaViewportScene

/// Retains one prepared pattern affordance, already materialized against the
/// mounted camera projection, and converts pointer samples into the existing
/// public callback payloads.
///
/// The retained projection is only meaningful against the camera revision that
/// produced it, so the gesture owner ends the gesture when that revision
/// changes.  This owner never reprojects, consults `ViewportLayout`, or
/// re-resolves the handle.
struct ViewportNativePatternInput: Sendable {
    /// The value one update read from the retained projection.
    enum Value: Equatable, Sendable {
        case angleRadians(Double)
        case copyCount(Int)
        case curveExtentDistanceMeters(Double)

        /// A non-finite value would never compare equal to itself, so the
        /// overlay revision refuses it rather than invalidating every frame.
        var isFinite: Bool {
            switch self {
            case .angleRadians(let value): value.isFinite
            case .copyCount: true
            case .curveExtentDistanceMeters(let value): value.isFinite
            }
        }
    }

    enum Commit: Equatable, Sendable {
        case patternArrayRadialAngle(ViewportPatternArrayRadialAngleDragTarget)
        case patternArrayCopyCount(ViewportPatternArrayCopyCountDragTarget)
        case patternArrayCurveExtent(ViewportPatternArrayCurveExtentDragTarget)
        case patternArrayOutputMode(ViewportPatternArrayOutputModeTarget)
    }

    let record: ViewportSpatialInteractionRecord
    let target: ViewportSpatialMaterializedInteractionTarget

    /// Whether this owner claims the prepared route.
    ///
    /// It owns the pattern routes whose drag math is defined on the press-time
    /// screen basis.  The curve path point is excluded: it resolves a world
    /// point rather than a screen sample and is owned elsewhere.
    static func claims(_ target: ViewportSpatialPreparedInteractionTarget) -> Bool {
        switch target {
        case .patternArrayRadialAngle, .patternArrayCopyCount,
             .patternArrayCurveExtent, .patternArrayOutputMode:
            true
        default:
            false
        }
    }

    /// Materializes a claimed record once against the mounted camera
    /// projection.  Every unclaimed record returns `nil`.
    @MainActor
    init?(
        record: ViewportSpatialInteractionRecord,
        project: (Point3D) throws -> CGPoint
    ) throws {
        guard Self.claims(record.target) else { return nil }
        self.record = record
        self.target = try record.materialize(using: project)
    }

    /// The value this update reads from the retained projection.
    ///
    /// `nil` means the update carries no new value: the pointer sits on the
    /// projected centre and names no direction, or the route commits on click
    /// and holds no drag state.  The caller keeps the value it already
    /// retained rather than substituting one.
    func value(start: CGPoint, current: CGPoint) throws -> Value? {
        switch target {
        case .patternArrayRadialAngle(_, let projection):
            return try projection.angle(start: start, current: current).map { .angleRadians($0) }

        case .patternArrayCopyCountLinear(_, let projection):
            return .copyCount(try projection.count(start: start, current: current))

        case .patternArrayCopyCountLinearDensity(_, let projection):
            return .copyCount(try projection.count(start: start, current: current))

        case .patternArrayCopyCountAngular(_, let projection):
            return try projection.count(start: start, current: current).map { .copyCount($0) }

        case .patternArrayCopyCountAngularDensity(_, let projection):
            return .copyCount(try projection.count(start: start, current: current))

        case .patternArrayCopyCountCurve(_, let projection):
            return .copyCount(try projection.count(start: start, current: current))

        case .patternArrayCurveExtent(_, let projection):
            return .curveExtentDistanceMeters(try projection.distance(current: current))

        case .patternArrayOutputMode:
            return nil

        default:
            throw RealityViewportSpatialBatch.invalid(
                "The materialized record is not a pattern affordance."
            )
        }
    }

    /// The public callback payload for a released drag, or `nil` when the
    /// gesture read no value or left the prepared value unchanged.
    func commit(value: Value?) throws -> Commit? {
        switch target {
        case .patternArrayRadialAngle(let source, let projection):
            guard let value else { return nil }
            guard case .angleRadians(let angleRadians) = value else {
                throw Self.mismatch("radial-angle")
            }
            guard angleRadians.isFinite else {
                throw RealityViewportSpatialBatch.invalid("The native pattern angle is not finite.")
            }
            guard abs(angleRadians - projection.baseAngleRadians) > 1.0e-12 else { return nil }
            return .patternArrayRadialAngle(.init(
                sourceID: source.sourceID, angleRadians: angleRadians
            ))

        case .patternArrayCopyCountLinear(let source, let projection):
            return try Self.copyCountCommit(source: source, base: projection.baseCopyCount, value: value)

        case .patternArrayCopyCountLinearDensity(let source, let projection):
            return try Self.copyCountCommit(source: source, base: projection.baseCopyCount, value: value)

        case .patternArrayCopyCountAngular(let source, let projection):
            return try Self.copyCountCommit(source: source, base: projection.baseCopyCount, value: value)

        case .patternArrayCopyCountAngularDensity(let source, let projection):
            return try Self.copyCountCommit(source: source, base: projection.baseCopyCount, value: value)

        case .patternArrayCopyCountCurve(let source, let projection):
            return try Self.copyCountCommit(source: source, base: projection.baseCopyCount, value: value)

        case .patternArrayCurveExtent(let source, let projection):
            guard let value else { return nil }
            guard case .curveExtentDistanceMeters(let distanceMeters) = value else {
                throw Self.mismatch("curve-extent")
            }
            guard distanceMeters.isFinite else {
                throw RealityViewportSpatialBatch.invalid("The native pattern extent is not finite.")
            }
            guard abs(distanceMeters - projection.baseDistanceMeters) > 1.0e-12 else { return nil }
            return .patternArrayCurveExtent(.init(
                sourceID: source.sourceID,
                extent: try Self.extent(distanceMeters, mode: source.extentMode, projection: projection)
            ))

        case .patternArrayOutputMode:
            // Output mode commits on click through `outputModeCommit(releasedAt:)`.
            return nil

        default:
            throw RealityViewportSpatialBatch.invalid(
                "The materialized record is not a pattern affordance."
            )
        }
    }

    /// The output-mode toggle for a click released on the retained label rect.
    ///
    /// `nil` when the release left the label, or when this input owns another
    /// route: only output mode commits without drag state.
    func outputModeCommit(releasedAt point: CGPoint) throws -> Commit? {
        guard case .patternArrayOutputMode(let source, let projection) = target else { return nil }
        guard point.x.isFinite, point.y.isFinite else {
            throw RealityViewportSpatialBatch.invalid("The native pattern click point is not finite.")
        }
        guard projection.hitRect.insetBy(dx: -6.0, dy: -6.0).contains(point) else { return nil }
        return .patternArrayOutputMode(.init(
            sourceID: source.sourceID,
            outputMode: Self.nextOutputMode(after: source.outputMode)
        ))
    }

    private static func copyCountCommit(
        source: ViewportPatternAffordanceSource.CopyCountHandle,
        base: Int,
        value: Value?
    ) throws -> Commit? {
        guard let value else { return nil }
        guard case .copyCount(let copyCount) = value else {
            throw mismatch("copy-count")
        }
        guard copyCount != base else { return nil }
        return .patternArrayCopyCount(.init(
            sourceID: source.sourceID, slot: source.slot, copyCount: copyCount
        ))
    }

    private static func extent(
        _ distanceMeters: Double,
        mode: PatternArrayCurveExtentMode,
        projection: ViewportSpatialMaterializedInteractionTarget.CurveExtentProjection
    ) throws -> ViewportPatternArrayCurveExtentDragValue {
        switch mode {
        case .distance:
            return .distance(distanceMeters)
        case .ratio:
            guard projection.totalLengthMeters.isFinite, projection.totalLengthMeters > 0.0 else {
                throw RealityViewportSpatialBatch.invalid("The pattern curve path has no positive length.")
            }
            let ratio = distanceMeters / projection.totalLengthMeters
            guard ratio.isFinite else {
                throw RealityViewportSpatialBatch.invalid("The native pattern extent ratio is not finite.")
            }
            return .ratio(ratio)
        }
    }

    /// The prepared handle carries the source's current mode, so the click
    /// commits the other one.
    private static func nextOutputMode(after outputMode: PatternArrayOutputMode) -> PatternArrayOutputMode {
        switch outputMode {
        case .componentInstance:
            .independentCopy
        case .independentCopy:
            .componentInstance
        }
    }

    private static func mismatch(_ route: String) -> Error {
        RealityViewportSpatialBatch.invalid("A pattern \(route) route read a value of another kind.")
    }
}
