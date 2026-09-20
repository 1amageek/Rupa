import Foundation
import SwiftCAD
import Testing
import RupaCoreTypes
@testable import RupaCore

@Suite("Rectangle profile bevel")
struct RectangleProfileBevelTests {

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

    private func cube(
        _ document: inout DesignDocument
    ) throws -> (body: SceneNode, sketch: SceneNode, featureID: FeatureID) {
        let featureID = try document.createExtrudedRectangle(
            name: "Box",
            plane: .xy,
            width: .length(0.1, .meter),
            height: .length(0.08, .meter),
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

    /// The profile's `bevel` and the body's `corner.radius` are two names for one fillet, so an
    /// edit to either reaches the canvas and both read back the value the feature now carries.
    @Test(.timeLimit(.minutes(2)))
    func bevelAndCornerRadiusAreTwoViewsOfOneFillet() throws {
        var document = DesignDocument.empty()
        let scene = try cube(&document)
        #expect(try faceCount(document) == 6)

        try document.setSceneNodeObjectProperty(
            id: scene.sketch.id,
            propertyID: PropertyID(rawValue: "bevel"),
            value: .length(0.01)
        )
        #expect(try document.boxCornerRadius(scene.featureID) == 0.01)
        #expect(try faceCount(document) == 26)
        #expect(storedLength(document, scene.body.id, PropertyID(rawValue: "corner.radius")) == 0.01)
        #expect(storedLength(document, scene.sketch.id, PropertyID(rawValue: "bevel")) == 0.01)

        // A body reached through the design graph is named to the scene by its visible feature, so
        // resizing the profile underneath the wrapper still resynchronizes the body's size.
        try document.setSceneNodeObjectProperty(
            id: scene.sketch.id,
            propertyID: PropertyID(rawValue: "size.x"),
            value: .length(0.12)
        )
        #expect(try faceCount(document) == 26)
        #expect(storedLength(document, scene.body.id, PropertyID(rawValue: "size.x")) == 0.12)

        try document.setSceneNodeObjectProperty(
            id: scene.body.id,
            propertyID: PropertyID(rawValue: "corner.radius"),
            value: .length(0)
        )
        #expect(try faceCount(document) == 6)
        #expect(storedLength(document, scene.sketch.id, PropertyID(rawValue: "bevel")) == 0)
    }

    /// Rounding the profile and bevelling its box describe the same rounding, and the kernel
    /// builds only one of them, so each refuses the other before it mutates.
    @Test(.timeLimit(.minutes(2)))
    func aRoundedProfileAndABevelledBoxRefuseEachOther() throws {
        var document = DesignDocument.empty()
        let scene = try cube(&document)
        try document.setSceneNodeObjectProperty(
            id: scene.sketch.id,
            propertyID: PropertyID(rawValue: "bevel"),
            value: .length(0.01)
        )
        let bevelled = document

        do {
            try document.setSceneNodeObjectProperty(
                id: scene.sketch.id,
                propertyID: PropertyID(rawValue: "corner.radius"),
                value: .length(0.01)
            )
            Issue.record("Rounding the profile of a bevelled box must be refused.")
        } catch let error as EditorError {
            #expect(error.code == .commandInvalid)
        }
        #expect(document.productMetadata == bevelled.productMetadata)
        #expect(try faceCount(document) == 26)

        var rounded = DesignDocument.empty()
        let roundedScene = try cube(&rounded)
        try rounded.setSceneNodeObjectProperty(
            id: roundedScene.sketch.id,
            propertyID: PropertyID(rawValue: "corner.radius"),
            value: .length(0.01)
        )
        let roundedFaces = try faceCount(rounded)
        let beforeBevel = rounded

        do {
            try rounded.setSceneNodeObjectProperty(
                id: roundedScene.sketch.id,
                propertyID: PropertyID(rawValue: "bevel"),
                value: .length(0.005)
            )
            Issue.record("Bevelling the box of a rounded profile must be refused.")
        } catch let error as EditorError {
            #expect(error.code == .commandInvalid)
        }
        do {
            try rounded.setSceneNodeObjectProperty(
                id: roundedScene.body.id,
                propertyID: PropertyID(rawValue: "corner.radius"),
                value: .length(0.005)
            )
            Issue.record("Rounding the box of a rounded profile must be refused.")
        } catch let error as EditorError {
            #expect(error.code == .commandInvalid)
        }
        #expect(rounded.productMetadata == beforeBevel.productMetadata)
        #expect(try faceCount(rounded) == roundedFaces)
    }

    /// A bevel on a profile nothing has extruded yet is latent state: it is bounded by the
    /// profile's own sides, and the extrusion that creates the body applies it.
    @Test(.timeLimit(.minutes(2)))
    func aLatentBevelIsAppliedByTheExtrusionThatCreatesTheBody() throws {
        var document = DesignDocument.empty()
        let featureID = try document.createRectangleSketch(
            name: "Profile",
            plane: .xy,
            width: .length(0.1, .meter),
            height: .length(0.08, .meter)
        )
        let node = try #require(document.productMetadata.sceneNodes.values.first {
            $0.reference?.featureID == featureID
        })

        do {
            try document.setSceneNodeObjectProperty(
                id: node.id,
                propertyID: PropertyID(rawValue: "bevel"),
                value: .length(0.05)
            )
            Issue.record("A bevel wider than half the profile's shorter side must be refused.")
        } catch let error as EditorError {
            #expect(error.code == .commandInvalid)
        }

        try document.setSceneNodeObjectProperty(
            id: node.id,
            propertyID: PropertyID(rawValue: "bevel"),
            value: .length(0.01)
        )
        #expect(document.cadDocument.designGraph.order == [featureID])

        try document.setSceneNodeObjectProperty(
            id: node.id,
            propertyID: PropertyID(rawValue: "extrusion"),
            value: .length(0.06)
        )
        #expect(try faceCount(document) == 26)
    }

