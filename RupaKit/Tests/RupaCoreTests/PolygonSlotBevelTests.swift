import Foundation
import SwiftCAD
import Testing
import RupaCoreTypes
@testable import RupaCore

/// The bevel a polygon or slot profile carries is the all-edge fillet on the prism it extrudes.
///
/// Neither body is a typed object, so `corner.radius` is not reachable on it and the profile's own
/// `bevel` is the whole Inspector surface for this fillet. Every case here drives that property.
@Suite("Polygon and slot bevel source")
struct PolygonSlotBevelTests {

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

    private func bodyFeatureID(_ document: DesignDocument) throws -> FeatureID {
        let body = try #require(document.productMetadata.sceneNodes.values.first {
            $0.reference?.kind == .body
        })
        return try #require(body.reference?.featureID)
    }

    /// A regular polygon prism, by default a hexagon of circumradius 0.05 m and so of side 0.05 m,
    /// tall enough that the cross-section rather than the depth is the tighter of its two bounds.
    private func polygonPrism(
        _ document: inout DesignDocument,
        sides: Int = 6,
        circumradius: Double = 0.05,
        height: Double = 0.12
    ) throws -> (sketch: SceneNode, bodyFeatureID: FeatureID) {
        let sketchFeatureID = try document.createPolygonSketch(
            name: "Profile",
            plane: .xy,
            center: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
            radius: .length(circumradius, .meter),
            sides: sides
        )
        let sketch = try #require(document.productMetadata.sceneNodes.values.first {
            $0.reference?.featureID == sketchFeatureID
        })
        try document.setSceneNodeObjectProperty(
            id: sketch.id,
            propertyID: PropertyID(rawValue: "extrusion"),
            value: .length(height)
        )
        return (sketch, try bodyFeatureID(document))
    }

    /// A slot along one straight segment, whose profile is a stadium of cap radius half its width.
    private func slotProfile(
        _ document: inout DesignDocument,
        width: Double = 0.03
    ) throws -> SceneNode {
        let pathFeatureID = try document.createLineSketch(
            name: "Path",
            plane: .xy,
            start: SketchPoint(x: .length(-0.02, .meter), y: .length(0.0, .meter)),
            end: SketchPoint(x: .length(0.02, .meter), y: .length(0.0, .meter))
        )
        let snapshot = try SketchEntitySnapshotService().snapshot(document: document)
        let path = try #require(snapshot.entries.first {
            $0.sourceFeatureID == pathFeatureID.description && $0.entityKind == "line"
        })
        let slotFeatureID = try document.createSlotSketch(
            target: try #require(path.selectionTarget()),
            width: .length(width, .meter)
        )
        return try #require(document.productMetadata.sceneNodes.values.first {
            $0.reference?.featureID == slotFeatureID
        })
    }

    private func slotPrism(
        _ document: inout DesignDocument,
        width: Double = 0.03,
        height: Double = 0.06
    ) throws -> (sketch: SceneNode, bodyFeatureID: FeatureID) {
        let sketch = try slotProfile(&document, width: width)
        try document.setSceneNodeObjectProperty(
            id: sketch.id,
            propertyID: PropertyID(rawValue: "extrusion"),
            value: .length(height)
        )
        return (sketch, try bodyFeatureID(document))
    }

    /// A hexagonal prism's `bevel` reaches the kernel's prism fillet and rounds every edge of it.
    ///
    /// The unrounded prism carries its two caps and one face per side; rounding replaces each of
    /// those six corners with a vertical cylinder and each of the twelve cap edges and six corner
    /// junctions with its own face, which is the `6N + 2` the kernel's prism builder produces.
    @Test(.timeLimit(.minutes(2)))
    func aHexagonalPrismIsRoundedByTheProfileBevel() throws {
        var document = DesignDocument.empty()
        let scene = try polygonPrism(&document)
        #expect(try faceCount(document) == 8)

        try document.setSceneNodeObjectProperty(
            id: scene.sketch.id,
            propertyID: PropertyID(rawValue: "bevel"),
            value: .length(0.01)
        )
        #expect(try document.boxCornerRadius(scene.bodyFeatureID) == 0.01)
        #expect(try faceCount(document) == 38)
        #expect(storedLength(document, scene.sketch.id, PropertyID(rawValue: "bevel")) == 0.01)

        try document.setSceneNodeObjectProperty(
            id: scene.sketch.id,
            propertyID: PropertyID(rawValue: "bevel"),
            value: .length(0)
        )
        #expect(try document.boxCornerRadius(scene.bodyFeatureID) == 0)
        #expect(try faceCount(document) == 8)
    }

    /// A four-sided polygon rounds even though no rectangle recognizer claims it.
    ///
    /// Its vertices sit on the axes at rotation zero, so the square is a diamond the rectangle
    /// family refuses and the polygon family carries, and the bound the polygon target computes
    /// reduces at four sides to the one a box of the same side would be given.
    @Test(.timeLimit(.minutes(2)))
    func aSquarePolygonRoundsThroughThePolygonFamily() throws {
        var document = DesignDocument.empty()
        let scene = try polygonPrism(&document, sides: 4)
        #expect(try faceCount(document) == 6)

        try document.setSceneNodeObjectProperty(
            id: scene.sketch.id,
            propertyID: PropertyID(rawValue: "bevel"),
            value: .length(0.01)
        )
        // Six planar faces, twelve edge cylinders and eight corner octants.
        #expect(try faceCount(document) == 26)
        #expect(try document.boxCornerRadius(scene.bodyFeatureID) == 0.01)
    }

    /// A slot's `bevel` rounds the stadium prism it extrudes.
    ///
    /// The straight sides meet the caps tangentially, so the unrounded prism has its two caps and
    /// six lateral faces, and rounding adds one face per lateral edge pair and per cap edge.
    @Test(.timeLimit(.minutes(2)))
    func aSlotPrismIsRoundedByTheProfileBevel() throws {
        var document = DesignDocument.empty()
        let scene = try slotPrism(&document)
        #expect(try faceCount(document) == 8)

        try document.setSceneNodeObjectProperty(
            id: scene.sketch.id,
            propertyID: PropertyID(rawValue: "bevel"),
            value: .length(0.005)
        )
        #expect(try document.boxCornerRadius(scene.bodyFeatureID) == 0.005)
        #expect(try faceCount(document) == 20)
        #expect(storedLength(document, scene.sketch.id, PropertyID(rawValue: "bevel")) == 0.005)

        try document.setSceneNodeObjectProperty(
            id: scene.sketch.id,
            propertyID: PropertyID(rawValue: "bevel"),
            value: .length(0)
        )
        #expect(try faceCount(document) == 8)
    }

    /// The maximum Core publishes for each family applies, and one tolerance past it is refused
    /// before the mutation rather than committed and then failed by the evaluator.
    @Test(.timeLimit(.minutes(2)))
    func eachFamilyPublishesABoundItsOwnKernelBuilderAccepts() throws {
        typealias Prism = (inout DesignDocument) throws -> (sketch: SceneNode, bodyFeatureID: FeatureID)
        let families: [Prism] = [
            { try self.polygonPrism(&$0) },
            { try self.polygonPrism(&$0, sides: 4) },
            { try self.slotPrism(&$0) },
        ]
        for makePrism in families {
            var document = DesignDocument.empty()
            let scene = try makePrism(&document)
            let tolerance = document.modelingSettings.tolerance.distance
            let maximum = try #require(
                try document.maximumAllEdgeCornerRadius(featureID: scene.bodyFeatureID)
            )

            // One tolerance past the bound itself, so the refusal is the rule rather than the
            // last bit of the round trip through `radiusBound`.
            let before = document
            #expect(throws: EditorError.self) {
                try document.setSceneNodeObjectProperty(
                    id: scene.sketch.id,
                    propertyID: PropertyID(rawValue: "bevel"),
                    value: .length(maximum + 2.0 * tolerance)
                )
            }
            #expect(try document.cadDocument.sourceFingerprint(tolerance: .standard)
                == before.cadDocument.sourceFingerprint(tolerance: .standard))
            #expect(document.productMetadata == before.productMetadata)

            // The published maximum is inside the kernel's own ceiling, so the end of a control
            // bound by it is an edit that applies and leaves a document that still evaluates.
            try document.setSceneNodeObjectProperty(
                id: scene.sketch.id,
                propertyID: PropertyID(rawValue: "bevel"),
                value: .length(maximum)
            )
            #expect(try document.boxCornerRadius(scene.bodyFeatureID) == maximum)
            #expect(try faceCount(document) > 0)
        }
    }

    /// A prism shorter than its cross-section is bounded by its depth rather than by its section,
    /// and the depth is checked before the mutation like every other bound.
    @Test(.timeLimit(.minutes(2)))
    func aShallowPrismIsBoundedByItsDepth() throws {
        var document = DesignDocument.empty()
        let scene = try polygonPrism(&document, height: 0.04)
        let tolerance = document.modelingSettings.tolerance.distance
        let maximum = try #require(
            try document.maximumAllEdgeCornerRadius(featureID: scene.bodyFeatureID)
        )
        // Half the depth, not the 0.0433 m the 0.05 m sides would otherwise allow.
        #expect(abs(maximum - (0.02 - 1.5 * tolerance)) < 1e-12)

        let before = document
        #expect(throws: EditorError.self) {
            try document.setSceneNodeObjectProperty(
                id: scene.sketch.id,
                propertyID: PropertyID(rawValue: "bevel"),
                value: .length(0.021)
            )
        }
        #expect(document.productMetadata == before.productMetadata)
    }

    /// Reshaping a polygon under a bevel is refused when the new cross-section no longer leaves
    /// the fillet room, so the document the mutator commits is always one that still evaluates.
    @Test(.timeLimit(.minutes(2)))
    func aPolygonReshapeUnderABevelIsRefusedBeforeTheRebuild() throws {
        var document = DesignDocument.empty()
        let scene = try polygonPrism(&document)
        try document.setSceneNodeObjectProperty(
            id: scene.sketch.id,
            propertyID: PropertyID(rawValue: "bevel"),
            value: .length(0.01)
        )
        let rounded = document

        // Sides of 0.01 m cannot carry the 0.01155 m two 0.01 m corners charge them.
        #expect(throws: EditorError.self) {
            try document.setSceneNodeObjectProperty(
                id: scene.sketch.id,
                propertyID: PropertyID(rawValue: "sizing.radius"),
                value: .length(0.01)
            )
        }
        #expect(try document.cadDocument.sourceFingerprint(tolerance: .standard)
            == rounded.cadDocument.sourceFingerprint(tolerance: .standard))
        #expect(document.productMetadata == rounded.productMetadata)
        #expect(try faceCount(document) == 38)

        // A radius the corners still fit inside rebuilds the profile and keeps the fillet.
        try document.setSceneNodeObjectProperty(
            id: scene.sketch.id,
            propertyID: PropertyID(rawValue: "sizing.radius"),
            value: .length(0.04)
        )
        #expect(try document.boxCornerRadius(scene.bodyFeatureID) == 0.01)
        #expect(try faceCount(document) == 38)
    }

    /// A slot profile nothing has extruded yet keeps its `bevel` as latent state, and the
    /// extrusion that creates its prism applies it.
    @Test(.timeLimit(.minutes(2)))
    func aLatentSlotBevelIsAppliedByTheExtrusionThatCreatesThePrism() throws {
        var document = DesignDocument.empty()
        let sketch = try slotProfile(&document)

        // The cap arcs are the whole bound while nothing has extruded the profile, and they admit
        // only half the cap radius rather than the whole of it.
        #expect(throws: EditorError.self) {
            try document.setSceneNodeObjectProperty(
                id: sketch.id,
                propertyID: PropertyID(rawValue: "bevel"),
                value: .length(0.015)
            )
        }
        let tolerance = document.modelingSettings.tolerance.distance
        #expect(throws: EditorError.self) {
            try document.setSceneNodeObjectProperty(
                id: sketch.id,
                propertyID: PropertyID(rawValue: "bevel"),
                value: .length(0.0075 - 0.25 * tolerance)
            )
        }

        try document.setSceneNodeObjectProperty(
            id: sketch.id,
            propertyID: PropertyID(rawValue: "bevel"),
            value: .length(0.005)
        )
        #expect(storedLength(document, sketch.id, PropertyID(rawValue: "bevel")) == 0.005)

        try document.setSceneNodeObjectProperty(
            id: sketch.id,
            propertyID: PropertyID(rawValue: "extrusion"),
            value: .length(0.06)
        )
        #expect(try document.boxCornerRadius(try bodyFeatureID(document)) == 0.005)
        #expect(try faceCount(document) == 20)
    }

    /// A slot whose path curves is outside every family the kernel rounds, so a positive bevel is
    /// refused on it while clearing one is still accepted.
    @Test(.timeLimit(.minutes(2)))
    func aCurvedSlotRefusesAPositiveBevelAndAcceptsZero() throws {
        var document = DesignDocument.empty()
        let pathFeatureID = try document.createArcSketch(
            name: "Path",
            plane: .xy,
            center: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
            radius: .length(0.05, .meter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(90.0, .degree)
        )
        let snapshot = try SketchEntitySnapshotService().snapshot(document: document)
        let path = try #require(snapshot.entries.first {
            $0.sourceFeatureID == pathFeatureID.description && $0.entityKind == "arc"
        })
        let slotFeatureID = try document.createSlotSketch(
            target: try #require(path.selectionTarget()),
            width: .length(0.02, .meter)
        )
        let sketch = try #require(document.productMetadata.sceneNodes.values.first {
            $0.reference?.featureID == slotFeatureID
        })

        let before = document
        #expect(throws: EditorError.self) {
            try document.setSceneNodeObjectProperty(
                id: sketch.id,
                propertyID: PropertyID(rawValue: "bevel"),
                value: .length(0.002)
            )
        }
        #expect(document.productMetadata == before.productMetadata)

        // Clearing is how a profile edited out of every family is repaired, so it is accepted
        // before the family is resolved rather than after.
        try document.setSceneNodeObjectProperty(
            id: sketch.id,
            propertyID: PropertyID(rawValue: "bevel"),
            value: .length(0)
        )
        #expect(storedLength(document, sketch.id, PropertyID(rawValue: "bevel")) == 0)

        try document.setSceneNodeObjectProperty(
            id: sketch.id,
            propertyID: PropertyID(rawValue: "extrusion"),
            value: .length(0.06)
        )
        let extruded = document
        #expect(throws: EditorError.self) {
            try document.setSceneNodeObjectProperty(
                id: sketch.id,
                propertyID: PropertyID(rawValue: "bevel"),
                value: .length(0.002)
            )
        }
        #expect(document.productMetadata == extruded.productMetadata)
    }
}
