import Foundation
import SwiftCAD
import RupaCoreTypes

/// Rebuilds a sketch profile from the shape properties its object type declares.
///
/// Every mutator here keeps the feature identity, its inputs, and its outputs, and commits the
/// rebuilt sketch through an in-place `replaceFeature`. That is what lets the evaluation engine
/// reuse every unaffected feature and rebuild only the profile and the bodies that consume it,
/// the same fast path the cube dimensions take.
extension DesignDocument {

    // MARK: - Profile access

    /// Reads a sketch feature without borrowing `self` mutably, so a caller can resolve
    /// expressions while it reshapes the sketch.
    func sketchProfileFeature(
        featureID: FeatureID,
        owner: String
    ) throws -> (feature: FeatureNode, sketch: Sketch) {
        guard let feature = cadDocument.designGraph.nodes[featureID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) requires an existing sketch feature."
            )
        }
        guard case let .sketch(sketch) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) requires a sketch feature."
            )
        }
        return (feature, sketch)
    }

    /// Replaces the sketch a feature already owns, keeping its ID, inputs, and outputs.
    ///
    /// The document is only adopted once the replacement validates, so a rejected shape leaves
    /// the previous geometry in place.
    mutating func commitSketchProfile(
        _ feature: FeatureNode,
        sketch: Sketch,
        owner: String
    ) throws {
        var updatedFeature = feature
        updatedFeature.operation = .sketch(sketch)
        var updatedCADDocument = cadDocument
        do {
            try updatedCADDocument.replaceFeature(
                updatedFeature,
                tolerance: modelingSettings.tolerance
            )
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) produced invalid geometry: \(error)."
            )
        }
        cadDocument = updatedCADDocument
    }

    // MARK: - Line

    mutating func setLineSketchGeometry(
        featureID: FeatureID,
        lengthMeters: Double,
        angleDegrees: Double,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let owner = "Line length"
        try validatePositiveLength(lengthMeters, owner: owner)
        try validateFiniteAngle(angleDegrees, owner: "Line angle")

        let profile = try sketchProfileFeature(featureID: featureID, owner: owner)
        guard let entry = singleLineEntry(in: profile.sketch) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Line geometry requires a sketch holding a single line."
            )
        }
        let startX = try resolvedLengthValue(entry.line.start.x, owner: "Line start x")
        let startY = try resolvedLengthValue(entry.line.start.y, owner: "Line start y")
        let angleRadians = angleDegrees * Double.pi / 180.0

        var sketch = profile.sketch
        sketch.entities[entry.id] = .line(
            SketchLine(
                start: entry.line.start,
                end: SketchPoint(
                    x: .length(startX + cos(angleRadians) * lengthMeters, .meter),
                    y: .length(startY + sin(angleRadians) * lengthMeters, .meter)
                )
            )
        )
        try commitSketchProfile(profile.feature, sketch: sketch, owner: owner)
        try synchronizeObjectPropertiesAffectedBySketch(
            featureID: featureID,
            objectRegistry: objectRegistry
        )
    }

    // MARK: - Arc

    mutating func setArcSketchGeometry(
        featureID: FeatureID,
        radiusMeters: Double,
        startAngleDegrees: Double,
        endAngleDegrees: Double,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let owner = "Arc radius"
        try validatePositiveLength(radiusMeters, owner: owner)
        try validateFiniteAngle(startAngleDegrees, owner: "Arc start angle")
        try validateFiniteAngle(endAngleDegrees, owner: "Arc end angle")

        let startRadians = startAngleDegrees * Double.pi / 180.0
        let endRadians = endAngleDegrees * Double.pi / 180.0
        let span = try normalizedPartialArcSpan(startAngle: startRadians, endAngle: endRadians)

        let profile = try sketchProfileFeature(featureID: featureID, owner: owner)
        guard let entry = singleArcEntry(in: profile.sketch) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Arc geometry requires a sketch holding a single arc."
            )
        }

        var sketch = profile.sketch
        sketch.entities[entry.id] = .arc(
            SketchArc(
                center: entry.arc.center,
                radius: .length(radiusMeters, .meter),
                startAngle: .angle(startRadians, .radian),
                endAngle: .angle(startRadians + span, .radian)
            )
        )
        try commitSketchProfile(profile.feature, sketch: sketch, owner: owner)

        // The stored end angle is the start angle plus the resolved span, matching what arc
        // creation writes, so a span that wrapped past a full turn reads back unwrapped.
        let resolvedEndDegrees = (startRadians + span) * 180.0 / Double.pi
        try updateSketchObjectProperties(
            featureID: featureID,
            objectRegistry: objectRegistry
        ) { object, definition in
            Self.setAngleProperty(
                "end.angle",
                to: resolvedEndDegrees,
                object: &object,
                definition: definition
            )
        }
        try synchronizeObjectPropertiesAffectedBySketch(
            featureID: featureID,
            objectRegistry: objectRegistry
        )
    }

    // MARK: - Circle

    mutating func setCircleSketchGeometry(
        featureID: FeatureID,
        radiusMeters: Double,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let owner = "Circle radius"
        try validatePositiveLength(radiusMeters, owner: owner)

        let profile = try sketchProfileFeature(featureID: featureID, owner: owner)
        guard let entry = singleCircleEntry(in: profile.sketch) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Circle geometry requires a sketch holding a single circle."
            )
        }

        // The cylinder this profile extrudes may already carry an all-edge fillet, and a smaller
        // radius has to keep admitting it. Refusing before the rebuild leaves the document as it
        // was rather than committing one the evaluator will reject.
        for bodyFeatureID in extrudedBodyFeatureIDs(forProfile: featureID) {
            let cornerRadius = try boxCornerRadius(bodyFeatureID)
            guard cornerRadius != 0 else { continue }
            let sizes = try resolvedExtrudedBodyDimensions(featureID: bodyFeatureID)
            try validateAllEdgeCorner(
                cornerRadius,
                on: .cylinder(radius: radiusMeters, height: sizes.sizeY)
            )
        }

        var sketch = profile.sketch
        sketch.entities[entry.id] = .circle(
            SketchCircle(
                center: entry.circle.center,
                radius: .length(radiusMeters, .meter)
            )
        )
        try commitSketchProfile(profile.feature, sketch: sketch, owner: owner)
        try synchronizeObjectPropertiesAffectedBySketch(
            featureID: featureID,
            objectRegistry: objectRegistry
        )
    }

    // MARK: - Rectangle

    /// Rebuilds a rectangle profile from the size and corner radius its schema declares.
    ///
    /// The corner radius is the second property that changes the profile's entity count, so the
    /// whole family is rebuilt through `RectangleProfileBuilder`: the four line IDs survive, the
    /// arc IDs are minted when the radius becomes positive and dropped when it returns to zero,
    /// and the constraint set is replaced rather than patched.
    mutating func setRectangleSketchGeometry(
        featureID: FeatureID,
        sizeXMeters: Double,
        sizeYMeters: Double,
        cornerRadiusMeters: Double,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let owner = "Rectangle size"
        try validatePositiveLength(sizeXMeters, owner: "Rectangle width")
        try validatePositiveLength(sizeYMeters, owner: "Rectangle height")

        let profile = try sketchProfileFeature(featureID: featureID, owner: owner)
        guard let recognized = try recognizedRectangleProfile(in: profile.sketch) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Rectangle geometry requires an axis-aligned rectangle profile."
            )
        }
        try validateRectangleCornerRadius(
            cornerRadiusMeters, sizeX: sizeXMeters, sizeY: sizeYMeters)
        // Rounding the profile and bevelling the box it extrudes are the same rounding, and the
        // kernel's all-edge fillet needs the orthogonal box only a square-cornered profile makes.
        // Refusing before the rebuild leaves the document as it was rather than committing one the
        // evaluator will reject.
        if cornerRadiusMeters > 0 {
            for bodyFeatureID in extrudedBodyFeatureIDs(forProfile: featureID) {
                guard try boxCornerRadius(bodyFeatureID) != 0 else { continue }
                throw EditorError(
                    code: .commandInvalid,
                    message: "The box this profile extrudes is bevelled, so its corners cannot also be rounded."
                )
            }
        }

        let rebuilt = RectangleProfileBuilder.build(
            centerX: recognized.centerX,
            centerY: recognized.centerY,
            sizeX: sizeXMeters,
            sizeY: sizeYMeters,
            cornerRadius: cornerRadiusMeters,
            reusing: recognized.ids
        )
        var sketch = profile.sketch
        sketch.entities = rebuilt.entities
        sketch.constraints = rebuilt.constraints
        if sketch.entityOrder.isEmpty == false {
            sketch.entityOrder = rebuilt.entityOrder
        }
        try commitSketchProfile(profile.feature, sketch: sketch, owner: owner)
        try synchronizeObjectPropertiesAffectedBySketch(
            featureID: featureID,
            objectRegistry: objectRegistry
        )
    }

    // MARK: - Polygon

    mutating func setPolygonSketchGeometry(
        featureID: FeatureID,
        sizingRadiusMeters: Double,
        isInradius: Bool,
        sides: Int,
        rotationDegrees: Double,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let owner = "Polygon radius"
        try validatePositiveLength(sizingRadiusMeters, owner: owner)
        try validateFiniteAngle(rotationDegrees, owner: "Polygon angle")
        try validatePolygonSides(sides)
        let sizingMode: PolygonSizingMode = isInradius ? .inradius : .circumradius

        let profile = try sketchProfileFeature(featureID: featureID, owner: owner)
        let center = try polygonProfileCenter(in: profile.sketch)
        let rotationRadians = rotationDegrees * Double.pi / 180.0
        // Keep the ID of every side that survives the rebuild so a count-preserving edit leaves the
        // sketch entity set untouched and only the vertex expressions change.
        let existingIDs = try polygonSideIDsInChainOrder(
            in: profile.sketch,
            center: center,
            fromAngleRadians: rotationRadians
        )
        let sideIDs = (0..<sides).map { index in
            index < existingIDs.count ? existingIDs[index] : SketchEntityID()
        }
        let rebuilt = polygonSketch(
            plane: profile.sketch.plane,
            center: SketchPoint(
                x: .length(center.x, .meter),
                y: .length(center.y, .meter)
            ),
            radius: polygonCircumradiusExpression(
                .length(sizingRadiusMeters, .meter),
                sides: sides,
                sizingMode: sizingMode
            ),
            sides: sides,
            rotationAngle: .angle(rotationRadians, .radian),
            reusedEntityIDs: sideIDs
        )

        var sketch = profile.sketch
        sketch.entities = rebuilt.entities
        sketch.constraints = rebuilt.constraints
        if sketch.entityOrder.isEmpty == false {
            var order = sketch.entityOrder.filter { rebuilt.entities[$0] != nil }
            let retained = Set(order)
            order.append(contentsOf: sideIDs.filter { retained.contains($0) == false })
            sketch.entityOrder = order
        }
        try commitSketchProfile(profile.feature, sketch: sketch, owner: owner)

        let circumradius = sizingMode.circumradius(from: sizingRadiusMeters, sides: sides)
        let sideLength = sizingMode.sideLength(from: sizingRadiusMeters, sides: sides)
        try updateSketchObjectProperties(
            featureID: featureID,
            objectRegistry: objectRegistry
        ) { object, definition in
            Self.setLengthProperty(PropertyID(rawValue: "radius"), to: circumradius, object: &object, definition: definition)
            Self.setLengthProperty(PropertyID(rawValue: "side.length"), to: sideLength, object: &object, definition: definition)
        }
        try synchronizeObjectPropertiesAffectedBySketch(
            featureID: featureID,
            objectRegistry: objectRegistry
        )
    }

    /// The center of a closed polygon, taken as the mean of its vertices.
    private func polygonProfileCenter(
        in sketch: Sketch
    ) throws -> (x: Double, y: Double) {
        var sumX = 0.0
        var sumY = 0.0
        var count = 0
        for entity in sketch.entities.values {
            guard case let .line(line) = entity else {
                throw polygonProfileRequired()
            }
            sumX += try resolvedLengthValue(line.start.x, owner: "Polygon vertex x")
            sumY += try resolvedLengthValue(line.start.y, owner: "Polygon vertex y")
            count += 1
        }
        guard count >= 3 else {
            throw polygonProfileRequired()
        }
        return (sumX / Double(count), sumY / Double(count))
    }

    /// Orders the existing sides the way `polygonSketch` lays a chain out: by the angle of each
    /// side's first vertex measured from the polygon's stored rotation.
    private func polygonSideIDsInChainOrder(
        in sketch: Sketch,
        center: (x: Double, y: Double),
        fromAngleRadians: Double
    ) throws -> [SketchEntityID] {
        var keyed: [(id: SketchEntityID, key: Double)] = []
        for (id, entity) in sketch.entities {
            guard case let .line(line) = entity else {
                throw polygonProfileRequired()
            }
            let x = try resolvedLengthValue(line.start.x, owner: "Polygon vertex x")
            let y = try resolvedLengthValue(line.start.y, owner: "Polygon vertex y")
            var key = atan2(y - center.y, x - center.x) - fromAngleRadians
            key = key.truncatingRemainder(dividingBy: 2.0 * Double.pi)
            if key < 0.0 {
                key += 2.0 * Double.pi
            }
            keyed.append((id, key))
        }
        return keyed.sorted { lhs, rhs in
            lhs.key == rhs.key
                ? lhs.id.description < rhs.id.description
                : lhs.key < rhs.key
        }.map(\.id)
    }

    private func polygonProfileRequired() -> EditorError {
        EditorError(
            code: .referenceUnresolved,
            message: "Polygon geometry requires a sketch of closed polygon sides."
        )
    }

    // MARK: - Input validation

    private func validatePositiveLength(_ meters: Double, owner: String) throws {
        guard meters.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must be a finite length."
            )
        }
        guard meters > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must be greater than zero."
            )
        }
    }

    private func validateFiniteAngle(_ degrees: Double, owner: String) throws {
        guard degrees.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must be a finite angle."
            )
        }
    }
}
