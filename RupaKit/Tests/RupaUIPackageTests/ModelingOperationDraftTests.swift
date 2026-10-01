import Testing
import RupaCore
import SwiftCAD
@testable import RupaUI

@Suite("Modeling operation drafts", .timeLimit(.minutes(1)))
struct ModelingOperationDraftTests {
    @Test(arguments: [ModelingOperationDraft.Kind.extrude, .revolve, .loft])
    func surfaceCreationAcceptsWholeOpenCurveSelection(kind: ModelingOperationDraft.Kind) throws {
        var document = DesignDocument.empty()
        let source = try document.createLineSketch(name: "Open section", plane: .xy,
            start: SketchPoint(x: .length(0.02, .meter), y: .length(0, .meter)),
            end: SketchPoint(x: .length(0.02, .meter), y: .length(0.04, .meter)))
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(source) })
        var targets = [SelectionTarget(sceneNodeID: node.id)]
        if kind == .loft {
            let second = try document.createLineSketch(name: "Second section",
                plane: .plane(Plane3D(origin: Point3D(x: 0, y: 0, z: 0.02), normal: .unitZ)),
                start: SketchPoint(x: .length(0.02, .meter), y: .length(0, .meter)),
                end: SketchPoint(x: .length(0.02, .meter), y: .length(0.04, .meter)))
            let secondNode = try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(second) })
            targets.append(SelectionTarget(sceneNodeID: secondNode.id))
        }
        var draft = makeDraft(kind, targets: targets)
        draft.isSurfaceCreation = true
        draft.distance = "10 mm"
        draft.angle = "180"
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let result = try DocumentEvaluator.modelingDefault(for: store.document).evaluateExact(store.document.cadDocument)
        #expect(result.brep.faces.count == (kind == .revolve ? 2 : 1))
        #expect(result.brep.bodies.values.allSatisfy { $0.kind == .sheet })
        draft.isSurfaceCreation = false
        if kind == .revolve {
            // A revolved curve may ask for a solid; the kernel closes it along the axis or reports
            // the evaluation invalid.
            guard case .revolveSection(_, _, _, _, .solid, _, _, _, _) = try draft.command(in: document) else {
                Issue.record("A solid revolve of a curve is one revolve.")
                return
            }
        } else {
            #expect(throws: EditorError.self) { try draft.command(in: document) }
        }
    }

    @Test(arguments: [ModelingOperationDraft.Kind.extrude, .sweep, .loft])
    func surfaceCreationBuildsActualSheets(kind: ModelingOperationDraft.Kind) throws {
        var document = DesignDocument.empty()
        let first = try addProfile(to: &document, z: 0)
        var targets = [first.target]
        if kind == .loft {
            targets.append(try addProfile(to: &document, z: 0.02).target)
        } else if kind == .sweep {
            let path = try document.createLineSketch(name: "Path", plane: .yz,
                start: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
                end: SketchPoint(x: .length(0, .meter), y: .length(0.02, .meter)))
            let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(path) })
            targets.append(.init(sceneNodeID: node.id))
        }
        var draft = makeDraft(.surfacePatch, targets: targets)
        draft.selectSurfaceOperation(kind)
        draft.distance = "20 mm"
        #expect(draft.name == kind.rawValue)
        #expect(draft.createsSheet)
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let result = try DocumentEvaluator.modelingDefault(for: store.document).evaluateExact(store.document.cadDocument)
        try result.brep.validate(level: .exact, tolerance: document.modelingSettings.tolerance)
        #expect(result.brep.bodies.count == 1)
        #expect(result.brep.bodies.values.allSatisfy { $0.kind == .sheet })
        #expect(result.brep.faces.count == 4)
        #expect(document.cadDocument.designGraph.order.allSatisfy {
            document.cadDocument.designGraph.nodes[$0] == store.document.cadDocument.designGraph.nodes[$0]
        })
        if kind == .sweep {
            draft.targets.insert(try addProfile(to: &document, z: 0.01).target, at: 1)
            #expect(throws: EditorError.self) { try draft.command(in: document) }
        }
        draft.reverseSecondBoundary = true
        draft.selectSurfaceOperation(.patch)
        #expect(!draft.reverseSecondBoundary)
        // Curve sources make Patch span them as closed curves.
        guard case .createCurvePatch = try draft.command(in: document) else {
            Issue.record("Patch over curve sources spans them as closed curves.")
            return
        }
        draft.kind = .box
        #expect(throws: EditorError.self) { try draft.command(in: document) }
    }

    @Test func topologyAmountsRetainParameterExpressions() throws {
        var document = DesignDocument.empty()
        let body = try addBody(to: &document)
        try document.upsertParameter(name: "wall_thickness", expression: .length(0.0002, .meter), kind: .length)
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        let face = try #require(topology.entries.first { $0.kind == .face }?.selectionTarget())
        let edge = try #require(topology.entries.first { $0.kind == .edge }?.selectionTarget())
        let expression = try ParameterExpressionParser().parse("wall_thickness * 2",
            parameters: document.cadDocument.parameters, targetKind: .length)
        for kind in [ModelingOperationDraft.Kind.shell, .fillet, .chamfer, .g2Blend] {
            var draft = makeDraft(kind, targets: [kind == .shell ? face : edge])
            draft.distance = "wall_thickness * 2"
            let command = try draft.command(in: document)
            switch kind {
            case .shell: #expect(command == .createBodyShell(name: draft.name, target: face, thickness: expression))
            case .fillet: #expect(command == .createBodyEdgeTreatment(name: draft.name, target: edge, treatment: .fillet(radius: expression)))
            case .chamfer: #expect(command == .createBodyEdgeTreatment(name: draft.name, target: edge, treatment: .chamfer(distance: expression)))
            default: #expect(command == .createBodyEdgeTreatment(name: draft.name, target: edge, treatment: .g2Blend(distance: expression)))
            }
            // A negative Fillet distance chamfers instead (Fillet Shell); elsewhere it is invalid.
            for invalid in ["missingParameter", "wall_thickness / 0", "2 deg"] + (kind == .fillet ? [] : ["-wall_thickness"]) {
                draft.distance = invalid
                #expect(throws: (any Error).self) { try draft.command(in: document) }
            }
            if kind == .fillet {
                draft.distance = "-wall_thickness"
                let negative = try draft.command(in: document)
                guard case .createBodyEdgeTreatment(_, _, .chamfer) = negative else {
                    Issue.record("A negative fillet distance chamfers.")
                    continue
                }
            }
        }
        #expect(document.productMetadata.sceneNodes[body.sceneNodeID] != nil)
    }

    @Test func shellDraftUsesSelectedOpeningAndPhysicalThickness() throws {
        let session = EditorSession()
        _ = try #require(session.createDefaultExtrudedRectangle())
        let topology = try TopologySnapshotService().snapshot(document: session.document, metricPolicy: .omit)
        let face = try #require(topology.entries.first { $0.kind == .face }?.selectionTarget())
        var draft = makeDraft(.shell, targets: [face])
        draft.distance = "2 mm"
        #expect(try draft.command(in: session.document) == .createBodyShell(
            name: "Shell", target: face, thickness: .length(0.002, .meter)))
        draft.distance = "0"
        #expect(throws: EditorError.self) { try draft.command(in: session.document) }
        draft.distance = "2 mm"
        draft.targets = [.init(sceneNodeID: face.sceneNodeID)]
        #expect(throws: EditorError.self) { try draft.command(in: session.document) }
    }

    @Test func doubleHelicalDraftRetainsAngleLawAndExplicitAllowance() throws {
        var document = DesignDocument.empty()
        let profile = try addProfile(to: &document, z: 0)
        let path = try document.createLineSketch(name: "Path", plane: .yz,
            start: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            end: SketchPoint(x: .length(0, .meter), y: .length(0.03, .meter)))
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(path) })
        var draft = makeDraft(.sweep, targets: [profile.target, .init(sceneNodeID: node.id)])
        draft.doubleHelical = true
        draft.twistAngle = "30"
        #expect(throws: EditorError.self) { try draft.command(in: document) }
        draft.approximationTolerance = "0.001 mm"
        guard case .createSweep(_, _, _, _, _, let options, _) = try draft.command(in: document) else {
            Issue.record("Expected native Sweep source intent.")
            return
        }
        #expect(options.twistAngle == .angle(0, .degree))
        #expect(options.approximationTolerance == .length(0.000001, .meter))
        #expect(options.twistLaw == [
            .init(position: 0, angle: .angle(0, .degree)),
            .init(position: 0.5, angle: .angle(30, .degree)),
            .init(position: 1, angle: .angle(0, .degree))
        ])
    }

    @Test func aNormalSweepFollowsACurvedPathWithinItsAllowance() throws {
        var document = DesignDocument.empty()
        let circle = try document.createCircleSketch(name: "Section", plane: .xy,
            center: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)), radius: .length(0.003, .meter))
        // A planar cubic in the ZX plane leaving the origin along +Z (sketch x is world z).
        let controls: [(Double, Double)] = [(0, 0), (0.02, 0), (0.04, 0.01), (0.05, 0.03)]
        let path = try document.createSplineSketch(name: "Path", plane: .zx, spline: SketchSpline(controlPoints: controls.map {
            SketchPoint(x: .length($0.0, .meter), y: .length($0.1, .meter))
        }))
        let circleNode = try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(circle) })
        let pathNode = try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(path) })
        var draft = makeDraft(.sweep, targets: [.init(sceneNodeID: circleNode.id), .init(sceneNodeID: pathNode.id)])
        draft.approximationTolerance = "0.0001 mm"
        guard case .createSweep(_, _, _, _, _, let options, _) = try draft.command(in: document) else {
            Issue.record("Expected native Sweep source intent.")
            return
        }
        #expect(options.alignment == .normal && options.approximationTolerance == .length(1e-7, .meter))
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        #expect(store.evaluationStatus == .valid)
        // Pappus: the circle's area times the path's length, within the allowance over the side.
        let nodes = [-0.906179845938664, -0.5384693101056831, 0, 0.5384693101056831, 0.906179845938664]
        let weights = [0.2369268850561891, 0.4786286704993665, 0.5688888888888889, 0.4786286704993665, 0.2369268850561891]
        func speed(_ t: Double) -> Double {
            let a = 3 * (1 - t) * (1 - t), b = 6 * (1 - t) * t, c = 3 * t * t
            let dz = a * (controls[1].0 - controls[0].0) + b * (controls[2].0 - controls[1].0) + c * (controls[3].0 - controls[2].0)
            let dx = a * (controls[1].1 - controls[0].1) + b * (controls[2].1 - controls[1].1) + c * (controls[3].1 - controls[2].1)
            return (dz * dz + dx * dx).squareRoot()
        }
        let length = (0..<256).reduce(0.0) { sum, index in
            let lower = Double(index) / 256, half = 0.5 / 256
            return sum + zip(nodes, weights).reduce(0.0) { $0 + $1.1 * speed(lower + half * (1 + $1.0)) } * half
        }
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        let exact = Double.pi * 0.003 * 0.003 * length
        #expect(abs(measurement.totals.solidVolumeCubicMeters - exact) <= 2 * Double.pi * 0.003 * length * 1e-7 + 1e-12)
        // Without the allowance the curved Normal sweep is refused; Parallel keeps the section's
        // orientation instead.
        draft.approximationTolerance = ""
        let refused = CADDocumentStore(document: document)
        #expect(throws: EditorError.self) { _ = try refused.apply(draft.command(in: document)) }
        draft.sweepAlignment = .parallel
        guard case .createSweep(_, _, _, _, _, let parallel, _) = try draft.command(in: document) else {
            Issue.record("Expected native Sweep source intent.")
            return
        }
        #expect(parallel.alignment == .parallel && parallel.approximationTolerance == nil)
    }

    @Test func aFaceSweepsIntoABlockOrGrowsItsBody() throws {
        var document = DesignDocument.empty()
        let box = try document.createExtrudedRectangleFromCorners(
            name: "Box", plane: .xy,
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
            depth: .length(0.02, .meter), direction: .normal
        )
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        let top = try #require(topology.entries.first { entry in
            entry.kind == .face && (entry.surfaceNormal.map { $0.z > 0.99 } ?? false)
        }?.selectionTarget())
        // A straight path up from the top face's middle (sketch x is world z, sketch y world x).
        let path = try document.createLineSketch(name: "Path", plane: .zx,
            start: SketchPoint(x: .length(0.02, .meter), y: .length(0.01, .meter)),
            end: SketchPoint(x: .length(0.05, .meter), y: .length(0.01, .meter)))
        let pathNode = try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(path) })
        var draft = makeDraft(.sweep, targets: [top, .init(sceneNodeID: pathNode.id)])
        guard case .createSweep(_, let sections, _, _, let targets, _, _) = try draft.command(in: document) else {
            Issue.record("Expected native Sweep source intent.")
            return
        }
        guard case .face(let face) = sections.first else {
            Issue.record("A selected face sweeps as a face section.")
            return
        }
        #expect(face.featureID == box && targets.isEmpty)
        let apart = CADDocumentStore(document: document)
        _ = try apart.apply(draft.command(in: document))
        let separate = try MeasurementService().measure(document: apart.document, ruler: .standard(for: .meter))
        #expect(abs(separate.totals.solidVolumeCubicMeters - (0.02 * 0.02 * 0.02 + 0.02 * 0.02 * 0.03)) < 1e-12)

        draft.solidBoolean = .union
        guard case .createSweep(_, _, _, _, let grownTargets, let options, _) = try draft.command(in: document) else {
            Issue.record("Expected native Sweep source intent.")
            return
        }
        #expect(grownTargets == [SweepTargetReference(featureID: box)] && options.booleanOperation == .union)
        let grown = CADDocumentStore(document: document)
        _ = try grown.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: grown.document, ruler: .standard(for: .meter))
        #expect(measurement.counts.solids == 1)
        #expect(abs(measurement.totals.solidVolumeCubicMeters - 0.02 * 0.02 * 0.05) < 1e-12)
    }

    @Test func aPipeFollowsEachCurveAndCombinesWithBodies() throws {
        var document = DesignDocument.empty()
        // Two 50 mm lines up the Z axis (sketch x is world z on the ZX plane).
        let paths = try [0.0, 0.03].map { x in
            try document.createLineSketch(name: "Path", plane: .zx,
                start: SketchPoint(x: .length(0, .meter), y: .length(x, .meter)),
                end: SketchPoint(x: .length(0.05, .meter), y: .length(x, .meter)))
        }
        let nodes = try paths.map { path in try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(path) }) }
        var draft = makeDraft(.pipe, targets: nodes.map { .init(sceneNodeID: $0.id) })
        draft.pipeDiameter = "10 mm"
        draft.wallThickness = "1 mm"
        guard case .createPipes(_, let sources, _) = try draft.command(in: document) else {
            Issue.record("Expected native Pipe source intent.")
            return
        }
        #expect(sources.map(\.path.featureID) == paths && sources.allSatisfy { $0.thickness == .length(0.001, .meter) })
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        #expect(measurement.counts.solids == 2)
        #expect(abs(measurement.totals.solidVolumeCubicMeters - 2 * Double.pi * (0.005 * 0.005 - 0.004 * 0.004) * 0.05) < 1e-12)

        draft.pipeVertices = "2"
        #expect(throws: EditorError.self) { try draft.command(in: document) }
        draft.pipeVertices = "0"
        draft.solidBoolean = .union
        #expect(throws: EditorError.self) { try draft.command(in: document) }
    }

    @Test func aPipeCarriesACustomProfileAlongEachCurve() throws {
        var document = DesignDocument.empty()
        // A 4 mm square drawn away from the path, then a 50 mm line up the Z axis.
        let square = try document.createRectangleSketchFromCorners(
            name: "Profile", plane: .xy,
            firstCorner: SketchPoint(x: .length(0.03, .meter), y: .length(0.03, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.034, .meter), y: .length(0.034, .meter))
        )
        let path = try document.createLineSketch(name: "Path", plane: .zx,
            start: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            end: SketchPoint(x: .length(0.05, .meter), y: .length(0, .meter)))
        let nodes = try [square, path].map { feature in
            try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(feature) })
        }
        var draft = makeDraft(.pipe, targets: nodes.map { .init(sceneNodeID: $0.id) })
        draft.pipeCustomProfile = true
        draft.wallThickness = "1 mm"
        guard case .createPipes(_, let sources, _) = try draft.command(in: document) else {
            Issue.record("Expected native Pipe source intent.")
            return
        }
        #expect(sources.count == 1 && sources[0].path.featureID == path && sources[0].diameter == nil
            && sources[0].profile?.featureID == square)
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        #expect(measurement.counts.solids == 1)
        #expect(abs(measurement.totals.solidVolumeCubicMeters - (0.004 * 0.004 - 0.002 * 0.002) * 0.05) < 1e-12)

        // Without a curve after it, the profile leaves no path.
        draft.targets = [.init(sceneNodeID: nodes[0].id)]
        #expect(throws: EditorError.self) { try draft.command(in: document) }
    }

    @Test func aPipeFollowsAnEdgeOfABody() throws {
        var document = DesignDocument.empty()
        let box = try document.createExtrudedRectangleFromCorners(
            name: "Box", plane: .xy,
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
            depth: .length(0.02, .meter), direction: .normal
        )
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        // A top edge along X, at y = 0 and z = 20 mm.
        let edge = try #require(topology.entries.first { entry in
            guard entry.kind == .edge, let start = entry.start, let end = entry.end else { return false }
            return abs(start.z - 0.02) < 1e-9 && abs(end.z - 0.02) < 1e-9 && abs(start.y) < 1e-9 && abs(end.y) < 1e-9
        }?.selectionTarget())
        var draft = makeDraft(.pipe, targets: [edge])
        draft.pipeDiameter = "4 mm"
        guard case .createPipes(_, let sources, let edgeCurves) = try draft.command(in: document) else {
            Issue.record("Expected native Pipe source intent.")
            return
        }
        #expect(edgeCurves.count == 1 && edgeCurves[0].feature.source == box && sources.map(\.path.featureID) == [edgeCurves[0].id])
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        #expect(abs(measurement.totals.solidVolumeCubicMeters - (0.02 * 0.02 * 0.02 + Double.pi * 0.002 * 0.002 * 0.02)) < 1e-12)

        // Along its edge, a Boolean pipe combines with the edge's own body.
        draft.solidBoolean = .union
        guard case .createPipes(_, let combined, _) = try draft.command(in: document) else {
            Issue.record("Expected native Pipe source intent.")
            return
        }
        #expect(combined.first?.targets == [SweepTargetReference(featureID: box)])
    }

    @Test func aSquareSweepsAroundARectangularFrame() throws {
        var document = DesignDocument.empty()
        let square = try document.createRectangleSketchFromCorners(
            name: "Section", plane: .xy,
            firstCorner: SketchPoint(x: .length(-0.002, .meter), y: .length(-0.002, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.002, .meter), y: .length(0.002, .meter))
        )
        // A 40 × 30 mm frame in the ZX plane with a corner at the origin (sketch x is world z).
        let frame = try document.createRectangleSketchFromCorners(
            name: "Frame", plane: .zx,
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.04, .meter), y: .length(0.03, .meter))
        )
        let nodes = try [square, frame].map { id in try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(id) }) }
        var draft = makeDraft(.sweep, targets: nodes.map { .init(sceneNodeID: $0.id) })
        guard case .createSweep(_, let sections, let path, _, _, _, _) = try draft.command(in: document) else {
            Issue.record("Expected native Sweep source intent.")
            return
        }
        #expect(sections.map(\.featureID) == [square] && path.featureID == frame)
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        #expect(abs(measurement.totals.solidVolumeCubicMeters - 0.004 * 0.004 * 0.14) < 1e-12)

        // Round corners round each outer corner by half the section's width and keep the inner
        // ones mitred.
        draft.sweepCorners = .round
        guard case .createSweep(_, _, _, _, _, let options, _) = try draft.command(in: document) else {
            Issue.record("Expected native Sweep source intent.")
            return
        }
        #expect(options.cornerStyle == .round)
        let rounded = CADDocumentStore(document: document)
        _ = try rounded.apply(draft.command(in: document))
        let roundedVolume = try MeasurementService().measure(document: rounded.document, ruler: .standard(for: .meter))
            .totals.solidVolumeCubicMeters
        let h = 0.002
        #expect(abs(roundedVolume - 2 * h * (2 * h * 0.14 - 4 * h * h + Double.pi * h * h)) < 1e-12)

        // Chord steers the section by its guide without scaling it.
        draft.sweepGuide = .chord
        guard case .createSweep(_, _, _, _, _, let chord, _) = try draft.command(in: document) else {
            Issue.record("Expected native Sweep source intent.")
            return
        }
        #expect(chord.guideMethod == .chord)
        draft.sweepGuide = .point

        // Simplify asks for the flat sides as trimmed planes.
        draft.sweepCorners = .mitre
        draft.sweepSimplify = true
        guard case .createSweep(_, _, _, _, _, let simplified, _) = try draft.command(in: document) else {
            Issue.record("Expected native Sweep source intent.")
            return
        }
        #expect(simplified.simplify)
        let flat = CADDocumentStore(document: document)
        _ = try flat.apply(draft.command(in: document))
        #expect(abs(try MeasurementService().measure(document: flat.document, ruler: .standard(for: .meter))
            .totals.solidVolumeCubicMeters - 0.004 * 0.004 * 0.14) < 1e-12)
    }

    @Test func anEdgeOfABodyExtrudesIntoASheet() throws {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedRectangleFromCorners(
            name: "Box", plane: .xy,
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
            depth: .length(0.02, .meter), direction: .normal
        )
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        let edge = try #require(topology.entries.first { entry in
            guard entry.kind == .edge, let start = entry.start, let end = entry.end else { return false }
            return abs(start.z - 0.02) < 1e-9 && abs(end.z - 0.02) < 1e-9 && abs(start.y) < 1e-9 && abs(end.y) < 1e-9
        }?.selectionTarget())
        var draft = makeDraft(.extrude, targets: [edge])
        draft.extrusionDirection = .vector
        draft.axis = ["0", "0", "1"]
        draft.startDistance = "0"
        draft.distance = "10 mm"
        guard case .extrudeEdges(_, let edgeCurves, _, _, let direction) = try draft.command(in: document) else {
            Issue.record("Edges extrude through extrudeEdges.")
            return
        }
        #expect(edgeCurves.count == 1 && direction == .vector(.unitZ))
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        #expect(measurement.counts.sheets == 1)
        #expect(abs(measurement.totals.sheetAreaSquareMeters - 0.02 * 0.01) < 1e-12)
    }

    @Test func aSectionSweepsAlongAnEdgeOfABody() throws {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedRectangleFromCorners(
            name: "Box", plane: .xy,
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
            depth: .length(0.02, .meter), direction: .normal
        )
        // A 4 mm square across the top front edge's end at the origin side.
        let square = try document.createRectangleSketchFromCorners(
            name: "Section", plane: .plane(Plane3D(origin: Point3D(x: 0, y: 0, z: 0.02), normal: .unitX)),
            firstCorner: SketchPoint(x: .length(-0.002, .meter), y: .length(-0.002, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.002, .meter), y: .length(0.002, .meter))
        )
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        let edge = try #require(topology.entries.first { entry in
            guard entry.kind == .edge, let start = entry.start, let end = entry.end else { return false }
            return abs(start.z - 0.02) < 1e-9 && abs(end.z - 0.02) < 1e-9 && abs(start.y) < 1e-9 && abs(end.y) < 1e-9
        }?.selectionTarget())
        let squareNode = try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(square) })
        let draft = makeDraft(.sweep, targets: [.init(sceneNodeID: squareNode.id), edge])
        guard case .createSweep(_, let sections, let path, _, _, _, let edgeCurves) = try draft.command(in: document) else {
            Issue.record("Expected native Sweep source intent.")
            return
        }
        #expect(sections.map(\.featureID) == [square] && edgeCurves.map(\.id) == [path.featureID])
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        #expect(abs(measurement.totals.solidVolumeCubicMeters - (0.02 * 0.02 * 0.02 + 0.004 * 0.004 * 0.02)) < 1e-12)
    }

    @Test func aSquareLoftsToABoxsCornerAsAPyramid() throws {
        var document = DesignDocument.empty()
        // A 20 mm box from z = 30 mm; its corner (0, 0, 30) mm is the apex.
        _ = try document.createExtrudedRectangleFromCorners(
            name: "Box", plane: .plane(Plane3D(origin: Point3D(x: 0, y: 0, z: 0.03), normal: .unitZ)),
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
            depth: .length(0.02, .meter), direction: .normal
        )
        let square = try document.createRectangleSketchFromCorners(
            name: "Square", plane: .xy,
            firstCorner: SketchPoint(x: .length(-0.01, .meter), y: .length(-0.01, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.01, .meter), y: .length(0.01, .meter))
        )
        let squareNode = try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(square) })
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        let corner = try #require(topology.entries.first { entry in
            guard entry.kind == .vertex, let point = entry.start else { return false }
            return abs(point.x) < 1e-9 && abs(point.y) < 1e-9 && abs(point.z - 0.03) < 1e-9
        }?.selectionTarget())
        let draft = makeDraft(.loft, targets: [.init(sceneNodeID: squareNode.id), corner])
        guard case .createApexLoft(_, _, let apex, _, _) = try draft.command(in: document) else {
            Issue.record("Expected a loft to a vertex.")
            return
        }
        #expect(document.cadDocument.designGraph.nodes[apex.source] != nil)
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        // The box and the pyramid, a third of its 20 mm square base times its 30 mm height.
        #expect(measurement.counts.solids == 2)
        #expect(abs(measurement.totals.solidVolumeCubicMeters - (0.02 * 0.02 * 0.02 + 0.02 * 0.02 * 0.03 / 3)) < 1e-12)
    }

    @Test func twoEdgesOfABoxLoftIntoASheet() throws {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedRectangleFromCorners(
            name: "Box", plane: .xy,
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
            depth: .length(0.02, .meter), direction: .normal
        )
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        // The top edge along X at y = 0 and the bottom edge along X at y = 20 mm.
        let edges = try [(0.0, 0.02), (0.02, 0.0)].map { y, z in
            try #require(topology.entries.first { entry in
                guard entry.kind == .edge, let start = entry.start, let end = entry.end else { return false }
                return abs(start.y - y) < 1e-9 && abs(end.y - y) < 1e-9 && abs(start.z - z) < 1e-9 && abs(end.z - z) < 1e-9
            }?.selectionTarget())
        }
        var draft = makeDraft(.loft, targets: edges)
        draft.sheet = true
        guard case .createLoft(_, let sections, _, _, let edgeCurves) = try draft.command(in: document) else {
            Issue.record("Expected native Loft source intent.")
            return
        }
        #expect(edgeCurves.count == 2 && sections.map(\.featureID) == edgeCurves.map(\.id))
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        // The diagonal sheet between them: 20 mm by 20√2 mm.
        #expect(measurement.counts.sheets == 1)
        #expect(abs(measurement.totals.sheetAreaSquareMeters - 0.02 * 0.02 * 2.0.squareRoot()) < 1e-12)
    }

    @Test func edgesOfTwoBoxesLoftTangentToTheirFaces() throws {
        var document = DesignDocument.empty()
        // Box A spans [0, 20 mm]³, box B [0, 20] × [-70, -50] × [30, 50] mm.
        let boxes = try [Point3D(x: 0, y: 0, z: 0), Point3D(x: 0, y: -0.07, z: 0.03)].map { origin in
            try document.createExtrudedRectangleFromCorners(
                name: "Box", plane: .plane(Plane3D(origin: origin, normal: .unitZ)),
                firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
                oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
                depth: .length(0.02, .meter), direction: .normal
            )
        }
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        // A's top front edge and B's bottom back edge, both along X.
        let edges = try [(0.0, 0.02), (-0.05, 0.03)].map { y, z in
            try #require(topology.entries.first { entry in
                guard entry.kind == .edge, let start = entry.start, let end = entry.end else { return false }
                return abs(start.y - y) < 1e-9 && abs(end.y - y) < 1e-9 && abs(start.z - z) < 1e-9 && abs(end.z - z) < 1e-9
            }?.selectionTarget())
        }
        var draft = makeDraft(.loft, targets: edges)
        draft.sheet = true
        draft.loftStartContinuity = .g1
        draft.loftEndContinuity = .g2
        draft.loftEdgeTension = "1.2"
        guard case .createLoft(_, let sections, _, _, _) = try draft.command(in: document) else {
            Issue.record("Expected native Loft source intent.")
            return
        }
        #expect(sections.map { $0.continuity?.source } == boxes)
        guard case .createLoft(_, _, _, let loftOptions, _) = try draft.command(in: document) else { return }
        #expect(loftOptions.simplify)
        #expect(sections.map { $0.continuity?.order } == [.tangent, .curvature])
        #expect(sections.allSatisfy { $0.continuity?.tension == 1.2 })
        #expect(sections.allSatisfy { abs(($0.continuity?.angularAllowance ?? 0) - 0.1 * Double.pi / 180) < 1e-15 })
        // Only the G2 end carries a curvature allowance, the reciprocal of the entered radius.
        #expect(sections.map { $0.continuity?.curvatureAllowance } == [nil, 1])
        draft.curvatureAllowanceRadius = "0 m"
        #expect(throws: EditorError.self) { try draft.command(in: document) }
        draft.curvatureAllowanceRadius = "1 m"
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        // The S-shaped sheet is longer across than the flat one between the edges (√(50² + 10²) mm).
        #expect(measurement.counts.sheets == 1)
        #expect(measurement.totals.sheetAreaSquareMeters > 0.02 * (0.05 * 0.05 + 0.01 * 0.01).squareRoot() + 1e-9)

        // A G1 end needs an edge there.
        let sketch = try document.createLineSketch(name: "Line", plane: .xy,
            start: SketchPoint(x: .length(0, .meter), y: .length(-0.1, .meter)),
            end: SketchPoint(x: .length(0.02, .meter), y: .length(-0.1, .meter)))
        let line = try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(sketch) })
        draft.targets = [edges[0], .init(sceneNodeID: line.id)]
        #expect(throws: EditorError.self) { try draft.command(in: document) }
    }

    @Test func twoEdgesOfABoxRoundTogether() throws {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedRectangleFromCorners(
            name: "Box", plane: .xy,
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
            depth: .length(0.02, .meter), direction: .normal
        )
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        // The top edge along X at y = 0 and the bottom one at y = 20 mm: they do not meet.
        let edges = try [(0.0, 0.02), (0.02, 0.0)].map { y, z in
            try #require(topology.entries.first { entry in
                guard entry.kind == .edge, let start = entry.start, let end = entry.end else { return false }
                return abs(start.y - y) < 1e-9 && abs(end.y - y) < 1e-9 && abs(start.z - z) < 1e-9 && abs(end.z - z) < 1e-9
            }?.selectionTarget())
        }
        var draft = makeDraft(.fillet, targets: edges)
        draft.distance = "3 mm"
        guard case .createBodyEdgeTreatment(_, _, .several(.fillet, let more)) = try draft.command(in: document) else {
            Issue.record("Expected a fillet of two edges.")
            return
        }
        #expect(more.count == 1)
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        let r = 0.003
        #expect(measurement.counts.solids == 1)
        #expect(abs(measurement.totals.solidVolumeCubicMeters - (0.02 * 0.02 * 0.02 - 2 * (r * r - Double.pi * r * r / 4) * 0.02)) < 1e-11)
    }

    @Test func twoEdgesMeetingAtACornerRoundIntoAMitre() throws {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedRectangleFromCorners(
            name: "Box", plane: .xy,
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
            depth: .length(0.02, .meter), direction: .normal
        )
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        // The top edges along X at y = 0 and along Y at x = 0: they meet at the corner (0, 0, 20 mm).
        let edges = try [true, false].map { alongX in
            try #require(topology.entries.first { entry in
                guard entry.kind == .edge, let start = entry.start, let end = entry.end else { return false }
                let (a, b) = alongX ? (start.y, end.y) : (start.x, end.x)
                return abs(start.z - 0.02) < 1e-9 && abs(end.z - 0.02) < 1e-9 && abs(a) < 1e-9 && abs(b) < 1e-9
            }?.selectionTarget())
        }
        let (alongX, alongY) = (edges[0], edges[1])
        var draft = makeDraft(.fillet, targets: [alongX, alongY])
        draft.distance = "3 mm"
        guard case .createBodyEdgeTreatment(_, _, .several(.fillet, let more)) = try draft.command(in: document) else {
            Issue.record("Expected a fillet of two edges.")
            return
        }
        #expect(more.count == 1)
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        let r = 0.003
        // Each round removes its cross-section along its 20 mm edge, the mitre giving back the
        // corner the two would both remove.
        let expected = 0.02 * 0.02 * 0.02 - r * r * (1 - Double.pi / 4) * 0.04 + r * r * r * (5.0 / 3 - Double.pi / 2)
        #expect(measurement.counts.solids == 1)
        #expect(abs(measurement.totals.solidVolumeCubicMeters - expected) < 1e-11)
    }

    @Test func everyEdgeOfABoxRoundsIntoARoundedBox() throws {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedRectangleFromCorners(
            name: "Box", plane: .xy,
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
            depth: .length(0.02, .meter), direction: .normal
        )
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        let edges = try topology.entries.filter { $0.kind == .edge }.map { try #require($0.selectionTarget()) }
        #expect(edges.count == 12)
        var draft = makeDraft(.fillet, targets: edges)
        draft.distance = "3 mm"
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        let (r, a) = (0.003, 0.014)
        // The inner box swept by the ball.
        let expected = a * a * a + 6 * a * a * r + 3 * Double.pi * r * r * a + 4 * Double.pi * r * r * r / 3
        #expect(measurement.counts.solids == 1)
        #expect(abs(measurement.totals.solidVolumeCubicMeters - expected) < 1e-11)
    }

    @Test func everyEdgeOfABoxChamfersOnTheirPlanes() throws {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedRectangleFromCorners(
            name: "Box", plane: .xy,
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
            depth: .length(0.02, .meter), direction: .normal
        )
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        let edges = try topology.entries.filter { $0.kind == .edge }.map { try #require($0.selectionTarget()) }
        var draft = makeDraft(.chamfer, targets: edges)
        draft.distance = "3 mm"
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        let (s, d) = (0.02, 0.003)
        // Each edge's triangle along it, less d³/3 per meeting pair, plus d³/4 per corner.
        #expect(measurement.counts.solids == 1)
        #expect(abs(measurement.totals.solidVolumeCubicMeters - (s * s * s - 6 * d * d * s + 6 * d * d * d)) < 1e-11)
    }

    @Test func oneArcOfACylindersRimRoundsTheWholeRim() throws {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedCircle(
            name: "Cylinder", plane: .xy,
            center: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            radius: .length(0.01, .meter), depth: .length(0.02, .meter), direction: .normal
        )
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        // One arc of the top rim, the edges there not upright.
        let arc = try #require(topology.entries.first { entry in
            guard entry.kind == .edge, let start = entry.start, let end = entry.end else { return false }
            return abs(start.z - 0.02) < 1e-9 && abs(end.z - 0.02) < 1e-9
        }?.selectionTarget())
        var draft = makeDraft(.fillet, targets: [arc])
        draft.distance = "2 mm"
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        let r = 0.002
        // Pappus: the corner section about the axis at its centroid's radius.
        let inset = r * (10 - 3 * Double.pi) / (12 - 3 * Double.pi)
        let expected = Double.pi * 0.01 * 0.01 * 0.02 - r * r * (1 - Double.pi / 4) * 2 * Double.pi * (0.01 - inset)
        #expect(measurement.counts.solids == 1)
        #expect(abs(measurement.totals.solidVolumeCubicMeters - expected) < 1e-11)
    }

    @Test func theChamferFormsAngleCutsFromItsReferenceFaceAndFlips() throws {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedRectangleFromCorners(
            name: "Box", plane: .xy,
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
            depth: .length(0.02, .meter), direction: .normal
        )
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        let edge = try #require(topology.entries.first { entry in
            guard entry.kind == .edge, let start = entry.start, let end = entry.end else { return false }
            return abs(start.z - 0.02) < 1e-9 && abs(end.z - 0.02) < 1e-9 && abs(start.y) < 1e-9 && abs(end.y) < 1e-9
        }?.selectionTarget())
        let (s, d) = (0.02, 0.002)
        // sin 30° / sin 120° = 1 / √3.
        let e = d / 3.0.squareRoot()
        var volumes: [Double] = []
        for flipped in [false, true] {
            var draft = makeDraft(.chamfer, targets: [edge])
            draft.distance = "2 mm"
            draft.chamferAngle = "30"
            draft.chamferFlipped = flipped
            guard case .createBodyEdgeTreatment(_, _, .chamfer(_, _, .some, let isFlipped, nil)) = try draft.command(in: document) else {
                Issue.record("Expected an angled chamfer.")
                return
            }
            #expect(isFlipped == flipped)
            let store = CADDocumentStore(document: document)
            _ = try store.apply(draft.command(in: document))
            volumes.append(try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter)).totals.solidVolumeCubicMeters)
        }
        // Either way the triangle of the distance and the far contact along the edge.
        for volume in volumes { #expect(abs(volume - (s * s * s - d * e / 2 * s)) < 1e-11) }
        // Apex and Offset agree on a square edge.
        var apex = makeDraft(.chamfer, targets: [edge])
        apex.distance = "2 mm"
        apex.chamferMode = .apex
        guard case .createBodyEdgeTreatment(_, _, .chamfer(_, .apex, nil, false, nil)) = try apex.command(in: document) else {
            Issue.record("Expected an apex chamfer.")
            return
        }
    }

    @Test func aNegativeFilletDistanceChamfers() throws {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedRectangleFromCorners(
            name: "Box", plane: .xy,
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
            depth: .length(0.02, .meter), direction: .normal
        )
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        let edge = try #require(topology.entries.first { $0.kind == .edge }?.selectionTarget())
        var draft = makeDraft(.fillet, targets: [edge])
        draft.distance = "-2 mm"
        guard case .createBodyEdgeTreatment(_, _, .chamfer(let distance, .offset, nil, false, nil)) = try draft.command(in: document) else {
            Issue.record("Expected a chamfer.")
            return
        }
        #expect(abs(try document.cadDocument.parameters.resolvedValue(for: distance).value - 0.002) < 1e-12)
    }

    @Test func variablePointsSetTheRadiusAlongTheEdge() throws {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedRectangleFromCorners(
            name: "Box", plane: .xy,
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
            depth: .length(0.02, .meter), direction: .normal
        )
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        let edge = try #require(topology.entries.first { entry in
            guard entry.kind == .edge, let start = entry.start, let end = entry.end else { return false }
            return abs(start.z - 0.02) < 1e-9 && abs(end.z - 0.02) < 1e-9 && abs(start.y) < 1e-9 && abs(end.y) < 1e-9
        }?.selectionTarget())
        var draft = makeDraft(.fillet, targets: [edge])
        draft.distance = "2 mm"
        draft.filletVariablePoints = "0.5@5 mm"
        guard case .createBodyEdgeTreatment(_, _, .variableFillet(_, _, .round, nil, let points)) = try draft.command(in: document) else {
            Issue.record("Expected a fillet with a variable point.")
            return
        }
        #expect(points.map(\.position) == [0.5])
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        // The radius runs along the natural cubic spline through 2, 5 and 2 mm: its second
        // derivative halfway M = 6(a − 2b + a)/h²/4, none at the ends; (1 − π/4)∫r² by Gauss.
        let (a, b, s) = (0.002, 0.005, 0.02)
        let h = s / 2
        let m = 6 * (2 * a - 2 * b) / (h * h) / 4
        func radius(_ x: Double) -> Double {
            // The half from the start; the other mirrors it.
            m * x * x * x / (6 * h) + (a / h) * (h - x) + (b / h - m * h / 6) * x
        }
        let nodes = [-0.861136311594053, -0.339981043584856, 0.339981043584856, 0.861136311594053]
        let weights = [0.347854845137454, 0.652145154862546, 0.652145154862546, 0.347854845137454]
        let half = zip(nodes, weights).reduce(0.0) { sum, pair in
            let r = radius(h / 2 * (1 + pair.0))
            return sum + pair.1 * r * r * h / 2
        }
        let removed = (1 - Double.pi / 4) * 2 * half
        #expect(abs(measurement.totals.solidVolumeCubicMeters - (s * s * s - removed)) < 1e-11)
        draft.filletVariablePoints = "0.5"
        #expect(throws: EditorError.self) { try draft.command(in: document) }
    }

    @Test func limitPointsBlendOnlyTheirStretchOfTheEdge() throws {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedRectangleFromCorners(
            name: "Box", plane: .xy,
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
            depth: .length(0.02, .meter), direction: .normal
        )
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        let edge = try #require(topology.entries.first { entry in
            guard entry.kind == .edge, let start = entry.start, let end = entry.end else { return false }
            return abs(start.z - 0.02) < 1e-9 && abs(end.z - 0.02) < 1e-9 && abs(start.y) < 1e-9 && abs(end.y) < 1e-9
        }?.selectionTarget())
        var draft = makeDraft(.fillet, targets: [edge])
        draft.distance = "3 mm"
        draft.limitStart = "0.25"
        draft.limitEnd = "0.75"
        guard case .createBodyEdgeTreatment(_, _, .limitedFillet(_, .round, nil, let limits)) = try draft.command(in: document) else {
            Issue.record("Expected a limited fillet.")
            return
        }
        #expect(limits == EdgeBlendLimits(start: 0.25, end: 0.75))
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        let r = 0.003
        #expect(abs(measurement.totals.solidVolumeCubicMeters - (0.02 * 0.02 * 0.02 - r * r * (1 - Double.pi / 4) * 0.01)) < 1e-11)
        draft.limitStart = "0.8"
        #expect(throws: EditorError.self) { try draft.command(in: document) }
        // A chamfer takes the same limits: its triangle over the stretch only.
        var chamfer = makeDraft(.chamfer, targets: [edge])
        chamfer.distance = "2 mm"
        chamfer.limitStart = "0.25"
        chamfer.limitEnd = "0.75"
        guard case .createBodyEdgeTreatment(_, _, .chamfer(_, .offset, nil, false, let chamferLimits)) = try chamfer.command(in: document) else {
            Issue.record("Expected a limited chamfer.")
            return
        }
        #expect(chamferLimits == EdgeBlendLimits(start: 0.25, end: 0.75))
        let chamferStore = CADDocumentStore(document: document)
        _ = try chamferStore.apply(chamfer.command(in: document))
        let cut = try MeasurementService().measure(document: chamferStore.document, ruler: .standard(for: .meter))
        #expect(abs(cut.totals.solidVolumeCubicMeters - (0.02 * 0.02 * 0.02 - 0.002 * 0.002 / 2 * 0.01)) < 1e-11)
        // Reversed, the chamfer runs over the edge's two ends instead.
        chamfer.limitsReversed = true
        guard case .createBodyEdgeTreatment(_, _, .chamfer(_, _, _, _, let reversedLimits)) = try chamfer.command(in: document) else {
            Issue.record("Expected a reversed limited chamfer.")
            return
        }
        #expect(reversedLimits == EdgeBlendLimits(start: 0.25, end: 0.75, reversed: true))
        let reversedStore = CADDocumentStore(document: document)
        _ = try reversedStore.apply(chamfer.command(in: document))
        let ends = try MeasurementService().measure(document: reversedStore.document, ruler: .standard(for: .meter))
        #expect(abs(ends.totals.solidVolumeCubicMeters - (0.02 * 0.02 * 0.02 - 0.002 * 0.002 / 2 * 0.01)) < 1e-11)
    }

    @Test func aVariableFilletGrowsAlongItsEdge() throws {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedRectangleFromCorners(
            name: "Box", plane: .xy,
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
            depth: .length(0.02, .meter), direction: .normal
        )
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        let edge = try #require(topology.entries.first { entry in
            guard entry.kind == .edge, let start = entry.start, let end = entry.end else { return false }
            return abs(start.z - 0.02) < 1e-9 && abs(end.z - 0.02) < 1e-9 && abs(start.y) < 1e-9 && abs(end.y) < 1e-9
        }?.selectionTarget())
        var draft = makeDraft(.fillet, targets: [edge])
        draft.distance = "2 mm"
        draft.filletEndRadius = "6 mm"
        guard case .createBodyEdgeTreatment(_, _, .variableFillet) = try draft.command(in: document) else {
            Issue.record("Expected a variable fillet.")
            return
        }
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        let (r0, r1) = (0.002, 0.006)
        #expect(abs(measurement.totals.solidVolumeCubicMeters - (0.02 * 0.02 * 0.02 - (1 - Double.pi / 4) * (r0 * r0 + r0 * r1 + r1 * r1) / 3 * 0.02)) < 1e-11)
    }

    @Test func aConicFilletRoundsABoxEdge() throws {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedRectangleFromCorners(
            name: "Box", plane: .xy,
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
            depth: .length(0.02, .meter), direction: .normal
        )
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        // The top edge along X at y = 0.
        let edge = try #require(topology.entries.first { entry in
            guard entry.kind == .edge, let start = entry.start, let end = entry.end else { return false }
            return abs(start.z - 0.02) < 1e-9 && abs(end.z - 0.02) < 1e-9 && abs(start.y) < 1e-9 && abs(end.y) < 1e-9
        }?.selectionTarget())
        var draft = makeDraft(.fillet, targets: [edge])
        draft.distance = "4 mm"
        draft.filletShape = .conic
        guard case .createBodyEdgeTreatment(_, _, let treatment) = try draft.command(in: document),
              case .shapedFillet(_, let shape, let tension) = treatment else {
            Issue.record("Expected a shaped fillet.")
            return
        }
        #expect(shape == .conic && tension == nil)
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        // A parabola (rho 0.5) removes a sixth of the 4 mm square's corner along the 20 mm edge.
        #expect(measurement.counts.solids == 1)
        #expect(abs(measurement.totals.solidVolumeCubicMeters - (0.02 * 0.02 * 0.02 - 0.004 * 0.004 / 6 * 0.02)) < 1e-12)
    }

    @Test func aFullFilletRoundsABlocksTopBetweenTwoEdges() throws {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedRectangleFromCorners(
            name: "Block", plane: .xy,
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
            depth: .length(0.03, .meter), direction: .normal
        )
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        // The top edges along X at y = 0 and y = 20 mm.
        let edges = try [0.0, 0.02].map { y in
            try #require(topology.entries.first { entry in
                guard entry.kind == .edge, let start = entry.start, let end = entry.end else { return false }
                return abs(start.z - 0.03) < 1e-9 && abs(end.z - 0.03) < 1e-9 && abs(start.y - y) < 1e-9 && abs(end.y - y) < 1e-9
            }?.selectionTarget())
        }
        var draft = makeDraft(.fillet, targets: [edges[0]])
        draft.filletShape = .full
        #expect(throws: EditorError.self) { try draft.command(in: document) }
        draft.targets = edges
        guard case .createBodyEdgeTreatment(_, _, .fullFillet) = try draft.command(in: document) else {
            Issue.record("Expected a full fillet.")
            return
        }
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        // The top 10 mm of the 20 mm cross-section becomes a half disc of radius 10 mm.
        let r = 0.01
        #expect(measurement.counts.solids == 1)
        #expect(abs(measurement.totals.solidVolumeCubicMeters - (0.02 * 0.02 * 0.03 - 0.02 * (2 * r * r - Double.pi * r * r / 2))) < 1e-11)
    }

    @Test func aSheetsBendFilletsIntoARoundedSheet() throws {
        var document = DesignDocument.empty()
        func sheet(on plane: SketchPlane, _ corners: [(Double, Double)]) throws -> FeatureID {
            let lines = try corners.indices.map { index in
                let (start, end) = (corners[index], corners[(index + 1) % corners.count])
                return try document.createLineSketch(name: "Side", plane: plane,
                    start: SketchPoint(x: .length(start.0, .meter), y: .length(start.1, .meter)),
                    end: SketchPoint(x: .length(end.0, .meter), y: .length(end.1, .meter)))
            }
            return try document.createCurvePatch(name: "Sheet", curves: lines.map { CurveSectionReference(featureID: $0) })
        }
        // A 40 mm floor and wall meeting along X (on the ZX plane sketch x is z).
        let pieces = [try sheet(on: .xy, [(0, 0), (0.04, 0), (0.04, 0.04), (0, 0.04)]),
                      try sheet(on: .zx, [(0, 0), (0, 0.04), (0.04, 0.04), (0.04, 0)])]
        let nodes = try pieces.map { feature in
            try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .body(feature) })
        }
        try document.joinSheets(targets: nodes.map { SelectionTarget(sceneNodeID: $0.id) })
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        let bend = try #require(topology.entries.first { entry in
            guard entry.kind == .edge, let start = entry.start, let end = entry.end else { return false }
            return [start, end].allSatisfy { abs($0.y) < 1e-9 && abs($0.z) < 1e-9 }
        }?.selectionTarget())
        var draft = makeDraft(.fillet, targets: [bend])
        draft.distance = "5 mm"
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        #expect(measurement.counts.sheets == 1 && measurement.counts.solids == 0)
        // Each flat face loses 5 mm of its 40 mm; the quarter cylinder adds π/2 · 5 mm across 40 mm,
        // its rational face's area measured within its approximation (FB23.3), not exactly.
        let expected = 2 * 0.04 * 0.035 + Double.pi / 2 * 0.005 * 0.04
        #expect(abs(measurement.totals.sheetAreaSquareMeters - expected) < 1e-6)

        // A G2 blend of the bend is a sheet as well.
        var blend = makeDraft(.g2Blend, targets: [bend])
        blend.distance = "5 mm"
        let blended = CADDocumentStore(document: document)
        _ = try blended.apply(blend.command(in: document))
        let blendMeasurement = try MeasurementService().measure(document: blended.document, ruler: .standard(for: .meter))
        #expect(blendMeasurement.counts.sheets == 1 && blendMeasurement.counts.solids == 0)

        // A chamfer of the bend: a flat strip 5√2 mm across.
        var chamfer = makeDraft(.chamfer, targets: [bend])
        chamfer.distance = "5 mm"
        let chamfered = CADDocumentStore(document: document)
        _ = try chamfered.apply(chamfer.command(in: document))
        let chamferMeasurement = try MeasurementService().measure(document: chamfered.document, ruler: .standard(for: .meter))
        #expect(chamferMeasurement.counts.sheets == 1 && chamferMeasurement.counts.solids == 0)
        #expect(abs(chamferMeasurement.totals.sheetAreaSquareMeters - (2 * 0.04 * 0.035 + 0.005 * 2.0.squareRoot() * 0.04)) < 1e-9)
    }

    @Test func aPatchSpansAClosedLoopOfCurves() throws {
        var document = DesignDocument.empty()
        // A 20 mm right triangle of three lines.
        let ends = [(0.0, 0.0, 0.02, 0.0), (0.02, 0.0, 0.0, 0.02), (0.0, 0.02, 0.0, 0.0)]
        let lines = try ends.map { x0, y0, x1, y1 in
            try document.createLineSketch(name: "Side", plane: .xy,
                start: SketchPoint(x: .length(x0, .meter), y: .length(y0, .meter)),
                end: SketchPoint(x: .length(x1, .meter), y: .length(y1, .meter)))
        }
        let nodes = try lines.map { line in try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(line) }) }
        var draft = makeDraft(.patch, targets: nodes.map { .init(sceneNodeID: $0.id) })
        draft.isSurfaceCreation = true
        guard case .createCurvePatch(_, let curves, let edgeCurves) = try draft.command(in: document) else {
            Issue.record("Expected a curve patch.")
            return
        }
        #expect(curves.map(\.featureID) == lines && edgeCurves.isEmpty)
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        #expect(measurement.counts.sheets == 1)
        #expect(abs(measurement.totals.sheetAreaSquareMeters - 0.0002) < 1e-12)
    }

    @Test func aBridgeSurfaceJoinsTwoPlanarSheets() throws {
        var document = DesignDocument.empty()
        // A floor on z = 0 (y from 10 to 40 mm) and a wall on y = 0 (z from 10 to 40 mm), both 40 mm
        // long in x; sketch x is world z and sketch y world x on the ZX plane.
        func sheet(on plane: SketchPlane, _ corners: [(Double, Double)]) throws -> FeatureID {
            let lines = try corners.indices.map { index in
                let (start, end) = (corners[index], corners[(index + 1) % corners.count])
                return try document.createLineSketch(name: "Edge", plane: plane,
                    start: SketchPoint(x: .length(start.0, .meter), y: .length(start.1, .meter)),
                    end: SketchPoint(x: .length(end.0, .meter), y: .length(end.1, .meter)))
            }
            return try document.createCurvePatch(name: "Sheet", curves: lines.map { CurveSectionReference(featureID: $0) })
        }
        let floor = try sheet(on: .xy, [(0, 0.01), (0.04, 0.01), (0.04, 0.04), (0, 0.04)])
        let wall = try sheet(on: .zx, [(0.01, 0), (0.01, 0.04), (0.04, 0.04), (0.04, 0)])
        let nodes = try [floor, wall].map { feature in
            try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .body(feature) })
        }
        var draft = makeDraft(.bridgeSurface, targets: nodes.map { .init(sceneNodeID: $0.id) })
        draft.isSurfaceCreation = true
        draft.distance = "20 mm"
        guard case .createBridgeSurface(_, let bridge, let wallByReach) = try draft.command(in: document) else {
            Issue.record("Expected a Bridge Surface.")
            return
        }
        #expect(wallByReach == nil)
        #expect(bridge.first == floor && bridge.second == wall && bridge.shape == .curvature)
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        #expect(measurement.counts.sheets == 3)
        // The chamfer strip spans 20√2 mm across and 40 mm along.
        draft.bridgeShape = .chamfer
        let chamfered = CADDocumentStore(document: document)
        _ = try chamfered.apply(draft.command(in: document))
        let strips = try MeasurementService().measure(document: chamfered.document, ruler: .standard(for: .meter))
        #expect(abs(strips.totals.sheetAreaSquareMeters - (2 * 0.04 * 0.03 + 0.02 * 2.0.squareRoot() * 0.04)) < 1e-12)

        // Trimming the walls joins what is left of them with the strip into one sheet.
        draft.bridgeTrim = .both
        let trimmed = CADDocumentStore(document: document)
        _ = try trimmed.apply(draft.command(in: document))
        let joined = try MeasurementService().measure(document: trimmed.document, ruler: .standard(for: .meter))
        #expect(joined.counts.sheets == 1)
        #expect(abs(joined.totals.sheetAreaSquareMeters - (2 * 0.04 * 0.02 + 0.02 * 2.0.squareRoot() * 0.04)) < 1e-12)
    }

    @Test func aShortBridgeTrimsOnlyTheSheetReachingLess() throws {
        var document = DesignDocument.empty()
        func sheet(on plane: SketchPlane, _ corners: [(Double, Double)]) throws -> FeatureID {
            let lines = try corners.indices.map { index in
                let (start, end) = (corners[index], corners[(index + 1) % corners.count])
                return try document.createLineSketch(name: "Side", plane: plane,
                    start: SketchPoint(x: .length(start.0, .meter), y: .length(start.1, .meter)),
                    end: SketchPoint(x: .length(end.0, .meter), y: .length(end.1, .meter)))
            }
            return try document.createCurvePatch(name: "Sheet", curves: lines.map { CurveSectionReference(featureID: $0) })
        }
        // The floor reaches 40 mm from where the planes meet, the wall 30 mm (sketch x is world z
        // on the ZX plane).
        let floor = try sheet(on: .xy, [(0, 0.01), (0.04, 0.01), (0.04, 0.04), (0, 0.04)])
        let wall = try sheet(on: .zx, [(0.01, 0), (0.01, 0.04), (0.03, 0.04), (0.03, 0)])
        let nodes = try [floor, wall].map { feature in
            try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .body(feature) })
        }
        var draft = makeDraft(.bridgeSurface, targets: nodes.map { .init(sceneNodeID: $0.id) })
        draft.isSurfaceCreation = true
        draft.distance = "20 mm"
        draft.bridgeShape = .chamfer
        draft.bridgeTrim = .short
        guard case .createBridgeSurface(_, let bridge, let wallByReach) = try draft.command(in: document) else {
            Issue.record("Expected a Bridge Surface.")
            return
        }
        #expect(wallByReach == .short && bridge.trimWalls == .none)
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        // The wall is trimmed and joined with the strip; the floor keeps its object.
        let feature = try #require(store.document.cadDocument.designGraph.nodes.values.first { node in
            if case .sheetBridge = node.operation { return true }
            return false
        })
        guard case let .sheetBridge(resolved) = feature.operation else { return }
        #expect(resolved.trimWalls == .second)
        let nodesShown = store.document.productMetadata.sceneNodes.values
        #expect(nodesShown.contains { $0.reference == .body(floor) } && nodesShown.contains { $0.reference == .body(wall) } == false)
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        #expect(measurement.counts.sheets == 2)
        // The floor 40 × 30 mm, the wall above z = 20 mm 40 × 10 mm and the strip 20√2 × 40 mm.
        #expect(abs(measurement.totals.sheetAreaSquareMeters - (0.04 * 0.03 + 0.04 * 0.01 + 0.02 * 2.0.squareRoot() * 0.04)) < 1e-12)
    }

    @Test func fourCurvesFrameAFlatSquare() throws {
        var document = DesignDocument.empty()
        let ends = [(0.0, 0.0, 0.02, 0.0), (0.02, 0.0, 0.02, 0.02), (0.02, 0.02, 0.0, 0.02), (0.0, 0.02, 0.0, 0.0)]
        let lines = try ends.map { x0, y0, x1, y1 in
            try document.createLineSketch(name: "Side", plane: .xy,
                start: SketchPoint(x: .length(x0, .meter), y: .length(y0, .meter)),
                end: SketchPoint(x: .length(x1, .meter), y: .length(y1, .meter)))
        }
        let nodes = try lines.map { line in try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(line) }) }
        // Selected out of boundary order.
        let draft = makeDraft(.square, targets: [nodes[0], nodes[2], nodes[1], nodes[3]].map { .init(sceneNodeID: $0.id) })
        guard case .createSquare(_, let sides, let edgeCurves) = try draft.command(in: document) else {
            Issue.record("Expected a Square command.")
            return
        }
        #expect(sides.count == 4 && edgeCurves.isEmpty && sides.allSatisfy { $0.continuity == nil })
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        #expect(measurement.counts.sheets == 1)
        #expect(abs(measurement.totals.sheetAreaSquareMeters - 0.0004) < 1e-12)
    }

    @Test func aSquareBetweenEdgesOfTwoBoxesIsTangentToTheirFaces() throws {
        var document = DesignDocument.empty()
        // Box A spans [0, 20 mm]³, box B [0, 20] × [-70, -50] × [30, 50] mm.
        let boxes = try [Point3D(x: 0, y: 0, z: 0), Point3D(x: 0, y: -0.07, z: 0.03)].map { origin in
            try document.createExtrudedRectangleFromCorners(
                name: "Box", plane: .plane(Plane3D(origin: origin, normal: .unitZ)),
                firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
                oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
                depth: .length(0.02, .meter), direction: .normal
            )
        }
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        let edges = try [(0.0, 0.02), (-0.05, 0.03)].map { y, z in
            try #require(topology.entries.first { entry in
                guard entry.kind == .edge, let start = entry.start, let end = entry.end else { return false }
                return abs(start.y - y) < 1e-9 && abs(end.y - y) < 1e-9 && abs(start.z - z) < 1e-9 && abs(end.z - z) < 1e-9
            }?.selectionTarget())
        }
        // Rails leaving A's top face and arriving at B's bottom face level, in the planes x = 0 and
        // x = 20 mm (sketch x is world y and sketch y is world z on planes across X).
        let rail: [(Double, Double)] = [(0, 0.02), (-0.02, 0.02), (-0.03, 0.03), (-0.05, 0.03)]
        let rails = try [SketchPlane.yz, .plane(Plane3D(origin: Point3D(x: 0.02, y: 0, z: 0), normal: .unitX))].map { plane in
            try document.createSketch(name: "Rail", sketch: Sketch(plane: plane, entities: [
                SketchEntityID(): .spline(SketchSpline(controlPoints: rail.map { SketchPoint(x: .length($0.0, .meter), y: .length($0.1, .meter)) })),
            ]), geometryRole: .curve)
        }
        let railNodes = try rails.map { rail in try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(rail) }) }
        var draft = makeDraft(.square, targets: [edges[0], .init(sceneNodeID: railNodes[1].id), edges[1], .init(sceneNodeID: railNodes[0].id)])
        draft.squareContinuity = .g1
        guard case .createSquare(_, let sides, let edgeCurves) = try draft.command(in: document) else {
            Issue.record("Expected a Square command.")
            return
        }
        #expect(edgeCurves.count == 2)
        #expect(sides.compactMap { $0.continuity?.source } == boxes)
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        // Bending from one face's level to the other's, the sheet is wider than the flat one
        // between the edges.
        #expect(measurement.counts.sheets == 1)
        #expect(measurement.totals.sheetAreaSquareMeters > 0.02 * (0.05 * 0.05 + 0.01 * 0.01).squareRoot())
    }

    @Test func facesOfTwoBodiesLoftIntoASolid() throws {
        var document = DesignDocument.empty()
        let boxes = try [0.0, 0.05].map { z in
            try document.createExtrudedRectangleFromCorners(
                name: "Box", plane: .plane(Plane3D(origin: Point3D(x: 0, y: 0, z: z), normal: .unitZ)),
                firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
                oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
                depth: .length(0.02, .meter), direction: .normal
            )
        }
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        // The lower box's top at z = 20 mm and the upper box's bottom at z = 50 mm.
        let faces = try [0.02, 0.05].map { z in
            try #require(topology.entries.first { entry in
                guard entry.kind == .face, let normal = entry.surfaceNormal, abs(normal.z) > 0.99,
                      let center = entry.center else { return false }
                return abs(center.z - z) < 1e-9
            }?.selectionTarget())
        }
        let draft = makeDraft(.loft, targets: faces)
        guard case .createLoft(_, let sections, _, _, _) = try draft.command(in: document) else {
            Issue.record("Expected native Loft source intent.")
            return
        }
        #expect(sections.map(\.featureID) == boxes && sections.allSatisfy(\.section.isFace))
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        #expect(abs(measurement.totals.solidVolumeCubicMeters - (2 * 0.02 * 0.02 * 0.02 + 0.02 * 0.02 * 0.03)) < 1e-12)
    }

    @Test func sheetDraftsUseNativeSourceCommands() throws {
        var patch = makeDraft(.surfacePatch)
        patch.width = "100 mm"
        patch.height = "50 mm"
        let store = CADDocumentStore(document: .empty())
        _ = try store.apply(patch.command(in: store.document))
        let topology = try TopologySnapshotService().snapshot(document: store.document, metricPolicy: .omit)
        let target = try #require(topology.entries.first { $0.kind == .face }?.selectionTarget())
        _ = try store.apply(.upsertParameter(name: "sheet_thickness", expression: .length(0.002, .meter), kind: .length))
        let thickness = try ParameterExpressionParser().parse("sheet_thickness",
            parameters: store.document.cadDocument.parameters, targetKind: .length)
        let zero = try ParameterExpressionParser().parse("0", parameters: store.document.cadDocument.parameters,
            targetKind: .length, defaults: ParameterExpressionDefaults(lengthUnit: makeDraft(.thicken, targets: [target]).unit))
        for (front, back) in [("sheet_thickness", "0"), ("0", "sheet_thickness"), ("sheet_thickness", "sheet_thickness")] {
            var thicken = makeDraft(.thicken, targets: [target])
            thicken.distance = front
            thicken.thickenBack = back
            #expect(try thicken.command(in: store.document) == .createSheetSurfaceEdit(
                name: "Thicken", target: target,
                edit: .thicken(front: front == "0" ? zero : thickness, back: back == "0" ? zero : thickness)))
            thicken.distance = "-2 mm"
            #expect(throws: EditorError.self) { try thicken.command(in: store.document) }
        }
        #expect(ModelingOperationDraft.Kind.paletteOperations.contains(.thicken))
        var offset = makeDraft(.surfaceOffset, targets: [target])
        offset.distance = "-2 mm"
        #expect(try offset.command(in: store.document) == .createSheetSurfaceEdit(
            name: "Sheet Offset", target: target, edit: .offset(distance: .multiply(.constant(.scalar(-1)), .length(0.002, .meter)))))
        offset.distance = "-2"
        #expect(try offset.command(in: store.document) == .createSheetSurfaceEdit(
            name: "Sheet Offset", target: target, edit: .offset(distance: .length(-0.002, .meter))))
        offset.distance = "0"
        #expect(throws: EditorError.self) { try offset.command(in: store.document) }
        var extend = makeDraft(.surfaceExtend, targets: [target])
        extend.uBounds = ["0.1", "0.9"]
        #expect(try extend.command(in: store.document) == .createSheetSurfaceEdit(
            name: "Extend Trim", target: target, edit: .extend(uDomain: .closed(0.1, 0.9), vDomain: .closed(0, 1))))
        extend.uBounds = ["1", "0"]
        #expect(throws: EditorError.self) { try extend.command(in: store.document) }
    }

    @Test func boundaryDraftsUseExplicitCommandsWithoutImplicitAlgorithmSwitching() throws {
        var document = DesignDocument.empty()
        _ = try document.createBSplineSurface(name: "Source", surface: .bilinearPatch(
            bottomLeft: .origin,
            bottomRight: Point3D(x: 0.1, y: 0, z: 0),
            topRight: Point3D(x: 0.1, y: 0.1, z: 0),
            topLeft: Point3D(x: 0, y: 0.1, z: 0)
        ))
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        let edge = try #require(topology.entries.first { $0.kind == .edge }?.selectionTarget())
        var draft = makeDraft(.bridge, targets: [edge])

        #expect(throws: EditorError.self) { try draft.command(in: document) }
        #expect(ModelingOperationDraft.Kind.allCases.contains { $0.rawValue == "XNURBS" } == false)
        _ = try document.createBSplineSurface(name: "Second source", surface: .bilinearPatch(
            bottomLeft: Point3D(x: 0.2, y: 0, z: 0),
            bottomRight: Point3D(x: 0.3, y: 0, z: 0),
            topRight: Point3D(x: 0.3, y: 0.1, z: 0),
            topLeft: Point3D(x: 0.2, y: 0.1, z: 0)
        ))
        let updatedTopology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        let second = try #require(updatedTopology.entries.first {
            $0.kind == .edge && $0.sceneNodeID != edge.sceneNodeID.description
        }?.selectionTarget())
        draft.targets = [edge, second]
        var bridge = draft
        bridge.selectSurfaceOperation(.bridge)
        #expect(try bridge.command(in: document) == .createBoundaryBridge(
            name: bridge.name, first: edge, second: second, reverseSecondBoundary: false))
        bridge.targets = [edge]
        #expect(throws: EditorError.self) { try bridge.command(in: document) }
        bridge.selectSurfaceOperation(.patch)
        #expect(try bridge.command(in: document) == .createSurfaceFill(name: bridge.name, target: edge))
        bridge.targets = [edge, second]
        #expect(throws: EditorError.self) { try bridge.command(in: document) }
        #expect(try draft.command(in: document) == .createBoundaryBridge(
            name: draft.name, first: edge, second: second, reverseSecondBoundary: false))
        draft.targets = [edge, edge]
        #expect(throws: EditorError.self) { try draft.command(in: document) }
        draft.targets = []
        #expect(throws: EditorError.self) { try draft.command(in: document) }
    }

    @Test func boxForwardsExplicitUnitsAndEvaluates() throws {
        var draft = makeDraft(.box)
        draft.width = "20 mm"
        draft.height = "1 cm"
        draft.distance = "0.005 m"
        let command = try draft.command(in: .empty())
        guard case .createExtrudedRectangle(_, _, let width, let height, let depth, _) = command else {
            Issue.record("Box must use the existing exact source command.")
            return
        }
        #expect(width == .length(0.02, .meter))
        #expect(height == .length(0.01, .meter))
        #expect(depth == .length(0.005, .meter))
        let store = CADDocumentStore(document: .empty())
        _ = try store.apply(command)
        let evaluated = try CADPipeline.modelingDefault(for: store.document).evaluate(store.document.cadDocument)
        #expect(evaluated.brep.bodies.count == 1)
    }

    @Test func extrudeAndRevolveUseSelectedSourceAndExactParameters() throws {
        var document = DesignDocument.empty()
        let profile = try addProfile(to: &document, z: 0)
        var draft = makeDraft(.extrude, targets: [profile.target])
        draft.distance = "12 mm"
        draft.extrusionDirection = .symmetric
        #expect(try draft.command(in: document) == .extrudeSection(
            name: "Extrude", section: .profile(ProfileReference(featureID: profile.feature)),
            distance: .length(0.012, .meter), direction: .symmetric, resultKind: .solid
        ))
        draft.kind = .revolve
        draft.angle = "180"
        guard case .revolveSection(_, let reference, let axis, let angle, let resultKind, _, _, _, _) = try draft.command(in: document) else {
            Issue.record("Expected revolve source command.")
            return
        }
        #expect(reference.featureID == profile.feature)
        #expect(resultKind == .solid)
        #expect(axis == RevolveAxis(origin: .origin, direction: .unitY))
        #expect(angle == .angle(180, .degree))
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let evaluated = try CADPipeline.modelingDefault(for: store.document).evaluate(store.document.cadDocument)
        #expect(evaluated.brep.bodies.count == 1)
    }

    @Test func aBooleanExtrusionTakesTheSectionFirstAndCombinesWithTheBodiesAfterIt() throws {
        var document = DesignDocument.empty()
        let cube = try document.createExtrudedRectangle(
            name: "Cube", plane: .xy, width: .length(0.01, .meter), height: .length(0.02, .meter),
            depth: .length(0.01, .meter), direction: .normal
        )
        let cubeNode = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == cube }).id
        let profile = try addProfile(to: &document, z: 0)
        var draft = makeDraft(.extrude, targets: [profile.target, SelectionTarget(sceneNodeID: cubeNode)])
        draft.distance = "20 mm"
        // A new body takes one section only.
        #expect(throws: EditorError.self) { try draft.command(in: document) }
        draft.solidBoolean = .difference
        draft.keepsTools = true
        guard case .createExtrusion(_, let source) = try draft.command(in: document) else {
            Issue.record("A Boolean extrusion must be one authored extrusion.")
            return
        }
        #expect(source.section == .profile(ProfileReference(featureID: profile.feature)))
        #expect(source.operation == .difference && source.keepTools)
        #expect(source.targets.map(\.featureID) == [cube])
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        #expect(store.document.productMetadata.sceneNodes[cubeNode] == nil)
        _ = try CADPipeline.modelingDefault(for: store.document).evaluate(store.document.cadDocument)
        // A Boolean makes a solid.
        draft.sheet = true
        #expect(throws: EditorError.self) { try draft.command(in: document) }
    }

    @Test func aDraftedExtrusionCarriesItsDegrees() throws {
        var document = DesignDocument.empty()
        let profile = try addProfile(to: &document, z: 0)
        var draft = makeDraft(.extrude, targets: [profile.target])
        draft.distance = "5 mm"
        draft.draftDegrees = "3"
        guard case .createExtrusion(_, let source) = try draft.command(in: document) else {
            Issue.record("A drafted extrusion is one authored extrusion.")
            return
        }
        #expect(source.draftAngle == .angle(3, .degree))
        #expect(source.operation == .newBody)
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let evaluated = try CADPipeline.modelingDefault(for: store.document).evaluate(store.document.cadDocument)
        #expect(evaluated.brep.bodies.count == 1)
        draft.draftDegrees = "90"
        #expect(throws: EditorError.self) { try draft.command(in: document) }
    }

    @Test func facesExtrudeIndividuallyOrDirectlyWithTheirBody() throws {
        let node = SceneNodeID()
        let faces = [0, 1].map { SelectionTarget(sceneNodeID: node, component: .face(SelectionComponentID(rawValue: "generatedTopology:face/\($0)"))) }
        var draft = makeDraft(.extrude, targets: faces)
        draft.distance = "5 mm"
        draft.startDistance = "0"
        draft.extrudesIndividually = true
        draft.solidBoolean = .union
        #expect(draft.extrudesFaces)
        guard case .extrudeFaces(let targets, let distance, _, let individual, let operation, _, _, _) = try draft.command(in: .empty()) else {
            Issue.record("Faces extrude through extrudeFaces.")
            return
        }
        #expect(targets == faces && individual && operation == .union)
        #expect(distance == .length(0.005, .meter))
        draft.sheet = true
        #expect(throws: EditorError.self) { try draft.command(in: .empty()) }

        // An edge, or a face beside a whole object, is not read as its whole object.
        let edge = SelectionTarget(sceneNodeID: node, component: .edge(SelectionComponentID(rawValue: "generatedTopology:edge/0")))
        for targets in [[edge], [faces[0], SelectionTarget(sceneNodeID: SceneNodeID(), component: .object)]] {
            var mixed = makeDraft(.extrude, targets: targets)
            mixed.distance = "5 mm"
            #expect(mixed.extrudesFaces == false)
            #expect(throws: EditorError.self) { try mixed.command(in: .empty()) }
        }
    }

    /// A 10 × 300 mm strip 20–30 mm from a Y axis at x = 50 mm, and a 100 mm cube it bores
    /// through.
    private func stripAndCube(in document: inout DesignDocument) throws -> (strip: FeatureID, stripTarget: SelectionTarget, cube: FeatureID, cubeNode: SceneNodeID) {
        let strip = try document.createRectangleSketchFromCorners(
            name: "Strip", plane: .xy,
            firstCorner: SketchPoint(x: .length(0.02, .meter), y: .length(-0.1, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.03, .meter), y: .length(0.2, .meter))
        )
        let cube = try document.createExtrudedRectangleFromCorners(
            name: "Cube", plane: .plane(Plane3D(origin: Point3D(x: 0, y: 0, z: -0.05), normal: .unitZ)),
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.1, .meter), y: .length(0.1, .meter)),
            depth: .length(0.1, .meter), direction: .normal
        )
        let stripNode = try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(strip) })
        let cubeNode = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == cube }).id
        return (strip, SelectionTarget(sceneNodeID: stripNode.id), cube, cubeNode)
    }

    @Test func aRevolveCombinesWithTheBodiesAfterItsSection() throws {
        var document = DesignDocument.empty()
        let fixture = try stripAndCube(in: &document)
        var draft = makeDraft(.revolve, targets: [fixture.stripTarget, SelectionTarget(sceneNodeID: fixture.cubeNode)])
        draft.origin = ["50 mm", "0", "0"]
        // A new body takes one section only.
        #expect(throws: EditorError.self) { try draft.command(in: document) }
        draft.solidBoolean = .difference
        draft.keepsTools = true
        guard case .revolveSection(_, let section, _, _, let resultKind, let operation, let targets, let keepTools, _) = try draft.command(in: document) else {
            Issue.record("A Boolean revolve is one revolve.")
            return
        }
        #expect(section == .profile(ProfileReference(featureID: fixture.strip)) && resultKind == .solid)
        #expect(operation == .difference && keepTools && targets == [fixture.cube])
        draft.keepsTools = false
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        #expect(store.document.productMetadata.sceneNodes[fixture.cubeNode] == nil)
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        // The tube's 20–30 mm annulus bores 100 mm through the cube.
        #expect(abs(measurement.totals.solidVolumeCubicMeters - (0.001 - Double.pi * (0.03 * 0.03 - 0.02 * 0.02) * 0.1)) < 1e-12)
        draft.sheet = true
        #expect(throws: EditorError.self) { try draft.command(in: document) }
    }

    @Test func aThinRevolveTakesItsAxisFromTwoPoints() throws {
        var document = DesignDocument.empty()
        let fixture = try stripAndCube(in: &document)
        var draft = makeDraft(.revolve, targets: [fixture.stripTarget])
        draft.revolveAxisChoice = .twoPoints
        draft.origin = ["50 mm", "0", "0"]
        draft.axisEnd = ["50 mm", "0", "0"]
        #expect(throws: EditorError.self) { try draft.command(in: document) }
        draft.axisEnd = ["50 mm", "10 mm", "0"]
        draft.angle = "90"
        draft.wallThickness = "2 mm"
        guard case .revolveSection(_, _, let axis, _, _, _, _, _, let thickness) = try draft.command(in: document) else {
            Issue.record("A thin revolve is one revolve.")
            return
        }
        let direction = try axis.direction.normalized(tolerance: 1e-12)
        #expect(axis.origin == Point3D(x: 0.05, y: 0, z: 0) && direction == .unitY)
        #expect(thickness == .length(0.002, .meter))
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        // Pappus: the strip's 2 mm ring (6 × 296 mm hollow), 25 mm from the axis, a quarter turn,
        // beside the 100 mm cube.
        let ring = 0.01 * 0.3 - 0.006 * 0.296
        #expect(abs(measurement.totals.solidVolumeCubicMeters - (0.001 + 0.25 * 2 * Double.pi * 0.025 * ring)) < 1e-12)
    }

    @Test func aThinExtrusionCarriesItsWallThickness() throws {
        var document = DesignDocument.empty()
        let profile = try addProfile(to: &document, z: 0)
        var draft = makeDraft(.extrude, targets: [profile.target])
        draft.distance = "5 mm"
        draft.wallThickness = "1 mm"
        guard case .createExtrusion(_, let source) = try draft.command(in: document) else {
            Issue.record("A thin extrusion is one authored extrusion.")
            return
        }
        #expect(source.thickness == .length(0.001, .meter))
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        // The 4 × 12 mm rectangle's 1 mm wall, 5 mm tall.
        #expect(abs(measurement.totals.solidVolumeCubicMeters - (0.004 * 0.012 - 0.002 * 0.010) * 0.005) < 1e-12)
        draft.sheet = true
        #expect(throws: EditorError.self) { try draft.command(in: document) }
    }

    @Test(arguments: ModelingOperationDraft.ExtrusionDirectionChoice.allCases)
    func curveExtrusionDirectionEvaluates(direction: ModelingOperationDraft.ExtrusionDirectionChoice) throws {
        var document = DesignDocument.empty()
        let source = try document.createLineSketch(name: "Section", plane: .xy,
            start: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            end: SketchPoint(x: .length(0.04, .meter), y: .length(0, .meter)))
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(source) })
        var draft = makeDraft(.extrude, targets: [.init(sceneNodeID: node.id)])
        draft.isSurfaceCreation = true
        draft.distance = "10 mm"
        draft.extrusionDirection = direction
        draft.axis = ["0", "1", "0"]
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let result = try DocumentEvaluator.modelingDefault(for: store.document).evaluateExact(store.document.cadDocument)
        #expect(result.brep.faces.count == 1)
        #expect(result.brep.bodies.values.allSatisfy { $0.kind == .sheet })
        let points = result.brep.vertices.values.map(\.point)
        let coordinates = points.map { direction == .vector ? $0.y : $0.z }
        let lower = direction == .symmetric ? -0.005 : 0
        let upper = direction == .symmetric ? 0.005 : 0.01
        #expect(abs(try #require(coordinates.min()) - lower) < 1e-8)
        #expect(abs(try #require(coordinates.max()) - upper) < 1e-8)
        draft.extrusionDirection = .vector
        draft.axis = ["0", "0", "0"]
        #expect(throws: (any Error).self) { try draft.command(in: document) }
    }

    @Test(arguments: [false, true])
    func loftPreservesExplicitSectionOrderAndEvaluates(sheet: Bool) throws {
        var document = DesignDocument.empty()
        let first = try addProfile(to: &document, z: 0)
        let second = try addProfile(to: &document, z: 0.02)
        var draft = makeDraft(.loft, targets: [first.target, second.target])
        draft.sheet = sheet
        draft.smooth = true
        draft.loftDefaultTension = "0.8"
        for target in draft.targets {
            #expect(try draft.sectionReference(for: target.sceneNodeID, in: document).isProfile)
            var controls = LoftSectionDraft()
            controls.profileDirection = .reversed
            draft.loftSectionControls[target.sceneNodeID] = controls
        }
        draft.targets.swapAt(0, 1)
        guard case .createLoft(_, let sections, _, let options, _) = try draft.command(in: document) else {
            Issue.record("Expected loft source command.")
            return
        }
        #expect(sections.map(\.featureID) == [second.feature, first.feature])
        #expect(sections.allSatisfy { $0.profileDirection == .reversed })
        #expect(options.resultKind == (sheet ? .sheet : .solid))
        #expect(options.smoothTangentScale == 0.8)
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let evaluated = try CADPipeline.modelingDefault(for: store.document).evaluate(store.document.cadDocument)
        #expect(evaluated.brep.bodies.count == 1)
        for invalid in ["", "0", "-1", "nan", "inf", "1 mm"] {
            draft.loftDefaultTension = invalid
            #expect(throws: (any Error).self) { try draft.command(in: document) }
        }
    }

    @Test func loftUsesTheExplicitlySelectedProfileRegion() throws {
        var document = DesignDocument.empty()
        var targets: [SelectionTarget] = []
        var expectedMinimumX: Double?
        for z in [0.0, 0.02] {
            let original = try addProfile(to: &document, z: z)
            let extra = try document.createRectangleSketchFromCorners(name: "Second region", plane: .xy,
                firstCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0, .meter)),
                oppositeCorner: SketchPoint(x: .length(0.026, .meter), y: .length(0.012, .meter)))
            var feature = try #require(document.cadDocument.designGraph.nodes[original.feature])
            guard case .sketch(var sketch) = feature.operation,
                  case .sketch(let additional) = document.cadDocument.designGraph.nodes[extra]?.operation else {
                Issue.record("Expected source sketches."); return
            }
            for (id, entity) in additional.entities { sketch.entities[id] = entity }
            sketch.entityOrder += additional.entityOrder
            sketch.constraints += additional.constraints
            sketch.dimensions += additional.dimensions
            feature.operation = .sketch(sketch)
            try document.cadDocument.replaceFeature(feature, tolerance: document.modelingSettings.tolerance)
            let profiles = try SketchProfileExtractor(tolerance: document.modelingSettings.tolerance)
                .extractProfiles(from: sketch, sourceFeatureID: original.feature,
                    parameters: ParameterResolver().resolve(document.cadDocument.parameters))
            #expect(profiles.count == 2)
            expectedMinimumX = profiles[1].vertices.map(\.x).min()
            targets.append(SelectionTarget(sceneNodeID: original.target.sceneNodeID,
                component: .region(.profileRegion(featureID: original.feature, profileIndex: 1))))
        }
        var draft = makeDraft(.loft, targets: targets)
        let command = try draft.command(in: document)
        guard case .createLoft(_, let sections, _, _, _) = command else { Issue.record("Expected Loft."); return }
        #expect(sections.allSatisfy { if case .profile(let reference) = $0.section { return reference.profileIndex == 1 }; return false })
        for kind in [ModelingOperationDraft.Kind.extrude, .revolve] {
            let sibling = makeDraft(kind, targets: [targets[0]])
            let reference: SectionReference
            switch try sibling.command(in: document) {
            case .extrudeSection(_, let section, _, _, _, _), .revolveSection(_, let section, _, _, _, _, _, _, _): reference = section
            default: Issue.record("Expected a section operation."); return
            }
            #expect(reference == sections[0].section)
        }
        let store = CADDocumentStore(document: document)
        _ = try store.apply(command)
        let result = try DocumentEvaluator.modelingDefault(for: store.document).evaluateExact(store.document.cadDocument)
        #expect(abs(try #require(result.brep.vertices.values.map { $0.point.x }.min()) - #require(expectedMinimumX)) < 1e-10)
        let path = try document.createLineSketch(name: "Sweep path", plane: .yz,
            start: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            end: SketchPoint(x: .length(0, .meter), y: .length(0.03, .meter)))
        let pathNode = try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(path) })
        let sweepDraft = makeDraft(.sweep, targets: [targets[0], SelectionTarget(sceneNodeID: pathNode.id)])
        let sweepCommand = try sweepDraft.command(in: document)
        guard case .createSweep(_, let sweepSections, _, _, _, _, _) = sweepCommand else {
            Issue.record("Expected Sweep."); return
        }
        #expect(sweepSections == [sections[0].section])
        let sweepStore = CADDocumentStore(document: document)
        _ = try sweepStore.apply(sweepCommand)
        let sweepResult = try DocumentEvaluator.modelingDefault(for: sweepStore.document).evaluateExact(sweepStore.document.cadDocument)
        #expect(sweepResult.brep.bodies.count == 1)
        draft.targets.append(SelectionTarget(sceneNodeID: targets[0].sceneNodeID,
            component: .region(.profileRegion(featureID: sections[0].featureID, profileIndex: 0))))
        #expect(throws: EditorError.self) { try draft.command(in: document) }
    }

    @Test func loftHistorySectionReplacementReevaluatesTheExistingFeature() throws {
        var document = DesignDocument.empty()
        let first = try addProfile(to: &document, z: 0)
        let second = try addProfile(to: &document, z: 0.02)
        let third = try addProfile(to: &document, z: 0.04)
        let creation = makeDraft(.loft, targets: [first.target, second.target])
        let store = CADDocumentStore(document: document)
        _ = try store.apply(creation.command(in: document))
        let feature = try #require(store.document.cadDocument.designGraph.nodes.values.first {
            if case .loft = $0.operation { return true }; return false
        })
        var history = try #require(LoftFeatureDraft(feature: feature))
        history.removeSection(second.feature)
        history.appendSection(.profile(ProfileReference(featureID: third.feature)))
        _ = try store.apply(history.command())
        let edited = try #require(store.document.cadDocument.designGraph.nodes[feature.id])
        #expect(edited.inputs.map(\.featureID) == [first.feature, third.feature])
        let result = try DocumentEvaluator.modelingDefault(for: store.document).evaluateExact(store.document.cadDocument)
        #expect(result.brep.bodies.count == 1)
        let maximumZ = try #require(result.brep.vertices.values.map { $0.point.z }.max())
        #expect(abs(maximumZ - 0.04) < 1e-10)
    }

    @Test func loftGuideRolesSurviveReorderingAndReachExactConstruction() throws {
        var document = DesignDocument.empty()
        var targets: [SelectionTarget] = []
        for index in 0..<2 {
            let source = try document.createLineSketch(name: "Section \(index)",
                plane: .plane(Plane3D(origin: Point3D(x: 0, y: 0, z: Double(index) * 0.02), normal: .unitZ)),
                start: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
                end: SketchPoint(x: .length(0.04, .meter), y: .length(0, .meter)))
            let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(source) })
            targets.append(.init(sceneNodeID: node.id))
        }
        let guide = try document.createLineSketch(name: "Guide", plane: .zx,
            start: SketchPoint(x: .length(0, .meter), y: .length(0.01, .meter)),
            end: SketchPoint(x: .length(0.02, .meter), y: .length(0.03, .meter)))
        let guideNode = try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(guide) })
        var draft = makeDraft(.loft, targets: targets + [.init(sceneNodeID: guideNode.id)])
        draft.isSurfaceCreation = true
        // The guided sides are read in their tensor charts, so they stay B-spline patches.
        draft.loftSimplify = false
        draft.loftGuideNodeIDs.insert(guideNode.id)
        draft.targets.insert(draft.targets.removeLast(), at: 0)
        let command = try draft.command(in: document)
        guard case .createLoft(_, let sections, let guides, _, _) = command else {
            Issue.record("Expected a Loft command."); return
        }
        #expect(sections.count == 2)
        #expect(guides == [LoftGuideReference(featureID: guide)])
        #expect(draft.operandTitle(at: 0, in: document) == "Guide 1: Guide")
        let store = CADDocumentStore(document: document)
        _ = try store.apply(command)
        let result = try DocumentEvaluator.modelingDefault(for: store.document).evaluateExact(store.document.cadDocument)
        #expect(result.brep.faces.count == 2)
        let contacts = try result.brep.geometry.surfaces.values.flatMap { surface in
            try [0.0, 1.0].map { try surface.point(u: $0, v: 0.5, tolerance: .standard) }
        }
        #expect(contacts.filter { ($0 - Point3D(x: 0.02, y: 0, z: 0.01)).length < 1e-8 }.count == 2)
        draft.loftGuideNodeIDs.insert(targets[0].sceneNodeID)
        #expect(throws: EditorError.self) { try draft.command(in: document) }
        draft.loftGuideNodeIDs.remove(targets[0].sceneNodeID)
        document.productMetadata.sceneNodes[guideNode.id]?.isLocked = true
        #expect(throws: EditorError.self) { try draft.command(in: document) }
    }

    @Test func loftCurveControlsFollowOperandsAndBuildRestrictedGeometry() throws {
        var document = DesignDocument.empty()
        var targets: [SelectionTarget] = []
        for index in 0..<2 {
            let source = try document.createLineSketch(name: "Section \(index)",
                plane: .plane(Plane3D(origin: Point3D(x: 0, y: 0, z: Double(index) * 0.02), normal: .unitZ)),
                start: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
                end: SketchPoint(x: .length(0.04, .meter), y: .length(0, .meter)))
            let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(source) })
            targets.append(.init(sceneNodeID: node.id))
        }
        var draft = makeDraft(.loft, targets: targets)
        draft.isSurfaceCreation = true
        draft.smooth = true
        draft.loftSectionControls[targets[0].sceneNodeID] = .init(tangentScale: "0.5",
            usesCurveInterval: true, lowerParameter: "0.01", upperParameter: "0.03", isReversed: true)
        draft.loftSectionControls[targets[1].sceneNodeID] = .init(tangentScale: "1.25",
            usesCurveInterval: true, lowerParameter: "0.005", upperParameter: "0.035", isReversed: true)
        draft.targets.reverse()
        let command = try draft.command(in: document)
        guard case .createLoft(_, let sections, _, _, _) = command else { Issue.record("Expected Loft."); return }
        #expect(sections.map(\.smoothTangentScale) == [1.25, 0.5])
        guard case .curve(let first) = sections[0].section else { Issue.record("Expected curve."); return }
        #expect(first.parameterDomain == .closed(0.005, 0.035))
        #expect(first.isReversed)
        let store = CADDocumentStore(document: document)
        _ = try store.apply(command)
        let result = try DocumentEvaluator.modelingDefault(for: store.document).evaluateExact(store.document.cadDocument)
        #expect(result.brep.faces.count == 1)
        let surface = try #require(result.brep.geometry.surfaces.values.first)
        #expect(abs(try surface.point(u: 0, v: 0, tolerance: .standard).x - 0.035) < 1e-10)
        let points = result.brep.vertices.values.map(\.point)
        #expect(abs(try #require(points.map(\.x).min()) - 0.005) < 1e-10)
        #expect(abs(try #require(points.map(\.x).max()) - 0.035) < 1e-10)
        for value in ["nan", "0.001", "nonsense"] {
            draft.loftSectionControls[targets[0].sceneNodeID]?.upperParameter = value
            #expect(throws: EditorError.self) { try draft.command(in: document) }
        }
    }

    @Test func loftMixesProfileSelectionWithClosedCurveSelection() throws {
        var document = DesignDocument.empty()
        var targets: [SelectionTarget] = []
        for index in 0..<2 {
            let id = try document.createCircleSketch(name: "Section \(index)",
                plane: .plane(Plane3D(origin: Point3D(x: 0, y: 0, z: Double(index) * 0.02), normal: .unitZ)),
                center: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)), radius: .length(0.01, .meter))
            let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(id) })
            if index == 0 {
                targets.append(SelectionTarget(sceneNodeID: node.id))
            } else {
                let feature = try #require(document.cadDocument.designGraph.nodes[id])
                guard case .sketch(let sketch) = feature.operation else { Issue.record("Expected sketch."); return }
                let entity = try #require(sketch.entities.keys.first)
                targets.append(SelectionTarget(sceneNodeID: node.id,
                    component: .sketchEntity(.sketchEntity(featureID: id, entityID: entity))))
            }
        }
        var draft = makeDraft(.loft, targets: targets)
        draft.isSurfaceCreation = true
        let command = try draft.command(in: document)
        guard case .createLoft(_, let sections, _, _, _) = command else { Issue.record("Expected Loft."); return }
        #expect(sections[0].section.isProfile)
        #expect(!sections[1].section.isProfile)
        let store = CADDocumentStore(document: document)
        _ = try store.apply(command)
        let result = try DocumentEvaluator.modelingDefault(for: store.document).evaluateExact(store.document.cadDocument)
        #expect(result.brep.faces.count == 4)
        #expect(result.brep.bodies.values.allSatisfy { $0.kind == .sheet })
    }

    @Test func invalidTextAndSelectionNeverProduceACommand() throws {
        var draft = makeDraft(.box)
        for value in ["", "nonsense", "nan", "inf", "0", "-1 mm"] {
            draft.distance = value
            #expect(throws: (any Error).self) { try draft.command(in: .empty()) }
        }
        draft = makeDraft(.extrude)
        #expect(throws: (any Error).self) { try draft.command(in: .empty()) }
        var document = DesignDocument.empty()
        let profile = try addProfile(to: &document, z: 0)
        draft = makeDraft(.revolve, targets: [profile.target])
        draft.axis = ["0", "0", "0"]
        #expect(throws: (any Error).self) { try draft.command(in: document) }
    }

    @Test func transformedOrNonCADOperandsAreNotSilentlyReinterpreted() throws {
        var document = DesignDocument.empty()
        let profile = try addProfile(to: &document, z: 0)
        let draft = makeDraft(.extrude, targets: [profile.target])
        try document.setSceneNodeTransform(id: profile.target.sceneNodeID, localTransform: Transform3D(matrix: Matrix4x4(values: [
            1, 0, 0, 0.1, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1,
        ])))
        #expect(throws: EditorError.self) { try draft.command(in: document) }
        try document.setSceneNodeTransform(id: profile.target.sceneNodeID, localTransform: .identity)
        document.productMetadata.sceneNodes[profile.target.sceneNodeID]?.object?.geometryRepresentations = .empty
        #expect(throws: EditorError.self) { try draft.command(in: document) }
    }

    @Test func edgeTreatmentForwardsExactAmountAndAllEdges() throws {
        var document = DesignDocument.empty()
        let profile = try addProfile(to: &document, z: 0)
        let edge = SelectionTarget(sceneNodeID: profile.target.sceneNodeID, component: .edge(.generatedTopology(SubshapeID(featureID: profile.feature, role: "body:edge:first", ordinal: 0))))
        var draft = makeDraft(.fillet, targets: [edge])
        draft.distance = "0.025 in"
        #expect(try draft.command(in: document) == .createBodyEdgeTreatment(name: draft.name,
            target: edge, treatment: .fillet(radius: .length(0.025 * 0.0254, .meter))))
        draft.kind = .chamfer
        draft.distance = "0.75 mm"
        #expect(try draft.command(in: document) == .createBodyEdgeTreatment(name: draft.name,
            target: edge, treatment: .chamfer(distance: .length(0.00075, .meter))))
        draft.kind = .g2Blend
        #expect(try draft.command(in: document) == .createBodyEdgeTreatment(name: draft.name,
            target: edge, treatment: .g2Blend(distance: .length(0.00075, .meter))))
        draft.targets.append(edge)
        #expect(throws: EditorError.self) { try draft.command(in: document) }
    }

    /// Every workspace scale the app ships opens a primitive draft the kernel
    /// accepts.
    ///
    /// The seeded values are sizes, so they have to exceed the document's
    /// distance tolerance at the finest scale as well as read sensibly at the
    /// coarsest. Planning alone cannot prove that: `command(in:)` and the
    /// kernel hold separate preconditions, so each default is applied and
    /// evaluated. A default the kernel would refuse is a failure here rather
    /// than a recorded failure the first time someone opens the panel.
    @Test(arguments: WorkspaceScalePreset.allCases)
    func everyWorkspaceScaleOpensPrimitivesTheKernelAccepts(
        preset: WorkspaceScalePreset
    ) throws {
        for kind in [ModelingOperationDraft.Kind.box, .cylinder, .sphere] {
            let draft = ModelingOperationDraft(
                kind: kind,
                selection: SelectionModel(selectedTargets: []),
                ruler: preset.rulerConfiguration
            )
            let store = CADDocumentStore(document: .empty())
            _ = try store.apply(draft.command(in: store.document))
            let evaluated = try CADPipeline
                .modelingDefault(for: store.document)
                .evaluate(store.document.cadDocument)
            #expect(
                evaluated.brep.bodies.count == 1,
                "\(preset.rawValue) opened \(kind.rawValue) the kernel refused."
            )
        }
    }

    /// A length that establishes geometry is held to the document's distance
    /// tolerance; an amount applied to geometry that already exists is held to
    /// Core's own floor for it.
    ///
    /// The two thresholds differ because Core holds two: a size at or below
    /// the tolerance is degenerate and refused, while an edge treatment is
    /// asked only to be positive and its geometric outcome is decided when the
    /// edit is evaluated. Holding both here keeps the panel from inventing a
    /// threshold Core does not have, which would refuse a micrometre chamfer
    /// on a part measured in micrometres.
    @Test func aSizeAtTheDocumentToleranceNamesNoCommand() throws {
        var document = DesignDocument.empty()
        let toleranceMeters = document.modelingSettings.tolerance.distance
        var draft = makeDraft(.sphere)
        draft.width = fieldText(forMeters: toleranceMeters, preferredUnit: draft.unit)
        #expect(throws: EditorError.self) { try draft.command(in: document) }
        draft.width = fieldText(forMeters: toleranceMeters * 100.0, preferredUnit: draft.unit)
        #expect(throws: Never.self) { try draft.command(in: document) }

        let profile = try addProfile(to: &document, z: 0)
        let edge = SelectionTarget(
            sceneNodeID: profile.target.sceneNodeID,
            component: .edge(
                .generatedTopology(
                    SubshapeID(featureID: profile.feature, role: "body:edge:first", ordinal: 0)
                )
            )
        )
        var chamfer = makeDraft(.chamfer, targets: [edge])
        chamfer.distance = fieldText(forMeters: toleranceMeters, preferredUnit: chamfer.unit)
        #expect(throws: EditorError.self) { try chamfer.command(in: document) }
        chamfer.distance = "0 mm"
        #expect(throws: EditorError.self) { try chamfer.command(in: document) }
    }

    @Test func anOperandProducingNoSectionNamesNoSweptCommand() throws {
        var document = DesignDocument.empty()
        let profile = try addProfile(to: &document, z: 0)
        let body = try addBody(to: &document)

        func refusal(_ draft: ModelingOperationDraft) -> String {
            do {
                _ = try draft.command(in: document)
                Issue.record("An operand producing no section named a command.")
                return ""
            } catch let error as EditorError {
                #expect(error.code == .referenceUnresolved)
                return error.message
            } catch {
                Issue.record("Planning failed with an untyped error: \(error).")
                return ""
            }
        }

        // Distinguish missing output from operand-count or geometry refusals.
        var draft = makeDraft(.extrude, targets: [body])
        draft.distance = "5 mm"
        #expect(refusal(draft) == "Source has no profile or curve section output.")
        draft.kind = .revolve
        #expect(refusal(draft) == "Source has no profile or curve section output.")
        draft.kind = .loft
        draft.targets = [profile.target, body]
        #expect(refusal(draft) == "Source has no profile or curve section output.")
    }

    /// A field value the panel would show for a length, so a test drives the
    /// same text a reader would see rather than a number the parser never gets.
    private func fieldText(forMeters meters: Double, preferredUnit: LengthDisplayUnit) -> String {
        let presentation = workspaceLengthFieldPresentation(
            fromMeters: meters,
            preferredUnit: preferredUnit
        )
        return presentation.text + " " + presentation.unit.symbol
    }

    private func makeDraft(_ kind: ModelingOperationDraft.Kind, targets: [SelectionTarget] = []) -> ModelingOperationDraft {
        ModelingOperationDraft(
            kind: kind,
            selection: SelectionModel(selectedTargets: targets),
            ruler: .standard(for: .millimeter)
        )
    }

    /// A solid body, which is a CAD feature that outputs no profile.
    private func addBody(to document: inout DesignDocument) throws -> SelectionTarget {
        let sketch = try document.createRectangleSketchFromCorners(
            name: "Body Sketch", plane: .xy,
            firstCorner: SketchPoint(x: .length(0, .millimeter), y: .length(0, .millimeter)),
            oppositeCorner: SketchPoint(x: .length(8, .millimeter), y: .length(8, .millimeter))
        )
        let feature = try document.extrudeProfile(
            name: "Body", profile: ProfileReference(featureID: sketch),
            distance: .length(4, .millimeter), direction: .normal
        )
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .body(feature) })
        return SelectionTarget(sceneNodeID: node.id)
    }

    private func addProfile(to document: inout DesignDocument, z: Double) throws -> (feature: FeatureID, target: SelectionTarget) {
        let feature = try document.createRectangleSketchFromCorners(
            name: "Profile", plane: .plane(Plane3D(origin: Point3D(x: 0, y: 0, z: z), normal: .unitZ)),
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.004, .meter), y: .length(0.012, .meter))
        )
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(feature) })
        return (feature, SelectionTarget(sceneNodeID: node.id))
    }
}
