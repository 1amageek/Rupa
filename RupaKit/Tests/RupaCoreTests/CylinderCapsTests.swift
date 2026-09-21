import Foundation
import SwiftCAD
import Testing
import RupaCoreTypes
@testable import RupaCore

@Suite("Cylinder caps source")
struct CylinderCapsTests {

    private let capsID = PropertyID(rawValue: "caps")
    private let angleID = PropertyID(rawValue: "angle")
    private let hollowID = PropertyID(rawValue: "hollow")
    private let cornerID = PropertyID(rawValue: "corner.radius")
    private let sizeYID = PropertyID(rawValue: "size.y")

    private func evaluatedBRep(_ document: DesignDocument) throws -> BRepModel {
        try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
            .evaluate(document.cadDocument)
            .brep
    }

    private func faceCount(_ document: DesignDocument) throws -> Int {
        try evaluatedBRep(document).faces.count
    }

    /// What the kernel actually built, asserted against exact validation rather than against the
    /// face count alone, which is how an uncapped cylinder is shown to be a sheet the kernel
    /// accepts instead of a solid missing two faces.
    private func expectUncappedSheet(
        _ document: DesignDocument,
        faces: Int,
        shells: Int
    ) throws {
        let brep = try evaluatedBRep(document)
        #expect(brep.bodies.count == 1)
        #expect(brep.bodies.values.first?.kind == .sheet)
        #expect(brep.faces.count == faces)
        #expect(brep.shells.count == shells)
        try brep.validate(level: .exact, tolerance: .standard)
    }

    private func sketch(_ document: DesignDocument, _ sketchNode: SceneNode) throws -> Sketch {
        guard let featureID = sketchNode.reference?.featureID,
              let feature = document.cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation else {
            throw EditorError(code: .referenceUnresolved, message: "The profile is unavailable.")
        }
        return sketch
    }

    /// The entity kinds the profile holds, which is how the profile is observed to be untouched
    /// by an edit that only opens or closes the two ends of the extrusion.
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

    /// A cylinder of radius 0.05 m and 0.06 m tall, the same body the angle and hollow suites edit.
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

    /// The three values that have to agree about what a cylinder is: the result kind its own
    /// extrusion declares, the single output role the feature node publishes, and the geometry
    /// role the object carries.
    private func bodyKinds(
        _ document: DesignDocument,
        _ bodyID: SceneNodeID,
        _ featureID: FeatureID
    ) throws -> (caps: Bool?, outputs: [FeatureOutput], role: ObjectDescriptor.GeometryRole?) {
        let node = document.cadDocument.designGraph.nodes[featureID]
        return (
            try document.cylinderCaps(featureID: featureID),
            node?.outputs ?? [],
            document.productMetadata.sceneNodes[bodyID]?.object?.geometryRole
        )
    }

    /// Caps belong to the extrusion, not to the profile: clearing them drops the two end faces and
    /// turns the body into a sheet, restoring them sews the same two back on, and the circle the
    /// wall sweeps is the same entity throughout.
    @Test(.timeLimit(.minutes(2)))
    func capsOpenAndCloseTheEndsOverTheSameProfile() throws {
        var document = DesignDocument.empty()
        let scene = try cylinder(&document)
        #expect(try faceCount(document) == 6)
        var kinds = try bodyKinds(document, scene.body.id, scene.featureID)
        #expect(kinds.caps == true)
        #expect(kinds.outputs == [FeatureOutput(role: .body)])
        #expect(kinds.role == .solid)

        try document.setSceneNodeObjectProperty(
            id: scene.body.id, propertyID: capsID, value: .boolean(false)
        )

        // The wall alone: the same four quadrant faces, without the two caps.
        try expectUncappedSheet(document, faces: 4, shells: 1)
        kinds = try bodyKinds(document, scene.body.id, scene.featureID)
        #expect(kinds.caps == false)
        #expect(kinds.outputs == [FeatureOutput(role: .sheet)])
        #expect(kinds.role == .surface)
        #expect(document.productMetadata.sceneNodes[scene.body.id]?.object?.properties[capsID] == .boolean(false))
        // The profile is the circle it always was.
        #expect(try entityCounts(document, scene.sketch) == (circles: 1, arcs: 0, lines: 0))
        try document.validate()

        try document.setSceneNodeObjectProperty(
            id: scene.body.id, propertyID: capsID, value: .boolean(true)
        )

        #expect(try faceCount(document) == 6)
        kinds = try bodyKinds(document, scene.body.id, scene.featureID)
        #expect(kinds.caps == true)
        #expect(kinds.outputs == [FeatureOutput(role: .body)])
        #expect(kinds.role == .solid)
        #expect(document.productMetadata.sceneNodes[scene.body.id]?.object?.properties[capsID] == .boolean(true))
        try document.validate()
    }

