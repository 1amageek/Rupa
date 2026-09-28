import SwiftCAD
import Testing
@testable import RupaCore

@Suite struct GeneralSplineRefinementTests {
    private func fixture(_ spline: SketchSpline, base: DesignDocument = .empty()) throws -> (DesignDocument, SelectionTarget, FeatureID, SketchEntityID) {
        var document = base
        let id = try document.createSplineSketch(name: "Curve", plane: .xy, spline: spline)
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[id]?.operation else {
            throw EditorError(code: .referenceUnresolved, message: "Missing sketch.")
        }
        let entity = try #require(sketch.entityOrder.first)
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == id })
        return (document, SelectionTarget(sceneNodeID: node.id, component: .sketchEntity(.sketchEntity(featureID: id, entityID: entity))), id, entity)
    }

    private func spline(_ document: DesignDocument, _ feature: FeatureID, _ entity: SketchEntityID) throws -> SketchSpline {
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[feature]?.operation,
              case .spline(let result) = sketch.entities[entity] else {
            throw EditorError(code: .referenceUnresolved, message: "Missing spline.")
        }
        return result
    }

    private func point(_ x: Double, _ y: Double) -> SketchPoint {
        .init(x: .length(x, .meter), y: .length(y, .meter))
    }

    @Test(arguments: [1, 2, 3, 6, 7])
    func subdivisionPreservesDegreeAndCurve(degree: Int) throws {
        let source = SketchSpline(controlPoints: (0...degree).map { point(Double($0), $0 == degree / 2 ? 3 : 0) }, degree: degree)
        var (document, target, feature, entity) = try fixture(source)
        let before = try document.resolvedSketchSplineCurve(source, owner: "Test")
        let expected = try document.sketchSplineSubdivisionControlPointIndices(source)
        #expect(try document.subdivideSketchSpline(target: target) == expected)
        let result = try spline(document, feature, entity)
        #expect(result.degree == degree && result.knots == nil)
        #expect(result.controlPoints.count == 2 * degree + 1)
        let after = try document.resolvedSketchSplineCurve(result, owner: "Test")
        for i in 0...32 {
            let t = Double(i) / 32
            let a = try before.bSpline.point(at: before.parameter(ofFraction: t), tolerance: .standard)
            let b = try after.bSpline.point(at: after.parameter(ofFraction: t), tolerance: .standard)
            #expect(abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9)
        }
    }

    @Test(arguments: [false, true])
    func nonuniformKnotsAndClosureSurviveSubdivision(closed: Bool) throws {
        var points = (0..<7).map { point(Double($0), Double($0 % 3)) }
        if closed { points[6] = points[0] }
        let source = SketchSpline(controlPoints: points, isClosed: closed, degree: 3,
                                  knots: [2,2,2,2,2.3,3.1,4,5,5,5,5])
        var (document, target, feature, entity) = try fixture(source)
        let before = try document.resolvedSketchSplineCurve(source, owner: "Test")
        let indices = try document.subdivideSketchSpline(target: target)
        let result = try spline(document, feature, entity)
        #expect(result.degree == 3 && result.isClosed == closed)
        #expect(result.controlPoints.count == 19)
        #expect(indices.count == 12 && Set(indices).count == 12)
        let after = try document.resolvedSketchSplineCurve(result, owner: "Test")
        for i in 0...40 {
            let t = 2 + 3 * Double(i) / 40
            let a = try before.bSpline.point(at: t, tolerance: .standard)
            let b = try after.bSpline.point(at: t, tolerance: .standard)
            #expect(abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9)
        }
    }

    @Test func subdivisionRetainsParameterExpressionsAndEndReferences() throws {
        var base = DesignDocument.empty()
        try base.upsertParameter(name: "height", expression: .length(3, .meter), kind: .length)
        let height = try ParameterExpressionParser().parse("height", parameters: base.cadDocument.parameters, targetKind: .length)
        var points = (0...6).map { point(Double($0), 0) }
        points[3].y = height
        let source = SketchSpline(controlPoints: points, degree: 6)
        var (document, target, feature, entity) = try fixture(source, base: base)
        try document.addSketchConstraint(featureID: feature, constraint: .fixed(.splineControlPoint(entity: entity, index: 6)))
        _ = try document.subdivideSketchSpline(target: target)
        try document.upsertParameter(name: "height", expression: .length(6, .meter), kind: .length)
        let result = try spline(document, feature, entity)
        let after = try document.resolvedSketchSplineCurve(result, owner: "Test")
        #expect(abs(try after.bSpline.point(at: 1, tolerance: .standard).y - 1.875) < 1e-9)
        guard case .sketch(let edited) = document.cadDocument.designGraph.nodes[feature]?.operation else {
            Issue.record("Missing sketch."); return
        }
        #expect(edited.constraints.contains(.fixed(.splineControlPoint(entity: entity, index: 12))))
    }

    @MainActor @Test func subdivisionIsOneUndoableSourceCommand() throws {
        let source = SketchSpline(controlPoints: (0...6).map { point(Double($0), Double($0 % 2)) }, degree: 6)
        let (document, target, _, _) = try fixture(source)
        let session = EditorSession(document: document)
        _ = try session.execute(.subdivideSketchSpline(target: target))
        let edited = session.document.cadDocument.designGraph
        #expect(edited != document.cadDocument.designGraph)
        _ = try session.undo()
        #expect(session.document.cadDocument.designGraph == document.cadDocument.designGraph)
        _ = try session.redo()
        #expect(session.document.cadDocument.designGraph == edited)
    }

    @Test func replacedReferenceRefusesWithoutMutation() throws {
        let source = SketchSpline(controlPoints: (0...6).map { point(Double($0), Double($0 % 2)) }, degree: 6)
        var (document, target, feature, entity) = try fixture(source)
        try document.addSketchConstraint(featureID: feature, constraint: .fixed(.splineControlPoint(entity: entity, index: 2)))
        let before = document
        #expect(throws: EditorError.self) { try document.subdivideSketchSpline(target: target) }
        #expect(document.cadDocument.designGraph == before.cadDocument.designGraph)
        #expect(document.productMetadata == before.productMetadata)
    }

    @Test func completeEdgeExtendsGeneralSplineWithoutChangingItsOriginalDomain() throws {
        let source = SketchSpline(controlPoints: (0..<7).map { point(Double($0), 0) }, degree: 3,
                                  knots: [0,0,0,0,0.2,0.7,0.9,1,1,1,1])
        var (document, target, feature, entity) = try fixture(source)
        _ = try document.createLineSketch(name: "Stop", plane: .xy, start: point(8,-1), end: point(8,1))
        let before = try document.resolvedSketchSplineCurve(source, owner: "Test")
        #expect(try document.completeSketchCurve(target: target) == [.end])
        let result = try spline(document, feature, entity)
        let after = try document.resolvedSketchSplineCurve(result, owner: "Test")
        #expect(result.degree == source.degree && result.knots != nil)
        for i in 0...20 {
            let t = Double(i) / 20
            let a = try before.bSpline.point(at: t, tolerance: .standard)
            let b = try after.bSpline.point(at: t, tolerance: .standard)
            #expect(abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9)
        }
        let end = try document.cadDocument.parameters.resolvedValue(for: #require(result.controlPoints.last).x).value
        #expect(abs(end - 8) < 1e-9)
    }
}
