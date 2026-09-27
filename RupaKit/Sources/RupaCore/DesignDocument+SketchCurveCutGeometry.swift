import Foundation
import SwiftCAD
import RupaCoreTypes

/// Cut Curve locates its cuts from Swift-CAD's certified sketch curve intersections; this file
/// only resolves the authored entities, chooses the cutter reach and turns each intersection's
/// natural parameter into the fraction or angle the source edit consumes.
extension DesignDocument {
    /// Sorted interior fractions of a line, arc or open spline target where the cutter crosses it.
    func cutSketchCurveFractions(
        targetSelection: EditableSketchEntitySelection,
        cutterSelection: EditableSketchEntitySelection,
        options: CutCurveOptions
    ) throws -> [Double] {
        try validateCutSketchCurveSelections(
            targetSelection: targetSelection,
            cutterSelection: cutterSelection,
            options: options
        )
        let target = try cutCurveGeometry(targetSelection.entity, role: .target)
        if case .circle = target {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve source subset requires a line, arc, or open spline target curve."
            )
        }
        let cutter = try cutCurveGeometry(cutterSelection.entity, role: .cutter)
        let fractions = try cutInteriorFractions(
            target: target,
            cutter: cutter,
            extendsCutter: options.extendsCutter
        )
        guard fractions.isEmpty == false else {
            if options.extendsCutter == false,
               cutCurveCanExtend(cutter),
               try cutInteriorFractions(target: target, cutter: cutter, extendsCutter: true).isEmpty == false {
                throw cutterDoesNotReach
            }
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve cutter does not intersect the target curve inside the supported target segment."
            )
        }
        return fractions
    }

    /// The two distinct polar angles where the cutter crosses a circle target.
    func cutAnglesForCircleTarget(
        target: SketchCircle,
        cutterSelection: EditableSketchEntitySelection,
        extendsCutter: Bool
    ) throws -> [Double] {
        let targetGeometry = try cutCurveGeometry(.circle(target), role: .target)
        let cutter = try cutCurveGeometry(cutterSelection.entity, role: .cutter)
        let angles = uniqueCutAngles(try cutCurveIntersections(
            target: targetGeometry,
            cutter: cutter,
            extendsCutter: extendsCutter
        ).map(\.firstParameter))
        if angles.isEmpty,
           extendsCutter == false,
           cutCurveCanExtend(cutter),
           try cutCurveIntersections(target: targetGeometry, cutter: cutter, extendsCutter: true).isEmpty == false {
            throw cutterDoesNotReach
        }
        guard angles.count == 2 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve circle target requires two distinct cutter intersections to create two arc segments."
            )
        }
        return angles
    }

    /// Where every other line, circle, arc and open spline of the target's sketch crosses it, at
    /// the authored reach: interior fractions for a line, arc or open spline target, distinct angles
    /// for a circle. The bounds Trim takes its segments from.
    func trimCrossings(of targetSelection: EditableSketchEntitySelection) throws -> [Double] {
        let target = try cutCurveGeometry(targetSelection.entity, role: .target)
        var crossings: [Double] = []
        for (entityID, entity) in targetSelection.sketch.entities.sorted(by: { $0.key.description < $1.key.description })
            where entityID != targetSelection.entityID {
            switch entity {
            case .point: continue
            case .spline(let spline) where spline.isClosed: continue
            default: break
            }
            let cutter = try cutCurveGeometry(entity, role: .cutter)
            for intersection in try cutCurveIntersections(target: target, cutter: cutter, extendsCutter: false) {
                crossings.append(splitParameter(ofNatural: intersection.firstParameter, on: target))
            }
        }
        if case .circle = target {
            return uniqueCutAngles(crossings)
        }
        return uniqueInteriorCutFractions(crossings)
    }

    func validateCutSketchCurveSelections(
        targetSelection: EditableSketchEntitySelection,
        cutterSelection: EditableSketchEntitySelection,
        options: CutCurveOptions
    ) throws {
        guard options.usesScreenSpaceDirection == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve screen-space direction requires a 3D cutter context that is not represented yet."
            )
        }
        guard targetSelection.featureID != cutterSelection.featureID ||
            targetSelection.entityID != cutterSelection.entityID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve requires distinct target and cutter curves."
            )
        }
        guard targetSelection.sketch.plane == cutterSelection.sketch.plane else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve source curve cutter requires target and cutter to share a sketch plane."
            )
        }
    }

    private enum CutCurveRole {
        case target
        case cutter

        var owner: String {
            switch self {
            case .target: "Cut Curve target"
            case .cutter: "Cut Curve cutter"
            }
        }
    }

    private var cutterDoesNotReach: EditorError {
        EditorError(
            code: .commandInvalid,
            message: "Cut Curve cutter does not reach the target curve; enable cutter extension for this case."
        )
    }

    private func cutCurveCanExtend(_ cutter: SketchCurveGeometry2D) -> Bool {
        switch cutter {
        case .line, .arc: true
        case .circle, .cubicBezierChain: false
        }
    }

    /// Target fractions strictly inside the target, in the parameter `splitSketchCurve` takes.
    /// Whether `cutter` cuts `target` at all: two crossings on a circle target, an interior
    /// crossing on any other target, with the cutter extended when `options` says so.
    func cutCurveCrosses(target: SelectionTarget, cutter: SelectionTarget, options: CutCurveOptions) throws -> Bool {
        let targetSelection = try editableSketchEntity(for: target, operationName: "Cut Curve target")
        let cutterSelection = try editableSketchEntity(for: cutter, operationName: "Cut Curve cutter")
        try validateCutSketchCurveSelections(
            targetSelection: targetSelection,
            cutterSelection: cutterSelection,
            options: options
        )
        let targetGeometry = try cutCurveGeometry(targetSelection.entity, role: .target)
        let cutterGeometry = try cutCurveGeometry(cutterSelection.entity, role: .cutter)
        if case .circle = targetGeometry {
            let hits = try cutCurveIntersections(
                target: targetGeometry, cutter: cutterGeometry, extendsCutter: options.extendsCutter
            )
            return uniqueCutAngles(hits.map(\.firstParameter)).count == 2
        }
        return try cutInteriorFractions(
            target: targetGeometry, cutter: cutterGeometry, extendsCutter: options.extendsCutter
        ).isEmpty == false
    }

    private func cutInteriorFractions(
        target: SketchCurveGeometry2D,
        cutter: SketchCurveGeometry2D,
        extendsCutter: Bool
    ) throws -> [Double] {
        let intersections = try cutCurveIntersections(target: target, cutter: cutter, extendsCutter: extendsCutter)
        return uniqueInteriorCutFractions(intersections.map { intersection in
            splitParameter(ofNatural: intersection.firstParameter, on: target)
        })
    }

    /// The parameter `splitSketchCurve` takes (line fraction, arc sweep fraction, chain parameter
    /// over span count) for a natural parameter Swift-CAD reports on `target`; a circle keeps its
    /// polar angle.
    func splitParameter(ofNatural parameter: Double, on target: SketchCurveGeometry2D) -> Double {
        switch target {
        case .line, .circle:
            return parameter
        case let .arc(_, _, startAngle, endAngle):
            return normalizedAngleDelta(from: startAngle, to: parameter) /
                positiveArcSpan(startAngle: startAngle, endAngle: endAngle)
        case let .cubicBezierChain(controlPoints):
            return parameter / Double((controlPoints.count - 1) / 3)
        }
    }

    /// The split parameter of the point of `entity` nearest `point`, from Swift-CAD's
    /// `SketchCurveProjector`: a line, arc or open spline's fraction, a circle's polar angle.
    func sketchCurveSplitParameter(of entity: SketchEntity, nearestTo point: Point2D) throws -> Double {
        let geometry = try cutCurveGeometry(entity, role: .target)
        do {
            let projection = try SketchCurveProjector(tolerance: .standard).nearest(on: geometry, to: point)
            return splitParameter(ofNatural: projection.parameter, on: geometry)
        } catch let error as KernelError {
            throw EditorError(code: .commandInvalid, message: "The curve point could not be found: \(error.message)")
        }
    }

    private func cutCurveIntersections(
        target: SketchCurveGeometry2D,
        cutter: SketchCurveGeometry2D,
        extendsCutter: Bool
    ) throws -> [SketchCurveIntersection2D] {
        if extendsCutter, case .cubicBezierChain = cutter {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve spline cutter extension is not represented in the current source subset."
            )
        }
        do {
            return try SketchCurveIntersector(tolerance: .standard).intersections(
                of: target,
                with: cutter,
                secondReach: extendsCutter ? .extended : .authored
            )
        } catch let error as KernelError where error.code == .resourceLimitExceeded {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve cannot certify where the cutter crosses the target (tangent or overlapping curves have no discrete cut): \(error.message)"
            )
        } catch let error as KernelError {
            throw EditorError(code: .commandInvalid, message: "Cut Curve geometry is invalid: \(error.message)")
        }
    }

    /// The authored entity as exact planar geometry in its sketch plane.
    private func cutCurveGeometry(
        _ entity: SketchEntity,
        role: CutCurveRole
    ) throws -> SketchCurveGeometry2D {
        let owner = role.owner
        switch entity {
        case .line(let line):
            return .line(
                start: try resolvedCutCurvePoint(line.start, owner: "\(owner) start"),
                end: try resolvedCutCurvePoint(line.end, owner: "\(owner) end")
            )
        case .circle(let circle):
            return .circle(
                center: try resolvedCutCurvePoint(circle.center, owner: "\(owner) center"),
                radius: try resolvedPositiveLengthValue(circle.radius, owner: "\(owner) radius")
            )
        case .arc(let arc):
            return .arc(
                center: try resolvedCutCurvePoint(arc.center, owner: "\(owner) center"),
                radius: try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) radius"),
                startAngle: try resolvedAngleValue(arc.startAngle, owner: "\(owner) start angle"),
                endAngle: try resolvedAngleValue(arc.endAngle, owner: "\(owner) end angle")
            )
        case .spline(let spline):
            guard spline.isClosed == false else {
                throw EditorError(code: .commandInvalid, message: "\(owner) requires an open spline curve.")
            }
            guard spline.controlPoints.count >= 4,
                  (spline.controlPoints.count - 1).isMultiple(of: 3) else {
                throw EditorError(code: .commandInvalid, message: "\(owner) requires a cubic Bezier spline.")
            }
            return .cubicBezierChain(controlPoints: try spline.controlPoints.map { point in
                try resolvedCutCurvePoint(point, owner: owner)
            })
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: role == .target
                    ? "Cut Curve source subset requires a line, arc, or open spline target curve."
                    : "Cut Curve source subset requires a line, circle, arc, or open spline cutter curve."
            )
        }
    }

    private func resolvedCutCurvePoint(
        _ point: SketchPoint,
        owner: String
    ) throws -> Point2D {
        Point2D(
            x: try resolvedLengthValue(point.x, owner: "\(owner) x"),
            y: try resolvedLengthValue(point.y, owner: "\(owner) y")
        )
    }
}
