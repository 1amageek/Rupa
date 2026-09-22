import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Suite("Native sheet surface edits", .timeLimit(.minutes(1)))
struct SheetSurfaceEditTests {
    @Test(arguments: [ThickenSide.positive, .negative, .symmetric])
    func thickenRetainsOccurrenceAndReevaluatesParameters(side: ThickenSide) throws {
        let session = EditorSession()
        _ = try session.execute(.createBSplineSurface(name: "Patch", surface: patch))
        _ = try session.execute(.upsertParameter(name: "thickness", expression: .length(0.002, .meter), kind: .length))
        let target = try face(in: session.document)
        let placement = try Transform3D(matrix: Matrix4x4(values: [
            1, 0, 0, 0.15, 0, 1, 0, 0.2, 0, 0, 1, 0.3, 0, 0, 0, 1]))
        _ = try session.execute(.setSceneNodeTransform(id: target.sceneNodeID, localTransform: placement))
        let original = session.document
        for thickness in [0.0, -0.002] {
            #expect(throws: (any Error).self) {
                try session.execute(.createSheetSurfaceEdit(name: "Invalid", target: target,
                    edit: .thicken(thickness: .length(thickness, .meter), side: side)))
            }
            #expect(session.document.cadDocument.designGraph == original.cadDocument.designGraph)
            #expect(session.document.productMetadata == original.productMetadata)
        }
        let expression = try ParameterExpressionParser().parse("thickness",
            parameters: original.cadDocument.parameters, targetKind: .length)
        _ = try session.execute(.createSheetSurfaceEdit(name: "Thicken", target: target,
            edit: .thicken(thickness: expression, side: side)))
        let node = try #require(session.document.productMetadata.sceneNodes[target.sceneNodeID])
        let object = try #require(node.object)
        let originalObject = try #require(original.productMetadata.sceneNodes[target.sceneNodeID]?.object)
        #expect(node.localTransform == placement)
        #expect(object.geometryRole == .solid)
        #expect(Set(object.geometryRepresentations.representations.keys)
            == Set(originalObject.geometryRepresentations.representations.keys))
        _ = try session.execute(.upsertParameter(name: "thickness", expression: .length(0.004, .meter), kind: .length))
        let current = session.document
        let result = try DocumentEvaluator.modelingDefault(for: current).evaluateExact(current.cadDocument)
        #expect(result.brep.bodies.count == 1)
        #expect(abs(try result.brep.volume(tolerance: current.modelingSettings.tolerance) - 0.00004) < 1e-10)
        let lower = side == .positive ? 0.0 : side == .negative ? -0.004 : -0.002
        let upper = lower + 0.004
        #expect(result.brep.vertices.values.allSatisfy { abs($0.point.z - lower) < 1e-10 || abs($0.point.z - upper) < 1e-10 })
        let topology = try TopologySnapshotService().snapshot(document: current, metricPolicy: .omit)
        let faces = topology.entries.filter { $0.kind == .face }
        #expect(faces.count == 6)
        for entry in faces {
            let normal = try #require(entry.normal)
            #expect(abs(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z - 1) < 1e-10)
        }
        let solidFace = try #require(faces.first?.selectionTarget())
        #expect(throws: (any Error).self) {
            try session.execute(.createSheetSurfaceEdit(name: "Invalid solid", target: solidFace,
                edit: .thicken(thickness: expression, side: side)))
        }
        #expect(session.document.cadDocument.designGraph == current.cadDocument.designGraph)
        #expect(session.document.productMetadata == current.productMetadata)
        let decoded = try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(current.cadDocument))
        #expect(try DocumentEvaluator.modelingDefault(for: current).evaluateExact(decoded).brep == result.brep)
        _ = try session.undo()
        _ = try session.undo()
        #expect(session.document.cadDocument.designGraph == original.cadDocument.designGraph)
        #expect(session.document.productMetadata == original.productMetadata)
    }

    @Test(arguments: [-0.005, 0.005])
    func offsetPreservesSourceAndUndo(distance: Double) throws {
        let session = EditorSession()
        _ = try session.execute(.createBSplineSurface(name: "Patch", surface: patch))
        let original = session.document
        let target = try face(in: original)
        _ = try session.execute(.createSheetSurfaceEdit(name: "Offset", target: target,
            edit: .offset(distance: .length(distance, .meter))))
        let result = try DocumentEvaluator.modelingDefault(for: session.document).evaluateExact(session.document.cadDocument)
        try result.brep.validate(level: .exact, tolerance: original.modelingSettings.tolerance)
        #expect(result.brep.bodies.count == 1)
        #expect(result.brep.faces.count == 1)
        #expect(result.brep.vertices.values.allSatisfy { abs($0.point.z - distance) < 1e-10 })
        for (id, feature) in original.cadDocument.designGraph.nodes {
            #expect(session.document.cadDocument.designGraph.nodes[id] == feature)
        }
        let decoded = try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(session.document.cadDocument))
        #expect(try DocumentEvaluator.modelingDefault(for: session.document).evaluateExact(decoded).brep == result.brep)
        _ = try session.undo()
        #expect(session.document.cadDocument.designGraph == original.cadDocument.designGraph)
        #expect(session.document.productMetadata == original.productMetadata)
    }

    @Test func extendRestoresTrimmedPatchAndRejectsExtrapolation() throws {
        let session = EditorSession()
        _ = try session.execute(.createBSplineSurface(name: "Patch", surface: patch))
        let summary = try SurfaceSourceSummaryService().summarize(document: session.document, displayUnit: .millimeter)
        let target = try #require(summary.sources.first?.patches.first?.faceSelectionReference)
        let corners = [SurfaceParameter(u: 0.2, v: 0.2), SurfaceParameter(u: 0.8, v: 0.2),
            SurfaceParameter(u: 0.8, v: 0.8), SurfaceParameter(u: 0.2, v: 0.8)]
        let loop = SurfaceTrimLoop(role: .outer, parameterCurves: (0..<4).map {
            .polyline([corners[$0], corners[($0 + 1) % 4]])
        })
        _ = try session.execute(.setSurfaceTrimLoops(target: target, trimLoops: [loop]))
        let original = session.document
        let selected = try face(in: original)
        _ = try session.execute(.createSheetSurfaceEdit(name: "Extend", target: selected,
            edit: .extend(uDomain: .closed(0, 1), vDomain: .closed(0, 1))))
        let result = try DocumentEvaluator.modelingDefault(for: session.document).evaluateExact(session.document.cadDocument)
        #expect(result.brep.bodies.count == 1)
        #expect(result.brep.vertices.count == 4)
        #expect(result.brep.vertices.values.contains { $0.point.isApproximatelyEqual(to: .origin, tolerance: 1e-10) })
        let extended = session.document
        #expect(throws: (any Error).self) { try session.execute(.setSurfaceTrimLoops(target: target, trimLoops: [])) }
        #expect(session.document.cadDocument.designGraph == extended.cadDocument.designGraph)
        #expect(session.document.productMetadata == extended.productMetadata)
        _ = try session.undo()
        #expect(session.document.cadDocument.designGraph == original.cadDocument.designGraph)
        for edit in [SheetSurfaceEdit.extend(uDomain: .closed(-1, 2), vDomain: .closed(0, 1)), .offset(distance: .length(0, .meter))] {
            #expect(throws: (any Error).self) {
                try session.execute(.createSheetSurfaceEdit(name: "Invalid", target: selected, edit: edit))
            }
            #expect(session.document.cadDocument.designGraph == original.cadDocument.designGraph)
            #expect(session.document.productMetadata == original.productMetadata)
        }
    }

    private var patch: BSplineSurface3D {
        .bilinearPatch(bottomLeft: .origin, bottomRight: Point3D(x: 0.1, y: 0, z: 0),
            topRight: Point3D(x: 0.1, y: 0.1, z: 0), topLeft: Point3D(x: 0, y: 0.1, z: 0))
    }

    private func face(in document: DesignDocument) throws -> SelectionTarget {
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        return try #require(topology.entries.first { $0.kind == .face }?.selectionTarget())
    }
}
