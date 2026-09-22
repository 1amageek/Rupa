import Testing
import RupaCore
import SwiftCAD
@testable import RupaUI

@Suite("Modeling operation drafts", .timeLimit(.minutes(1)))
struct ModelingOperationDraftTests {
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

    @Test func sheetDraftsUseNativeSourceCommands() throws {
        var patch = makeDraft(.surfacePatch)
        patch.width = "100 mm"
        patch.height = "50 mm"
        let store = CADDocumentStore(document: .empty())
        _ = try store.apply(patch.command(in: store.document))
        let topology = try TopologySnapshotService().snapshot(document: store.document, metricPolicy: .omit)
        let target = try #require(topology.entries.first { $0.kind == .face }?.selectionTarget())
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
        draft.symmetric = true
        #expect(try draft.command(in: document) == .extrudeProfile(
            name: "Extrude", profile: ProfileReference(featureID: profile.feature),
            distance: .length(0.012, .meter), direction: .symmetric
        ))
        draft.kind = .revolve
        draft.angle = "180"
        guard case .createRevolve(_, let reference, let axis, let angle) = try draft.command(in: document) else {
            Issue.record("Expected revolve source command.")
            return
        }
        #expect(reference.featureID == profile.feature)
        #expect(axis == RevolveAxis(origin: .origin, direction: .unitY))
        #expect(angle == .angle(180, .degree))
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let evaluated = try CADPipeline.modelingDefault(for: store.document).evaluate(store.document.cadDocument)
        #expect(evaluated.brep.bodies.count == 1)
    }

    @Test(arguments: [false, true])
    func loftPreservesExplicitSectionOrderAndEvaluates(sheet: Bool) throws {
        var document = DesignDocument.empty()
        let first = try addProfile(to: &document, z: 0)
        let second = try addProfile(to: &document, z: 0.02)
        var draft = makeDraft(.loft, targets: [first.target, second.target])
        draft.sheet = sheet
        draft.targets.swapAt(0, 1)
        guard case .createLoft(_, let sections, _, let options) = try draft.command(in: document) else {
            Issue.record("Expected loft source command.")
            return
        }
        #expect(sections.map(\.featureID) == [second.feature, first.feature])
        #expect(options.resultKind == (sheet ? .sheet : .solid))
        let store = CADDocumentStore(document: document)
        _ = try store.apply(draft.command(in: document))
        let evaluated = try CADPipeline.modelingDefault(for: store.document).evaluate(store.document.cadDocument)
        #expect(evaluated.brep.bodies.count == 1)
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

    @Test func anOperandProducingNoProfileNamesNoSweptCommand() throws {
        var document = DesignDocument.empty()
        let profile = try addProfile(to: &document, z: 0)
        let body = try addBody(to: &document)

        func refusal(_ draft: ModelingOperationDraft) -> String {
            do {
                _ = try draft.command(in: document)
                Issue.record("An operand producing no profile named a command.")
                return ""
            } catch let error as EditorError {
                return error.message
            } catch {
                Issue.record("Planning failed with an untyped error: \(error).")
                return ""
            }
        }

        // The sibling guards on these routes also name a profile, so the
        // check reads the part only this refusal carries. Matching "profile"
        // alone would pass on an operand-count refusal instead.
        var draft = makeDraft(.extrude, targets: [body])
        draft.distance = "5 mm"
        #expect(refusal(draft).contains("produces none"))
        draft.kind = .revolve
        #expect(refusal(draft).contains("produces none"))
        draft.kind = .loft
        draft.targets = [profile.target, body]
        #expect(refusal(draft).contains("produces none"))
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
