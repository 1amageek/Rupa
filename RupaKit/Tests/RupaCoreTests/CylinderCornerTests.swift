import Foundation
import SwiftCAD
import Testing
import RupaCoreTypes
@testable import RupaCore

@Suite("Cylinder corner source")
struct CylinderCornerTests {

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

    /// A cylinder of radius 0.05 m, by default 0.06 m tall, which admits a 0.01 m all-edge
    /// corner. Half its radius, 0.025 m, is the tighter of its two bounds at that height; a
    /// shorter one is bounded by half its height instead.
    private func cylinder(
        _ document: inout DesignDocument,
        height: Double = 0.06
    ) throws -> (body: SceneNode, sketch: SceneNode, featureID: FeatureID) {
        let featureID = try document.createExtrudedCircle(
            name: "Cylinder",
            plane: .xy,
            center: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
            radius: .length(0.05, .meter),
            depth: .length(height, .meter),
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

    /// The body's `corner.radius` and the circle profile's `bevel` are two names for one fillet,
    /// so an edit to either reaches the canvas and both read back the value the feature carries.
    @Test(.timeLimit(.minutes(2)))
    func cornerAndBevelAreTwoViewsOfOneCylinderFillet() throws {
        var document = DesignDocument.empty()
        let scene = try cylinder(&document)
        #expect(try faceCount(document) == 6)

        try document.setSceneNodeObjectProperty(
            id: scene.body.id,
            propertyID: PropertyID(rawValue: "corner.radius"),
            value: .length(0.01)
        )
        #expect(try document.boxCornerRadius(scene.featureID) == 0.01)
        // Two planar caps, four lateral faces on one cylinder, and eight torus faces.
        #expect(try faceCount(document) == 14)
        #expect(storedLength(document, scene.body.id, PropertyID(rawValue: "corner.radius")) == 0.01)
        #expect(storedLength(document, scene.sketch.id, PropertyID(rawValue: "bevel")) == 0.01)
        #expect(document.productMetadata.sceneNodes[scene.body.id]?.reference == scene.body.reference)

        try document.setSceneNodeObjectProperty(
            id: scene.sketch.id,
            propertyID: PropertyID(rawValue: "bevel"),
            value: .length(0.02)
        )
        #expect(try document.boxCornerRadius(scene.featureID) == 0.02)
        #expect(try faceCount(document) == 14)
        #expect(storedLength(document, scene.body.id, PropertyID(rawValue: "corner.radius")) == 0.02)

        try document.setSceneNodeObjectProperty(
            id: scene.sketch.id,
            propertyID: PropertyID(rawValue: "bevel"),
            value: .length(0)
        )
        #expect(try faceCount(document) == 6)
        #expect(storedLength(document, scene.body.id, PropertyID(rawValue: "corner.radius")) == 0)
    }

    /// Dimension edits resolve through the all-edge wrapper rather than the feature it hides, and
    /// the cylinder the kernel rounds keeps its exact face count across them.
    @Test(.timeLimit(.minutes(2)))
    func roundedCylinderDimensionsResolveThroughTheWrapper() throws {
        var document = DesignDocument.empty()
        let scene = try cylinder(&document)
        try document.setSceneNodeObjectProperty(
            id: scene.body.id,
            propertyID: PropertyID(rawValue: "corner.radius"),
            value: .length(0.01)
        )

        try document.setCylinderDimensions(
            featureID: scene.featureID,
            radius: .length(0.06, .meter),
            sizeY: .length(0.07, .meter)
        )
        #expect(try faceCount(document) == 14)
        #expect(try document.boxCornerRadius(scene.featureID) == 0.01)
        let dimensions = try ObjectDimensionSourceResolver().resolve(
            target: .init(sceneNodeID: scene.body.id, component: .object), in: document)
        #expect(abs(dimensions.radius.map { $0 - 0.06 } ?? 1.0) < 1e-12)
        #expect(abs(dimensions.sizeY - 0.07) < 1e-12)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".rupa")
        defer { do { try FileManager.default.removeItem(at: url) } catch { Issue.record(error) } }
        try DocumentFileService().save(document, to: url)
        document = try DocumentFileService().load(from: url).document
        #expect(try document.boxCornerRadius(scene.featureID) == 0.01)

        // Setting zero restores the extrusion the wrapper hid, unchanged by the round trip, and
        // removes the intermediate feature it lived in.
        let hiddenFeatureID = document.boxExtrusionFeatureID(scene.featureID)
        let hiddenOperation = document.cadDocument.designGraph.nodes[hiddenFeatureID]?.operation
        #expect(hiddenFeatureID != scene.featureID)
        try document.setSceneNodeObjectProperty(
            id: scene.body.id,
            propertyID: PropertyID(rawValue: "corner.radius"),
            value: .length(0)
        )
        #expect(document.cadDocument.designGraph.nodes[scene.featureID]?.operation == hiddenOperation)
        #expect(document.cadDocument.designGraph.nodes[hiddenFeatureID] == nil)
        #expect(try faceCount(document) == 6)
    }

    /// Every bound the kernel's cylinder fillet enforces is checked before the mutation, so a
    /// refused edit leaves the document exactly as it was instead of committing one that stops
    /// evaluating.
    @Test(.timeLimit(.minutes(2)))
    func kernelBoundsAreEnforcedBeforeTheMutation() throws {
        var document = DesignDocument.empty()
        let scene = try cylinder(&document)

        // `radius - 2r > tolerance` fails: the corner would consume the whole cross-section.
        let beforeCorner = document
        #expect(throws: EditorError.self) {
            try document.setSceneNodeObjectProperty(
                id: scene.body.id,
                propertyID: PropertyID(rawValue: "corner.radius"),
                value: .length(0.05)
            )
        }
        #expect(try document.cadDocument.sourceFingerprint(tolerance: .standard)
            == beforeCorner.cadDocument.sourceFingerprint(tolerance: .standard))
        #expect(document.productMetadata == beforeCorner.productMetadata)

        // The rim rides a torus whose center circle `radius - r` must clear its tube `r`, so the
        // cross-section admits only half the cylinder's radius. A radius just inside that ceiling
        // is refused here rather than accepted and then failed by the evaluator.
        let tolerance = document.modelingSettings.tolerance.distance
        #expect(throws: EditorError.self) {
            try document.setSceneNodeObjectProperty(
                id: scene.body.id,
                propertyID: PropertyID(rawValue: "corner.radius"),
                value: .length(0.025 - 0.25 * tolerance)
            )
        }
        #expect(try document.cadDocument.sourceFingerprint(tolerance: .standard)
            == beforeCorner.cadDocument.sourceFingerprint(tolerance: .standard))
        #expect(document.productMetadata == beforeCorner.productMetadata)

        // The maximum Core publishes lies inside that ceiling, so the end of a control bound by it
        // is an edit that applies rather than one the evaluator refuses, even though it leaves the
        // torus only a few tolerances of clearance.
        let published = try document.maximumAllEdgeCornerRadius(featureID: scene.featureID)
        let maximum = try #require(published)
        #expect(maximum < 0.025 - tolerance)
        try document.setSceneNodeObjectProperty(
            id: scene.body.id,
            propertyID: PropertyID(rawValue: "corner.radius"),
            value: .length(maximum)
        )
        #expect(try faceCount(document) == 14)

        // `height - 2r > tolerance` fails on its own: a cylinder shorter than it is wide runs out
        // of height while its cross-section still has room.
        var short = DesignDocument.empty()
        let shortScene = try cylinder(&short, height: 0.04)
        let beforeShort = short
        #expect(throws: EditorError.self) {
            try short.setSceneNodeObjectProperty(
                id: shortScene.body.id,
                propertyID: PropertyID(rawValue: "corner.radius"),
                value: .length(0.021)
            )
        }
        #expect(short.productMetadata == beforeShort.productMetadata)

        try document.setSceneNodeObjectProperty(
            id: scene.body.id,
            propertyID: PropertyID(rawValue: "corner.radius"),
            value: .length(0.02)
        )
        let rounded = document

        // Shrinking the profile below the radius the wrapper carries is refused by the profile
        // mutator, which the Inspector reaches through the circle's own `radius`.
        #expect(throws: EditorError.self) {
            try document.setSceneNodeObjectProperty(
                id: scene.sketch.id,
                propertyID: PropertyID(rawValue: "radius"),
                value: .length(0.015)
            )
        }
        #expect(document.productMetadata == rounded.productMetadata)
        #expect(try faceCount(document) == 14)

        // The same bound holds when the body's own dimensions are the edit.
        #expect(throws: EditorError.self) {
            try document.setCylinderDimensions(
                featureID: scene.featureID,
                radius: .length(0.05, .meter),
                sizeY: .length(0.03, .meter)
            )
        }
        #expect(try document.boxCornerRadius(scene.featureID) == 0.02)
        #expect(try faceCount(document) == 14)

    }

    /// A circle profile nothing has extruded yet keeps its `bevel` as latent state, and the
    /// extrusion that creates its cylinder applies it, so the order the two were edited in does
    /// not matter.
    @Test(.timeLimit(.minutes(2)))
    func aLatentBevelIsAppliedByTheExtrusionThatCreatesTheCylinder() throws {
        var document = DesignDocument.empty()
        let sketchFeatureID = try document.createCircleSketch(
            name: "Profile",
            plane: .xy,
            center: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
            radius: .length(0.05, .meter)
        )
        let sketch = try #require(document.productMetadata.sceneNodes.values.first {
            $0.reference?.featureID == sketchFeatureID
        })

        // The profile's own extent is the only bound while no body exists, and it is half the
        // circle's radius rather than its diameter, so a bevel at the old, looser ceiling is
        // refused too.
        #expect(throws: EditorError.self) {
            try document.setSceneNodeObjectProperty(
                id: sketch.id,
                propertyID: PropertyID(rawValue: "bevel"),
                value: .length(0.05)
            )
        }
        let tolerance = document.modelingSettings.tolerance.distance
        #expect(throws: EditorError.self) {
            try document.setSceneNodeObjectProperty(
                id: sketch.id,
                propertyID: PropertyID(rawValue: "bevel"),
                value: .length(0.025 - 0.25 * tolerance)
            )
        }

        try document.setSceneNodeObjectProperty(
            id: sketch.id,
            propertyID: PropertyID(rawValue: "bevel"),
            value: .length(0.01)
        )
        #expect(storedLength(document, sketch.id, PropertyID(rawValue: "bevel")) == 0.01)

        try document.setSceneNodeObjectProperty(
            id: sketch.id,
            propertyID: PropertyID(rawValue: "extrusion"),
            value: .length(0.06)
        )
        let body = try #require(document.productMetadata.sceneNodes.values.first {
            $0.object?.category == .body
        })
        let bodyFeatureID = try #require(body.object?.sourceFeatureID ?? body.reference?.featureID)
        #expect(try document.boxCornerRadius(bodyFeatureID) == 0.01)
        #expect(try faceCount(document) == 14)
    }
}
