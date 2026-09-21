import Foundation
import SwiftCAD
import Testing
import RupaCoreTypes
@testable import RupaCore

@MainActor
@Suite("Sketch profile source properties")
struct SketchProfileSourcePropertyTests {

    // MARK: - Line

    @Test(.timeLimit(.minutes(1)))
    func lineLengthAndAngleReshapeTheProfile() throws {
        let store = CADDocumentStore()
        let featureID = try #require(
            try store.apply(.createLineSketch(
                name: "Line",
                plane: .xy,
                start: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
                end: SketchPoint(x: .length(0.1, .meter), y: .length(0.0, .meter))
            )).primaryFeatureID
        )
        let nodeID = try sketchNodeID(in: store, featureID: featureID)

        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "length"),
            value: .length(0.2)
        ))
        var end = try lineEnd(in: store, featureID: featureID)
        #expect(nearlyEqual(end.x, 0.2))
        #expect(nearlyEqual(end.y, 0.0))

        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "angle"),
            value: .angle(90.0)
        ))
        end = try lineEnd(in: store, featureID: featureID)
        #expect(nearlyEqual(end.x, 0.0))
        #expect(nearlyEqual(end.y, 0.2))

        // The edit reshapes the feature the document already owns rather than replacing it.
        #expect(store.document.cadDocument.designGraph.nodes[featureID] != nil)
        #expect(store.document.cadDocument.designGraph.nodes.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func lineLengthOfZeroIsRejectedWithoutTouchingTheDocument() throws {
        let store = CADDocumentStore()
        let featureID = try #require(
            try store.apply(.createLineSketch(
                name: "Line",
                plane: .xy,
                start: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
                end: SketchPoint(x: .length(0.1, .meter), y: .length(0.0, .meter))
            )).primaryFeatureID
        )
        let nodeID = try sketchNodeID(in: store, featureID: featureID)
        let graphBefore = store.document.cadDocument.designGraph
        let nodeBefore = store.document.productMetadata.sceneNodes[nodeID]

        #expect(throws: EditorError.self) {
            _ = try store.apply(.setSceneNodeObjectProperty(
                id: nodeID,
                propertyID: PropertyID(rawValue: "length"),
                value: .length(0.0)
            ))
        }
        #expect(store.document.cadDocument.designGraph == graphBefore)
        #expect(store.document.productMetadata.sceneNodes[nodeID] == nodeBefore)
    }

    // MARK: - Arc

    @Test(.timeLimit(.minutes(1)))
    func arcRadiusAndAnglesReshapeTheProfile() throws {
        let store = CADDocumentStore()
        let featureID = try #require(
            try store.apply(.createArcSketch(
                name: "Arc",
                plane: .xy,
                center: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
                radius: .length(0.1, .meter),
                startAngle: .angle(0.0, .degree),
                endAngle: .angle(90.0, .degree)
            )).primaryFeatureID
        )
        let nodeID = try sketchNodeID(in: store, featureID: featureID)

        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "radius"),
            value: .length(0.25)
        ))
        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "end.angle"),
            value: .angle(180.0)
        ))

        let arc = try #require(store.document.singleArcEntry(in: try sketch(in: store, featureID: featureID)))
        let radius = try store.document.resolvedLengthValue(arc.arc.radius, owner: "Arc radius")
        let startAngle = try store.document.resolvedAngleValue(arc.arc.startAngle, owner: "Arc start")
        let endAngle = try store.document.resolvedAngleValue(arc.arc.endAngle, owner: "Arc end")
        #expect(nearlyEqual(radius, 0.25))
        #expect(nearlyEqual(startAngle, 0.0))
        #expect(nearlyEqual(endAngle, Double.pi))

        // The stored end angle is rewritten from the resolved span so it agrees with the geometry.
        let stored = store.document.productMetadata.sceneNodes[nodeID]?
            .object?.properties[PropertyID(rawValue: "end.angle")]
        #expect(stored == .angle(180.0))
    }

    @Test(.timeLimit(.minutes(1)))
    func arcSpanningNothingIsRejectedWithoutTouchingTheDocument() throws {
        let store = CADDocumentStore()
        let featureID = try #require(
            try store.apply(.createArcSketch(
                name: "Arc",
                plane: .xy,
                center: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
                radius: .length(0.1, .meter),
                startAngle: .angle(0.0, .degree),
                endAngle: .angle(90.0, .degree)
            )).primaryFeatureID
        )
        let nodeID = try sketchNodeID(in: store, featureID: featureID)
        let graphBefore = store.document.cadDocument.designGraph
        let nodeBefore = store.document.productMetadata.sceneNodes[nodeID]

        #expect(throws: EditorError.self) {
            _ = try store.apply(.setSceneNodeObjectProperty(
                id: nodeID,
                propertyID: PropertyID(rawValue: "end.angle"),
                value: .angle(0.0)
            ))
        }
        #expect(store.document.cadDocument.designGraph == graphBefore)
        #expect(store.document.productMetadata.sceneNodes[nodeID] == nodeBefore)
    }

    // MARK: - Circle

    @Test(.timeLimit(.minutes(1)))
    func circleRadiusReshapesTheProfile() throws {
        let store = CADDocumentStore()
        let featureID = try #require(
            try store.apply(.createCircleSketch(
                name: "Circle",
                plane: .xy,
                center: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
                radius: .length(0.1, .meter)
            )).primaryFeatureID
        )
        let nodeID = try sketchNodeID(in: store, featureID: featureID)

        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "radius"),
            value: .length(0.3)
        ))

        let profile = try #require(
            try store.document.recognizedCylinderCircleProfile(
                in: try sketch(in: store, featureID: featureID)
            )
        )
        #expect(nearlyEqual(profile.outer.radius, 0.3))
        #expect(profile.inner == nil)
    }

    // MARK: - Rectangle

    @Test(.timeLimit(.minutes(1)))
    func rectangleSizeKeepsTheProfileCenterAndItsEntityIdentities() throws {
        let store = CADDocumentStore()
        let featureID = try #require(
            try store.apply(.createRectangleSketch(
                name: "Profile",
                plane: .xy,
                width: .length(0.2, .meter),
                height: .length(0.1, .meter)
            )).primaryFeatureID
        )
        let nodeID = try sketchNodeID(in: store, featureID: featureID)
        let idsBefore = Set(try sketch(in: store, featureID: featureID).entities.keys)
        let boundsBefore = try #require(
            try store.document.resolvedSketchBounds2D(try sketch(in: store, featureID: featureID))
        )

        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "size.x"),
            value: .length(0.5)
        ))

        let updated = try sketch(in: store, featureID: featureID)
        #expect(Set(updated.entities.keys) == idsBefore)
        let bounds = try #require(try store.document.resolvedSketchBounds2D(updated))
        #expect(nearlyEqual(bounds.maxX - bounds.minX, 0.5))
        #expect(nearlyEqual(bounds.maxY - bounds.minY, 0.1))
        #expect(nearlyEqual(
            (bounds.minX + bounds.maxX) / 2.0,
            (boundsBefore.minX + boundsBefore.maxX) / 2.0
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func rectangleSizeEditRebuildsTheProfileAndItsBodyAndReusesTheRest() throws {
        let store = CADDocumentStore()
        let featureID = try #require(
            try store.apply(.createRectangleSketch(
                name: "Profile",
                plane: .xy,
                width: .length(0.2, .meter),
                height: .length(0.1, .meter)
            )).primaryFeatureID
        )
        let nodeID = try sketchNodeID(in: store, featureID: featureID)
        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "extrusion"),
            value: .length(0.05)
        ))
        _ = try store.apply(.createCircleSketch(
            name: "Unrelated",
            plane: .xy,
            center: SketchPoint(x: .length(1.0, .meter), y: .length(1.0, .meter)),
            radius: .length(0.1, .meter)
        ))

        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "size.x"),
            value: .length(0.5)
        ))

        let metrics = try #require(store.currentModelingEvaluationMetrics)
        #expect(metrics.totalFeatureCount == 3)
        #expect(metrics.rebuiltFeatureCount == 2)
        #expect(metrics.reusedFeatureCount == 1)
        #expect(metrics.replayFallbackCount == 0)
    }

    // MARK: - Rectangle corners

    @Test(.timeLimit(.minutes(1)))
    func rectangleCornerRadiusRoundsTheProfileAndKeepsTheSideIdentities() throws {
        let store = CADDocumentStore()
        let featureID = try rectangleFeatureID(in: store, width: 0.2, height: 0.1)
        let nodeID = try sketchNodeID(in: store, featureID: featureID)
        let sideIDs = Set(try sketch(in: store, featureID: featureID).entities.keys)
        let boundsBefore = try #require(
            try store.document.resolvedSketchBounds2D(try sketch(in: store, featureID: featureID))
        )

        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "corner.radius"),
            value: .length(0.02)
        ))

        let rounded = try sketch(in: store, featureID: featureID)
        let entities = rectangleEntities(in: rounded)
        #expect(rounded.entities.count == 8)
        #expect(Set(entities.lines.keys) == sideIDs)
        #expect(entities.arcs.count == 4)
        for arc in entities.arcs.values {
            #expect(nearlyEqual(
                try store.document.resolvedLengthValue(arc.radius, owner: "Corner radius"),
                0.02
            ))
        }
        let bounds = try #require(try store.document.resolvedSketchBounds2D(rounded))
        #expect(nearlyEqual(bounds.minX, boundsBefore.minX))
        #expect(nearlyEqual(bounds.minY, boundsBefore.minY))
        #expect(nearlyEqual(bounds.maxX, boundsBefore.maxX))
        #expect(nearlyEqual(bounds.maxY, boundsBefore.maxY))
    }

    @Test(.timeLimit(.minutes(1)))
    func rectangleCornerRadiusChangeKeepsTheCornerIdentities() throws {
        let store = CADDocumentStore()
        let featureID = try rectangleFeatureID(in: store, width: 0.2, height: 0.1)
        let nodeID = try sketchNodeID(in: store, featureID: featureID)
        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "corner.radius"),
            value: .length(0.02)
        ))
        let idsBefore = Set(try sketch(in: store, featureID: featureID).entities.keys)

        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "corner.radius"),
            value: .length(0.03)
        ))

        let rounded = try sketch(in: store, featureID: featureID)
        #expect(Set(rounded.entities.keys) == idsBefore)
        for arc in rectangleEntities(in: rounded).arcs.values {
            #expect(nearlyEqual(
                try store.document.resolvedLengthValue(arc.radius, owner: "Corner radius"),
                0.03
            ))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rectangleCornerRadiusReturningToZeroRestoresTheSquareProfile() throws {
        let store = CADDocumentStore()
        let featureID = try rectangleFeatureID(in: store, width: 0.2, height: 0.1)
        let nodeID = try sketchNodeID(in: store, featureID: featureID)
        let sideIDs = Set(try sketch(in: store, featureID: featureID).entities.keys)
        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "corner.radius"),
            value: .length(0.02)
        ))

        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "corner.radius"),
            value: .length(0.0)
        ))

        let square = try sketch(in: store, featureID: featureID)
        #expect(Set(square.entities.keys) == sideIDs)
        #expect(store.document.isRectangleProfile(square))
        let bounds = try #require(try store.document.resolvedSketchBounds2D(square))
        #expect(nearlyEqual(bounds.maxX - bounds.minX, 0.2))
        #expect(nearlyEqual(bounds.maxY - bounds.minY, 0.1))
    }

    @Test(.timeLimit(.minutes(1)))
    func rectangleSizeKeepsTheCornerRadiusTheProfileCarries() throws {
        let store = CADDocumentStore()
        let featureID = try rectangleFeatureID(in: store, width: 0.2, height: 0.1)
        let nodeID = try sketchNodeID(in: store, featureID: featureID)
        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "corner.radius"),
            value: .length(0.02)
        ))
        let idsBefore = Set(try sketch(in: store, featureID: featureID).entities.keys)

        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "size.x"),
            value: .length(0.5)
        ))

        let resized = try sketch(in: store, featureID: featureID)
        #expect(Set(resized.entities.keys) == idsBefore)
        for arc in rectangleEntities(in: resized).arcs.values {
            #expect(nearlyEqual(
                try store.document.resolvedLengthValue(arc.radius, owner: "Corner radius"),
                0.02
            ))
        }
        let bounds = try #require(try store.document.resolvedSketchBounds2D(resized))
        #expect(nearlyEqual(bounds.maxX - bounds.minX, 0.5))
        #expect(nearlyEqual(bounds.maxY - bounds.minY, 0.1))
    }

    @Test(.timeLimit(.minutes(1)))
    func rectangleCornerRadiusEditRebuildsTheProfileAndItsBodyAndReusesTheRest() throws {
        let store = CADDocumentStore()
        let featureID = try rectangleFeatureID(in: store, width: 0.2, height: 0.1)
        let nodeID = try sketchNodeID(in: store, featureID: featureID)
        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "extrusion"),
            value: .length(0.05)
        ))
        _ = try store.apply(.createCircleSketch(
            name: "Unrelated",
            plane: .xy,
            center: SketchPoint(x: .length(1.0, .meter), y: .length(1.0, .meter)),
            radius: .length(0.1, .meter)
        ))

        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "corner.radius"),
            value: .length(0.02)
        ))

        let metrics = try #require(store.currentModelingEvaluationMetrics)
        #expect(metrics.totalFeatureCount == 3)
        #expect(metrics.rebuiltFeatureCount == 2)
        #expect(metrics.reusedFeatureCount == 1)
        #expect(metrics.replayFallbackCount == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func rectangleCornerRadiusAtHalfTheShorterSideIsRejectedWithoutTouchingTheDocument() throws {
        var document = DesignDocument.empty()
        let featureID = try document.createRectangleSketch(
            name: "Profile",
            plane: .xy,
            width: .length(0.2, .meter),
            height: .length(0.1, .meter)
        )
        let nodeID = try #require(document.productMetadata.sceneNodes.values.first {
            $0.reference?.featureID == featureID
        }).id
        let before = document.cadDocument.designGraph
        let propertiesBefore = try #require(
            document.productMetadata.sceneNodes[nodeID]?.object?.properties)

        do {
            try document.setSceneNodeObjectProperty(
                id: nodeID,
                propertyID: PropertyID(rawValue: "corner.radius"),
                value: .length(0.05)
            )
            Issue.record("A corner radius at half the shorter side must be refused.")
        } catch let error as EditorError {
            #expect(error.code == .commandInvalid)
        }
        #expect(document.cadDocument.designGraph == before)
        #expect(document.productMetadata.sceneNodes[nodeID]?.object?.properties == propertiesBefore)
    }

    @Test(.timeLimit(.minutes(1)))
    func negativeRectangleCornerRadiusIsRejectedWithoutTouchingTheDocument() throws {
        var document = DesignDocument.empty()
        let featureID = try document.createRectangleSketch(
            name: "Profile",
            plane: .xy,
            width: .length(0.2, .meter),
            height: .length(0.1, .meter)
        )
        let nodeID = try #require(document.productMetadata.sceneNodes.values.first {
            $0.reference?.featureID == featureID
        }).id
        let before = document.cadDocument.designGraph
        let propertiesBefore = try #require(
            document.productMetadata.sceneNodes[nodeID]?.object?.properties)

        #expect(throws: (any Error).self) {
            try document.setSceneNodeObjectProperty(
                id: nodeID,
                propertyID: PropertyID(rawValue: "corner.radius"),
                value: .length(-0.01)
            )
        }
        #expect(document.cadDocument.designGraph == before)
        #expect(document.productMetadata.sceneNodes[nodeID]?.object?.properties == propertiesBefore)
    }

    @Test(.timeLimit(.minutes(1)))
    func cubeSizeKeepsTheRoundedProfileNestedUnderneathIt() throws {
        var document = DesignDocument.empty()
        let bodyFeatureID = try document.createExtrudedRectangle(
            name: "Cube",
            plane: .xy,
            width: .length(0.2, .meter),
            height: .length(0.1, .meter),
            depth: .length(0.05, .meter),
            direction: .normal
        )
        let profileFeatureID = try roundedCubeProfile(in: &document, bodyFeatureID: bodyFeatureID)

        try document.setCubeDimensions(
            featureID: bodyFeatureID,
            sizeX: .length(0.3, .meter),
            sizeY: .length(0.05, .meter),
            sizeZ: .length(0.2, .meter)
        )

        let profile = try designSketch(in: document, featureID: profileFeatureID)
        #expect(profile.entities.count == 8)
        for arc in rectangleEntities(in: profile).arcs.values {
            #expect(nearlyEqual(
                try document.resolvedLengthValue(arc.radius, owner: "Corner radius"),
                0.04
            ))
        }
        let bounds = try #require(try document.resolvedSketchBounds2D(profile))
        #expect(nearlyEqual(bounds.maxX - bounds.minX, 0.3))
        #expect(nearlyEqual(bounds.maxY - bounds.minY, 0.2))
    }

    @Test(.timeLimit(.minutes(1)))
    func cubeSizeBelowTheProfileCornerDiameterIsRejectedWithoutTouchingTheDocument() throws {
        var document = DesignDocument.empty()
        let bodyFeatureID = try document.createExtrudedRectangle(
            name: "Cube",
            plane: .xy,
            width: .length(0.2, .meter),
            height: .length(0.1, .meter),
            depth: .length(0.05, .meter),
            direction: .normal
        )
        _ = try roundedCubeProfile(in: &document, bodyFeatureID: bodyFeatureID)
        let before = document.cadDocument.designGraph

        do {
            try document.setCubeDimensions(
                featureID: bodyFeatureID,
                sizeX: .length(0.3, .meter),
                sizeY: .length(0.05, .meter),
                sizeZ: .length(0.07, .meter)
            )
            Issue.record("A cube must not be shrunk below the corner diameter its profile carries.")
        } catch let error as EditorError {
            #expect(error.code == .commandInvalid)
        }
        #expect(document.cadDocument.designGraph == before)
    }

    // MARK: - Polygon

    @Test(.timeLimit(.minutes(1)))
    func polygonRadiusAndRotationKeepTheSideIdentities() throws {
        let store = CADDocumentStore()
        let featureID = try polygonFeatureID(in: store, sides: 6, radius: 0.1)
        let nodeID = try sketchNodeID(in: store, featureID: featureID)
        let idsBefore = Set(try sketch(in: store, featureID: featureID).entities.keys)

        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "sizing.radius"),
            value: .length(0.25)
        ))
        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "angle"),
            value: .angle(30.0)
        ))

        let updated = try sketch(in: store, featureID: featureID)
        #expect(Set(updated.entities.keys) == idsBefore)
        let vertices = try polygonVertices(in: store, sketch: updated)
        #expect(vertices.count == 6)
        for vertex in vertices {
            #expect(nearlyEqual(hypot(vertex.x, vertex.y), 0.25, tolerance: 1.0e-7))
        }
        // The rotation the schema stores is the absolute angle of the first vertex.
        #expect(vertices.contains { nearlyEqual(atan2($0.y, $0.x), 30.0 * Double.pi / 180.0, tolerance: 1.0e-7) })

        let properties = try #require(store.document.productMetadata.sceneNodes[nodeID]?.object?.properties)
        #expect(properties[PropertyID(rawValue: "radius")] == .length(0.25))
    }

    @Test(.timeLimit(.minutes(1)))
    func polygonInradiusModeRecomputesTheDerivedCircumradius() throws {
        let store = CADDocumentStore()
        let featureID = try polygonFeatureID(in: store, sides: 6, radius: 0.1)
        let nodeID = try sketchNodeID(in: store, featureID: featureID)

        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "radius.is.inradius"),
            value: .boolean(true)
        ))

        let expected = PolygonSizingMode.inradius.circumradius(from: 0.1, sides: 6)
        let vertices = try polygonVertices(in: store, sketch: try sketch(in: store, featureID: featureID))
        for vertex in vertices {
            #expect(nearlyEqual(hypot(vertex.x, vertex.y), expected, tolerance: 1.0e-7))
        }
        let properties = try #require(store.document.productMetadata.sceneNodes[nodeID]?.object?.properties)
        guard case let .length(storedRadius)? = properties[PropertyID(rawValue: "radius")] else {
            Issue.record("Polygon must keep a derived circumradius.")
            return
        }
        #expect(nearlyEqual(storedRadius, expected))
        guard case let .length(storedSide)? = properties[PropertyID(rawValue: "side.length")] else {
            Issue.record("Polygon must keep a derived side length.")
            return
        }
        #expect(nearlyEqual(storedSide, PolygonSizingMode.inradius.sideLength(from: 0.1, sides: 6)))
    }

    @Test(.timeLimit(.minutes(1)))
    func polygonSideCountChangeReusesTheSidesItKeeps() throws {
        let store = CADDocumentStore()
        let featureID = try polygonFeatureID(in: store, sides: 5, radius: 0.1)
        let nodeID = try sketchNodeID(in: store, featureID: featureID)
        let idsBefore = Set(try sketch(in: store, featureID: featureID).entities.keys)

        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "sides.x"),
            value: .integer(8)
        ))
        let grown = try sketch(in: store, featureID: featureID)
        #expect(grown.entities.count == 8)
        #expect(idsBefore.isSubset(of: Set(grown.entities.keys)))

        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "sides.x"),
            value: .integer(3)
        ))
        let shrunk = try sketch(in: store, featureID: featureID)
        #expect(shrunk.entities.count == 3)
        #expect(Set(shrunk.entities.keys).isSubset(of: Set(grown.entities.keys)))
        #expect(try polygonVertices(in: store, sketch: shrunk).count == 3)
    }

    @Test(.timeLimit(.minutes(1)))
    func polygonRadiusEditRebuildsTheProfileAndItsBodyAndReusesTheRest() throws {
        let store = CADDocumentStore()
        let featureID = try polygonFeatureID(in: store, sides: 6, radius: 0.1)
        let nodeID = try sketchNodeID(in: store, featureID: featureID)
        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "extrusion"),
            value: .length(0.05)
        ))
        _ = try store.apply(.createCircleSketch(
            name: "Unrelated",
            plane: .xy,
            center: SketchPoint(x: .length(1.0, .meter), y: .length(1.0, .meter)),
            radius: .length(0.1, .meter)
        ))

        _ = try store.apply(.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "sizing.radius"),
            value: .length(0.25)
        ))

        // The polygon mutator rebuilds every side entity, so reuse depends on it keeping the
        // entity identities the extrusion refers to.
        let metrics = try #require(store.currentModelingEvaluationMetrics)
        #expect(metrics.totalFeatureCount == 3)
        #expect(metrics.rebuiltFeatureCount == 2)
        #expect(metrics.reusedFeatureCount == 1)
        #expect(metrics.replayFallbackCount == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func polygonWithFewerThanThreeSidesIsRejectedWithoutTouchingTheDocument() throws {
        let store = CADDocumentStore()
        let featureID = try polygonFeatureID(in: store, sides: 6, radius: 0.1)
        let nodeID = try sketchNodeID(in: store, featureID: featureID)
        let graphBefore = store.document.cadDocument.designGraph
        let nodeBefore = store.document.productMetadata.sceneNodes[nodeID]

        #expect(throws: EditorError.self) {
            _ = try store.apply(.setSceneNodeObjectProperty(
                id: nodeID,
                propertyID: PropertyID(rawValue: "sides.x"),
                value: .integer(2)
            ))
        }
        #expect(store.document.cadDocument.designGraph == graphBefore)
        #expect(store.document.productMetadata.sceneNodes[nodeID] == nodeBefore)
    }

    // MARK: - Helpers

    private func polygonFeatureID(
        in store: CADDocumentStore,
        sides: Int,
        radius: Double
    ) throws -> FeatureID {
        try #require(
            try store.apply(.createPolygonSketch(
                name: "Polygon",
                plane: .xy,
                center: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
                radius: .length(radius, .meter),
                sides: sides,
                sizingMode: .circumradius,
                inclinationMode: .vertical,
                rotationAngle: .angle(0.0, .radian)
            )).primaryFeatureID
        )
    }

    private func rectangleFeatureID(
        in store: CADDocumentStore,
        width: Double,
        height: Double
    ) throws -> FeatureID {
        try #require(
            try store.apply(.createRectangleSketch(
                name: "Profile",
                plane: .xy,
                width: .length(width, .meter),
                height: .length(height, .meter)
            )).primaryFeatureID
        )
    }

    /// Rounds the rectangle profile a cube nests, and names the profile feature it rounded.
    private func roundedCubeProfile(
        in document: inout DesignDocument,
        bodyFeatureID: FeatureID
    ) throws -> FeatureID {
        let extrusionFeatureID = document.boxExtrusionFeatureID(bodyFeatureID)
        let feature = try #require(document.cadDocument.designGraph.nodes[extrusionFeatureID])
        guard case let .extrude(extrude) = feature.operation else {
            Issue.record("A cube nests its rectangle profile under an extrude feature.")
            throw EditorError(code: .referenceUnresolved, message: "Not an extrude.")
        }
        let profileFeatureID = extrude.profile.featureID
        let nodeID = try #require(document.productMetadata.sceneNodes.values.first {
            $0.reference?.featureID == profileFeatureID
        }).id
        try document.setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID(rawValue: "corner.radius"),
            value: .length(0.04)
        )
        return profileFeatureID
    }

    private func rectangleEntities(
        in sketch: Sketch
    ) -> (lines: [SketchEntityID: SketchLine], arcs: [SketchEntityID: SketchArc]) {
        var lines: [SketchEntityID: SketchLine] = [:]
        var arcs: [SketchEntityID: SketchArc] = [:]
        for (id, entity) in sketch.entities {
            switch entity {
            case .line(let line):
                lines[id] = line
            case .arc(let arc):
                arcs[id] = arc
            default:
                continue
            }
        }
        return (lines, arcs)
    }

    private func designSketch(in document: DesignDocument, featureID: FeatureID) throws -> Sketch {
        let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
        guard case let .sketch(sketch) = feature.operation else {
            Issue.record("Feature \(featureID) is not a sketch.")
            throw EditorError(code: .referenceUnresolved, message: "Not a sketch.")
        }
        return sketch
    }

    private func sketchNodeID(
        in store: CADDocumentStore,
        featureID: FeatureID
    ) throws -> SceneNodeID {
        try #require(store.document.productMetadata.sceneNodes.values.first {
            $0.reference?.featureID == featureID
        }).id
    }

    private func sketch(in store: CADDocumentStore, featureID: FeatureID) throws -> Sketch {
        let feature = try #require(store.document.cadDocument.designGraph.nodes[featureID])
        guard case let .sketch(sketch) = feature.operation else {
            Issue.record("Feature \(featureID) is not a sketch.")
            throw EditorError(code: .referenceUnresolved, message: "Not a sketch.")
        }
        return sketch
    }

    private func lineEnd(
        in store: CADDocumentStore,
        featureID: FeatureID
    ) throws -> (x: Double, y: Double) {
        let entry = try #require(store.document.singleLineEntry(in: try sketch(in: store, featureID: featureID)))
        return (
            x: try store.document.resolvedLengthValue(entry.line.end.x, owner: "Line end x"),
            y: try store.document.resolvedLengthValue(entry.line.end.y, owner: "Line end y")
        )
    }

    private func polygonVertices(
        in store: CADDocumentStore,
        sketch: Sketch
    ) throws -> [(x: Double, y: Double)] {
        var vertices: [(x: Double, y: Double)] = []
        for entity in sketch.entities.values {
            guard case let .line(line) = entity else {
                Issue.record("A polygon profile must be made of lines.")
                continue
            }
            vertices.append((
                x: try store.document.resolvedLengthValue(line.start.x, owner: "Polygon vertex x"),
                y: try store.document.resolvedLengthValue(line.start.y, owner: "Polygon vertex y")
            ))
        }
        return vertices
    }

    private func nearlyEqual(_ lhs: Double, _ rhs: Double, tolerance: Double = 1.0e-9) -> Bool {
        abs(lhs - rhs) <= tolerance
    }
}
