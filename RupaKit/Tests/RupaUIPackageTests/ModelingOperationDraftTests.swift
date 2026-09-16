import Testing
import RupaCore
import SwiftCAD
@testable import RupaUI

@Suite("Modeling operation drafts", .timeLimit(.minutes(1)))
struct ModelingOperationDraftTests {
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

    @Test func loftPreservesExplicitSectionOrderAndEvaluates() throws {
        var document = DesignDocument.empty()
        let first = try addProfile(to: &document, z: 0)
        let second = try addProfile(to: &document, z: 0.02)
        var draft = makeDraft(.loft, targets: [first.target, second.target])
        draft.targets.swapAt(0, 1)
        guard case .createLoft(_, let sections, _, _) = try draft.command(in: document) else {
            Issue.record("Expected loft source command.")
            return
        }
        #expect(sections.map(\.featureID) == [second.feature, first.feature])
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
        draft.filletSegments = "16"
        #expect(try draft.command(in: document) == .filletBodyEdges(targets: [edge], radius: .length(0.025 * 0.0254, .meter), segmentCount: 16))
        draft.kind = .chamfer
        draft.distance = "0.75 mm"
        #expect(try draft.command(in: document) == .chamferBodyEdges(targets: [edge], distance: .length(0.00075, .meter)))
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
        #expect(throws: Never.self) { try chamfer.command(in: document) }
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
