import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    func rectangleSideDimensionAxis(
        in sketch: Sketch,
        entityID: SketchEntityID
    ) throws -> RectangleSideDimensionAxis? {
        guard let lineIDs = try rectangleLineIDs(in: sketch) else {
            return nil
        }
        if entityID == lineIDs.bottom || entityID == lineIDs.top {
            return .width
        }
        if entityID == lineIDs.left || entityID == lineIDs.right {
            return .height
        }
        return nil
    }

    func updateRectangleSketchForSideDimension(
        _ sketch: inout Sketch,
        axis: RectangleSideDimensionAxis,
        length: CADExpression,
        resolvedLength: Double
    ) throws {
        guard let bounds = try resolvedSketchBounds2D(sketch) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch line dimension update requires a finite rectangle profile."
            )
        }
        guard resolvedLength > 1.0e-9 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch line dimension would collapse the rectangle profile."
            )
        }
        let fixedSnapshot = try fixedPointSnapshot(in: sketch, owner: "Sketch line dimension update")
        let fixedSides = try fixedRectangleSides(
            in: sketch,
            bounds: bounds,
            owner: "Sketch line dimension update"
        )
        let currentWidth = bounds.maxX - bounds.minX
        let currentHeight = bounds.maxY - bounds.minY
        if axis == .width,
           fixedSides.left,
           fixedSides.right,
           abs(currentWidth - resolvedLength) > 1.0e-12 {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch line dimension update cannot resize a rectangle with both horizontal sides fixed."
            )
        }
        if axis == .height,
           fixedSides.bottom,
           fixedSides.top,
           abs(currentHeight - resolvedLength) > 1.0e-12 {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch line dimension update cannot resize a rectangle with both vertical sides fixed."
            )
        }
        let minX: CADExpression
        let maxX: CADExpression
        let minY: CADExpression
        let maxY: CADExpression
        switch axis {
        case .width:
            if fixedSides.right && fixedSides.left == false {
                minX = .subtract(.length(bounds.maxX, .meter), length)
                maxX = .length(bounds.maxX, .meter)
            } else {
                minX = .length(bounds.minX, .meter)
                maxX = .add(minX, length)
            }
            minY = .length(bounds.minY, .meter)
            maxY = .length(bounds.maxY, .meter)
        case .height:
            minX = .length(bounds.minX, .meter)
            maxX = .length(bounds.maxX, .meter)
            if fixedSides.top && fixedSides.bottom == false {
                minY = .subtract(.length(bounds.maxY, .meter), length)
                maxY = .length(bounds.maxY, .meter)
            } else {
                minY = .length(bounds.minY, .meter)
                maxY = .add(minY, length)
            }
        }
        let firstCorner = SketchPoint(
            x: minX,
            y: minY
        )
        let oppositeCorner = SketchPoint(
            x: maxX,
            y: maxY
        )
        try updateRectangleSketch(
            &sketch,
            firstCorner: firstCorner,
            oppositeCorner: oppositeCorner
        )
        try validateFixedPointSnapshot(
            fixedSnapshot,
            in: sketch,
            owner: "Sketch line dimension update"
        )
    }

    private func fixedRectangleSides(
        in sketch: Sketch,
        bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double),
        owner: String
    ) throws -> RectangleFixedSides {
        var sides = RectangleFixedSides()
        for snapshot in try fixedPointSnapshot(in: sketch, owner: owner) {
            if nearlyEqual(snapshot.x, bounds.minX, tolerance: 1.0e-9) {
                sides.left = true
            }
            if nearlyEqual(snapshot.x, bounds.maxX, tolerance: 1.0e-9) {
                sides.right = true
            }
            if nearlyEqual(snapshot.y, bounds.minY, tolerance: 1.0e-9) {
                sides.bottom = true
            }
            if nearlyEqual(snapshot.y, bounds.maxY, tolerance: 1.0e-9) {
                sides.top = true
            }
        }
        return sides
    }

    private func fixedPointSnapshot(
        in sketch: Sketch,
        owner: String
    ) throws -> [FixedSketchPointSnapshot] {
        var snapshots: [FixedSketchPointSnapshot] = []
        for constraint in sketch.constraints {
            guard case let .fixed(reference) = constraint,
                  let point = try resolvedPoint(reference, in: sketch, owner: owner) else {
                continue
            }
            snapshots.append(FixedSketchPointSnapshot(
                reference: reference,
                x: point.x,
                y: point.y
            ))
        }
        return snapshots
    }

    private func validateFixedPointSnapshot(
        _ snapshots: [FixedSketchPointSnapshot],
        in sketch: Sketch,
        owner: String
    ) throws {
        for snapshot in snapshots {
            guard let point = try resolvedPoint(snapshot.reference, in: sketch, owner: owner) else {
                continue
            }
            guard nearlyEqual(point.x, snapshot.x, tolerance: 1.0e-9),
                  nearlyEqual(point.y, snapshot.y, tolerance: 1.0e-9) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) cannot move a fixed sketch point."
                )
            }
        }
    }
}

enum RectangleSideDimensionAxis: Equatable {
    case width
    case height
}

private struct RectangleFixedSides: Equatable {
    var left = false
    var right = false
    var bottom = false
    var top = false
}

private struct FixedSketchPointSnapshot: Equatable {
    var reference: SketchReference
    var x: Double
    var y: Double
}