    /// The extrusion a bevelled box hides behind its wrapper is the one the depth edit replaces,
    /// and the one removing the body has to take with it.
    @Test(.timeLimit(.minutes(2)))
    func extrusionEditsResolveThroughTheBevelWrapper() throws {
        var document = DesignDocument.empty()
        let featureID = try document.createRectangleSketch(
            name: "Profile",
            plane: .xy,
            width: .length(0.1, .meter),
            height: .length(0.08, .meter)
        )
        let node = try #require(document.productMetadata.sceneNodes.values.first {
            $0.reference?.featureID == featureID
        })
        try document.setSceneNodeObjectProperty(
            id: node.id,
            propertyID: PropertyID(rawValue: "extrusion"),
            value: .length(0.06)
        )
        let body = try #require(document.productMetadata.sceneNodes.values.first {
            $0.reference?.kind == .body
        })
        try document.setSceneNodeObjectProperty(
            id: body.id,
            propertyID: PropertyID(rawValue: "corner.radius"),
            value: .length(0.01)
        )
        #expect(try faceCount(document) == 26)

        try document.setSceneNodeObjectProperty(
            id: node.id,
            propertyID: PropertyID(rawValue: "extrusion"),
            value: .length(0.04)
        )
        let bodyFeatureID = try #require(
            document.productMetadata.sceneNodes[body.id]?.reference?.featureID
        )
        #expect(try document.boxCornerRadius(bodyFeatureID) == 0.01)
        #expect(try faceCount(document) == 26)

        // A depth below twice the radius leaves the box with no edge to round.
        let beforeRefusal = document
        do {
            try document.setSceneNodeObjectProperty(
                id: node.id,
                propertyID: PropertyID(rawValue: "extrusion"),
                value: .length(0.015)
            )
            Issue.record("A depth below twice the corner radius must be refused.")
        } catch let error as EditorError {
            #expect(error.code == .commandInvalid)
        }
        #expect(document.productMetadata == beforeRefusal.productMetadata)
        #expect(try faceCount(document) == 26)

        try document.setSceneNodeObjectProperty(
            id: node.id,
            propertyID: PropertyID(rawValue: "extrusion"),
            value: .length(0)
        )
        #expect(document.cadDocument.designGraph.order == [featureID])
        #expect(try faceCount(document) == 0)
    }

    /// Editing the bevel of a box that already carries one replaces the fillet in place, so the
    /// profile and the extrusion under it are reused rather than replayed.
    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func changingAnExistingBevelRebuildsOnlyTheFillet() throws {
        let store = CADDocumentStore()
        let featureID = try #require(
            try store.apply(.createRectangleSketch(
                name: "Profile",
                plane: .xy,
                width: .length(0.1, .meter),
                height: .length(0.08, .meter)
            )).primaryFeatureID
        )
        let nodeID = try #require(store.document.productMetadata.sceneNodes.values.first {
            $0.reference?.featureID == featureID
        }).id
        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "extrusion"),
            value: .length(0.06)
        ))
        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "bevel"),
            value: .length(0.01)
        ))

        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "bevel"),
            value: .length(0.02)
        ))

        let metrics = try #require(store.currentModelingEvaluationMetrics)
        #expect(metrics.totalFeatureCount == 3)
        #expect(metrics.rebuiltFeatureCount == 1)
        #expect(metrics.reusedFeatureCount == 2)
        #expect(metrics.replayFallbackCount == 0)
    }
}
