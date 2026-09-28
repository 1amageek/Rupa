import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Suite struct SketchP1PlacementAndTrimTests {
    private func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(x: .length(x, .meter), y: .length(y, .meter))
    }

    private func target(_ document: DesignDocument, _ feature: FeatureID, _ entity: SketchEntityID) throws -> SelectionTarget {
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == feature })
        return SelectionTarget(sceneNodeID: node.id, component: .sketchEntity(.sketchEntity(featureID: feature, entityID: entity)))
    }

    private func sketch(_ document: DesignDocument, _ feature: FeatureID) throws -> Sketch {
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[feature]?.operation else {
            throw EditorError(code: .referenceUnresolved, message: "Missing sketch")
        }
        return sketch
    }

    private func add(_ entity: SketchEntity, plane: SketchPlane = .xy, to document: inout DesignDocument) throws -> (FeatureID, SketchEntityID, SelectionTarget) {
        let id = SketchEntityID()
        let feature = try document.appendSketchFeature(name: "Curve", sketch: Sketch(plane: plane, entities: [id: entity]), geometryRole: .curve)
        return (feature, id, try target(document, feature, id))
    }

    @Test(arguments: [1, 3])
    func closedSplineBoundsTrim(degree: Int) throws {
        var document = DesignDocument.empty()
        let lineID = SketchEntityID(), cutterID = SketchEntityID()
        let corners = [(3.0, -1.0), (7, -1), (7, 1), (3, 1), (3, -1)]
        var points = [point(3, -1)]
        for (a, b) in zip(corners, corners.dropFirst()) {
            for i in 1...degree {
                let f = Double(i) / Double(degree)
                points.append(point(a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f))
            }
        }
        let cutter = SketchEntity.spline(SketchSpline(controlPoints: points, isClosed: true, degree: degree))
        let feature = try document.appendSketchFeature(name: "Trim", sketch: Sketch(plane: .xy, entities: [
            lineID: .line(SketchLine(start: point(0, 0), end: point(10, 0))), cutterID: cutter
        ]), geometryRole: .curve)
        try document.trimSketchCurve(target: target(document, feature, lineID), near: Point2D(x: 5, y: 0))
        let result = try sketch(document, feature)
        #expect(result.entities[cutterID] == cutter)
        let spans = try result.entities.values.compactMap { entity -> [Double]? in
            guard case .line(let line) = entity else { return nil }
            return try [line.start.x, line.end.x].map { try document.resolvedLengthValue($0, owner: "Test") }.sorted()
        }.sorted { $0[0] < $1[0] }
        #expect(spans.count == 2)
        if spans.count == 2 {
            let actual: [Double] = spans.flatMap { $0 }
            let expected: [Double] = [0, 3, 7, 10]
            for index in actual.indices { #expect(abs(actual[index] - expected[index]) < 1e-8) }
        }
    }

    @Test func cutUsesBothPlacementsAndDifferentAuthoredPlanes() throws {
        var document = DesignDocument.empty()
        let (feature, id, selected) = try add(.line(SketchLine(start: point(0, 0), end: point(10, 0))), to: &document)
        let (_, _, cutter) = try add(.line(SketchLine(start: point(-1, 0), end: point(1, 0))), plane: .yz, to: &document)
        let root = try #require(document.productMetadata.rootSceneNodeIDs.first)
        try document.setSceneNodeTransform(id: root, localTransform: .translation(Vector3D(x: 100, y: 20, z: 0)).composed(with: .rotation(axis: .unitZ, angleRadians: 0.6)))
        try document.setSceneNodeTransform(id: selected.sceneNodeID, localTransform: .translation(Vector3D(x: 10, y: 0, z: 0)))
        try document.setSceneNodeTransform(id: cutter.sceneNodeID, localTransform: .translation(Vector3D(x: 13, y: 0, z: 0)).composed(with: .rotation(axis: .unitY, angleRadians: .pi / 2)))
        let savedCutter = document.productMetadata.sceneNodes[cutter.sceneNodeID]
        #expect(try document.cutCurveCrosses(target: selected, cutter: cutter, options: CutCurveOptions()))
        let created = try document.cutSketchCurve(target: selected, cutter: cutter)
        #expect(created.count == 1)
        guard case .line(let retained) = try sketch(document, feature).entities[id] else { Issue.record("Missing line"); return }
        #expect(abs(try document.resolvedLengthValue(retained.end.x, owner: "Test") - 3) < 1e-8)
        #expect(document.productMetadata.sceneNodes[cutter.sceneNodeID] == savedCutter)
    }

    @Test func projectionIncludesRootPlacementOnce() throws {
        var document = DesignDocument.empty()
        let (_, _, selected) = try add(.line(SketchLine(start: point(1, 0), end: point(2, 0))), to: &document)
        let root = try #require(document.productMetadata.rootSceneNodeIDs.first)
        try document.setSceneNodeTransform(id: root, localTransform: .translation(Vector3D(x: 10, y: 0, z: 3)))
        try document.setSceneNodeTransform(id: selected.sceneNodeID, localTransform: .rotation(axis: .unitZ, angleRadians: .pi / 2).composed(with: .scale(Vector3D(x: 2, y: 2, z: 2), about: .origin)))
        let feature = try document.projectSketchCurvesToConstructionPlane(targets: [selected], plane: .xy)
        let projected = try sketch(document, feature)
        guard case .line(let line) = projected.entities.values.first else { Issue.record("Missing projection"); return }
        let id = try #require(projected.entities.keys.first)
        let node = try target(document, feature, id).sceneNodeID
        let placement = try SceneNodeHierarchy(metadata: document.productMetadata).worldTransform(of: node)
        for (p, expectedY) in [(line.start, 2.0), (line.end, 4.0)] {
            let resolved = try document.resolvedSketchPoint(p, owner: "Test")
            let world = try placement.applied(to: Point3D(x: resolved.x, y: resolved.y, z: 0))
            #expect(abs(world.x - 10) < 1e-9)
            #expect(abs(world.y - expectedY) < 1e-9)
            #expect(abs(world.z) < 1e-9)
        }
    }

    @Test func circlesAndReflectedArcsKeepPlacedSizeAndSweep() throws {
        var document = DesignDocument.empty()
        let (_, _, circle) = try add(.circle(SketchCircle(center: point(0, 0), radius: .length(1, .meter))), to: &document)
        let (_, _, arc) = try add(.arc(SketchArc(center: point(0, 0), radius: .length(1, .meter), startAngle: .angle(0, .radian), endAngle: .angle(.pi / 2, .radian))), to: &document)
        let placement = try Transform3D.translation(Vector3D(x: 5, y: 0, z: 0)).composed(with: .scale(Vector3D(x: -2, y: 2, z: 2), about: .origin))
        for selected in [circle, arc] { try document.setSceneNodeTransform(id: selected.sceneNodeID, localTransform: placement) }
        let feature = try document.projectSketchCurvesToConstructionPlane(targets: [circle, arc], plane: .xy)
        for entity in try sketch(document, feature).entities.values {
            switch entity {
            case .circle(let circle):
                #expect(try document.resolvedLengthValue(circle.radius, owner: "Test") == 2)
                #expect(try document.resolvedLengthValue(circle.center.x, owner: "Test") == 5)
            case .arc(let arc):
                #expect(try document.resolvedLengthValue(arc.radius, owner: "Test") == 2)
                let start = try document.resolvedAngleValue(arc.startAngle, owner: "Test")
                let end = try document.resolvedAngleValue(arc.endAngle, owner: "Test")
                #expect(abs(start - .pi / 2) < 1e-9)
                #expect(abs(end - .pi) < 1e-9)
            default: Issue.record("Unexpected projection")
            }
        }
        let (_, _, line) = try add(.line(SketchLine(start: point(0, 0), end: point(10, 0))), to: &document)
        #expect(try document.cutSketchCurve(target: line, cutter: circle).count == 2)
    }

    @Test func invalidPlacedCutsAndEllipticalProjectionAreAtomic() throws {
        var document = DesignDocument.empty()
        let (_, _, selected) = try add(.line(SketchLine(start: point(0, 0), end: point(10, 0))), to: &document)
        let (_, _, cutter) = try add(.line(SketchLine(start: point(3, -1), end: point(3, 1))), to: &document)
        for offset in [Vector3D(x: 20, y: 0, z: 0), Vector3D(x: 0, y: 0, z: 1)] {
            try document.setSceneNodeTransform(id: cutter.sceneNodeID, localTransform: .translation(offset))
            let before = document
            #expect(throws: EditorError.self) { try document.cutSketchCurve(target: selected, cutter: cutter) }
            #expect(document.cadDocument.designGraph == before.cadDocument.designGraph)
            #expect(document.productMetadata == before.productMetadata)
        }
        let (_, _, circle) = try add(.circle(SketchCircle(center: point(0, 0), radius: .length(1, .meter))), to: &document)
        try document.setSceneNodeTransform(id: circle.sceneNodeID, localTransform: .scale(Vector3D(x: 2, y: 1, z: 1), about: .origin))
        let before = document
        #expect(throws: EditorError.self) { try document.projectSketchCurvesToConstructionPlane(targets: [selected, circle], plane: .xy) }
        #expect(throws: EditorError.self) { try document.cutSketchCurve(target: selected, cutter: circle) }
        #expect(document.cadDocument.designGraph == before.cadDocument.designGraph)
            #expect(document.productMetadata == before.productMetadata)
    }
}
