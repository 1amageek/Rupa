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
        #expect(throws: EditorError.self) { try draft.command(in: document) }
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
            for invalid in ["missingParameter", "wall_thickness / 0", "-wall_thickness", "2 deg"] {
                draft.distance = invalid
                #expect(throws: (any Error).self) { try draft.command(in: document) }
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
        guard case .createSweep(_, _, _, _, _, let options) = try draft.command(in: document) else {
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
        guard case .createSweep(_, _, _, _, _, let options) = try draft.command(in: document) else {
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
        guard case .createSweep(_, _, _, _, _, let parallel) = try draft.command(in: document) else {
            Issue.record("Expected native Sweep source intent.")
            return
        }
        #expect(parallel.alignment == .parallel && parallel.approximationTolerance == nil)
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
        guard case .createLoft(_, let sections, _, let options) = try draft.command(in: document) else {
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
        guard case .createLoft(_, let sections, _, _) = command else { Issue.record("Expected Loft."); return }
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
        guard case .createSweep(_, let sweepSections, _, _, _, _) = sweepCommand else {
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
        draft.loftGuideNodeIDs.insert(guideNode.id)
        draft.targets.insert(draft.targets.removeLast(), at: 0)
        let command = try draft.command(in: document)
        guard case .createLoft(_, let sections, let guides, _) = command else {
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
        guard case .createLoft(_, let sections, _, _) = command else { Issue.record("Expected Loft."); return }
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
        guard case .createLoft(_, let sections, _, _) = command else { Issue.record("Expected Loft."); return }
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
