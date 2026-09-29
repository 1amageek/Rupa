import RupaCore
import SwiftCAD
import RupaRendering
import Testing
@testable import RupaUI

/// Boolean's and Cut's dialogs: the selection seeds their lists, clicks add to or remove from the
/// list being picked, and each builds the command the Core runs.
@MainActor
@Suite struct WorkspaceBodyOperationSessionTests {
    /// A document with two boxes and a line sketch; their scene nodes.
    private func document() throws -> (DesignDocument, first: SceneNodeID, second: SceneNodeID, line: SceneNodeID) {
        let session = EditorSession()
        for name in ["First", "Second"] {
            _ = try session.execute(.createExtrudedRectangle(
                name: name, plane: .xy,
                width: .length(0.1, .meter), height: .length(0.1, .meter),
                depth: .length(0.1, .meter), direction: .normal
            ))
        }
        _ = try session.execute(.createLineSketch(
            name: "Line", plane: .xy,
            start: SketchPoint(x: .length(-1, .meter), y: .length(0.02, .meter)),
            end: SketchPoint(x: .length(1, .meter), y: .length(0.02, .meter))
        ))
        let nodes = session.document.productMetadata.sceneNodes.values
        func body(_ name: String) throws -> SceneNodeID {
            try #require(nodes.first { $0.name.hasPrefix(name) && $0.reference?.kind == .body }).id
        }
        let line = try #require(nodes.first { $0.name.hasPrefix("Line") }).id
        return (session.document, try body("First"), try body("Second"), line)
    }

    @Test func theSelectionSeedsBooleanTargetsAndTheLastSelectedTool() throws {
        let (document, first, second, _) = try document()
        let one = WorkspaceBooleanSession(selectedBodies: [first])
        #expect(one.targets == [first] && one.tools.isEmpty && one.picking == .tools && !one.canApply)
        var two = WorkspaceBooleanSession(selectedBodies: [first, second])
        #expect(two.targets == [first] && two.tools == [second] && two.canApply && two.operation == .union)
        // A body clicked into the other list leaves the one it was in.
        two.picking = .targets
        two.toggle(second)
        #expect(two.targets == [first, second] && two.tools.isEmpty)
        two.picking = .tools
        two.toggle(second)
        two.setOperation(.difference)
        two.keepTools = true
        two.toolMaterial = .outside
        guard case let .createBoolean(_, targets, tools, operation, keepTools, _, toolMaterial) = try two.command(in: document) else {
            Issue.record("Boolean must build the Core's Boolean command.")
            return
        }
        #expect(targets.count == 1 && tools.count == 1 && operation == .difference && keepTools && toolMaterial == .outside)
    }

    @Test func aRegionDropsTheMaterialsItCannotTake() throws {
        var boolean = WorkspaceBooleanSession(selectedBodies: [SceneNodeID(), SceneNodeID()])
        boolean.targetMaterial = .inside
        boolean.setOperation(.region)
        #expect(boolean.targetMaterial == .default && !boolean.takesMaterials)
    }

    @Test func aBooleanOfANonBodyIsRefused() throws {
        let (document, first, _, line) = try document()
        let boolean = WorkspaceBooleanSession(selectedBodies: [first, line])
        #expect(throws: EditorError.self) { try boolean.command(in: document) }
    }

    @Test func cutTakesSelectedBodiesAsTargetsAndCurvesAndFacesAsCutters() throws {
        let (document, first, second, line) = try document()
        let cut = WorkspaceBodyCutSession(selection: [
            SelectionTarget(sceneNodeID: first),
            SelectionTarget(sceneNodeID: line),
            SelectionTarget(sceneNodeID: second),
        ], in: document)
        #expect(cut.targets == [first, second] && cut.cutters == [.curve(line)] && cut.picking == .cutters)
        // Cutters are clicked among curves and faces; targets among bodies.
        #expect(cut.viewportHitPolicy == .all)
        #expect(WorkspaceBodyCutSession(targets: [], cutters: []).viewportHitPolicy == .object)
        var session = cut
        session.extendsCurves = true
        session.viewDirection = Vector3D(x: 0, y: 0, z: 1)
        guard case let .cut(_, targets, cutters, options) = try session.command() else {
            Issue.record("Cut must build the Core's Cut command.")
            return
        }
        #expect(targets == [first, second] && cutters == [.curve(line)])
        #expect(options == CutOptions(extendsCurves: true, direction: Vector3D(x: 0, y: 0, z: 1)))
        session.toggle(cutter: .curve(line))
        #expect(!session.canCut)
        #expect(throws: EditorError.self) { try session.command() }
        let onlyBodies = WorkspaceBodyCutSession(selection: [SelectionTarget(sceneNodeID: first)], in: document)
        #expect(onlyBodies.picking == .cutters && onlyBodies.cutters.isEmpty)
    }
}
