import Foundation
import SwiftCAD
import Testing
import RupaCoreTypes
@testable import RupaCore

@Suite("Cylinder angle source")
struct CylinderAngleTests {

    private let angleID = PropertyID(rawValue: "angle")
    private let hollowID = PropertyID(rawValue: "hollow")
    private let cornerID = PropertyID(rawValue: "corner.radius")

    private func faceCount(_ document: DesignDocument) throws -> Int {
        try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
            .evaluate(document.cadDocument)
            .brep.faces.count
    }

    private func sketch(_ document: DesignDocument, _ sketchNode: SceneNode) throws -> Sketch {
        guard let featureID = sketchNode.reference?.featureID,
              let feature = document.cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation else {
            throw EditorError(code: .referenceUnresolved, message: "The profile is unavailable.")
        }
        return sketch
    }

    /// The entity kinds the profile holds, which is how the change of kind on the outer wall and
    /// the arrival and departure of the radial lines are observed rather than inferred from the
    /// face count alone.
    private func entityCounts(
        _ document: DesignDocument,
        _ sketchNode: SceneNode
    ) throws -> (circles: Int, arcs: Int, lines: Int) {
        let entities = try sketch(document, sketchNode).entities.values
        var counts = (circles: 0, arcs: 0, lines: 0)
        for entity in entities {
            switch entity {
            case .circle: counts.circles += 1
            case .arc: counts.arcs += 1
            case .line: counts.lines += 1
            default: break
            }
        }
        return counts
    }

    private func storedAngle(
        _ document: DesignDocument,
        _ nodeID: SceneNodeID
    ) -> Double? {
        guard case let .angle(degrees) = document.productMetadata.sceneNodes[nodeID]?
            .object?.properties[angleID] else {
            return nil
        }
        return degrees
    }

    private func editorErrorCode(_ body: () throws -> Void) -> EditorError.Code? {
        do {
            try body()
            return nil
        } catch let error as EditorError {
            return error.code
        } catch {
            return nil
        }
    }

    private func nearlyEqual(_ lhs: Double, _ rhs: Double, tolerance: Double = 1.0e-9) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    /// The turn the profile carries, as a value rather than an optional, so the sweep can be
    /// compared with a tolerance the way every other resolved length is.
    private func angle(_ document: DesignDocument, _ featureID: FeatureID) throws -> Double {
        guard let degrees = try document.cylinderAngle(featureID: featureID) else {
            throw EditorError(code: .referenceUnresolved, message: "The cylinder has no turn.")
        }
        return degrees
    }

    /// The entity the outer wall is drawn as, whose identity survives the change of kind between
    /// a circle and an arc.
    private func outerEntityID(
        _ document: DesignDocument,
        _ sketchNode: SceneNode
    ) throws -> SketchEntityID {
        guard let profile = try document.recognizedCylinderProfile(
            in: try sketch(document, sketchNode)
        ) else {
            throw EditorError(code: .referenceUnresolved, message: "The profile is unavailable.")
        }
        return profile.outer.id
    }

