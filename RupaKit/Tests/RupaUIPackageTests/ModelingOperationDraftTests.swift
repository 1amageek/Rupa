import Foundation
import Testing
import RupaCore
import SwiftCAD
@testable import RupaUI

@Suite("Modeling operation drafts", .timeLimit(.minutes(1)))
struct ModelingOperationDraftTests {
    @Test func surfaceAndSweepDialogsPreviewLiveAndConfirmOnRightClick() {
        // Plasticity's surface and sweep dialogs preview as they are edited; the primitives, the
        // edge treatments and the sheet edits keep their Preview button.
        #expect(Set(ModelingOperationDraft.Kind.allCases.filter(\.previewsLive))
            == [.constrainedSurface, .square, .xnurbs, .bridgeSurface, .loft, .patch, .bridge, .pipe, .sweep, .extrude, .revolve])
    }

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
        } else if kind == .loft {
            // Curves loft into a sheet whether or not Sheet output is on, as Plasticity lofts them.
            guard case .createLoft(_, _, _, let options, _) = try draft.command(in: document) else {
                Issue.record("A Loft of curves is one loft.")
                return
            }
            #expect(options.resultKind == .sheet)
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
        // A blank allowance takes the planner's default, as Plasticity asks for none.
        guard case .createSweep(_, _, _, _, _, let defaulted, _) = try draft.command(in: document) else {
            Issue.record("Expected native Sweep source intent.")
            return
        }
        #expect(defaulted.approximationTolerance == SweepSelectionPlanningService.defaultApproximationAllowance)
        draft.approximationTolerance = "0.002 mm"
        // Scale sizes the end section; Distance cuts the sweep to that fraction of its path.
        draft.sweepEndScale = "1.8"
        draft.sweepDistance = "0.5"
        guard case .createSweep(_, _, _, _, _, let options, _) = try draft.command(in: document) else {
            Issue.record("Expected native Sweep source intent.")
            return
        }
        #expect(options.endScale == .constant(.scalar(1.8)) && options.distanceFraction == .constant(.scalar(0.5)))
        #expect(options.twistAngle == .angle(0, .degree))
        #expect(options.approximationTolerance == .length(0.000002, .meter))
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
        draft.sweepDistance = "0"
        #expect(throws: EditorError.self) { try draft.command(in: document) }
        draft.sweepDistance = "1"
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
        // Left blank, the allowance is the planner's default and the curved Normal sweep builds.
        draft.approximationTolerance = ""
        let defaulted = CADDocumentStore(document: document)
        _ = try defaulted.apply(draft.command(in: document))
        #expect(defaulted.evaluationStatus == .valid)
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
        // A negative thickness hollows the section; a positive one grows outside it.
        draft.wallThickness = "-1 mm"
        guard case .createPipes(_, let sources, _) = try draft.command(in: document) else {
            Issue.record("Expected native Pipe source intent.")
            return
        }
        #expect(sources.map(\.path.featureID) == paths && sources.allSatisfy { $0.thickness == .length(-0.001, .meter) })
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        #expect(measurement.counts.solids == 2)
        #expect(abs(measurement.totals.solidVolumeCubicMeters - 2 * Double.pi * (0.005 * 0.005 - 0.004 * 0.004) * 0.05) < 1e-12)

        // Distance 1 below 0 runs the pipe on past the path's start; the twist reaches the source.
        var longer = draft
        longer.wallThickness = "1 mm"
        longer.pipeStart = "-0.2"
        longer.pipeTwist = "45"
        guard case .createPipes(_, let extended, _) = try longer.command(in: document) else {
            Issue.record("Expected native Pipe source intent.")
            return
        }
        #expect(extended.allSatisfy { $0.start == .scalar(-0.2) && $0.twist == .angle(45, .degree) })
        let grown = CADDocumentStore(document: document)
        _ = try grown.apply(longer.command(in: document))
        let sleeve = try MeasurementService().measure(document: grown.document, ruler: .standard(for: .meter))
        #expect(abs(sleeve.totals.solidVolumeCubicMeters - 2 * Double.pi * (0.006 * 0.006 - 0.005 * 0.005) * 0.06) < 1e-12)

        draft.pipeVertices = "2"
        #expect(throws: EditorError.self) { try draft.command(in: document) }
        draft.pipeVertices = "0"
        draft.solidBoolean = .union
        #expect(throws: EditorError.self) { try draft.command(in: document) }
    }

    @Test func pipeSweepAndXNurbsTakeTheirOperandsBySlot() throws {
        // Plasticity's dialogs pick into slots: Pipe's target bodies may be picked before its
        // curves, Sweep's spine before its guides, XNURBS's guides after its boundaries.
        var document = DesignDocument.empty()
        let box = try document.createExtrudedRectangleFromCorners(
            name: "Box", plane: .xy,
            firstCorner: SketchPoint(x: .length(-0.01, .meter), y: .length(-0.01, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.01, .meter), y: .length(0.01, .meter)),
            depth: .length(0.02, .meter), direction: .normal
        )
        let lines = try [0.0, 0.003, 0.006].map { x in
            try document.createLineSketch(name: "Line", plane: .zx,
                start: SketchPoint(x: .length(0, .meter), y: .length(x, .meter)),
                end: SketchPoint(x: .length(0.05, .meter), y: .length(x, .meter)))
        }
        let boxNode = try #require(document.productMetadata.sceneNodes.values.first { $0.object?.sourceFeatureID == box })
        let lineNodes = try lines.map { line in try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(line) }) }
        let body = SelectionTarget(sceneNodeID: boxNode.id)
        let curves = lineNodes.map { SelectionTarget(sceneNodeID: $0.id) }

        var pipe = makeDraft(.pipe, targets: [])
        pipe.pipeDiameter = "2 mm"
        pipe.solidBoolean = .union
        #expect(pipe.operandSlots == [.paths, .targetBodies])
        // A curve is not a target body.
        pipe.use([body, curves[0]], for: .targetBodies, document: document)
        #expect(pipe.operands(in: .targetBodies, document: document) == [body] && pipe.targets == [body])
        #expect(throws: EditorError.self) { try pipe.command(in: document) }
        pipe.use([curves[0]], for: .paths, document: document)
        #expect(pipe.targets == [curves[0], body])
        guard case .createPipes(_, let sources, _) = try pipe.command(in: document) else {
            Issue.record("Expected native Pipe source intent.")
            return
        }
        #expect(sources.count == 1 && sources[0].path.featureID == lines[0] && sources[0].targets == [SweepTargetReference(featureID: box)])
        // Rearranging the list keeps each operand in its slot.
        pipe.targets.swapAt(0, 1)
        guard case .createPipes(_, let swapped, _) = try pipe.command(in: document) else {
            Issue.record("Expected native Pipe source intent.")
            return
        }
        #expect(swapped == sources)
        #expect(pipe.operandTitle(at: 0, in: document).hasPrefix("Target bodies"))

        var sweep = makeDraft(.sweep, targets: [])
        sweep.use([curves[0]], for: .section, document: document)
        sweep.use([curves[2]], for: .spine, document: document)
        sweep.use([curves[1]], for: .guides, document: document)
        // Read as the section, the guides, then the spine.
        #expect(sweep.targets == [curves[0], curves[1], curves[2]])
        #expect(sweep.operands(in: .spine, document: document) == [curves[2]])
        // Putting the spine in the section's slot moves it there, leaving the spine to pick.
        sweep.use([curves[2]], for: .section, document: document)
        #expect(sweep.missingOperandSlot(document: document) == .spine)
        #expect(throws: EditorError.self) { try sweep.command(in: document) }

        var xnurbs = makeDraft(.xnurbs, targets: [])
        xnurbs.use([curves[0], curves[1]], for: .boundaries, document: document)
        xnurbs.use([curves[2]], for: .guides, document: document)
        #expect(xnurbs.xnurbsGuideNodeIDs == [lineNodes[2].id] && xnurbs.operands(in: .boundaries, document: document) == [curves[0], curves[1]])
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
        draft.wallThickness = "-1 mm"
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
        // Curve keeps the section touching the guide, wherever on the section that is.
        draft.sweepGuide = .curve
        guard case .createSweep(_, _, _, _, _, let curve, _) = try draft.command(in: document) else {
            Issue.record("Expected native Sweep source intent.")
            return
        }
        #expect(curve.guideMethod == .curve)
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
        // G0 at both edges: the ruled sheet straight between them (Loft defaults to G1 there).
        draft.loftStartContinuity = .g0
        draft.loftEndContinuity = .g0
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
        draft.loftStartTension = "1.2"
        draft.loftEndTension = "1.2"
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
        // An end that is not an edge of a body takes no continuity; the edge's end keeps its own.
        draft.targets = [edges[0], .init(sceneNodeID: line.id)]
        guard case .createLoft(_, let mixed, _, _, _) = try draft.command(in: document) else {
            Issue.record("Expected a Loft from an edge to a curve.")
            return
        }
        #expect(mixed.map { $0.continuity?.order } == [.tangent, nil])
    }

    @Test func surfaceDialogsOpenOnPlasticitysDefaults() throws {
        let xnurbs = makeDraft(.xnurbs, targets: [])
        #expect(xnurbs.xnurbsTension == "0.5" && xnurbs.xnurbsFlatness == "0.95")
        #expect(makeDraft(.square, targets: []).squareTension == "0.5")
        let constrained = makeDraft(.constrainedSurface, targets: [])
        #expect(constrained.pointTolerance == "0.01 mm" && constrained.angularTolerance == "5")
        #expect(constrained.pointOptimization == .performance)
        #expect(DialogTensionScale.kernelScale(0.5) == 1 && DialogTensionScale.kernelScale(0) == 0.5)
    }

    @Test func loftDefaultsFollowPlasticity() throws {
        // Smooth connectors and G1 at both ends by default; each end its own tension; curves loft
        // into a sheet without Sheet output.
        let draft = makeDraft(.loft, targets: [])
        #expect(draft.smooth)
        #expect(draft.loftStartContinuity == .g1 && draft.loftEndContinuity == .g1)
        var document = DesignDocument.empty()
        let boxes = try [Point3D(x: 0, y: 0, z: 0), Point3D(x: 0, y: -0.07, z: 0.03)].map { origin in
            try document.createExtrudedRectangleFromCorners(
                name: "Box", plane: .plane(Plane3D(origin: origin, normal: .unitZ)),
                firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
                oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
                depth: .length(0.02, .meter), direction: .normal
            )
        }
        #expect(boxes.count == 2)
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        let edges = try [(0.0, 0.02), (-0.05, 0.03)].map { y, z in
            try #require(topology.entries.first { entry in
                guard entry.kind == .edge, let start = entry.start, let end = entry.end else { return false }
                return abs(start.y - y) < 1e-9 && abs(end.y - y) < 1e-9 && abs(start.z - z) < 1e-9 && abs(end.z - z) < 1e-9
            }?.selectionTarget())
        }
        var edgeLoft = makeDraft(.loft, targets: edges)
        edgeLoft.loftStartTension = "2.5"
        edgeLoft.loftEndTension = "1.5"
        guard case .createLoft(_, let sections, _, let options, _) = try edgeLoft.command(in: document) else {
            Issue.record("Expected a Loft of two edges.")
            return
        }
        #expect(options.resultKind == .sheet)
        #expect(options.surfaceMode == .smooth)
        #expect(sections.map { $0.continuity?.order } == [.tangent, .tangent])
        #expect(sections.map { $0.continuity?.tension } == [2.5, 1.5])
        let store = CADDocumentStore(document: document)
        _ = try store.apply(edgeLoft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        #expect(measurement.counts.sheets == 1)
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
        // Tangent Edges off wraps the treatment, the feature taking only the selected edges.
        chamfer.limitsReversed = false
        chamfer.tangentEdges = false
        guard case .createBodyEdgeTreatment(_, _, .tangentEdgesOff(.chamfer)) = try chamfer.command(in: document) else {
            Issue.record("Expected a chamfer with Tangent Edges off.")
            return
        }
        let alone = CADDocumentStore(document: document)
        _ = try alone.apply(chamfer.command(in: document))
        #expect(alone.document.cadDocument.designGraph.nodes.values.contains { node in
            if case let .chamfer(feature) = node.operation { return feature.tangentEdges == false }
            return false
        })
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

    @Test func filletClicksToggleEdgesAndCopyARoundsRadius() throws {
        let node = SceneNodeID()
        let edges = (0..<2).map { index in
            SelectionTarget(sceneNodeID: node, component: .edge(SelectionComponentID(rawValue: "generatedTopology:edge/\(index)")))
        }
        var draft = makeDraft(.fillet, targets: [edges[0]])
        draft.toggleFilletEdge(edges[1])
        #expect(draft.targets == edges)
        draft.toggleFilletEdge(edges[0])
        #expect(draft.targets == [edges[1]])
        draft.unit = .millimeter
        draft.copyFilletRadius(meters: 0.0025)
        #expect(draft.distance == "2.5 mm")
    }

    @Test func loftClicksToggleGuides() throws {
        let section = SelectionTarget(sceneNodeID: SceneNodeID())
        let curve = SelectionTarget(sceneNodeID: SceneNodeID())
        let edge = SelectionTarget(sceneNodeID: SceneNodeID(), component: .edge(SelectionComponentID(rawValue: "generatedTopology:edge/0")))
        var draft = makeDraft(.loft, targets: [section])
        draft.toggleLoftGuide(curve)
        draft.toggleLoftGuide(edge)
        #expect(draft.targets == [section, curve, edge] && draft.isLoftGuide(curve) && draft.isLoftGuide(edge))
        #expect(draft.isLoftGuide(section) == false)
        draft.toggleLoftGuide(curve)
        #expect(draft.targets == [section, edge] && draft.isLoftGuide(curve) == false)
    }

    @Test func fullIsOfferedOnlyForAPairOfEdges() throws {
        let node = SceneNodeID()
        let edges = (0..<2).map { index in
            SelectionTarget(sceneNodeID: node, component: .edge(SelectionComponentID(rawValue: "generatedTopology:edge/\(index)")))
        }
        var draft = makeDraft(.fillet, targets: [edges[0]])
        #expect(draft.offeredFilletShapes == [.conic, .chordal, .curvature])
        draft.targets = edges
        #expect(draft.offeredFilletShapes == [.conic, .chordal, .curvature, .full])
        draft.targets = edges + [edges[0]]
        #expect(draft.offeredFilletShapes.contains(.full) == false)
    }

    @Test func oneEdgeLoftsOnAlongTwoGuideEdges() throws {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedRectangleFromCorners(
            name: "Box", plane: .xy,
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
            depth: .length(0.02, .meter), direction: .normal
        )
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        func edge(_ isIt: (TopologySummaryResult.Entry.Point, TopologySummaryResult.Entry.Point) -> Bool) throws -> SelectionTarget {
            try #require(topology.entries.first { entry in
                guard entry.kind == .edge, let start = entry.start, let end = entry.end else { return false }
                return isIt(start, end)
            }?.selectionTarget())
        }
        // The top edge along X at y = 0, and the upright edges at its ends.
        let top = try edge { abs($0.z - 0.02) < 1e-9 && abs($1.z - 0.02) < 1e-9 && abs($0.y) < 1e-9 && abs($1.y) < 1e-9 }
        let left = try edge { abs($0.x) < 1e-9 && abs($1.x) < 1e-9 && abs($0.y) < 1e-9 && abs($1.y) < 1e-9 }
        let right = try edge { abs($0.x - 0.02) < 1e-9 && abs($1.x - 0.02) < 1e-9 && abs($0.y) < 1e-9 && abs($1.y) < 1e-9 }
        var draft = makeDraft(.loft, targets: [top, left, right])
        draft.loftGuideEdges = [left, right]
        // A box's edge has two faces beside it; the loft runs down one, so it starts G0.
        draft.loftStartContinuity = .g0
        guard case let .createLoft(_, sections, guides, options, _) = try draft.command(in: document) else {
            Issue.record("Expected a loft.")
            return
        }
        #expect(sections.count == 1 && guides.count == 2 && options.resultKind == .sheet)
        // The kernel lofts the top edge down the upright edges onto the bottom: the box's front.
        let store = CADDocumentStore(document: document)
        _ = try store.apply(try draft.command(in: document))
        let result = try DocumentEvaluator.modelingDefault(for: store.document).evaluateExact(store.document.cadDocument)
        let sheets = result.brep.bodies.values.filter { $0.kind == .sheet }
        #expect(sheets.count == 1)
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
        // Plasticity's default, Conic at 0.5, is the round of the distance's radius itself.
        #expect(draft.filletShape == .conic && draft.filletTension == "0.5")
        guard case .createBodyEdgeTreatment(_, _, .fillet) = try draft.command(in: document) else {
            Issue.record("Expected a round fillet.")
            return
        }
        draft.filletTension = "0.3"
        guard case .createBodyEdgeTreatment(_, _, let treatment) = try draft.command(in: document),
              case .shapedFillet(_, let shape, let tension) = treatment else {
            Issue.record("Expected a shaped fillet.")
            return
        }
        #expect(shape == .conic && tension == 0.3)
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        // A conic of tension 0.3 set back 4 mm: weight sin 45° · 3/7, flatter than the round.
        let w = 0.5.squareRoot() * 0.3 / 0.7, d = 0.004
        // The area between the conic and the corner's sides (the rational quadratic's segment).
        var area = 0.0
        var previous = (d, 0.0)
        for step in 1...20_000 {
            let t = Double(step) / 20_000
            let (b0, b1, b2) = ((1 - t) * (1 - t), 2 * t * (1 - t) * w, t * t)
            let next = ((b0 * d) / (b0 + b1 + b2), (b2 * d) / (b0 + b1 + b2))
            area += previous.0 * next.1 - next.0 * previous.1
            previous = next
        }
        #expect(measurement.counts.solids == 1)
        #expect(abs(measurement.totals.solidVolumeCubicMeters - (0.02 * 0.02 * 0.02 - abs(0.5 * area) * 0.02)) < 1e-11)
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

    @Test func aFullFilletRoundsABlocksTopAndBottomAtOnce() throws {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedRectangleFromCorners(
            name: "Block", plane: .xy,
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
            depth: .length(0.03, .meter), direction: .normal
        )
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        // The edges along X at y = 0 and y = 20 mm, on the top and then on the bottom.
        let edges = try [0.03, 0.0].flatMap { z in
            try [0.0, 0.02].map { y in
                try #require(topology.entries.first { entry in
                    guard entry.kind == .edge, let start = entry.start, let end = entry.end else { return false }
                    return abs(start.z - z) < 1e-9 && abs(end.z - z) < 1e-9 && abs(start.y - y) < 1e-9 && abs(end.y - y) < 1e-9
                }?.selectionTarget())
            }
        }
        var draft = makeDraft(.fillet, targets: edges)
        #expect(draft.offeredFilletShapes.contains(.full))
        draft.filletShape = .full
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        let r = 0.01
        #expect(measurement.counts.solids == 1)
        #expect(abs(measurement.totals.solidVolumeCubicMeters - (0.02 * 0.02 * 0.03 - 2 * 0.02 * (2 * r * r - Double.pi * r * r / 2))) < 1e-11)
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

    @Test func parallelSheetsBridgeBetweenTheirNearestEdges() throws {
        var document = DesignDocument.empty()
        func sheet(on plane: SketchPlane, _ corners: [(Double, Double)]) throws -> FeatureID {
            let lines = try corners.indices.map { index in
                let (start, end) = (corners[index], corners[(index + 1) % corners.count])
                return try document.createLineSketch(name: "Edge", plane: plane,
                    start: SketchPoint(x: .length(start.0, .meter), y: .length(start.1, .meter)),
                    end: SketchPoint(x: .length(end.0, .meter), y: .length(end.1, .meter)))
            }
            return try document.createCurvePatch(name: "Sheet", curves: lines.map { CurveSectionReference(featureID: $0) })
        }
        // A floor at z = 0 and a shelf 20 mm up, 20 mm apart across y: parallel planes.
        let floor = try sheet(on: .xy, [(0, 0.01), (0.04, 0.01), (0.04, 0.04), (0, 0.04)])
        let shelf = try sheet(on: .plane(Plane3D(origin: Point3D(x: 0, y: 0, z: 0.02), normal: .unitZ)),
                              [(0, -0.04), (0.04, -0.04), (0.04, -0.01), (0, -0.01)])
        let nodes = try [floor, shelf].map { feature in
            try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .body(feature) })
        }
        var draft = makeDraft(.bridgeSurface, targets: nodes.map { .init(sceneNodeID: $0.id) })
        draft.isSurfaceCreation = true
        draft.distance = "10 mm"
        draft.bridgeTrimsWalls = false
        guard case .createBridgeSurface(_, let bridge, _) = try draft.command(in: document) else {
            Issue.record("Expected a Bridge Surface.")
            return
        }
        #expect(bridge.angularAllowance != nil && bridge.curvatureAllowance != nil)
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        #expect(measurement.counts.sheets == 3)
        // The default, Both, joins the trimmed sheets with the bridge.
        draft.bridgeTrimsWalls = true
        let trimmed = CADDocumentStore(document: document)
        _ = try trimmed.apply(draft.command(in: document))
        #expect(try MeasurementService().measure(document: trimmed.document, ruler: .standard(for: .meter)).counts.sheets == 1)
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
        // Trim walls opens on Both.
        #expect(draft.bridgeTrimsWalls && draft.bridgeExtent == .both)
        draft.bridgeTrimsWalls = false
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
        draft.bridgeTrimsWalls = true
        let trimmed = CADDocumentStore(document: document)
        _ = try trimmed.apply(draft.command(in: document))
        let joined = try MeasurementService().measure(document: trimmed.document, ruler: .standard(for: .meter))
        #expect(joined.counts.sheets == 1)
        #expect(abs(joined.totals.sheetAreaSquareMeters - (2 * 0.04 * 0.02 + 0.02 * 2.0.squareRoot() * 0.04)) < 1e-12)
    }

    @Test func aSetAsideWallPairIsBridgedWithThePairPickedNext() throws {
        var document = DesignDocument.empty()
        func sheet(on plane: SketchPlane, _ corners: [(Double, Double)]) throws -> FeatureID {
            let lines = try corners.indices.map { index in
                let (start, end) = (corners[index], corners[(index + 1) % corners.count])
                return try document.createLineSketch(name: "Edge", plane: plane,
                    start: SketchPoint(x: .length(start.0, .meter), y: .length(start.1, .meter)),
                    end: SketchPoint(x: .length(end.0, .meter), y: .length(end.1, .meter)))
            }
            return try document.createCurvePatch(name: "Sheet", curves: lines.map { CurveSectionReference(featureID: $0) })
        }
        // Two floor-and-wall corners side by side along x (the wall's sketch x is world z, its y world x).
        let floors = try [0.0, 0.1].map { x in try sheet(on: .xy, [(x, 0.01), (x + 0.04, 0.01), (x + 0.04, 0.04), (x, 0.04)]) }
        let walls = try [0.0, 0.1].map { x in try sheet(on: .zx, [(0.01, x), (0.01, x + 0.04), (0.04, x + 0.04), (0.04, x)]) }
        func target(_ feature: FeatureID) throws -> SelectionTarget {
            .init(sceneNodeID: try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .body(feature) }).id)
        }
        var draft = makeDraft(.bridgeSurface, targets: [try target(floors[0])])
        draft.isSurfaceCreation = true
        draft.distance = "20 mm"
        // A with one sheet picked sets nothing aside.
        #expect(draft.addBridgeWallPair().added == false)
        draft.targets = [try target(floors[0]), try target(walls[0])]
        #expect(draft.addBridgeWallPair().added)
        #expect(draft.targets.isEmpty && draft.bridgeWallPairs.count == 1)
        draft.targets = [try target(floors[1]), try target(walls[1])]
        let commands = try draft.commands(in: document)
        #expect(commands.count == 2)
        let bridges = commands.compactMap { command -> SheetBridgeFeature? in
            guard case .createBridgeSurface(_, let bridge, _) = command else { return nil }
            return bridge
        }
        #expect(bridges.map(\.first) == floors && bridges.map(\.second) == walls)
        // Both corners are bridged with the walls trimmed: each joins into one sheet.
        let store = CADDocumentStore(document: document)
        for command in commands { _ = try store.apply(command) }
        #expect(try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter)).counts.sheets == 2)
    }

    @Test func longAndShortSetHowFarTheBridgeRunsApartFromTrimmingTheWalls() throws {
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
        // The floor runs 40 mm along x, the wall 30 mm (sketch x is world z on the ZX plane).
        let floor = try sheet(on: .xy, [(0, 0.01), (0.04, 0.01), (0.04, 0.04), (0, 0.04)])
        let wall = try sheet(on: .zx, [(0.01, 0), (0.01, 0.03), (0.04, 0.03), (0.04, 0)])
        let nodes = try [floor, wall].map { feature in
            try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .body(feature) })
        }
        var draft = makeDraft(.bridgeSurface, targets: nodes.map { .init(sceneNodeID: $0.id) })
        draft.isSurfaceCreation = true
        draft.distance = "20 mm"
        draft.bridgeShape = .chamfer
        draft.bridgeTrimsWalls = false
        draft.bridgeExtent = .long
        guard case .createBridgeSurface(_, let bridge, let wallByReach) = try draft.command(in: document) else {
            Issue.record("Expected a Bridge Surface.")
            return
        }
        #expect(wallByReach == nil && bridge.trimWalls == .none && bridge.extent == .long)
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        // Long: the strip runs the floor's 40 mm, 20√2 mm across; both walls stay whole.
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        #expect(measurement.counts.sheets == 3)
        #expect(abs(measurement.totals.sheetAreaSquareMeters - (0.04 * 0.03 + 0.03 * 0.03 + 0.02 * 2.0.squareRoot() * 0.04)) < 1e-12)
    }

    @Test func aG1PatchFillsAHoleOfAPlateTangentToIt() throws {
        // A 40 mm plate with a 10 mm square hole through it: a box less a smaller box, then every
        // face but the top taken out, leaving the top as a sheet with a hole.
        var document = DesignDocument.empty()
        let plate = try document.createExtrudedRectangle(name: "Plate", plane: .xy, width: .length(0.04, .meter),
                                                          height: .length(0.04, .meter), depth: .length(0.01, .meter), direction: .normal)
        let tool = try document.createExtrudedRectangle(name: "Tool", plane: .xy, width: .length(0.01, .meter),
                                                         height: .length(0.01, .meter), depth: .length(0.03, .meter), direction: .symmetric)
        let holed = try document.createBoolean(name: "Holed", targets: [BooleanTargetReference(featureID: plate)],
                                               tools: [BooleanToolReference(featureID: tool)], operation: .difference)
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .body(holed) })
        let faces = try TopologySnapshotService().snapshot(document: document).entries.filter { $0.kind == .face && $0.sceneNodeID == node.id.description }
        let top = faces.max { ($0.center?.z ?? 0) < ($1.center?.z ?? 0) }
        _ = try document.deleteBodyFaces(targets: faces.filter { $0 != top }.compactMap { $0.selectionTarget() })
        let sheetNode = try #require(document.productMetadata.sceneNodes.values.first {
            $0.reference?.kind == .body && $0.object?.geometryRole == .surface
        })
        let loops = try OpenBoundaryLoopService().loops(of: sheetNode.id, in: document)
        #expect(loops.count == 2)
        // The hole's loop is the one near the plate's middle (both loops have four edges).
        let entries = try TopologySnapshotService().snapshot(document: document).entries
        func reach(_ loop: [SelectionTarget]) -> Double {
            loop.compactMap { edge in entries.first { $0.selectionTarget() == edge }?.start }.map { max(abs($0.x), abs($0.y)) }.max() ?? .infinity
        }
        let hole = try #require(loops.min { reach($0) < reach($1) })
        var draft = makeDraft(.patch, targets: [try #require(hole.first)])
        draft.isSurfaceCreation = true
        draft.patchContinuity = .g1
        guard case .createXNurbs(_, let xnurbs, _) = try draft.command(in: document) else {
            Issue.record("A G1 patch is an XNURBS over the hole's loop.")
            return
        }
        #expect(xnurbs.boundaries.count == 4 && xnurbs.boundaries.allSatisfy { $0.continuity?.order == .tangent })
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        #expect(measurement.counts.sheets == 2)
        // Tangent to the flat plate, the fill is the flat square of the hole.
        #expect(abs(measurement.totals.sheetAreaSquareMeters - 0.04 * 0.04) < 1e-8, "\(measurement.totals.sheetAreaSquareMeters)")

        // A guide arc over the hole: G0 patching then passes through it, an XNURBS with the guide.
        let arc = try document.createArcSketch(name: "Guide", plane: .zx, center: SketchPoint(x: .length(0.01, .meter), y: .length(0, .meter)),
                                               radius: .length(0.005, .meter), startAngle: .angle(-90, .degree), endAngle: .angle(90, .degree))
        let guideNode = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == arc })
        var guided = makeDraft(.patch, targets: [try #require(hole.first), SelectionTarget(sceneNodeID: guideNode.id)])
        guided.isSurfaceCreation = true
        guided.patchContinuity = .g0
        guard case .createXNurbs(_, let withGuide, _) = try guided.command(in: document) else {
            Issue.record("A patch with a guide is an XNURBS through it.")
            return
        }
        #expect(withGuide.guides.count == 1 && withGuide.boundaries.allSatisfy { $0.continuity == nil })
    }

    @Test func aPatchOnASolidsEdgeLoopMakesASheetOfTheFacesItEncloses() throws {
        // A box's four top edges: the loop encloses the top face, which becomes a sheet of its
        // own while the box stays a solid.
        var document = DesignDocument.empty()
        let box = try document.createExtrudedRectangle(name: "Box", plane: .xy, width: .length(0.02, .meter),
                                                        height: .length(0.02, .meter), depth: .length(0.01, .meter), direction: .normal)
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .body(box) })
        let top = try TopologySnapshotService().snapshot(document: document).entries.filter {
            $0.kind == .edge && $0.sceneNodeID == node.id.description
                && abs(($0.start?.z ?? 0) - 0.01) < 1e-9 && abs(($0.end?.z ?? 0) - 0.01) < 1e-9
        }.compactMap { $0.selectionTarget() }
        #expect(top.count == 4)
        var draft = makeDraft(.patch, targets: top)
        draft.isSurfaceCreation = true
        guard case .duplicateBodyFaces(_, let faces) = try draft.command(in: document) else {
            Issue.record("A loop of a solid's edges duplicates the faces it encloses.")
            return
        }
        #expect(faces.count == 1)
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let objects = store.document.productMetadata.sceneNodes.values.filter { $0.reference?.kind == .body }
        #expect(objects.filter { $0.object?.geometryRole == .solid }.count == 1)
        #expect(objects.filter { $0.object?.geometryRole == .surface }.count == 1)
        #expect(store.evaluationStatus == .valid)
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
        guard case .createSquare(_, let sides, _, let edgeCurves) = try draft.command(in: document) else {
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

    @Test func twoCurvesFrameASquareWithItsOptionsAndAFreeSide() throws {
        var document = DesignDocument.empty()
        // Two lines apart, 20 mm by 20 mm.
        let lines = try [(0.0, 0.0, 0.02, 0.0), (0.0, 0.02, 0.02, 0.02)].map { x0, y0, x1, y1 in
            try document.createLineSketch(name: "Side", plane: .xy,
                start: SketchPoint(x: .length(x0, .meter), y: .length(y0, .meter)),
                end: SketchPoint(x: .length(x1, .meter), y: .length(y1, .meter)))
        }
        let nodes = try lines.map { line in try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(line) }) }
        let targets = nodes.map { SelectionTarget(sceneNodeID: $0.id) }
        var draft = makeDraft(.square, targets: targets)
        draft.squareUDegree = "4"
        draft.squareVSpans = "2"
        draft.squareFlatness = "0.9"
        draft.squareBoundaryFlow = .natural
        draft.squareSideContinuity[targets[1]] = .free
        guard case .createSquare(_, let sides, let options, _) = try draft.command(in: document) else {
            Issue.record("Expected a Square command.")
            return
        }
        #expect(sides.map(\.isFree) == [false, true])
        #expect(options == SquareFitOptions(uDegree: 4, vDegree: 3, uSpans: 3, vSpans: 2, flatness: 0.9, weight: 1, boundaryFlow: .natural))
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        #expect(measurement.counts.sheets == 1)
        // The inspector shows the options and each side's Analysis.
        let squareNode = try #require(store.document.productMetadata.sceneNodes.values.first { node in
            guard let featureID = node.reference?.featureID, let feature = store.document.cadDocument.designGraph.nodes[featureID],
                  case .squareSurface = feature.operation else { return false }
            return true
        })
        let evaluated = try #require(store.currentEvaluation?.evaluatedDocument)
        let state = WorkspaceObjectOverviewInspectorStateBuilder(
            document: store.document, displayUnit: .millimeter, objectRegistry: .builtIn,
            selectedTargetSummary: "", selectedTargetCount: 1, evaluatedDocument: evaluated
        ).state(for: [squareNode])
        let rows = Dictionary(state.referenceSection.rows.map { ($0.title, $0.value) }, uniquingKeysWith: { first, _ in first })
        #expect(rows["Continuity"] == "G0 · Free" && rows["Degree"] == "4 × 3" && rows["Boundary"] == "Natural")
        #expect(rows["Side 1"]?.hasPrefix("G0 ✓") == true && rows["Side 2"] != nil)
    }

    @Test func xnurbsFillsAPentagonWithAGuideAndAQuadAsSquare() throws {
        var document = DesignDocument.empty()
        // A pentagon of lines in the XY plane and a short guide curve inside it.
        let corners: [(Double, Double)] = (0..<5).map { k in
            let angle = 2 * Double.pi * Double(k) / 5
            return (0.01 * cos(angle), 0.01 * sin(angle))
        }
        let lines = try corners.indices.map { k in
            let (a, b) = (corners[k], corners[(k + 1) % 5])
            return try document.createLineSketch(name: "Side", plane: .xy,
                start: SketchPoint(x: .length(a.0, .meter), y: .length(a.1, .meter)),
                end: SketchPoint(x: .length(b.0, .meter), y: .length(b.1, .meter)))
        }
        let guide = try document.createLineSketch(name: "Guide", plane: .xy,
            start: SketchPoint(x: .length(-0.002, .meter), y: .length(0, .meter)),
            end: SketchPoint(x: .length(0.002, .meter), y: .length(0, .meter)))
        let nodes = try (lines + [guide]).map { id in try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(id) }) }
        var draft = makeDraft(.xnurbs, targets: nodes.map { .init(sceneNodeID: $0.id) })
        draft.xnurbsGuideNodeIDs = [nodes[5].id]
        draft.xnurbsQuality = .high
        guard case .createXNurbs(_, let xnurbs, let edgeCurves) = try draft.command(in: document) else {
            Issue.record("Expected an XNURBS command.")
            return
        }
        #expect(xnurbs.boundaries.count == 5 && xnurbs.guides.count == 1 && edgeCurves.isEmpty && xnurbs.quality == .high)
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        #expect(store.evaluationStatus == .valid)
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        #expect(measurement.counts.sheets == 1)
        // Quad sided over four of the sides is refused as not framing a quad; over four lines of a
        // square it is Square's sheet.
        draft.xnurbsQuadSided = true
        draft.xnurbsGuideNodeIDs = []
        draft.targets = nodes.prefix(4).map { .init(sceneNodeID: $0.id) }
        guard case .createXNurbs(_, let quad, _) = try draft.command(in: document) else {
            Issue.record("Expected an XNURBS command.")
            return
        }
        #expect(quad.quadSided && quad.boundaries.count == 4)
    }

    @Test func tabStepsEverySidesContinuityInSquareAndXNurbs() {
        // Plasticity's Tab steps every badge: Square G0, G1, G2, Free; XNURBS G0, G1, G2.
        let side = SelectionTarget(sceneNodeID: SceneNodeID())
        var square = makeDraft(.square, targets: [side])
        square.squareSideContinuity[side] = .g2
        var steps: [String?] = []
        for _ in 0..<4 { steps.append(square.cycleSideContinuity()) }
        #expect(steps == ["G1", "G2", "Free", "G0"] && square.squareSideContinuity.isEmpty)
        var xnurbs = makeDraft(.xnurbs, targets: [side])
        xnurbs.xnurbsEdgeContinuity[side] = .g2
        let first = xnurbs.cycleSideContinuity()
        #expect(first == "G1" && xnurbs.xnurbsContinuity(of: side) == .g1)
        steps = []
        for _ in 0..<2 { steps.append(xnurbs.cycleSideContinuity()) }
        #expect(steps == ["G2", "G0"])
        var loft = makeDraft(.loft, targets: [])
        let none = loft.cycleSideContinuity()
        #expect(none == nil)
    }

    @Test func solidDialogKeysSetTheBooleanKeepToolsAndTheFieldTyped() {
        var revolve = makeDraft(.revolve, targets: [])
        let slice = revolve.apply(.boolean(.slice))
        let keep = revolve.apply(.keepTools)
        #expect(slice != nil && keep != nil && revolve.solidBoolean == .slice && revolve.keepsTools)
        let angle = revolve.apply(.angle)
        #expect(angle != nil && revolve.focusRequest?.field == .angle)
        let thickness = revolve.apply(.thickness)
        #expect(thickness != nil && revolve.focusRequest?.field == .thickness)
        let noDistance = revolve.apply(.distance)
        #expect(noDistance == nil)
        var sweep = makeDraft(.sweep, targets: [])
        let twist = sweep.apply(.distance)
        #expect(twist != nil && sweep.focusRequest?.field == .twist)
        let sweepAngle = sweep.apply(.angle)
        let sweepThickness = sweep.apply(.thickness)
        #expect(sweepAngle == nil && sweepThickness == nil)
        var pipe = makeDraft(.pipe, targets: [])
        let size = pipe.apply(.distance)
        #expect(size != nil && pipe.focusRequest?.field == .distance)
        pipe.pipeCustomProfile = true
        let customSize = pipe.apply(.distance)
        #expect(customSize == nil)
        var loft = makeDraft(.loft, targets: [])
        let loftUnion = loft.apply(.boolean(.union))
        #expect(loftUnion == nil && loft.solidBoolean == .automatic)
    }

    @Test func aBadgeClickStepsItsOwnBoundary() {
        // Plasticity's round badges: one per boundary edge, a click stepping that edge alone
        // (Square G0, G1, G2, Free; XNURBS G0, G1, G2); a curve side and a guide carry none; Patch's
        // hole has one continuity, which any of its badges steps.
        let node = SceneNodeID()
        let edges = (0..<2).map { _ in SelectionTarget(sceneNodeID: node, component: .edge(.init(rawValue: UUID().uuidString))) }
        let curve = SelectionTarget(sceneNodeID: SceneNodeID())
        var square = makeDraft(.square, targets: edges + [curve])
        #expect(square.continuityBadges.map(\.target) == edges)
        #expect(square.continuityBadges.map(\.label) == ["G0", "G0"])
        var labels: [String] = []
        for _ in 0..<4 {
            let stepped = square.stepContinuity(of: edges[0])
            #expect(stepped)
            labels.append(square.continuityBadges[0].label)
        }
        #expect(labels == ["G1", "G2", "Free", "G0"])
        #expect(square.continuityBadges[1].label == "G0")
        let curveStepped = square.stepContinuity(of: curve)
        #expect(curveStepped == false)

        let guide = SelectionTarget(sceneNodeID: SceneNodeID(), component: .edge(.init(rawValue: UUID().uuidString)))
        var xnurbs = makeDraft(.xnurbs, targets: edges + [guide])
        xnurbs.xnurbsGuideNodeIDs = [guide.sceneNodeID]
        #expect(xnurbs.continuityBadges.map(\.target) == edges)
        let firstStep = xnurbs.stepContinuity(of: edges[1])
        let secondStep = xnurbs.stepContinuity(of: edges[1])
        #expect(firstStep && secondStep)
        #expect(xnurbs.continuityBadges.map(\.label) == ["G0", "G2"])
        let guideStepped = xnurbs.stepContinuity(of: guide)
        #expect(guideStepped == false)

        var patch = makeDraft(.patch, targets: edges)
        let patchStepped = patch.stepContinuity(of: edges[0])
        #expect(patchStepped)
        #expect(patch.continuityBadges.map(\.label) == ["G1", "G1"])
    }

    @Test func xnurbsTakesEachEdgesOwnContinuity() throws {
        // The four top edges of a box as boundaries: one edge G2 with the side face beside it, the
        // others the dialog's G0, as Plasticity's badges mix them.
        var document = DesignDocument.empty()
        _ = try document.createExtrudedRectangleFromCorners(
            name: "Box", plane: .xy,
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
            depth: .length(0.02, .meter), direction: .normal
        )
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        let edges = topology.entries.filter { entry in
            guard entry.kind == .edge, let start = entry.start, let end = entry.end else { return false }
            return abs(start.z - 0.02) < 1e-9 && abs(end.z - 0.02) < 1e-9
        }.compactMap { $0.selectionTarget() }
        #expect(edges.count == 4)
        var draft = makeDraft(.xnurbs, targets: edges)
        draft.xnurbsEdgeContinuity[edges[0]] = .g2
        guard case .createXNurbs(_, let xnurbs, let edgeCurves) = try draft.command(in: document) else {
            Issue.record("Expected an XNURBS command.")
            return
        }
        #expect(edgeCurves.count == 4)
        #expect(xnurbs.boundaries.map { $0.continuity?.order } == [.curvature, nil, nil, nil])
        // The dialog's continuity clears the edges' own.
        #expect(draft.xnurbsContinuity(of: edges[1]) == .g0)
    }

    @Test func aLineExtrudedWithAThicknessMakesASolidWall() throws {
        var document = DesignDocument.empty()
        let line = try document.createLineSketch(name: "Line", plane: .xy,
            start: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            end: SketchPoint(x: .length(0.02, .meter), y: .length(0, .meter)))
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(line) })
        var draft = makeDraft(.extrude, targets: [.init(sceneNodeID: node.id)])
        draft.sheet = true
        draft.distance = "10 mm"
        draft.wallThickness = "2 mm"
        guard case .createExtrusion(_, let extrusion) = try draft.command(in: document) else {
            Issue.record("Expected a thin extrusion.")
            return
        }
        #expect(extrusion.resultKind == .solid && extrusion.thickness != nil)
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        #expect(abs(measurement.totals.solidVolumeCubicMeters - 0.02 * 0.002 * 0.01) < 1e-12)
    }

    @Test func aSquareOverAFaceRefitsIt() throws {
        var document = DesignDocument.empty()
        let box = try document.createExtrudedRectangleFromCorners(
            name: "Box", plane: .xy,
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
            depth: .length(0.02, .meter), direction: .normal
        )
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        let top = try #require(topology.entries.first { entry in
            entry.kind == .face && entry.sourceFeatureID == box.description && (entry.normal?.z ?? 0) > 0.99
        }?.selectionTarget())
        var draft = makeDraft(.square, targets: [top])
        draft.squareUDegree = "5"
        guard case .rebuildFaces(let targets, .square(let refit), _, _, _) = try draft.command(in: document) else {
            Issue.record("Expected a Refit.")
            return
        }
        #expect(targets == [top] && refit.order == nil && refit.options.uDegree == 5)
        draft.squareContinuity = .free
        #expect(throws: (any Error).self) { try draft.command(in: document) }
        draft.squareContinuity = .g0
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        #expect(abs(measurement.totals.solidVolumeCubicMeters - 0.02 * 0.02 * 0.02) < 1e-12)
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
        guard case .createSquare(_, let sides, _, let edgeCurves) = try draft.command(in: document) else {
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
        // Plasticity's face Loft opens on G1 at both ends: upright beside the boxes' walls.
        #expect(sections.allSatisfy { $0.faceContinuity?.order == .tangent })
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
        // Automatic by default: outward joins the faces' body (Union), inward cuts it.
        #expect(draft.solidBoolean == .automatic)
        guard case .extrudeFaces(_, _, _, _, let outward, _, _, _) = try draft.command(in: .empty()) else {
            Issue.record("Faces extrude through extrudeFaces.")
            return
        }
        #expect(outward == .union)
        draft.distance = "-5 mm"
        guard case .extrudeFaces(_, _, _, _, let inward, _, _, _) = try draft.command(in: .empty()) else {
            Issue.record("Faces extrude through extrudeFaces.")
            return
        }
        #expect(inward == .difference)
        draft.solidBoolean = .newBody
        guard case .extrudeFaces(_, _, _, _, let separate, _, _, _) = try draft.command(in: .empty()) else {
            Issue.record("Faces extrude through extrudeFaces.")
            return
        }
        #expect(separate == .newBody)
        draft.distance = "5 mm"
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

    @Test func aRevolveTakesItsSectionsTangentAxis() throws {
        var document = DesignDocument.empty()
        let fixture = try stripAndCube(in: &document)
        var draft = makeDraft(.revolve, targets: [fixture.stripTarget])
        draft.revolveAxisChoice = .tangent
        guard case .revolveSection(_, let section, let axis, _, _, _, _, _, _) = try draft.command(in: document) else {
            Issue.record("A revolve about its section's tangent is one revolve.")
            return
        }
        // The axis the kernel reads from the section: through its boundary start, along it there.
        let evaluated = try DocumentEvaluationContextResolver().exactEvaluatedDocument(document: document, failurePrefix: "test")
        #expect(axis == (try RevolveSectionAxis().axis(.tangent, section: section, in: evaluated)))
        draft.revolveAxisChoice = .binormal
        guard case .revolveSection(_, _, let across, _, _, _, _, _, _) = try draft.command(in: document) else {
            Issue.record("A revolve about its section's binormal is one revolve.")
            return
        }
        #expect(abs(across.direction.dot(axis.direction)) < 1e-12 && across.origin == axis.origin)
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
        // A section marked as a guide too leaves one section along two guides: continuous
        // lofting, which the kernel builds only when the guides leave the section's ends.
        draft.loftGuideNodeIDs.insert(targets[0].sceneNodeID)
        guard case let .createLoft(_, oneSection, twoGuides, _, _) = try draft.command(in: document) else {
            Issue.record("Expected a Loft command."); return
        }
        #expect(oneSection.count == 1 && twoGuides.count == 2)
        draft.loftGuideNodeIDs.remove(targets[0].sceneNodeID)
        document.productMetadata.sceneNodes[guideNode.id]?.isLocked = true
        #expect(throws: EditorError.self) { try draft.command(in: document) }
    }

    @Test func anEdgeGuidesALoftAlongItsCurve() throws {
        // The front face's top and bottom edges as sections and its left edge, joining their
        // starts, as a guide: every edge becomes a curve of the loft, the guide among its guides,
        // and the loft spans the front face.
        var document = DesignDocument.empty()
        _ = try document.createExtrudedRectangleFromCorners(
            name: "Box", plane: .xy,
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.02, .meter), y: .length(0.02, .meter)),
            depth: .length(0.02, .meter), direction: .normal
        )
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        func edge(_ test: (Point3D, Point3D) -> Bool) throws -> SelectionTarget {
            try #require(topology.entries.first { entry in
                guard entry.kind == .edge, let start = entry.start, let end = entry.end else { return false }
                return test(Point3D(x: start.x, y: start.y, z: start.z), Point3D(x: end.x, y: end.y, z: end.z))
            }?.selectionTarget())
        }
        let top = try edge { abs($0.y) < 1e-9 && abs($1.y) < 1e-9 && abs($0.z - 0.02) < 1e-9 && abs($1.z - 0.02) < 1e-9 }
        let bottom = try edge { abs($0.y) < 1e-9 && abs($1.y) < 1e-9 && abs($0.z) < 1e-9 && abs($1.z) < 1e-9 }
        let side = try edge { abs($0.x) < 1e-9 && abs($1.x) < 1e-9 && abs($0.y) < 1e-9 && abs($1.y) < 1e-9 }
        var draft = makeDraft(.loft, targets: [bottom, top, side])
        draft.loftStartContinuity = .g0
        draft.loftEndContinuity = .g0
        draft.loftGuideEdges.insert(side)
        guard case .createLoft(_, let sections, let guides, _, let edgeCurves) = try draft.command(in: document) else {
            Issue.record("Expected a Loft command.")
            return
        }
        #expect(sections.count == 2 && guides.count == 1 && edgeCurves.count == 3)
        #expect(guides.first.map { guide in edgeCurves.contains { $0.id == guide.featureID } } == true)
        #expect(draft.operandTitle(at: 2, in: document).hasPrefix("Guide 1"))
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        #expect(store.evaluationStatus == .valid)
        let measurement = try MeasurementService().measure(document: store.document, ruler: .standard(for: .meter))
        #expect(abs(measurement.totals.sheetAreaSquareMeters - 0.02 * 0.02) < 1e-9)
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
