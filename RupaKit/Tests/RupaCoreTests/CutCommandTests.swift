import SwiftCAD
import Testing
@testable import RupaCore

/// Cut splits bodies with curves and faces, each piece an object of its own, the cutters kept as
/// hidden sheets placed where the cutters are.
@Suite struct CutCommandTests {
    private let cube = 0.1 * 0.1 * 0.1

    @MainActor
    private func box(_ session: EditorSession) throws -> SceneNodeID {
        _ = try session.execute(.createExtrudedRectangle(
            name: "Box", plane: .xy,
            width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .length(0.1, .meter), direction: .normal
        ))
        return try #require(session.document.productMetadata.sceneNodes.values.first {
            $0.name.hasPrefix("Box") && $0.reference?.kind == .body
        }).id
    }

    /// A 100 mm cube, its x and y extents, and a line sketch on XY crossing it along x.
    @MainActor
    private func boxAndLine(from start: Double = -1, to end: Double = 1) throws -> (EditorSession, box: SceneNodeID, line: SceneNodeID) {
        let session = EditorSession()
        let box = try box(session)
        let y = try boxCenterY(session)
        _ = try session.execute(.createLineSketch(
            name: "Line", plane: .xy,
            start: SketchPoint(x: .length(start, .meter), y: .length(y + 0.02, .meter)),
            end: SketchPoint(x: .length(end, .meter), y: .length(y + 0.02, .meter))
        ))
        let line = try #require(session.document.productMetadata.sceneNodes.values.first { $0.name.hasPrefix("Line") }).id
        return (session, box, line)
    }

    @MainActor
    private func boxCenterY(_ session: EditorSession) throws -> Double {
        let measurement = try MeasurementService().measure(document: session.document, ruler: .standard(for: .meter))
        let bounds = try #require(measurement.bounds)
        return (bounds.minY + bounds.maxY) / 2
    }

    private func volume(_ document: DesignDocument) throws -> Double {
        try MeasurementService().measure(document: document, ruler: .standard(for: .meter)).totals.solidVolumeCubicMeters
    }

    @MainActor
    private func pieces(_ session: EditorSession, named name: String) -> [SceneNode] {
        session.document.productMetadata.sceneNodes.values.filter { $0.name.hasPrefix("\(name) ") && $0.isVisible }
    }

    @MainActor
    @Test func aLineCutsABoxAlongItsPlaneNormal() throws {
        let (session, box, line) = try boxAndLine()
        _ = try session.execute(.cut(name: "Cut", targets: [box], cutters: [.curve(line)], options: CutOptions()))
        #expect(pieces(session, named: "Cut").count == 2)
        #expect(abs(try volume(session.document) - cube) < 1e-9)
        let cutter = try #require(session.document.productMetadata.sceneNodes.values.first { $0.name == "Cut Cutter 1" })
        #expect(cutter.isVisible == false)
        #expect(session.evaluationStatus == .valid)
    }

    @MainActor
    @Test func aDirectionTiltsTheCut() throws {
        let (session, box, line) = try boxAndLine()
        _ = try session.execute(.cut(
            name: "Cut", targets: [box], cutters: [.curve(line)],
            options: CutOptions(direction: Vector3D(x: 0, y: 0.5, z: 1))
        ))
        #expect(pieces(session, named: "Cut").count == 2)
        #expect(abs(try volume(session.document) - cube) < 1e-9)
    }

    /// A line too short to reach across the box cuts it only when extended.
    @MainActor
    @Test func extendLengthensAShortCurve() throws {
        let (short, shortBox, shortLine) = try boxAndLine(from: 0.0, to: 0.001)
        let before = short.document.cadDocument.designGraph
        #expect(throws: (any Error).self) {
            _ = try short.execute(.cut(name: "Cut", targets: [shortBox], cutters: [.curve(shortLine)], options: CutOptions()))
        }
        #expect(short.document.cadDocument.designGraph == before)

        let (session, box, line) = try boxAndLine(from: 0.0, to: 0.001)
        _ = try session.execute(.cut(name: "Cut", targets: [box], cutters: [.curve(line)], options: CutOptions(extendsCurves: true)))
        #expect(pieces(session, named: "Cut").count == 2)
        #expect(abs(try volume(session.document) - cube) < 1e-9)
    }

    /// A face of a sheet cuts a box, and a second cutter cuts the pieces again.
    @MainActor
    @Test func facesAndSeveralCuttersCutInTurn() throws {
        let (session, box, line) = try boxAndLine()
        _ = try session.execute(.createBSplineSurface(name: "Sheet", surface: .bilinearPatch(
            bottomLeft: Point3D(x: -1, y: -1, z: 0.025), bottomRight: Point3D(x: 1, y: -1, z: 0.025),
            topRight: Point3D(x: 1, y: 1, z: 0.025), topLeft: Point3D(x: -1, y: 1, z: 0.025)
        )))
        let sheetNode = try #require(session.document.productMetadata.sceneNodes.values.first { $0.name.hasPrefix("Sheet") }).id
        let topology = try TopologySnapshotService().snapshot(document: session.document)
        let face = try #require(topology.entries.first { $0.kind == .face && $0.sceneNodeID == sheetNode.description }?.selectionTarget())
        _ = try session.execute(.cut(name: "Cut", targets: [box], cutters: [.face(face), .curve(line)], options: CutOptions()))
        #expect(pieces(session, named: "Cut").count == 4)
        #expect(abs(try volume(session.document) - cube) < 1e-9)
        #expect(session.evaluationStatus == .valid)
    }
}
