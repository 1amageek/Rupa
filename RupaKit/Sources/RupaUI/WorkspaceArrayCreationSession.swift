import RupaCore
import SwiftCAD

/// An array being shaped right after it is made: a click sets a rectangular direction and distance,
/// X/Y/Z set a direction along an axis, Shift-wheel changes the copy count and I switches between
/// instances and independent copies.
///
/// The array exists while the session runs, so every change is an ordinary array update drawn by
/// the viewport; Return or Escape ends the session and leaves the array as it is.
struct WorkspaceArrayCreationSession: Equatable, Sendable {
    enum Slot: Equatable, Sendable {
        case first
        case second
    }

    let sourceID: PatternArraySourceID
    /// The world point rectangular directions are measured from: the center of the arrayed selection.
    let originWorld: Point3D
    /// The rectangular direction the next click sets, or `nil` while no click is awaited.
    var pickingSlot: Slot?
    /// The rectangular direction count and axis changes apply to.
    var activeSlot: Slot = .first

    init(sourceID: PatternArraySourceID, originWorld: Point3D, isRectangular: Bool) {
        self.sourceID = sourceID
        self.originWorld = originWorld
        pickingSlot = isRectangular ? .first : nil
    }

    /// Starts picking the second rectangular direction.
    mutating func pickSecondDirection() {
        pickingSlot = .second
        activeSlot = .second
    }

    /// The distribution with the picking direction pointing from the selection center to `point`,
    /// as far as it is. `patternFrame` is the world transform of the frame the array is read in.
    mutating func distribution(
        of source: PatternArraySource,
        toward point: Point3D,
        patternFrame: Transform3D
    ) throws -> PatternArrayDistribution {
        guard let slot = pickingSlot else {
            throw EditorError(code: .commandInvalid, message: "The array is not waiting for a direction.")
        }
        let local = try patternFrame.inverseApplyingLinearPart(to: point - originWorld)
        guard local.length > ModelingTolerance.standard.distance else {
            throw EditorError(code: .commandInvalid, message: "Click away from the arrayed objects to set the direction.")
        }
        let updated = try setting(
            slot, of: source,
            direction: try local.normalized(tolerance: ModelingTolerance.standard.distance),
            distance: local.length
        )
        activeSlot = slot
        pickingSlot = nil
        return updated
    }

    /// The distribution with the active rectangular direction along a world axis, keeping its distance.
    func distribution(
        of source: PatternArraySource,
        alongWorldAxis axis: SceneTransformAxis,
        patternFrame: Transform3D
    ) throws -> PatternArrayDistribution {
        let world: Vector3D = switch axis {
        case .x: .unitX
        case .y: .unitY
        case .z: .unitZ
        }
        let local = try patternFrame.inverseApplyingLinearPart(to: world)
        return try setting(
            pickingSlot ?? activeSlot, of: source,
            direction: try local.normalized(tolerance: ModelingTolerance.standard.distance),
            distance: nil
        )
    }

    /// The distribution with one copy more or fewer (never fewer than one) along the active
    /// direction, around a radial array or along a curve.
    func distribution(of source: PatternArraySource, addingCopies delta: Int) throws -> PatternArrayDistribution {
        switch source.distribution {
        case .rectangular(var rectangular):
            if activeSlot == .second, var second = rectangular.secondAxis {
                second.copyCount = max(1, second.copyCount + delta)
                rectangular.secondAxis = second
            } else {
                rectangular.firstAxis.copyCount = max(1, rectangular.firstAxis.copyCount + delta)
            }
            return .rectangular(rectangular)
        case .radial(var radial):
            radial.angularAxis.copyCount = max(1, radial.angularAxis.copyCount + delta)
            return .radial(radial)
        case .curve(var curve):
            curve.copyCount = max(1, curve.copyCount + delta)
            return .curve(curve)
        }
    }

    private func setting(
        _ slot: Slot,
        of source: PatternArraySource,
        direction: Vector3D,
        distance: Double?
    ) throws -> PatternArrayDistribution {
        guard case .rectangular(var rectangular) = source.distribution else {
            throw EditorError(code: .commandInvalid, message: "Only a rectangular array takes directions.")
        }
        switch slot {
        case .first:
            rectangular.firstAxis.direction = direction
            if let distance { rectangular.firstAxis.distance = .length(distance, .meter) }
        case .second:
            var second = rectangular.secondAxis ?? PatternArrayLinearAxis(
                direction: direction,
                distance: rectangular.firstAxis.distance,
                copyCount: 1,
                distanceMode: rectangular.firstAxis.distanceMode
            )
            second.direction = direction
            if let distance { second.distance = .length(distance, .meter) }
            rectangular.secondAxis = second
        }
        return .rectangular(rectangular)
    }

    var prompt: String {
        switch pickingSlot {
        case .first:
            return "Rectangular Array: click the direction and distance, or X/Y/Z. Shift-wheel changes the count, I instances, 2 a second direction, Return finishes."
        case .second:
            return "Rectangular Array: click the second direction and distance, or X/Y/Z. Return finishes."
        case nil:
            return "Array: Shift-wheel changes the count, I instances, Return finishes."
        }
    }
}
