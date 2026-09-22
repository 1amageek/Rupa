import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Suite("Native sheet surface edits", .timeLimit(.minutes(1)))
struct SheetSurfaceEditTests {
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