    /// Nothing silently puts the caps back: the mutators that change a cylinder's size bind the
    /// extrusion the document already holds, so an uncapped cylinder stays a sheet across them.
    @Test(.timeLimit(.minutes(2)))
    func sizeEditsCarryTheClearedCapsForward() throws {
        var document = DesignDocument.empty()
        let scene = try cylinder(&document)
        try document.setSceneNodeObjectProperty(
            id: scene.body.id, propertyID: capsID, value: .boolean(false)
        )

        try document.setSceneNodeObjectProperty(
            id: scene.body.id, propertyID: sizeYID, value: .length(0.09)
        )
        var kinds = try bodyKinds(document, scene.body.id, scene.featureID)
        #expect(kinds.caps == false)
        #expect(kinds.outputs == [FeatureOutput(role: .sheet)])
        #expect(kinds.role == .surface)
        #expect(try faceCount(document) == 4)

        try document.setCylinderDimensions(
            featureID: scene.featureID,
            radius: .length(0.08, .meter),
            sizeY: .length(0.09, .meter)
        )
        kinds = try bodyKinds(document, scene.body.id, scene.featureID)
        #expect(kinds.caps == false)
        #expect(kinds.outputs == [FeatureOutput(role: .sheet)])
        #expect(kinds.role == .surface)
        #expect(try faceCount(document) == 4)
        try document.validate()
    }

    /// An all-edge fillet rounds a solid, so the two edits refuse each other in both orders, each
    /// refusal leaves the body as it was, and the bound the Inspector reads collapses on a sheet
    /// rather than offering a drag every step of which is refused.
    @Test(.timeLimit(.minutes(2)))
    func capsAndCornerRefuseEachOther() throws {
        var document = DesignDocument.empty()
        let scene = try cylinder(&document)
        try document.setSceneNodeObjectProperty(
            id: scene.body.id, propertyID: capsID, value: .boolean(false)
        )

        #expect(try document.maximumAllEdgeCornerRadius(featureID: scene.featureID) == 0)
        let cornerOnSheet = editorErrorCode {
            try document.setSceneNodeObjectProperty(
                id: scene.body.id, propertyID: cornerID, value: .length(0.005)
            )
        }
        #expect(cornerOnSheet == .commandInvalid)
        #expect(try faceCount(document) == 4)
        #expect(try document.cylinderCaps(featureID: scene.featureID) == false)
        #expect(try document.boxCornerRadius(scene.featureID) == 0)

        var rounded = DesignDocument.empty()
        let roundedScene = try cylinder(&rounded)
        try rounded.setSceneNodeObjectProperty(
            id: roundedScene.body.id, propertyID: cornerID, value: .length(0.01)
        )
        let capsOnFillet = editorErrorCode {
            try rounded.setSceneNodeObjectProperty(
                id: roundedScene.body.id, propertyID: capsID, value: .boolean(false)
            )
        }
        #expect(capsOnFillet == .commandInvalid)
        #expect(try faceCount(rounded) == 14)
        #expect(try rounded.cylinderCaps(featureID: roundedScene.featureID) == true)
        #expect(try rounded.boxCornerRadius(roundedScene.featureID) == 0.01)
    }

