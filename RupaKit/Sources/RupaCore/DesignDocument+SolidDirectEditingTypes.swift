import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    enum EditableBodyFace: Equatable {
        case front
        case back
        case top
        case bottom
        case left
        case right
        case side
    }

    enum EditableBodyEdge: Equatable, Hashable {
        case leftBottom
        case rightBottom
        case rightTop
        case leftTop

        var rectangleCorner: EditableBodyVertex {
            switch self {
            case .leftBottom:
                .bottomLeft
            case .rightBottom:
                .bottomRight
            case .rightTop:
                .topRight
            case .leftTop:
                .topLeft
            }
        }
    }

    enum EditableBodyVertex: Equatable, Hashable {
        case bottomLeft
        case bottomRight
        case topRight
        case topLeft
    }

    func movedRectangleProfileSketch(
        _ sketch: Sketch,
        corner: EditableBodyVertex,
        deltaXMeters: Double,
        deltaYMeters: Double,
        operationName: String
    ) throws -> Sketch {
        guard var bounds = try resolvedSketchBounds2D(sketch) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a finite rectangle profile."
            )
        }

        switch corner {
        case .bottomLeft:
            bounds.minX += deltaXMeters
            bounds.minY += deltaYMeters
        case .bottomRight:
            bounds.maxX += deltaXMeters
            bounds.minY += deltaYMeters
        case .topRight:
            bounds.maxX += deltaXMeters
            bounds.maxY += deltaYMeters
        case .topLeft:
            bounds.minX += deltaXMeters
            bounds.maxY += deltaYMeters
        }

        guard bounds.maxX - bounds.minX > 1.0e-9,
              bounds.maxY - bounds.minY > 1.0e-9 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) would collapse the rectangle profile."
            )
        }

        var rectangleSketch = sketch
        try updateRectangleSketch(
            &rectangleSketch,
            firstCorner: sketchPoint(x: bounds.minX, y: bounds.minY),
            oppositeCorner: sketchPoint(x: bounds.maxX, y: bounds.maxY)
        )
        return rectangleSketch
    }
}
