import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Reverse turns a sheet over in its place, Raise Surface Degree adds control points to a B-spline
/// surface without changing its shape, Find Boundary Edges finds a sheet's open edges, and Toggle
/// Curvature saves a curvature measurement whose combs follow its curves.
@MainActor
@Suite struct OrientationDegreeAnalysisCommandTests {
    private func sheet() throws -> (EditorSession, SceneNodeID, FeatureID) {
        let session = EditorSession()
        _ = try session.execute(.createBSplineSurface(
            name: "Sheet",
            surface: BSplineSurface3D(
                uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
                controlPoints: [
                    [Point3D(x: 0, y: 0, z: 0), Point3D(x: 0.1, y: 0, z: 0)],
                    [Point3D(x: 0, y: 0.1, z: 0.02), Point3D(x: 0.1, y: 0.1, z: 0)],
                ]
            )
        ))
        let node = try #require(session.document.productMetadata.sceneNodes.values.first {
            $0.reference?.kind == .body && $0.name.hasPrefix("Sheet")
        })
        return (session, node.id, try #require(node.reference?.featureID))
    }

    private func box() throws -> (EditorSession, SceneNodeID) {
        let session = EditorSession()
        _ = try session.execute(.createExtrudedRectangle(
            name: "Box", plane: .xy,
            width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .length(0.1, .meter), direction: .normal
        ))
        let node = try #require(session.document.productMetadata.sceneNodes.values.first {
            $0.name.hasPrefix("Box") && $0.reference?.kind == .body
        })
        return (session, node.id)
    }

    private func cylinder() throws -> (EditorSession, SceneNodeID) {
        let session = EditorSession()
        _ = try session.execute(.createExtrudedCircle(
            name: "Drum", plane: .xy,
            center: SketchPoint(x: .length(0, .millimeter), y: .length(0, .millimeter)),
            radius: .length(10, .millimeter), depth: .length(20, .millimeter), direction: .normal
        ))
        let node = try #require(session.document.productMetadata.sceneNodes.values.first {
            $0.name.hasPrefix("Drum") && $0.reference?.kind == .body
        })
        return (session, node.id)
    }

    private func entries(_ kind: TopologySummaryResult.Entry.Kind, of node: SceneNodeID, in session: EditorSession) throws -> [TopologySummaryResult.Entry] {
        try TopologySnapshotService().snapshot(document: session.document).entries
            .filter { $0.kind == kind && $0.sceneNodeID == node.description }
    }

    /// The side each face of the object faces at its surface's parameter centre.
    private func facingNormals(of node: SceneNodeID, in session: EditorSession) throws -> [Vector3D] {
        let feature = try #require(session.document.productMetadata.sceneNodes[node]?.reference?.featureID)
        let evaluated = try DocumentEvaluationContextResolver().evaluatedDocument(document: session.document, failurePrefix: "test")
        guard case .body(let bodyID) = evaluated.subshapes[SubshapeID(featureID: feature, role: GeneratedSubshapeRole.body.rawValue, ordinal: 0)],
              let body = evaluated.brep.bodies[bodyID] else {
            throw EditorError(code: .referenceUnresolved, message: "No evaluated body.")
        }
        return try body.shellIDs.flatMap { evaluated.brep.shells[$0]?.faceIDs ?? [] }.map { faceID in
            let face = try #require(evaluated.brep.faces[faceID])
            let surface = try #require(evaluated.brep.geometry.surfaces[face.surfaceID])
            let normal = try surface.normal(u: 0.5, v: 0.5, tolerance: .standard)
            return face.orientation == .forward ? normal : normal * -1
        }
    }

    private func unchanged(_ session: EditorSession, since before: DesignDocument) -> Bool {
        session.document.cadDocument.designGraph == before.cadDocument.designGraph
            && session.document.productMetadata == before.productMetadata
    }

    private func resolutions(_ session: EditorSession) -> [MeasurementAnnotationResolver.Resolution] {
        MeasurementAnnotationResolver().resolveAll(in: session.document, currentEvaluation: nil, currentGeneration: nil) {
            try TopologySnapshotService().snapshot(document: session.document)
        }
    }

    // MARK: Reverse

    @Test(.timeLimit(.minutes(1)))
    func reverseTurnsASheetOverAndKeepsItsControlNet() throws {
        let (session, node, source) = try sheet()
        let before = try facingNormals(of: node, in: session)
        _ = try session.execute(.reverseSheets(name: "Reverse", targets: [SelectionTarget(sceneNodeID: node)]))
        let object = try #require(session.document.productMetadata.sceneNodes[node])
        let reversed = try #require(object.reference?.featureID)
        #expect(reversed != source)
        #expect(object.name == "Sheet")
        #expect(object.object?.geometryRole == .surface)
        let after = try facingNormals(of: node, in: session)
        #expect(before.count == 1 && after.count == 1)
        #expect(before[0].dot(after[0]) < -0.999)
        // Its control points stay editable on the surface it was turned over from.
        #expect(session.document.surfaceControlSourceFeatureID(for: reversed) == source)
        #expect(session.evaluationStatus == .valid)
    }

    @Test(.timeLimit(.minutes(1)))
    func reverseRefusesASolid() throws {
        let (session, box) = try box()
        let before = session.document
        #expect(throws: EditorError.self) {
            _ = try session.execute(.reverseSheets(name: "Reverse", targets: [SelectionTarget(sceneNodeID: box)]))
        }
        #expect(unchanged(session, since: before))
    }

    // MARK: Raise Surface Degree

    @Test(.timeLimit(.minutes(1)))
    func raiseSurfaceDegreeAddsControlPointsWithoutChangingTheShape() throws {
        let (session, node, source) = try sheet()
        guard case .bSplineSurface(let original) = session.document.cadDocument.designGraph.nodes[source]?.operation else {
            Issue.record("Expected the sheet's surface.")
            return
        }
        let face = try #require(try entries(.face, of: node, in: session).first?.selectionTarget())
        _ = try session.execute(.raiseSurfaceDegree(targets: [face, SelectionTarget(sceneNodeID: node)]))
        guard case .bSplineSurface(let raised) = session.document.cadDocument.designGraph.nodes[source]?.operation else {
            Issue.record("Expected the raised surface.")
            return
        }
        // Raised once, though two targets name it.
        #expect(raised.surface.uDegree == 2 && raised.surface.vDegree == 2)
        #expect(raised.surface.uControlPointCount == 3 && raised.surface.vControlPointCount == 3)
        for (u, v) in [(0.0, 0.0), (0.3, 0.7), (1.0, 0.5)] {
            let a = try original.surface.point(u: u, v: v, tolerance: .standard)
            let b = try raised.surface.point(u: u, v: v, tolerance: .standard)
            #expect((a - b).length < 1e-12)
        }
        #expect(session.document.productMetadata.sceneNodes[node]?.object?.properties["surface.degree.u"] == .integer(2))
        #expect(session.evaluationStatus == .valid)
    }

    @Test(.timeLimit(.minutes(1)))
    func raiseSurfaceDegreeGivesAFaceOfASolidControlPointsAndRaisesThemAgain() throws {
        // Plasticity's Shift+S on a box's face: its corners become control points, raised to a 3×3
        // net, then 4×4 on the same face, the box keeping its shape.
        let (session, box) = try box()
        let volume = try MeasurementService().measure(document: session.document, ruler: .standard(for: .meter)).totals.solidVolumeCubicMeters
        let face = try #require(try entries(.face, of: box, in: session).first?.selectionTarget())
        _ = try session.execute(.raiseSurfaceDegree(targets: [face]))
        func givenSurface() throws -> (BSplineSurface3D, SelectionTarget) {
            let feature = try #require(session.document.productMetadata.sceneNodes[box]?.reference?.featureID)
            guard case .faceRebuild(let rebuild)? = session.document.cadDocument.designGraph.nodes[feature]?.operation,
                  case .given(let surface) = rebuild.method else {
                throw EditorError(code: .referenceUnresolved, message: "The box shows no face given a surface.")
            }
            let evaluated = try DocumentEvaluationContextResolver().evaluatedDocument(document: session.document, failurePrefix: "test")
            let keys = evaluated.subshapes.entries.compactMap { key, value -> String? in
                guard key.featureID == feature, case .face(let id) = value, let face = evaluated.brep.faces[id],
                      case .bSpline? = evaluated.brep.geometry.surfaces[face.surfaceID] else { return nil }
                return GeneratedSubshapeIdentity.string(for: key)
            }
            let target = try #require(try entries(.face, of: box, in: session).first { keys.contains($0.subshapeID) }?.selectionTarget())
            return (surface, target)
        }
        let (first, raisedFace) = try givenSurface()
        #expect(first.uDegree == 2 && first.vDegree == 2 && first.controlPoints.joined().count == 9)
        _ = try session.execute(.raiseSurfaceDegree(targets: [raisedFace]))
        let (second, _) = try givenSurface()
        #expect(second.uDegree == 3 && second.vDegree == 3 && second.controlPoints.joined().count == 16)
        let raisedVolume = try MeasurementService().measure(document: session.document, ruler: .standard(for: .meter)).totals.solidVolumeCubicMeters
        #expect(abs(raisedVolume - volume) < 1e-12)
        #expect(session.evaluationStatus == .valid)
        // A cylinder's side is not given control points.
        let (drumSession, drum) = try cylinder()
        let sides = try entries(.face, of: drum, in: drumSession).filter { $0.surfaceKind == "cylinder" }
        let side = try #require(sides.first?.selectionTarget())
        let drumBefore = drumSession.document
        #expect(throws: EditorError.self) { _ = try drumSession.execute(.raiseSurfaceDegree(targets: [side])) }
        #expect(unchanged(drumSession, since: drumBefore))
    }

    @Test(.timeLimit(.minutes(2)))
    func raiseSurfaceDegreeOnASolidRaisesEveryFaceAndThenRaisesThemAgain() throws {
        // Plasticity's page: Shift+S on a solid gives every face control points; again raises them.
        let (session, box) = try box()
        let volume = try MeasurementService().measure(document: session.document, ruler: .standard(for: .meter)).totals.solidVolumeCubicMeters
        func givenDegrees() -> [Int] {
            session.document.cadDocument.designGraph.nodes.values.compactMap { node -> Int? in
                guard case .faceRebuild(let rebuild) = node.operation, case .given(let surface) = rebuild.method else { return nil }
                return surface.uDegree
            }
        }
        _ = try session.execute(.raiseSurfaceDegree(targets: [SelectionTarget(sceneNodeID: box)]))
        #expect(givenDegrees().sorted() == Array(repeating: 2, count: 6))
        #expect(session.evaluationStatus == .valid)
        _ = try session.execute(.raiseSurfaceDegree(targets: [SelectionTarget(sceneNodeID: box)]))
        #expect(givenDegrees().sorted() == Array(repeating: 3, count: 6))
        let raised = try MeasurementService().measure(document: session.document, ruler: .standard(for: .meter)).totals.solidVolumeCubicMeters
        #expect(abs(raised - volume) < 1e-12)
        #expect(session.evaluationStatus == .valid)
    }

    @Test(.timeLimit(.minutes(2)))
    func aRaisedFaceOfASolidShowsAndMovesItsControlPoints() throws {
        // Plasticity's video: the raised face's control points are listed and moved; the middle one
        // pushed 5 mm out bulges the face, the box closed by its own edges: d · area / 9 more.
        let (session, box) = try box()
        let volume = try MeasurementService().measure(document: session.document, ruler: .standard(for: .meter)).totals.solidVolumeCubicMeters
        let entry = try #require(try entries(.face, of: box, in: session).first)
        let face = try #require(entry.selectionTarget())
        let normal = try #require(entry.normal)
        _ = try session.execute(.raiseSurfaceDegree(targets: [face]))
        let feature = try #require(session.document.productMetadata.sceneNodes[box]?.reference?.featureID)
        guard case .faceRebuild(let rebuild)? = session.document.cadDocument.designGraph.nodes[feature]?.operation else {
            Issue.record("The box shows no Raise Degree.")
            return
        }
        let summary = try SurfaceSourceSummaryService().summarize(document: session.document, displayUnit: .meter)
        let source = try #require(summary.sources.first { $0.featureID == feature.description })
        #expect(source.patches.first?.controlPoints.count == 9)
        let middle = SelectionReference.surface(.controlPoint(SurfaceControlPointReference(
            surface: SurfaceReference(subshape: rebuild.faces[0]), uIndex: 1, vIndex: 1
        )))
        let d = 0.005
        _ = try session.execute(.moveSurfaceControlPoint(
            target: middle, deltaX: .length(normal.x * d, .meter), deltaY: .length(normal.y * d, .meter), deltaZ: .length(normal.z * d, .meter)
        ))
        #expect(session.evaluationStatus == .valid)
        let moved = try MeasurementService().measure(document: session.document, ruler: .standard(for: .meter)).totals.solidVolumeCubicMeters
        #expect(abs(moved - (volume + d * 0.1 * 0.1 / 9)) < 1e-9, "\(moved) vs \(volume + d * 0.1 * 0.1 / 9)")
        // A control point the face does not have is refused.
        let missing = SelectionReference.surface(.controlPoint(SurfaceControlPointReference(
            surface: SurfaceReference(subshape: rebuild.faces[0]), uIndex: 3, vIndex: 0
        )))
        #expect(throws: EditorError.self) {
            _ = try session.execute(.moveSurfaceControlPoint(target: missing, deltaX: .length(0.001, .meter), deltaY: .length(0, .meter), deltaZ: .length(0, .meter)))
        }
    }

    // MARK: Find Boundary Edges

    @Test(.timeLimit(.minutes(1)))
    func findBoundaryEdgesSelectsASheetsOpenEdgesAndNoneOfASolid() throws {
        let (session, node, _) = try sheet()
        let edges = try BoundaryEdgeSelectionService().boundaryEdges(of: [SelectionTarget(sceneNodeID: node)], in: session.document)
        #expect(edges.count == 4)
        #expect(edges.allSatisfy { if case .edge = $0.component { $0.sceneNodeID == node } else { false } })

        let (solidSession, box) = try box()
        #expect(try BoundaryEdgeSelectionService().boundaryEdges(of: [SelectionTarget(sceneNodeID: box)], in: solidSession.document).isEmpty)
        // Without its top, the box's other five faces stay one sheet whose opening is the rim.
        let top = try #require(try entries(.face, of: box, in: solidSession).first {
            ($0.center?.z ?? 0) > 0.05 && abs($0.surfaceNormal?.z ?? 0) > 0.5
        }?.selectionTarget())
        _ = try solidSession.execute(.unjoinFaces(name: "Unjoin", targets: [top]))
        let open = try #require(solidSession.document.productMetadata.sceneNodes.values.first { node in
            node.reference?.kind == .body && ((try? self.entries(.face, of: node.id, in: solidSession).count) ?? 0) == 5
        })
        #expect(try BoundaryEdgeSelectionService().boundaryEdges(of: [SelectionTarget(sceneNodeID: open.id)], in: solidSession.document).count == 4)
    }

    // MARK: Toggle Curvature

    @Test(.timeLimit(.minutes(1)))
    func toggleCurvatureCombsAnEdgeWhereItIsShownAndTogglesOff() throws {
        let (session, drum) = try cylinder()
        let rim = try #require(try entries(.edge, of: drum, in: session).first { abs(($0.curveRadius ?? 0) - 0.01) < 1e-9 })
        let target = try #require(rim.selectionTarget())
        _ = try session.execute(.toggleCurvatureMeasurement(targets: [target]))
        let measurement = try #require(session.document.productMetadata.measurements.values.first)
        #expect(measurement.kind == .curvature)
        #expect(measurement.combScale == DesignDocument.defaultCurvatureCombScale)
        let group = try #require(session.document.productMetadata.sceneNodes.values.first { $0.name == DesignDocument.measurementsGroupName })
        #expect(group.childIDs.contains(try #require(measurement.sceneNodeID)))
        guard case .combed(let combs) = try #require(resolutions(session).first).outcome else {
            Issue.record("A curvature measurement resolves to combs.")
            return
        }
        #expect(combs.count == 1)
        let samples = try #require(combs.first).samples
        #expect(samples.count >= 32)
        // A circle of radius 10 mm bends by 100 per metre everywhere, toward its centre.
        #expect(samples.allSatisfy { abs($0.curvature - 100) < 1e-6 })
        #expect(samples.allSatisfy { sample in
            let radial = Vector3D(x: sample.point.x, y: sample.point.y, z: 0)
            return abs(radial.length - 0.01) < 1e-9 && abs(sample.normal.dot(radial) / 0.01 + 1) < 1e-9
        })

        // Moved, the comb follows the drum.
        let away = try Transform3D.translation(Vector3D(x: 0.5, y: 0, z: 0))
        _ = try session.execute(.setSceneNodeTransform(id: drum, localTransform: away))
        guard case .combed(let moved) = try #require(resolutions(session).first).outcome else {
            Issue.record("The moved measurement still resolves to combs.")
            return
        }
        #expect(zip(samples, try #require(moved.first).samples).allSatisfy { abs($1.point.x - $0.point.x - 0.5) < 1e-9 })

        // The same curves again take it away, and Undo brings it back.
        _ = try session.execute(.toggleCurvatureMeasurement(targets: [target]))
        #expect(session.document.productMetadata.measurements.isEmpty)
        _ = try session.undo()
        #expect(session.document.productMetadata.measurements.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func toggleCurvatureAddsOneMeasurementPerCurveAndTogglesEachOnItsOwn() throws {
        let session = EditorSession()
        for x in [0.0, 20.0] {
            _ = try session.execute(.createCircleSketch(
                name: "Circle", plane: .xy,
                center: SketchPoint(x: .length(x, .millimeter), y: .length(0, .millimeter)),
                radius: .length(5, .millimeter)
            ))
        }
        let circles = try SketchEntitySnapshotService().snapshot(document: session.document).entries.filter { $0.entityKind == "circle" }
        #expect(circles.count == 2)
        let targets = try circles.map { try #require($0.selectionTarget()) }
        _ = try session.execute(.toggleCurvatureMeasurement(targets: targets))
        #expect(session.document.productMetadata.measurements.count == 2)
        #expect(session.document.productMetadata.measurements.values.allSatisfy { $0.anchors.count == 1 })
        // One circle again takes its own measurement away and leaves the other.
        _ = try session.execute(.toggleCurvatureMeasurement(targets: [targets[0]]))
        #expect(session.document.productMetadata.measurements.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func toggleCurvatureCombsASketchCurveAndStraightEdgesHaveNoComb() throws {
        let session = EditorSession()
        _ = try session.execute(.createCircleSketch(
            name: "Circle", plane: .xy,
            center: SketchPoint(x: .length(0, .millimeter), y: .length(0, .millimeter)),
            radius: .length(5, .millimeter)
        ))
        let circle = try #require(try SketchEntitySnapshotService().snapshot(document: session.document).entries.first { $0.entityKind == "circle" })
        _ = try session.execute(.toggleCurvatureMeasurement(targets: [try #require(circle.selectionTarget())]))
        guard case .combed(let combs) = try #require(resolutions(session).first).outcome else {
            Issue.record("A curvature measurement resolves to combs.")
            return
        }
        #expect(combs.count == 1)
        #expect(try #require(combs.first).samples.allSatisfy { abs($0.curvature - 200) < 1e-6 })

        let (boxSession, box) = try box()
        let edge = try #require(try entries(.edge, of: box, in: boxSession).first?.selectionTarget())
        _ = try boxSession.execute(.toggleCurvatureMeasurement(targets: [edge]))
        guard case .combed(let straight) = try #require(resolutions(boxSession).first).outcome else {
            Issue.record("A curvature measurement resolves to combs.")
            return
        }
        #expect(straight.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func combScaleIsOnePositiveSettingOfEveryCurvatureMeasurement() throws {
        // Plasticity's Curvature panel: one Comb scale rescales every comb, and a new one takes it.
        let (session, drum) = try cylinder()
        let rims = try entries(.edge, of: drum, in: session).filter { ($0.curveRadius ?? 0) > 0 }.compactMap { $0.selectionTarget() }
        #expect(rims.count >= 2)
        _ = try session.execute(.toggleCurvatureMeasurement(targets: [rims[0]]))
        _ = try session.execute(.setCurvatureCombScale(combScale: 0.3))
        _ = try session.execute(.toggleCurvatureMeasurement(targets: [rims[1]]))
        let scales = session.document.productMetadata.measurements.values.filter { $0.kind == .curvature }.map(\.combScale)
        #expect(scales == [0.3, 0.3])
        _ = try session.execute(.setCurvatureCombScale(combScale: 0.12))
        #expect(session.document.productMetadata.measurements.values.allSatisfy { $0.combScale == 0.12 })
        #expect(session.document.curvatureCombScale == 0.12)
        let before = session.document
        #expect(throws: EditorError.self) {
            _ = try session.execute(.setCurvatureCombScale(combScale: 0))
        }
        #expect(unchanged(session, since: before))
        // A face is not a curve to comb.
        let face = try #require(try entries(.face, of: drum, in: session).first?.selectionTarget())
        #expect(throws: EditorError.self) {
            _ = try session.execute(.toggleCurvatureMeasurement(targets: [face]))
        }
        #expect(unchanged(session, since: before))
    }
}
