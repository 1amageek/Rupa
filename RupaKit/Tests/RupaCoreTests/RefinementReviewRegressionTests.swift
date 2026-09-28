import Foundation
import SwiftCAD
import RupaGeometry
import RupaProjectModel
import Testing
@testable import RupaCore

@Suite struct RefinementReviewRegressionTests {
    private func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(x: .length(x, .meter), y: .length(y, .meter))
    }

    private func curve(_ source: SketchSpline, in base: DesignDocument = .empty()) throws
        -> (DesignDocument, SelectionTarget, FeatureID, SketchEntityID) {
        var document = base
        let feature = try document.createSplineSketch(name: "Curve", plane: .xy, spline: source)
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[feature]?.operation else {
            throw EditorError(code: .referenceUnresolved, message: "Missing sketch.")
        }
        let entity = try #require(sketch.entityOrder.first)
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == feature })
        return (document, SelectionTarget(sceneNodeID: node.id,
            component: .sketchEntity(.sketchEntity(featureID: feature, entityID: entity))), feature, entity)
    }

    @Test func subdivisionAcceptsUnevenKnotSpans() throws {
        let source = SketchSpline(controlPoints: [point(0,0), point(1,1), point(2,0)],
            degree: 1, knots: [0,0,1,10_000_000,10_000_000])
        var (document, target, feature, entity) = try curve(source)
        #expect(try document.subdivideSketchSpline(target: target) == [1,3])
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[feature]?.operation,
              case .spline(let result) = sketch.entities[entity] else {
            Issue.record("Missing refined spline."); return
        }
        #expect(result.knots == [0,0,0.5,1,5_000_000.5,10_000_000,10_000_000])
        let before = try document.resolvedSketchSplineCurve(source, owner: "Test")
        let after = try document.resolvedSketchSplineCurve(result, owner: "Test")
        for parameter in [0.0, 0.25, 0.5, 1, 500, 5_000_000, 10_000_000] {
            let a = try before.bSpline.point(at: parameter, tolerance: .standard)
            let b = try after.bSpline.point(at: parameter, tolerance: .standard)
            #expect(hypot(a.x-b.x, a.y-b.y) < 1e-10)
        }
        let previous = document.cadDocument.designGraph
        for fraction in [0.0, 1.0, -0.1, 1.1] {
            #expect(throws: Error.self) { try document.insertSketchSplineControlPoint(target: target, fraction: .scalar(fraction)) }
            #expect(document.cadDocument.designGraph == previous)
        }
    }

    @Test(arguments: [false, true])
    func extensionTracksParametersAndRetainsLength(atStart: Bool) throws {
        var base = DesignDocument.empty()
        try base.upsertParameter(name: "height", expression: .length(0, .meter), kind: .length)
        let height = try ParameterExpressionParser().parse("height", parameters: base.cadDocument.parameters, targetKind: .length)
        let source = SketchSpline(controlPoints: [SketchPoint(x: .length(0, .meter), y: height), point(1,0)], degree: 1)
        var (document, target, feature, entity) = try curve(source, in: base)
        let endTarget = SelectionTarget(sceneNodeID: target.sceneNodeID, component: .sketchEntity(
            .sketchControlPoint(featureID: feature, entityID: entity, index: atStart ? 0 : 1)))
        try document.extendSketchCurve(target: endTarget, distance: .length(2, .meter), shape: .linear)
        try document.upsertParameter(name: "height", expression: .length(1, .meter), kind: .length)
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[feature]?.operation,
              case .spline(let spline) = sketch.entities[entity] else {
            Issue.record("Missing extended spline."); return
        }
        let reloaded = try JSONDecoder().decode(SketchSpline.self, from: JSONEncoder().encode(spline))
        let points = try reloaded.controlPoints.map { p in
            Point2D(x: try document.cadDocument.parameters.resolvedValue(for: p.x).value,
                    y: try document.cadDocument.parameters.resolvedValue(for: p.y).value)
        }
        let a = atStart ? points[2] : points[0]
        let b = points[1]
        let c = atStart ? points[0] : points[2]
        let dx = b.x-a.x, dy = b.y-a.y, ex = c.x-b.x, ey = c.y-b.y
        #expect(abs(dx*ey-dy*ex) < 1e-10)
        #expect(dx*ex+dy*ey > 0)
        #expect(abs(hypot(ex,ey)-2) < 1e-10)
    }

    @Test func openContourDoesNotDependOnSegmentOrderOrDirection() throws {
        let pairs = [(0.0,1.0),(1.0,2.0),(2.0,3.0)]
        for order in [[0,1,2],[0,2,1],[1,0,2],[1,2,0],[2,0,1],[2,1,0]] {
            for mask in 0..<8 {
                let segments = order.map { index in
                    let pair = pairs[index]
                    let (a,b) = mask & (1 << index) == 0 ? pair : (pair.1,pair.0)
                    return SectionAnalysisResult.IntersectionSegment(bodyID: "mesh", sceneNodeID: nil,
                        start: Point3D(x:a,y:0,z:0), end: Point3D(x:b,y:0,z:0),
                        start2D: Point2D(x:a,y:0), end2D: Point2D(x:b,y:0))
                }
                let contours = SectionAnalysisContourBuilder(tolerance: 1e-6).build(segments: segments)
                #expect(contours.count == 1)
                let result = try #require(contours.first)
                #expect(!result.isClosed && result.segmentCount == 3)
                #expect(abs(result.lengthMeters-3) < 1e-10)
            }
        }
    }

    @Test(arguments: [0.0005, 1.0])
    func smallMeshFacesSectionAtWorldScale(size: Double) throws {
        var builder = MeshSourceBuilder(identity: "review.mesh")
        let vertices = try [(-size,-size),(size,-size),(size,size),(-size,size)].map { x,z in
            try builder.addVertex(GeometryPoint3D(x:x,y:0,z:z))
        }
        _ = try builder.addFace(vertexIDs: vertices)
        let asset = try AuthoredMeshAsset(source: builder.build(), provenance: .created)
        var document = DesignDocument.empty()
        document.authoredMeshAssets[asset.id] = asset
        let id: GeometryRepresentationID = "review.mesh.rep"
        _ = try document.productMetadata.appendSceneNodeToFirstRoot(name: "Mesh", reference: .authoredMesh(asset.id),
            object: ObjectDescriptor(category: .body, geometryRole: .mesh,
                geometryRepresentations: GeometryRepresentationSet(
                    representations: [id: GeometryRepresentation(id: id, source: .authoredMesh(asset.id))],
                    selection: GeometryRepresentationSelection(modeling: id, presentation: id))))
        for tolerance in [1e-6, 1e-5] {
            let result = try SectionAnalysisService().analyze(document: document,
                query: SectionAnalysisQuery(source: .sketchPlane(.xy), toleranceMeters: tolerance),
                activeConstructionPlaneID: nil, displayUnit: .millimeter)
            #expect(result.bodyCount == 1 && result.intersectionContours.count == 1)
            #expect(abs(try #require(result.intersectionContours.first).lengthMeters - 2*size) < 1e-10)
        }
    }
}
