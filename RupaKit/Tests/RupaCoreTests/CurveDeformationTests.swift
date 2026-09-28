import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Deform Curve carries sketch curves from a reference face onto a target face through their
/// UVN coordinates, as spatial paths, and removes the sources unless Keep Tools is on.
@MainActor
@Suite struct CurveDeformationTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }

    private struct Fixture {
        var document: DesignDocument
        var bottom: SelectionTarget
        var side: SelectionTarget
        var sideReference: SurfaceReference
        var bottomReference: SurfaceReference
        var lineTarget: SelectionTarget
        var featureID: FeatureID
        var entityID: SketchEntityID
    }

    private func fixture() throws -> Fixture {
        let session = EditorSession()
        _ = try #require(session.createDefaultExtrudedRectangle())
        var document = session.document
        let faces = try TopologySnapshotService().snapshot(document: document).entries.filter { $0.kind == .face }
        let bottomEntry = try #require(faces.first { ($0.normal?.z ?? 0) < -0.5 })
        let sideEntry = try #require(faces.first { ($0.normal?.x ?? 0) > 0.5 })
        let center = try #require(bottomEntry.center)
        // A line on the bottom face's plane (z = 0), inside the face.
        let featureID = try document.createLineSketch(
            name: "Curve", plane: .xy,
            start: SketchPoint(x: .length(center.x - 0.002, .meter), y: .length(center.y - 0.001, .meter)),
            end: SketchPoint(x: .length(center.x + 0.003, .meter), y: .length(center.y + 0.001, .meter))
        )
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[featureID]?.operation,
              let entityID = sketch.entities.keys.first else {
            throw EditorError(code: .referenceUnresolved, message: "The sketch is missing.")
        }
        let sceneNodeID = try #require(document.productMetadata.sceneNodes.first { $0.value.reference?.featureID == featureID }?.key)
        return Fixture(
            document: document,
            bottom: try #require(bottomEntry.selectionTarget()),
            side: try #require(sideEntry.selectionTarget()),
            sideReference: SurfaceReference(subshape: try #require(sideEntry.stableReference)),
            bottomReference: SurfaceReference(subshape: try #require(bottomEntry.stableReference)),
            lineTarget: SelectionTarget(sceneNodeID: sceneNodeID, component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: entityID))),
            featureID: featureID,
            entityID: entityID
        )
    }

    private func paths(_ document: DesignDocument, _ ids: [FeatureID]) throws -> [SpatialPathFeature] {
        try ids.map { id in
            guard case .spatialPath(let path) = document.cadDocument.designGraph.nodes[id]?.operation else {
                throw EditorError(code: .referenceUnresolved, message: "The deformed path is missing.")
            }
            return path
        }
    }

    @Test func aLineOnTheBottomLandsOnTheSideAtTheSameFaceCoordinates() throws {
        var f = try fixture()
        let ids = try f.document.deformCurves(
            targets: [f.lineTarget], referenceFace: f.bottom, targetFace: f.side,
            options: CurveDeformationOptions(keepsTools: true)
        )
        let path = try #require(try paths(f.document, ids).first)
        let evaluated = try #require(try TopologySnapshotService().snapshot(document: f.document).evaluatedDocument)
        let from = try FaceUVNChart(face: f.bottomReference, in: evaluated, tolerance: .standard)
        let to = try FaceUVNChart(face: f.sideReference, in: evaluated, tolerance: .standard)
        // Every point of the path lies on the side face.
        let curve = try path.exactCurve(tolerance: .standard)
        let domain = curve.knots.last! - curve.knots.first!
        for i in 0...50 {
            let p = try curve.point(at: domain * Double(i) / 50, tolerance: .standard)
            #expect(abs(try to.coordinate(of: p).n) < 1.0e-9)
        }
        // The path's ends are the line's ends carried across.
        guard case .line(let line) = try #require(sketch(f.document, f.featureID).entities[f.entityID]) else {
            Issue.record("The kept line is missing.")
            return
        }
        let lineStart = Point3D(
            x: try f.document.cadDocument.parameters.resolvedValue(for: line.start.x).value,
            y: try f.document.cadDocument.parameters.resolvedValue(for: line.start.y).value,
            z: 0
        )
        let expected = try to.point(at: from.coordinate(of: lineStart))
        #expect((path.knots.first!.position - expected).length < 1.0e-9)
    }

    @Test func withoutKeepToolsTheSourceIsReplacedAndNormalFlipLiftsInward() throws {
        var f = try fixture()
        var options = CurveDeformationOptions(offsetN: .length(0.001, .meter), flipsNormal: true)
        options.keepsTools = false
        let ids = try f.document.deformCurves(targets: [f.lineTarget], referenceFace: f.bottom, targetFace: f.side, options: options)
        // The line was its sketch's only curve: the sketch goes with it.
        #expect(f.document.cadDocument.designGraph.nodes[f.featureID] == nil)
        let path = try #require(try paths(f.document, ids).first)
        let evaluated = try #require(try TopologySnapshotService().snapshot(document: f.document).evaluatedDocument)
        let to = try FaceUVNChart(face: f.sideReference, in: evaluated, tolerance: .standard)
        // n = −(0 · 1 + 1 mm): one millimeter inside the side face.
        #expect(abs(try to.coordinate(of: path.knots[0].position).n + 0.001) < 1.0e-9)
    }

    @Test func aTargetThatIsNotAFaceIsRefusedAndNothingChanges() throws {
        var f = try fixture()
        let before = f.document.cadDocument.designGraph
        #expect(throws: EditorError.self) {
            try f.document.deformCurves(targets: [f.lineTarget], referenceFace: f.bottom, targetFace: f.lineTarget, options: CurveDeformationOptions())
        }
        #expect(throws: EditorError.self) {
            try f.document.deformCurves(targets: [f.lineTarget], referenceFace: f.bottom, targetFace: f.side, options: CurveDeformationOptions(scaleU: 0))
        }
        #expect(f.document.cadDocument.designGraph == before)
    }

    private func sketch(_ document: DesignDocument, _ featureID: FeatureID) throws -> Sketch {
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[featureID]?.operation else {
            throw EditorError(code: .referenceUnresolved, message: "The sketch is missing.")
        }
        return sketch
    }
}
