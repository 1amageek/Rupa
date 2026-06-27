import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    @discardableResult
    public mutating func createSketch(
        name: String,
        sketch: Sketch,
        geometryRole: ObjectDescriptor.GeometryRole = .sketchProfile,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let trimmedName = try normalizedMetadataName(name, owner: "Sketch")
        guard sketch.entities.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch must contain at least one entity."
            )
        }
        guard geometryRole == .sketchProfile || geometryRole == .curve else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch geometry role must be sketchProfile or curve."
            )
        }
        try sketch.validate()
        try sketch.validateExpressions(using: cadDocument.parameters)
        return try appendSketchFeature(
            name: trimmedName,
            sketch: sketch,
            geometryRole: geometryRole,
            objectRegistry: objectRegistry
        )
    }

    @discardableResult
    public mutating func createLineSketch(
        name: String,
        plane: SketchPlane,
        start: SketchPoint,
        end: SketchPoint,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let startX = try resolvedLengthValue(start.x, owner: "Line start x")
        let startY = try resolvedLengthValue(start.y, owner: "Line start y")
        let endX = try resolvedLengthValue(end.x, owner: "Line end x")
        let endY = try resolvedLengthValue(end.y, owner: "Line end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        let length = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard length > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Line sketch length must be greater than zero."
            )
        }
        var builder = SketchBuilder(on: plane)
        _ = builder.line(from: start, to: end)
        let sketch = builder.build()
        return try appendSketchFeature(
            name: name,
            sketch: sketch,
            typeID: .line,
            geometryRole: .curve,
            properties: ObjectPropertySet(values: [
                "length": .length(length),
                "angle": .angle(
                    Self.normalizedAngleDegrees(atan2(deltaY, deltaX) * 180.0 / .pi)
                ),
            ]),
            objectRegistry: objectRegistry
        )
    }

    @discardableResult
    public mutating func createCircleSketch(
        name: String,
        plane: SketchPlane,
        center: SketchPoint,
        radius: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let resolvedRadius = try resolvedLengthValue(radius, owner: "Circle radius")
        guard resolvedRadius > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Circle sketch radius must be greater than zero."
            )
        }

        var builder = SketchBuilder(on: plane)
        builder.circle(center: center, radius: radius)
        let sketch = builder.build()
        return try appendSketchFeature(
            name: name,
            sketch: sketch,
            typeID: .circle,
            properties: ObjectPropertySet(values: [
                "radius": .length(resolvedRadius),
            ]),
            objectRegistry: objectRegistry
        )
    }

    @discardableResult
    public mutating func createArcSketch(
        name: String,
        plane: SketchPlane,
        center: SketchPoint,
        radius: CADExpression,
        startAngle: CADExpression,
        endAngle: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let resolvedRadius = try resolvedLengthValue(radius, owner: "Arc radius")
        guard resolvedRadius > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Arc sketch radius must be greater than zero."
            )
        }
        let resolvedStartAngle = try resolvedAngleValue(startAngle, owner: "Arc start angle")
        let resolvedEndAngle = try resolvedAngleValue(endAngle, owner: "Arc end angle")
        let angleSpan = try normalizedPartialArcSpan(
            startAngle: resolvedStartAngle,
            endAngle: resolvedEndAngle
        )

        var builder = SketchBuilder(on: plane)
        builder.arc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle
        )
        let sketch = builder.build()
        return try appendSketchFeature(
            name: name,
            sketch: sketch,
            typeID: .arc,
            geometryRole: .curve,
            properties: ObjectPropertySet(values: [
                "radius": .length(resolvedRadius),
                "start.angle": .angle(
                    Self.normalizedAngleDegrees(resolvedStartAngle * 180.0 / .pi)
                ),
                "end.angle": .angle(
                    Self.normalizedAngleDegrees((resolvedStartAngle + angleSpan) * 180.0 / .pi)
                ),
            ]),
            objectRegistry: objectRegistry
        )
    }

    @discardableResult
    public mutating func createSplineSketch(
        name: String,
        plane: SketchPlane,
        spline: SketchSpline,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        try validateSpline(spline, owner: "Spline sketch")

        var builder = SketchBuilder(on: plane)
        builder.spline(spline)
        let sketch = builder.build()
        return try appendSketchFeature(
            name: name,
            sketch: sketch,
            typeID: .spline,
            geometryRole: .curve,
            properties: ObjectPropertySet(values: [
                "control.point.count": .integer(spline.controlPoints.count),
            ]),
            objectRegistry: objectRegistry
        )
    }

    @discardableResult
    public mutating func createRectangleSketch(
        name: String,
        plane: SketchPlane,
        width: CADExpression,
        height: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let resolvedWidth = try resolvedLengthValue(width, owner: "Rectangle width")
        let resolvedHeight = try resolvedLengthValue(height, owner: "Rectangle height")
        guard resolvedWidth > 0.0, resolvedHeight > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Rectangle sketch size must be greater than zero."
            )
        }
        var builder = SketchBuilder(on: plane)
        builder.rectangle(width: width, height: height)
        let sketch = builder.build()
        return try appendSketchFeature(
            name: name,
            sketch: sketch,
            typeID: .rectangle,
            properties: ObjectPropertySet(values: [
                "size.x": .length(resolvedWidth),
                "size.y": .length(resolvedHeight),
            ]),
            objectRegistry: objectRegistry
        )
    }

    @discardableResult
    public mutating func createRectangleSketchFromCorners(
        name: String,
        plane: SketchPlane,
        firstCorner: SketchPoint,
        oppositeCorner: SketchPoint,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let firstX = try resolvedLengthValue(firstCorner.x, owner: "Rectangle first corner x")
        let firstY = try resolvedLengthValue(firstCorner.y, owner: "Rectangle first corner y")
        let oppositeX = try resolvedLengthValue(oppositeCorner.x, owner: "Rectangle opposite corner x")
        let oppositeY = try resolvedLengthValue(oppositeCorner.y, owner: "Rectangle opposite corner y")
        guard firstX != oppositeX, firstY != oppositeY else {
            throw EditorError(
                code: .commandInvalid,
                message: "Rectangle sketch corners must define a non-zero width and height."
            )
        }

        let bottom = SketchEntityID()
        let right = SketchEntityID()
        let top = SketchEntityID()
        let left = SketchEntityID()
        let bottomLeft = firstCorner
        let bottomRight = SketchPoint(x: oppositeCorner.x, y: firstCorner.y)
        let topRight = oppositeCorner
        let topLeft = SketchPoint(x: firstCorner.x, y: oppositeCorner.y)
        let sketch = Sketch(
            plane: plane,
            entities: [
                bottom: .line(SketchLine(start: bottomLeft, end: bottomRight)),
                right: .line(SketchLine(start: bottomRight, end: topRight)),
                top: .line(SketchLine(start: topRight, end: topLeft)),
                left: .line(SketchLine(start: topLeft, end: bottomLeft)),
            ],
            constraints: [
                .horizontal(bottom),
                .vertical(right),
                .horizontal(top),
                .vertical(left),
                .coincident(.lineEnd(bottom), .lineStart(right)),
                .coincident(.lineEnd(right), .lineStart(top)),
                .coincident(.lineEnd(top), .lineStart(left)),
                .coincident(.lineEnd(left), .lineStart(bottom)),
            ]
        )
        return try appendSketchFeature(
            name: name,
            sketch: sketch,
            typeID: .rectangle,
            properties: ObjectPropertySet(values: [
                "size.x": .length(abs(oppositeX - firstX)),
                "size.y": .length(abs(oppositeY - firstY)),
            ]),
            objectRegistry: objectRegistry
        )
    }

    @discardableResult
    public mutating func createPolygonSketch(
        name: String,
        plane: SketchPlane,
        center: SketchPoint,
        radius: CADExpression,
        sides: Int,
        sizingMode: PolygonSizingMode = .circumradius,
        inclinationMode: PolygonInclinationMode = .vertical,
        rotationAngle: CADExpression = .angle(0.0, .radian),
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        _ = try resolvedLengthValue(center.x, owner: "Polygon center x")
        _ = try resolvedLengthValue(center.y, owner: "Polygon center y")
        let resolvedRadius = try resolvedLengthValue(radius, owner: "Polygon radius")
        guard resolvedRadius > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Polygon sketch radius must be greater than zero."
            )
        }
        try validatePolygonSides(sides)
        let resolvedRotationAngle = try resolvedAngleValue(rotationAngle, owner: "Polygon rotation angle")
        let resolvedCircumradius = sizingMode.circumradius(from: resolvedRadius, sides: sides)
        let sideLength = sizingMode.sideLength(from: resolvedRadius, sides: sides)
        let sketch = polygonSketch(
            plane: plane,
            center: center,
            radius: polygonCircumradiusExpression(
                radius,
                sides: sides,
                sizingMode: sizingMode
            ),
            sides: sides,
            rotationAngle: rotationAngle
        )

        return try appendSketchFeature(
            name: name,
            sketch: sketch,
            typeID: .polygon,
            properties: ObjectPropertySet(values: [
                "radius": .length(resolvedCircumradius),
                "sizing.radius": .length(resolvedRadius),
                "radius.is.inradius": .boolean(sizingMode == .inradius),
                "inclination.mode": .text(inclinationMode.rawValue),
                "sides.x": .integer(sides),
                "angle": .angle(
                    Self.normalizedAngleDegrees(resolvedRotationAngle * 180.0 / .pi)
                ),
                "side.length": .length(sideLength),
            ]),
            objectRegistry: objectRegistry
        )
    }

    private func validatePolygonSides(_ sides: Int) throws {
        guard sides >= 3, sides <= 256 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Polygon sketch sides must be between 3 and 256."
            )
        }
    }

    private func polygonSketch(
        plane: SketchPlane,
        center: SketchPoint,
        radius: CADExpression,
        sides: Int,
        rotationAngle: CADExpression
    ) -> Sketch {
        let entityIDs = (0..<sides).map { _ in SketchEntityID() }
        let vertices = (0..<sides).map { index in
            polygonVertex(
                center: center,
                radius: radius,
                rotationAngle: rotationAngle,
                vertexIndex: index,
                sides: sides
            )
        }
        var entities: [SketchEntityID: SketchEntity] = [:]
        var constraints: [SketchConstraint] = []

        for index in 0..<sides {
            let nextIndex = (index + 1) % sides
            let entityID = entityIDs[index]
            entities[entityID] = .line(
                SketchLine(
                    start: vertices[index],
                    end: vertices[nextIndex]
                )
            )
            constraints.append(
                .coincident(
                    .lineEnd(entityID),
                    .lineStart(entityIDs[nextIndex])
                )
            )
        }

        if let firstEntityID = entityIDs.first {
            for entityID in entityIDs.dropFirst() {
                constraints.append(.equalLength(firstEntityID, entityID))
            }
        }

        return Sketch(
            plane: plane,
            entities: entities,
            constraints: constraints
        )
    }

    private func polygonCircumradiusExpression(
        _ radius: CADExpression,
        sides: Int,
        sizingMode: PolygonSizingMode
    ) -> CADExpression {
        switch sizingMode {
        case .circumradius:
            return radius
        case .inradius:
            return .divide(
                radius,
                .cos(.angle(Double.pi / Double(sides), .radian))
            )
        }
    }

    private func polygonVertex(
        center: SketchPoint,
        radius: CADExpression,
        rotationAngle: CADExpression,
        vertexIndex: Int,
        sides: Int
    ) -> SketchPoint {
        let stepAngle = CADExpression.angle(
            Double(vertexIndex) * 2.0 * Double.pi / Double(sides),
            .radian
        )
        let angle = CADExpression.add(rotationAngle, stepAngle)
        return SketchPoint(
            x: .add(center.x, .multiply(radius, .cos(angle))),
            y: .add(center.y, .multiply(radius, .sin(angle)))
        )
    }
}