    /// A cylinder of radius 0.05 m and 0.06 m tall, the same body the hollow suite edits.
    private func cylinder(
        _ document: inout DesignDocument
    ) throws -> (body: SceneNode, sketch: SceneNode, featureID: FeatureID) {
        let featureID = try document.createExtrudedCircle(
            name: "Cylinder",
            plane: .xy,
            center: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
            radius: .length(0.05, .meter),
            depth: .length(0.06, .meter),
            direction: .normal
        )
        let body = try #require(document.productMetadata.sceneNodes.values.first {
            $0.reference?.kind == .body
        })
        let sketch = try #require(document.productMetadata.sceneNodes.values.first {
            $0.reference?.kind == .sketch
        })
        return (body, sketch, featureID)
    }

    /// The angle the Inspector edits is the turn the profile's wall sweeps, so a partial turn
    /// writes an arc over the circle's own entity and mints the two radial lines, a wider turn
    /// rewrites the same three, and a full turn writes the circle back and drops the lines.
    @Test(.timeLimit(.minutes(2)))
    func angleSweepsAndRestoresTheCircleProfile() throws {
        var document = DesignDocument.empty()
        let scene = try cylinder(&document)
        #expect(try faceCount(document) == 6)
        #expect(try document.cylinderAngle(featureID: scene.featureID) == 360)
        let outerID = try outerEntityID(document, scene.sketch)

        try document.setSceneNodeObjectProperty(
            id: scene.body.id, propertyID: angleID, value: .angle(90.0)
        )
        #expect(nearlyEqual(try angle(document, scene.featureID), 90.0))
        // Two caps, one quadrant of the outer wall, and the two radial walls the sweep opens.
        #expect(try faceCount(document) == 5)
        var counts = try entityCounts(document, scene.sketch)
        #expect(counts == (circles: 0, arcs: 1, lines: 2))
        #expect(try outerEntityID(document, scene.sketch) == outerID)
        #expect(storedAngle(document, scene.body.id) == 90.0)

        try document.setSceneNodeObjectProperty(
            id: scene.body.id, propertyID: angleID, value: .angle(270.0)
        )
        #expect(nearlyEqual(try angle(document, scene.featureID), 270.0))
        #expect(try faceCount(document) == 7)
        counts = try entityCounts(document, scene.sketch)
        #expect(counts == (circles: 0, arcs: 1, lines: 2))

        try document.setSceneNodeObjectProperty(
            id: scene.body.id, propertyID: angleID, value: .angle(360.0)
        )
        #expect(try document.cylinderAngle(featureID: scene.featureID) == 360)
        #expect(try faceCount(document) == 6)
        counts = try entityCounts(document, scene.sketch)
        #expect(counts == (circles: 1, arcs: 0, lines: 0))
        #expect(try outerEntityID(document, scene.sketch) == outerID)
        // A full turn is stored as a full turn rather than folded onto no turn at all.
        #expect(storedAngle(document, scene.body.id) == 360.0)
    }

    /// The hole and the turn are two edits on one family, so a sector of a tube is reachable from
    /// either order and each edit carries the other's value forward untouched.
    @Test(.timeLimit(.minutes(2)))
    func angleAndHollowComposeIntoASectorOfATube() throws {
        var document = DesignDocument.empty()
        let scene = try cylinder(&document)

        try document.setSceneNodeObjectProperty(
            id: scene.body.id, propertyID: angleID, value: .angle(90.0)
        )
        try document.setSceneNodeObjectProperty(
            id: scene.body.id, propertyID: hollowID, value: .length(0.02)
        )
        // Two caps, one quadrant on each wall, and the two radial walls between them.
        #expect(try faceCount(document) == 6)
        #expect(try document.cylinderHollow(featureID: scene.featureID) == 0.02)
        #expect(nearlyEqual(try angle(document, scene.featureID), 90.0))
        #expect(try entityCounts(document, scene.sketch) == (circles: 0, arcs: 2, lines: 2))

        // Widening the turn keeps the hole, and closing the hole keeps the turn.
        try document.setSceneNodeObjectProperty(
            id: scene.body.id, propertyID: angleID, value: .angle(180.0)
        )
        #expect(try document.cylinderHollow(featureID: scene.featureID) == 0.02)
        #expect(try faceCount(document) == 8)

        try document.setSceneNodeObjectProperty(
            id: scene.body.id, propertyID: hollowID, value: .length(0.0)
        )
        #expect(nearlyEqual(try angle(document, scene.featureID), 180.0))
        #expect(try faceCount(document) == 6)
        #expect(try entityCounts(document, scene.sketch) == (circles: 0, arcs: 1, lines: 2))
    }

    /// A sector is none of the four prisms the kernel's all-edge fillet accepts, so the two edits
    /// refuse each other in both orders, each refusal leaves the body as it was, and the bound the
    /// Inspector reads collapses rather than offering a drag every step of which is refused.
    @Test(.timeLimit(.minutes(2)))
    func angleAndCornerRefuseEachOther() throws {
        var document = DesignDocument.empty()
        let scene = try cylinder(&document)

        try document.setSceneNodeObjectProperty(
            id: scene.body.id, propertyID: angleID, value: .angle(90.0)
        )
        #expect(try document.maximumAllEdgeCornerRadius(featureID: scene.featureID) == 0)
        let cornerOnSector = editorErrorCode {
            try document.setSceneNodeObjectProperty(
                id: scene.body.id, propertyID: cornerID, value: .length(0.005)
            )
        }
        #expect(cornerOnSector == .commandInvalid)
        #expect(try faceCount(document) == 5)
        #expect(try document.boxCornerRadius(scene.featureID) == 0)

        var rounded = DesignDocument.empty()
        let roundedScene = try cylinder(&rounded)
        try rounded.setSceneNodeObjectProperty(
            id: roundedScene.body.id, propertyID: cornerID, value: .length(0.01)
        )
        let sweepOnFillet = editorErrorCode {
            try rounded.setSceneNodeObjectProperty(
                id: roundedScene.body.id, propertyID: angleID, value: .angle(90.0)
            )
        }
        #expect(sweepOnFillet == .commandInvalid)
        #expect(try faceCount(rounded) == 14)
        #expect(try rounded.boxCornerRadius(roundedScene.featureID) == 0.01)
        #expect(try rounded.cylinderAngle(featureID: roundedScene.featureID) == 360)
    }

    /// A half turn of a tube is two arcs and two lines, which is the shape a stadium is too, so
    /// the recognizer has to tell them apart by concentricity rather than by entity kinds.
    @Test(.timeLimit(.minutes(2)))
    func aHalfTurnOfATubeIsNotMistakenForAStadium() throws {
        var document = DesignDocument.empty()
        let scene = try cylinder(&document)
        try document.setSceneNodeObjectProperty(
            id: scene.body.id, propertyID: hollowID, value: .length(0.02)
        )
        try document.setSceneNodeObjectProperty(
            id: scene.body.id, propertyID: angleID, value: .angle(180.0)
        )
        #expect(try entityCounts(document, scene.sketch) == (circles: 0, arcs: 2, lines: 2))
        #expect(try document.maximumAllEdgeCornerRadius(featureID: scene.featureID) == 0)

        let code = editorErrorCode {
            try document.setSceneNodeObjectProperty(
                id: scene.body.id, propertyID: cornerID, value: .length(0.005)
            )
        }
        #expect(code == .commandInvalid)
        #expect(try faceCount(document) == 8)
    }

    /// The sweep is a turn in `(0°, 360°]`, and inside that range it is a shape only while the
    /// chord across the smallest arc the family holds clears the modeling tolerance. One chord
    /// covers both ends of the control, because it closes as the sweep approaches a full turn the
    /// same way it closes as the sweep approaches nothing.
    @Test(.timeLimit(.minutes(2)))
    func sweepRefusesTheTurnsThatAreNotShapes() throws {
        var document = DesignDocument.empty()
        let scene = try cylinder(&document)

        #expect(editorErrorCode {
            try document.setCylinderAngle(featureID: scene.featureID, degrees: 0.0)
        } == .commandInvalid)
        #expect(editorErrorCode {
            try document.setCylinderAngle(featureID: scene.featureID, degrees: -90.0)
        } == .commandInvalid)
        #expect(editorErrorCode {
            try document.setCylinderAngle(featureID: scene.featureID, degrees: 361.0)
        } == .commandInvalid)

        // A sliver, and a turn a sliver short of the full one, both leave the two ends of the wall
        // 8.7e-7 m apart, which the tolerance of 1e-6 m cannot tell from a closed loop.
        #expect(editorErrorCode {
            try document.setCylinderAngle(featureID: scene.featureID, degrees: 0.001)
        } == .commandInvalid)
        #expect(editorErrorCode {
            try document.setCylinderAngle(featureID: scene.featureID, degrees: 359.999)
        } == .commandInvalid)

        // Every refusal left the circle the cylinder was built as.
        #expect(try document.cylinderAngle(featureID: scene.featureID) == 360)
        #expect(try faceCount(document) == 6)
        #expect(try entityCounts(document, scene.sketch) == (circles: 1, arcs: 0, lines: 0))
    }

    /// The chord is measured on the smallest arc the family holds, so a hollow and a radius each
    /// have to answer for a sweep they did not author: opening a hole inside a narrow sector, or
    /// shrinking the wall it sweeps, can close the ends the sweep left open.
    @Test(.timeLimit(.minutes(2)))
    func theSweepIsRecheckedByTheEditsThatChangeItsRadius() throws {
        var document = DesignDocument.empty()
        let scene = try cylinder(&document)
        try document.setSceneNodeObjectProperty(
            id: scene.body.id, propertyID: angleID, value: .angle(1.0)
        )
        let sketchFeatureID = try #require(scene.sketch.reference?.featureID)

        // The outer wall spans 8.7e-4 m across this turn; a hole of 2e-5 m spans 3.5e-7 m.
        let hollowCode = editorErrorCode {
            try document.setSceneNodeObjectProperty(
                id: scene.body.id, propertyID: hollowID, value: .length(2.0e-5)
            )
        }
        #expect(hollowCode == .commandInvalid)

        let dimensionCode = editorErrorCode {
            try document.setCylinderDimensions(
                featureID: scene.featureID,
                radius: .length(2.0e-5, .meter),
                sizeY: .length(0.06, .meter)
            )
        }
        #expect(dimensionCode == .commandInvalid)

        let geometryCode = editorErrorCode {
            try document.setCircleSketchGeometry(
                featureID: sketchFeatureID,
                radiusMeters: 2.0e-5,
                objectRegistry: .builtIn
            )
        }
        #expect(geometryCode == .commandInvalid)

        // All three refusals leave the sector as it was.
        #expect(nearlyEqual(try angle(document, scene.featureID), 1.0))
        #expect(try document.cylinderHollow(featureID: scene.featureID) == 0)
        #expect(try faceCount(document) == 5)

        // A radius the same turn still spans is accepted, and keeps the turn it rebuilt around.
        try document.setCylinderDimensions(
            featureID: scene.featureID,
            radius: .length(0.08, .meter),
            sizeY: .length(0.06, .meter)
        )
        #expect(nearlyEqual(try angle(document, scene.featureID), 1.0))
        #expect(try faceCount(document) == 5)
    }
}