    /// Caps exclude neither the hole nor the turn. All four combinations are reachable from either
    /// order, and each edit carries the others' values forward untouched.
    @Test(.timeLimit(.minutes(2)))
    func capsComposeWithHollowAndAngleInBothOrders() throws {
        var hollowFirst = DesignDocument.empty()
        let hollowScene = try cylinder(&hollowFirst)
        try hollowFirst.setSceneNodeObjectProperty(
            id: hollowScene.body.id, propertyID: hollowID, value: .length(0.02)
        )
        try hollowFirst.setSceneNodeObjectProperty(
            id: hollowScene.body.id, propertyID: capsID, value: .boolean(false)
        )
        // The outer and inner walls alone: four quadrants each, and no caps between them. The
        // two boundary loops of the profile sweep into two disjoint shells of one sheet body,
        // which bound no volume between them and claim none.
        try expectUncappedSheet(hollowFirst, faces: 8, shells: 2)
        #expect(try hollowFirst.cylinderHollow(featureID: hollowScene.featureID) == 0.02)
        try hollowFirst.validate()

        var capsFirst = DesignDocument.empty()
        let capsScene = try cylinder(&capsFirst)
        try capsFirst.setSceneNodeObjectProperty(
            id: capsScene.body.id, propertyID: capsID, value: .boolean(false)
        )
        try capsFirst.setSceneNodeObjectProperty(
            id: capsScene.body.id, propertyID: hollowID, value: .length(0.02)
        )
        try expectUncappedSheet(capsFirst, faces: 8, shells: 2)
        #expect(try capsFirst.cylinderCaps(featureID: capsScene.featureID) == false)

        // The two hollow orders agree, and the turn composes on top of both.
        try capsFirst.setSceneNodeObjectProperty(
            id: capsScene.body.id, propertyID: angleID, value: .angle(90.0)
        )
        // A quadrant of each wall and the two radial walls between them, still uncapped. The
        // single boundary loop of a hollow sector joins the wall to the hole, so it is one shell.
        try expectUncappedSheet(capsFirst, faces: 4, shells: 1)
        #expect(try capsFirst.cylinderCaps(featureID: capsScene.featureID) == false)
        #expect(try capsFirst.cylinderHollow(featureID: capsScene.featureID) == 0.02)

        var angleFirst = DesignDocument.empty()
        let angleScene = try cylinder(&angleFirst)
        try angleFirst.setSceneNodeObjectProperty(
            id: angleScene.body.id, propertyID: angleID, value: .angle(90.0)
        )
        try angleFirst.setSceneNodeObjectProperty(
            id: angleScene.body.id, propertyID: capsID, value: .boolean(false)
        )
        // One quadrant of the wall and the two radial walls, with no caps.
        try expectUncappedSheet(angleFirst, faces: 3, shells: 1)
        let storedTurn = try #require(try angleFirst.cylinderAngle(featureID: angleScene.featureID))
        #expect(abs(storedTurn - 90.0) < 1.0e-9)
        #expect(try angleFirst.cylinderCaps(featureID: angleScene.featureID) == false)
        try angleFirst.validate()
    }

    /// An uncapped cylinder bounds no volume, so it is measured as the sheet it is rather than as
    /// the solid its profile and distance would enclose.
    @Test(.timeLimit(.minutes(2)))
    func anUncappedCylinderIsMeasuredAsASheet() throws {
        var document = DesignDocument.empty()
        let scene = try cylinder(&document)
        try document.setSceneNodeObjectProperty(
            id: scene.body.id, propertyID: capsID, value: .boolean(false)
        )

        let result = try MeasurementService().measure(
            document: document,
            ruler: RulerConfiguration.standard(for: .millimeter)
        )

        #expect(result.counts.solids == 0)
        #expect(result.counts.sheets == 1)
        #expect(result.totals.solidVolumeCubicMeters == 0.0)
        // The open tube's wall: 2 pi r h = 2 pi * 0.05 m * 0.06 m.
        let expectedArea = 2.0 * Double.pi * 0.05 * 0.06
        let sheet = try #require(result.sheets.first)
        #expect(abs(sheet.surfaceAreaSquareMeters - expectedArea) < expectedArea * 0.02)
        #expect(abs(result.totals.sheetAreaSquareMeters - expectedArea) < expectedArea * 0.02)
    }

    /// The result kind, the output role and the geometry role are bound to each other, so a
    /// document where any two of them disagree fails validation rather than describing a body
    /// nothing evaluates into.
    @Test(.timeLimit(.minutes(2)))
    func aCappedCylinderCannotClaimToBeASurface() throws {
        var document = DesignDocument.empty()
        let scene = try cylinder(&document)
        var node = try #require(document.productMetadata.sceneNodes[scene.body.id])
        var object = try #require(node.object)

        object.geometryRole = .surface
        node.object = object
        document.productMetadata.sceneNodes[scene.body.id] = node

        #expect(throws: DocumentValidationError.self) {
            try document.productMetadata.validate(
                against: document.cadDocument,
                objectRegistry: .builtIn
            )
        }
    }
}
