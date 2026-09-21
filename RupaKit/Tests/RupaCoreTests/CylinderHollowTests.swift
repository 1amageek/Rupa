import Foundation
import SwiftCAD
import Testing
import RupaCoreTypes
@testable import RupaCore

@Suite("Cylinder hollow source")
struct CylinderHollowTests {

    private let hollowID = PropertyID(rawValue: "hollow")
    private let cornerID = PropertyID(rawValue: "corner.radius")

    private func faceCount(_ document: DesignDocument) throws -> Int {
        try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
            .evaluate(document.cadDocument)
            .brep.faces.count
    }

    private func storedLength(
        _ document: DesignDocument,
        _ nodeID: SceneNodeID,
        _ propertyID: PropertyID
    ) -> Double? {
        guard case let .length(meters) = document.productMetadata.sceneNodes[nodeID]?
            .object?.properties[propertyID] else {
            return nil
        }
        return meters
    }

    /// The circles the profile holds, which is how the inner entity's arrival and departure is
    /// observed rather than inferred from the face count alone.
    private func circleCount(_ document: DesignDocument, _ sketchNode: SceneNode) throws -> Int {
        guard let featureID = sketchNode.reference?.featureID,
              let feature = document.cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation else {
            throw EditorError(code: .referenceUnresolved, message: "The profile is unavailable.")
        }
        return sketch.entities.values.filter {
            if case .circle = $0 { return true }
            return false
        }.count
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

    /// A cylinder of radius 0.05 m and 0.06 m tall, which admits both a 0.01 m all-edge corner
    /// and a 0.02 m hollow, though never at once.
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

    /// The hollow the Inspector edits is the concentric hole in the circle profile, so a positive
    /// hollow opens one inner wall and a return to zero closes it again, leaving the profile the
    /// single circle it started as.
    @Test(.timeLimit(.minutes(2)))
    func hollowOpensAndClosesTheCircleProfile() throws {
        var document = DesignDocument.empty()
        let scene = try cylinder(&document)
        #expect(try faceCount(document) == 6)
        #expect(try circleCount(document, scene.sketch) == 1)
        #expect(try document.cylinderHollow(featureID: scene.featureID) == 0)

        try document.setSceneNodeObjectProperty(
            id: scene.body.id,
            propertyID: hollowID,
            value: .length(0.02)
        )
        #expect(try document.cylinderHollow(featureID: scene.featureID) == 0.02)
        // Two annular caps, four lateral faces on the outer wall, and four on the inner one.
        #expect(try faceCount(document) == 10)
        #expect(try circleCount(document, scene.sketch) == 2)
        #expect(storedLength(document, scene.body.id, hollowID) == 0.02)
        #expect(document.productMetadata.sceneNodes[scene.body.id]?.reference == scene.body.reference)

        try document.setSceneNodeObjectProperty(
            id: scene.body.id,
            propertyID: hollowID,
            value: .length(0.0)
        )
        #expect(try document.cylinderHollow(featureID: scene.featureID) == 0)
        #expect(try faceCount(document) == 6)
        #expect(try circleCount(document, scene.sketch) == 1)
        #expect(storedLength(document, scene.body.id, hollowID) == 0)
    }

    /// A tube is none of the prisms the kernel's all-edge fillet accepts, so the two edits refuse
    /// each other in both orders, and each refusal leaves the body exactly as it was.
    @Test(.timeLimit(.minutes(2)))
    func hollowAndCornerRefuseEachOther() throws {
        var document = DesignDocument.empty()
        let scene = try cylinder(&document)

        try document.setSceneNodeObjectProperty(
            id: scene.body.id, propertyID: hollowID, value: .length(0.02)
        )
        let cornerOnTube = editorErrorCode {
            try document.setSceneNodeObjectProperty(
                id: scene.body.id, propertyID: cornerID, value: .length(0.005)
            )
        }
        #expect(cornerOnTube == .commandInvalid)
        #expect(try faceCount(document) == 10)
        #expect(try document.boxCornerRadius(scene.featureID) == 0)
        #expect(try document.cylinderHollow(featureID: scene.featureID) == 0.02)

        var rounded = DesignDocument.empty()
        let roundedScene = try cylinder(&rounded)
        try rounded.setSceneNodeObjectProperty(
            id: roundedScene.body.id, propertyID: cornerID, value: .length(0.01)
        )
        let hollowOnFillet = editorErrorCode {
            try rounded.setSceneNodeObjectProperty(
                id: roundedScene.body.id, propertyID: hollowID, value: .length(0.02)
            )
        }
        #expect(hollowOnFillet == .commandInvalid)
        #expect(try faceCount(rounded) == 14)
        #expect(try rounded.boxCornerRadius(roundedScene.featureID) == 0.01)
        #expect(try rounded.cylinderHollow(featureID: roundedScene.featureID) == 0)
    }

    /// Each edit publishes a bound of zero while the other one holds the body, so the Inspector
    /// collapses the control it cannot accept instead of refusing every drag on it.
    @Test(.timeLimit(.minutes(2)))
    func eachBoundCollapsesUnderTheOtherEdit() throws {
        var document = DesignDocument.empty()
        let scene = try cylinder(&document)
        #expect(try document.maximumAllEdgeCornerRadius(featureID: scene.featureID) ?? -1 > 0)
        #expect(try document.maximumCylinderHollow(featureID: scene.featureID) ?? -1 > 0)

        try document.setSceneNodeObjectProperty(
            id: scene.body.id, propertyID: hollowID, value: .length(0.02)
        )
        #expect(try document.maximumAllEdgeCornerRadius(featureID: scene.featureID) == 0)

        try document.setSceneNodeObjectProperty(
            id: scene.body.id, propertyID: hollowID, value: .length(0.0)
        )
        try document.setSceneNodeObjectProperty(
            id: scene.body.id, propertyID: cornerID, value: .length(0.01)
        )
        #expect(try document.maximumCylinderHollow(featureID: scene.featureID) == 0)
    }

    /// The wall has to survive the hole, so a radius the current hollow no longer fits inside is
    /// refused before the rebuild, whether it arrives as a body dimension or as circle geometry.
    @Test(.timeLimit(.minutes(2)))
    func radiusRefusesToCloseOverTheHollow() throws {
        var document = DesignDocument.empty()
        let scene = try cylinder(&document)
        try document.setSceneNodeObjectProperty(
            id: scene.body.id, propertyID: hollowID, value: .length(0.04)
        )
        let sketchFeatureID = try #require(scene.sketch.reference?.featureID)

        let dimensionCode = editorErrorCode {
            try document.setCylinderDimensions(
                featureID: scene.featureID,
                radius: .length(0.03, .meter),
                sizeY: .length(0.06, .meter)
            )
        }
        #expect(dimensionCode == .commandInvalid)

        let geometryCode = editorErrorCode {
            try document.setCircleSketchGeometry(
                featureID: sketchFeatureID,
                radiusMeters: 0.03,
                objectRegistry: .builtIn
            )
        }
        #expect(geometryCode == .commandInvalid)

        // Both refusals leave the tube as it was.
        #expect(try faceCount(document) == 10)
        #expect(try document.cylinderHollow(featureID: scene.featureID) == 0.04)

        // A radius the hollow still fits inside is accepted by both paths, and each rebuild keeps
        // the hole the profile already holds rather than dropping it with the wall it rewrites.
        try document.setCylinderDimensions(
            featureID: scene.featureID,
            radius: .length(0.06, .meter),
            sizeY: .length(0.06, .meter)
        )
        #expect(try faceCount(document) == 10)
        #expect(try document.cylinderHollow(featureID: scene.featureID) == 0.04)

        try document.setCircleSketchGeometry(
            featureID: sketchFeatureID,
            radiusMeters: 0.08,
            objectRegistry: .builtIn
        )
        #expect(try faceCount(document) == 10)
        #expect(try document.cylinderHollow(featureID: scene.featureID) == 0.04)
    }
}
