import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Push Face, Draft Face and Match Face reshape an object where it is shown, keeping its place and
/// name: several faces, or one with an adjacent angle, push through Swift-CAD's face offset; a
/// face matches another object's face where that object is shown.
@MainActor
@Suite struct FaceEditCommandTests {
    private func box(_ session: EditorSession, _ name: String, height: Double = 0.1) throws -> SceneNodeID {
        _ = try session.execute(.createExtrudedRectangle(
            name: name, plane: .xy,
            width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .length(height, .meter), direction: .normal
        ))
        return try #require(session.document.productMetadata.sceneNodes.values.first {
            $0.name.hasPrefix(name) && $0.reference?.kind == .body
        }).id
    }

    private func faces(of node: SceneNodeID, in session: EditorSession) throws -> [TopologySummaryResult.Entry] {
        try TopologySnapshotService().snapshot(document: session.document).entries
            .filter { $0.kind == .face && $0.sceneNodeID == node.description }
    }

    private func face(of node: SceneNodeID, in session: EditorSession, normal: Vector3D, extreme: (Point3D) -> Double) throws -> SelectionTarget {
        let candidates = try faces(of: node, in: session).filter {
            guard let n = $0.surfaceNormal else { return false }
            return n.x * normal.x + n.y * normal.y + n.z * normal.z > 0.99
        }
        let best = try #require(candidates.max { extreme(Point3D(x: $0.center?.x ?? 0, y: $0.center?.y ?? 0, z: $0.center?.z ?? 0)) < extreme(Point3D(x: $1.center?.x ?? 0, y: $1.center?.y ?? 0, z: $1.center?.z ?? 0)) })
        return try #require(best.selectionTarget())
    }

    private func volume(_ session: EditorSession) throws -> Double {
        try MeasurementService().measure(document: session.document, ruler: .standard(for: .meter)).totals.solidVolumeCubicMeters
    }

    @Test(.timeLimit(.minutes(1)))
    func severalFacesPushTogetherThroughTheKernel() throws {
        let session = EditorSession()
        let target = try box(session, "Box")
        let top = try face(of: target, in: session, normal: Vector3D(x: 0, y: 0, z: 1)) { $0.z }
        let side = try face(of: target, in: session, normal: Vector3D(x: 1, y: 0, z: 0)) { $0.x }
        _ = try session.execute(.pushFaces(targets: [top, side], distance: .length(0.01, .meter)))
        #expect(abs(try volume(session) - 0.11 * 0.1 * 0.11) < 1e-12)
        #expect(session.document.productMetadata.sceneNodes[target]?.name.hasPrefix("Box") == true)
        #expect(session.evaluationStatus == .valid)
    }

    @Test(.timeLimit(.minutes(1)))
    func anAdjacentAngleTiltsTheWallsBesideAPushedTop() throws {
        let session = EditorSession()
        _ = try box(session, "Box")
        let target = try #require(session.document.productMetadata.sceneNodes.values.first { $0.reference?.kind == .body }).id
        let top = try face(of: target, in: session, normal: Vector3D(x: 0, y: 0, z: 1)) { $0.z }
        _ = try session.execute(.pushFaces(targets: [top], distance: .length(0.01, .meter), adjacentAngle: .angle(5, .degree)))
        // Each wall turns about its top edge, so above it the body grows and below it shrinks.
        let t = tan(5 * Double.pi / 180)
        let volume = try volume(session)
        let integrated = (0..<2_000).reduce(0.0) { sum, index in
            let z = (Double(index) + 0.5) * 0.11 / 2_000
            let side = 0.1 + 2 * (z - 0.1) * t
            return sum + side * side * 0.11 / 2_000
        }
        #expect(abs(volume - integrated) < 1e-9)
        #expect(session.evaluationStatus == .valid)
    }

    @Test(.timeLimit(.minutes(1)))
    func aTopMatchesAnotherObjectsTopWhereItIsShown() throws {
        let session = EditorSession()
        let short = try box(session, "Short")
        let tall = try box(session, "Tall")
        _ = try session.execute(.setSceneNodeTransform(id: tall, localTransform: try Transform3D.translation(Vector3D(x: 0.3, y: 0, z: 0.02))))
        let top = try face(of: short, in: session, normal: Vector3D(x: 0, y: 0, z: 1)) { $0.z }
        let reference = try face(of: tall, in: session, normal: Vector3D(x: 0, y: 0, z: 1)) { $0.z }
        _ = try session.execute(.matchFaces(targets: [top], reference: reference))
        // The tall box is shown 2 cm higher, so the short one's top rises to 12 cm.
        #expect(abs(try volume(session) - (0.1 * 0.1 * 0.12 + 0.1 * 0.1 * 0.1)) < 1e-12)
        #expect(session.evaluationStatus == .valid)
    }

    @Test(.timeLimit(.minutes(1)))
    func deletingAChamferWithHealingRestoresTheEdgeAndKeepsASolid() throws {
        let session = EditorSession()
        let target = try box(session, "Box")
        let edge = try #require(try TopologySnapshotService().snapshot(document: session.document).entries.first {
            // A vertical edge of the box, which Chamfer cuts through the whole height.
            $0.kind == .edge && $0.sceneNodeID == target.description
                && ($0.start?.x ?? 0) > 0.04 && ($0.end?.x ?? 0) > 0.04 && ($0.start?.y ?? 0) > 0.04 && ($0.end?.y ?? 0) > 0.04
        }?.selectionTarget())
        _ = try session.execute(.chamferBodyEdges(targets: [edge], distance: .length(0.01, .meter)))
        let chamfer = try #require(try faces(of: target, in: session).first {
            guard let n = $0.surfaceNormal else { return false }
            return abs(n.x) > 0.1 && abs(n.y) > 0.1
        }?.selectionTarget())
        _ = try session.execute(.deleteBodyFaces(targets: [chamfer], heals: true))
        #expect(abs(try volume(session) - 0.001) < 1e-12)
        #expect(session.document.productMetadata.sceneNodes[target]?.object?.geometryRole == .solid)
        #expect(session.evaluationStatus == .valid)
    }

    @Test(.timeLimit(.minutes(1)))
    func removeFilletsSharpensARoundedBox() throws {
        let session = EditorSession()
        let target = try box(session, "Box")
        let sketch = try #require(session.document.productMetadata.sceneNodes[target]?.childIDs.first)
        _ = try session.execute(.setSceneNodeObjectProperty(id: sketch, propertyID: PropertyID(rawValue: "corner.radius"), value: .length(0.01)))
        #expect(abs(try volume(session) - (0.01 - (4 - Double.pi) * 0.0001) * 0.1) < 1e-12)
        _ = try session.execute(.removeFillets(target: target, maximumRadius: .length(0.02, .meter), convexity: .convex))
        #expect(abs(try volume(session) - 0.001) < 1e-12)
        #expect(session.evaluationStatus == .valid)
    }

    @Test(.timeLimit(.minutes(1)))
    func deleteRedundantTopologyMakesASplitTopWholeAgain() throws {
        let session = EditorSession()
        let target = try box(session, "Box")
        let top = try face(of: target, in: session, normal: Vector3D(x: 0, y: 0, z: 1)) { $0.z }
        _ = try session.execute(.isoparam(name: "Isoparam", face: top, direction: .u, fractions: [0.5], subdividesControlNet: false))
        #expect(try faces(of: target, in: session).count == 7)
        _ = try session.execute(.removeRedundantTopology(targets: [target]))
        #expect(try faces(of: target, in: session).count == 6)
        #expect(abs(try volume(session) - 0.001) < 1e-12)
        #expect(session.evaluationStatus == .valid)
    }

    @Test(.timeLimit(.minutes(1)))
    func hollowOpensThroughAFaceOrClosesInsideTheSolid() throws {
        let opened = EditorSession()
        let box = try self.box(opened, "Box")
        let top = try face(of: box, in: opened, normal: Vector3D(x: 0, y: 0, z: 1)) { $0.z }
        _ = try opened.execute(.hollow(targets: [top], thickness: .length(0.01, .meter)))
        #expect(abs(try volume(opened) - (0.001 - 0.08 * 0.08 * 0.09)) < 1e-12)

        let closed = EditorSession()
        let solid = try self.box(closed, "Box")
        _ = try closed.execute(.hollow(targets: [SelectionTarget(sceneNodeID: solid)], thickness: .length(0.01, .meter)))
        #expect(abs(try volume(closed) - (0.001 - 0.08 * 0.08 * 0.08)) < 1e-12)
        #expect(closed.evaluationStatus == .valid)
    }

    @Test(.timeLimit(.minutes(1)))
    func thickenFaceMakesANewSolidBesideTheBody() throws {
        let session = EditorSession()
        let box = try self.box(session, "Box")
        let top = try face(of: box, in: session, normal: Vector3D(x: 0, y: 0, z: 1)) { $0.z }
        _ = try session.execute(.thicken(targets: [top], front: .length(0.01, .meter), back: .length(0, .meter)))
        let solids = session.document.productMetadata.sceneNodes.values.filter { $0.reference?.kind == .body && $0.object?.geometryRole == .solid }
        #expect(solids.count == 2)
        #expect(abs(try volume(session) - (0.001 + 0.1 * 0.1 * 0.01)) < 1e-12)
        #expect(session.evaluationStatus == .valid)
    }

    @Test(.timeLimit(.minutes(1)))
    func extendSheetRunsOnToAPlacedBox() throws {
        let session = EditorSession()
        _ = try session.execute(.createBSplineSurface(name: "Sheet", surface: .bilinearPatch(
            bottomLeft: .origin, bottomRight: Point3D(x: 0.1, y: 0, z: 0),
            topRight: Point3D(x: 0.1, y: 0.1, z: 0), topLeft: Point3D(x: 0, y: 0.1, z: 0))))
        let sheet = try #require(session.document.productMetadata.sceneNodes.values.first { $0.reference?.kind == .body }).id
        // A 100 mm box moved to x ∈ [150, 250] mm across the sheet's plane.
        let object = try box(session, "Box")
        _ = try session.execute(.setSceneNodeTransform(id: object, localTransform: try .translation(Vector3D(x: 0.2, y: 0.04, z: -0.05))))
        let edge = try #require(try TopologySnapshotService().snapshot(document: session.document).entries.first {
            $0.kind == .edge && $0.sceneNodeID == sheet.description && ($0.start?.x ?? 0) > 0.09 && ($0.end?.x ?? 0) > 0.09
        }?.selectionTarget())
        _ = try session.execute(.extendSheet(targets: [edge], distance: .length(0.01, .meter), shape: .natural, modifies: true,
                                             limit: SelectionTarget(sceneNodeID: object), limitMode: .minimal))
        #expect(session.evaluationStatus == .valid)
        let reach = try TopologySnapshotService().snapshot(document: session.document).entries
            .filter { $0.kind == .edge && $0.sceneNodeID == sheet.description }.compactMap { $0.end?.x }.max() ?? 0
        #expect(abs(reach - 0.15) < 1e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func extendSheetGrowsASheetInPlaceOrBesideIt() throws {
        for modifies in [true, false] {
            let session = EditorSession()
            _ = try session.execute(.createBSplineSurface(name: "Sheet", surface: .bilinearPatch(
                bottomLeft: .origin, bottomRight: Point3D(x: 0.1, y: 0, z: 0),
                topRight: Point3D(x: 0.1, y: 0.1, z: 0), topLeft: Point3D(x: 0, y: 0.1, z: 0))))
            let sheet = try #require(session.document.productMetadata.sceneNodes.values.first { $0.reference?.kind == .body }).id
            let edge = try #require(try TopologySnapshotService().snapshot(document: session.document).entries.first {
                $0.kind == .edge && $0.sceneNodeID == sheet.description && ($0.start?.x ?? 0) > 0.09 && ($0.end?.x ?? 0) > 0.09
            }?.selectionTarget())
            _ = try session.execute(.extendSheet(targets: [edge], distance: .length(0.01, .meter), shape: .natural, modifies: modifies))
            let sheets = session.document.productMetadata.sceneNodes.values.filter { $0.reference?.kind == .body && $0.object?.geometryRole == .surface }
            #expect(sheets.count == (modifies ? 1 : 2))
            let reach = try TopologySnapshotService().snapshot(document: session.document).entries
                .filter { $0.kind == .edge }.compactMap { $0.end?.x }.max() ?? 0
            #expect(abs(reach - 0.11) < 1e-9)
            #expect(session.evaluationStatus == .valid)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func alignSurfaceBringsASheetsEdgeOntoAnotherObjectsEdge() throws {
        let session = EditorSession()
        let row = { (y: Double) in [Point3D(x: 0, y: y, z: 0), Point3D(x: 0.05, y: y, z: 0.05), Point3D(x: 0.1, y: y, z: 0)] }
        _ = try session.execute(.createBSplineSurface(name: "Arch", surface: BSplineSurface3D(
            uDegree: 2, vDegree: 1, uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [row(0), row(0.1)]
        )))
        _ = try session.execute(.createBSplineSurface(name: "Flat", surface: .bilinearPatch(
            bottomLeft: Point3D(x: 0.12, y: 0, z: 0), bottomRight: Point3D(x: 0.2, y: 0, z: 0),
            topRight: Point3D(x: 0.2, y: 0.1, z: 0), topLeft: Point3D(x: 0.12, y: 0.1, z: 0))))
        let nodes = session.document.productMetadata.sceneNodes.values.filter { $0.reference?.kind == .body }
        let arch = try #require(nodes.first { $0.name.hasPrefix("Arch") }).id
        let flat = try #require(nodes.first { $0.name.hasPrefix("Flat") }).id
        func edges(atX x: Double) throws -> [TopologySummaryResult.Entry] {
            try TopologySnapshotService().snapshot(document: session.document).entries.filter {
                $0.kind == .edge && abs(($0.start?.x ?? -1) - x) < 1e-9 && abs(($0.end?.x ?? -1) - x) < 1e-9
            }
        }
        let edge = try #require(try edges(atX: 0.12).first { $0.sceneNodeID == flat.description }?.selectionTarget())
        let reference = try #require(try edges(atX: 0.1).first { $0.sceneNodeID == arch.description }?.selectionTarget())
        _ = try session.execute(.alignSurface(targets: [edge, reference], continuity: .curvature, tension: 1, blendRows: 1,
                                              boundaryFlow: .normal))
        #expect(session.evaluationStatus == .valid)
        // The flat sheet's edge now lies on the arch's, and the sheet is still one object.
        #expect(try edges(atX: 0.12).isEmpty)
        #expect(Set(try edges(atX: 0.1).map(\.sceneNodeID)) == [arch.description, flat.description])
        #expect(session.document.productMetadata.sceneNodes.values.filter { $0.reference?.kind == .body }.count == 2)
        // An edge of the sheet itself is no reference to align to.
        #expect(throws: (any Error).self) {
            _ = try session.execute(.alignSurface(targets: [edge, edge]))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aPartialAlignmentOnARefittedLayoutKeepsTheEdgesEnds() throws {
        let session = EditorSession()
        let row = { (y: Double) in [Point3D(x: 0, y: y, z: 0), Point3D(x: 0.05, y: y, z: 0.05), Point3D(x: 0.1, y: y, z: 0)] }
        _ = try session.execute(.createBSplineSurface(name: "Arch", surface: BSplineSurface3D(
            uDegree: 2, vDegree: 1, uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [row(0), row(0.1)]
        )))
        _ = try session.execute(.createBSplineSurface(name: "Flat", surface: .bilinearPatch(
            bottomLeft: Point3D(x: 0.12, y: 0, z: 0), bottomRight: Point3D(x: 0.2, y: 0, z: 0),
            topRight: Point3D(x: 0.2, y: 0.1, z: 0), topLeft: Point3D(x: 0.12, y: 0.1, z: 0))))
        let nodes = session.document.productMetadata.sceneNodes.values.filter { $0.reference?.kind == .body }
        let arch = try #require(nodes.first { $0.name.hasPrefix("Arch") }).id
        let flat = try #require(nodes.first { $0.name.hasPrefix("Flat") }).id
        func edges(atX x: Double, of node: SceneNodeID) throws -> [TopologySummaryResult.Entry] {
            try TopologySnapshotService().snapshot(document: session.document).entries.filter {
                $0.kind == .edge && $0.sceneNodeID == node.description
                    && abs(($0.start?.x ?? -1) - x) < 1e-9 && abs(($0.end?.x ?? -1) - x) < 1e-9
            }
        }
        let edge = try #require(try edges(atX: 0.12, of: flat).first?.selectionTarget())
        let reference = try #require(try edges(atX: 0.1, of: arch).first?.selectionTarget())
        _ = try session.execute(.alignSurface(
            targets: [edge, reference], continuity: .curvature, partialStart: 0.3, partialEnd: 0.3,
            layout: SurfaceControlLayout(uDegree: 3, vDegree: 3, uSpans: 4, vSpans: 8)
        ))
        #expect(session.evaluationStatus == .valid)
        // Faded out at both ends, the edge still runs between its old corners.
        #expect(try edges(atX: 0.12, of: flat).count == 1)
        #expect(throws: (any Error).self) {
            _ = try session.execute(.alignSurface(targets: [edge, reference], partialStart: 0.6, partialEnd: 0.6))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rebuildFaceRefitsASheetAndABoxsTopInPlace() throws {
        let session = EditorSession()
        _ = try session.execute(.createBSplineSurface(name: "Sheet", surface: .bilinearPatch(
            bottomLeft: .origin, bottomRight: Point3D(x: 0.1, y: 0, z: 0),
            topRight: Point3D(x: 0.1, y: 0.1, z: 0.02), topLeft: Point3D(x: 0, y: 0.1, z: 0))))
        let sheet = try #require(session.document.productMetadata.sceneNodes.values.first { $0.name.hasPrefix("Sheet") && $0.reference?.kind == .body }).id
        let sheetFace = try #require(try faces(of: sheet, in: session).first?.selectionTarget())
        _ = try session.execute(.rebuildFaces(
            targets: [sheetFace], method: .explicit(SurfaceControlLayout(uDegree: 3, vDegree: 3, uSpans: 2, vSpans: 2)), extendU: 0.2
        ))
        #expect(session.evaluationStatus == .valid)
        // Remove Nominal Surface cuts the extended sheet's surface back to its edges.
        let extendedFace = try #require(try faces(of: sheet, in: session).first?.selectionTarget())
        _ = try session.execute(.rebuildFaces(targets: [extendedFace], method: .nominal))
        #expect(session.evaluationStatus == .valid)
        let object = try box(session, "Box")
        let top = try face(of: object, in: session, normal: Vector3D(x: 0, y: 0, z: 1)) { $0.z }
        _ = try session.execute(.rebuildFaces(targets: [top], method: .tolerance(.length(0.00001, .meter))))
        #expect(session.evaluationStatus == .valid)
        #expect(try faces(of: object, in: session).count == 6)
        #expect(abs(try volume(session) - 0.1 * 0.1 * 0.1) < 1e-12)
        #expect(session.document.productMetadata.sceneNodes.values.filter { $0.reference?.kind == .body }.count == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func squareRefitsABoxsTopOnItsEdges() throws {
        let session = EditorSession()
        let object = try box(session, "Box")
        let top = try face(of: object, in: session, normal: Vector3D(x: 0, y: 0, z: 1)) { $0.z }
        _ = try session.execute(.rebuildFaces(targets: [top], method: .square(SquareRefit(options: SquareFitOptions(uDegree: 4, vDegree: 4)))))
        #expect(session.evaluationStatus == .valid)
        #expect(try faces(of: object, in: session).count == 6)
        #expect(abs(try volume(session) - 0.1 * 0.1 * 0.1) < 1e-12)
        #expect(throws: (any Error).self) {
            _ = try session.execute(.rebuildFaces(targets: [top], method: .square(SquareRefit()), extendU: 0.1))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func unwrapFaceLaysAMovedBoxsTopFlatAboutTheOrigin() throws {
        let session = EditorSession()
        let object = try box(session, "Box")
        _ = try session.execute(.setSceneNodeTransform(id: object, localTransform: try .translation(Vector3D(x: 1, y: 2, z: 3))))
        let top = try face(of: object, in: session, normal: Vector3D(x: 0, y: 0, z: 1)) { $0.z }
        _ = try session.execute(.unwrapFace(target: top))
        #expect(session.evaluationStatus == .valid)
        let flat = try #require(session.document.productMetadata.sceneNodes.values.first { $0.name.hasSuffix("Unwrap Face") }).id
        let points = try TopologySnapshotService().snapshot(document: session.document).entries
            .filter { $0.kind == .edge && $0.sceneNodeID == flat.description }.flatMap { [$0.start, $0.end] }.compactMap { $0 }
        #expect(points.isEmpty == false)
        #expect(points.allSatisfy { abs($0.z) < 1e-9 && abs($0.x) <= 0.05 + 1e-9 && abs($0.y) <= 0.05 + 1e-9 })
        #expect(abs((points.map(\.x).max() ?? 0) - (points.map(\.x).min() ?? 0) - 0.1) < 1e-9)
        // The box stays as it was, where it was.
        #expect(try faces(of: object, in: session).count == 6)
    }

    @Test(.timeLimit(.minutes(1)))
    func extrudingFacesGrowsBlocksOrTheBodyItself() throws {
        let apart = EditorSession()
        let block = try box(apart, "Box")
        let top = try face(of: block, in: apart, normal: Vector3D(x: 0, y: 0, z: 1)) { $0.z }
        _ = try apart.execute(.extrudeFaces(targets: [top], distance: .length(0.05, .meter)))
        #expect(apart.evaluationStatus == .valid)
        #expect(apart.document.productMetadata.sceneNodes.values.filter { $0.reference?.kind == .body }.count == 2)
        #expect(abs(try volume(apart) - 0.0015) < 1e-12)

        // Individual, united: the top grows up and the +X side out, each along its own normal.
        let grown = EditorSession()
        let body = try box(grown, "Box")
        let roof = try face(of: body, in: grown, normal: Vector3D(x: 0, y: 0, z: 1)) { $0.z }
        let side = try face(of: body, in: grown, normal: Vector3D(x: 1, y: 0, z: 0)) { $0.x }
        _ = try grown.execute(.extrudeFaces(targets: [roof, side], distance: .length(0.05, .meter), individual: true, operation: .union))
        #expect(grown.evaluationStatus == .valid)
        #expect(grown.document.productMetadata.sceneNodes.values.filter { $0.reference?.kind == .body }.count == 1)
        // Each face grows as it was selected, not as the other's growth left it.
        #expect(abs(try volume(grown) - 0.002) < 1e-12)

        // Direct has no one direction for faces facing different ways (Plasticity: "Can't
        // determine swept geometry"); nothing is built.
        let direct = EditorSession()
        let cube = try box(direct, "Box")
        let up = try face(of: cube, in: direct, normal: Vector3D(x: 0, y: 0, z: 1)) { $0.z }
        let out = try face(of: cube, in: direct, normal: Vector3D(x: 1, y: 0, z: 0)) { $0.x }
        #expect(throws: EditorError.self) {
            _ = try direct.execute(.extrudeFaces(targets: [up, out], distance: .length(0.05, .meter), individual: false, operation: .union))
        }
        #expect(abs(try volume(direct) - 0.001) < 1e-12)
    }
}
