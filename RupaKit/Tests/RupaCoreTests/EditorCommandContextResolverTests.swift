import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test func defaultResolverUsesSelectedSupportFaceForEdgeOffset() async throws {
    let fixture = try makeEdgeOffsetResolverFixture()
    #expect(fixture.session.selectTargets([fixture.supportFace, fixture.edge]))

    let command = edgeOffsetCommand(target: fixture.edge)
    let resolved = try DefaultEditorCommandContextResolver().resolve(
        command,
        in: planningContext(for: fixture.session)
    )

    guard case .offsetCurve(_, _, let options, _) = resolved else {
        Issue.record("The resolver must preserve the Offset Curve command shape.")
        return
    }
    #expect(options.supportTarget == fixture.supportFace)
}

@MainActor
@Test func defaultResolverReportsAmbiguousSelectedSupportFacesAsTypedFailure() async throws {
    let fixture = try makeEdgeOffsetResolverFixture()
    #expect(fixture.session.selectTargets([
        fixture.firstFace,
        fixture.secondFace,
        fixture.edge
    ]))

    var caught: EditorError?
    do {
        _ = try DefaultEditorCommandContextResolver().resolve(
            edgeOffsetCommand(target: fixture.edge),
            in: planningContext(for: fixture.session)
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(caught?.message == EdgeOffsetSupportFaceResolver.ambiguousSelectedSupportFaceMessage)
}

@MainActor
@Test func defaultResolverReportsUnavailableEdgeSupportAsTypedFailure() async throws {
    let fixture = try makeEdgeOffsetResolverFixture()

    var caught: EditorError?
    do {
        _ = try DefaultEditorCommandContextResolver().resolve(
            edgeOffsetCommand(target: fixture.edge),
            in: planningContext(for: fixture.session)
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(caught?.message == "Offset Edge support face inference requires the edge target to be selected.")
}

@MainActor
@Test func defaultResolverDoesNotOverwriteExplicitEdgeSupportTarget() async throws {
    let fixture = try makeEdgeOffsetResolverFixture()
    #expect(fixture.session.selectTargets([fixture.edge]))
    let command = EditorCommand.offsetCurve(
        target: fixture.edge,
        distance: .length(1.0, .millimeter),
        options: OffsetCurveOptions(supportTarget: fixture.supportFace),
        vertexHandle: nil
    )

    let resolved = try DefaultEditorCommandContextResolver().resolve(
        command,
        in: planningContext(for: fixture.session)
    )

    #expect(resolved == command)
}

@Test func defaultResolverAllowsSketchCurveWithoutVertexHandle() throws {
    let target = SelectionTarget(
        sceneNodeID: SceneNodeID(),
        component: .sketchEntity(SelectionComponentID(rawValue: "sketchEntity:curve"))
    )
    let command = EditorCommand.offsetCurve(
        target: target,
        distance: .length(1.0, .millimeter),
        options: OffsetCurveOptions(),
        vertexHandle: nil
    )
    let context = EditorCommandPlanningContext(
        document: .empty(),
        selection: .empty,
        objectRegistry: .builtIn,
        evaluationSnapshot: EvaluationSnapshot()
    )

    #expect(try DefaultEditorCommandContextResolver().resolve(command, in: context) == command)
    #expect(throws: Never.self) {
        try DefaultEditorCommandContextResolver().requireFullyResolved(command)
    }
}

@Test func defaultResolverRejectsUnresolvedEdgeOffsetWithoutConsultingSelection() throws {
    let target = SelectionTarget(
        sceneNodeID: SceneNodeID(),
        component: .edge(SelectionComponentID(rawValue: "edge:unresolved"))
    )
    let command = edgeOffsetCommand(target: target)

    var caught: EditorError?
    do {
        try DefaultEditorCommandContextResolver().requireFullyResolved(command)
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(caught?.message == EdgeOffsetSupportFaceResolver.missingSupportFaceMessage)
}

@Test func contextResolvedCommandExecutesWithoutConsultingSessionResolverAgain() throws {
    let session = EditorSession(
        document: .empty(named: "Before"),
        commandContextResolver: RejectingCommandContextResolver()
    )
    let command = try ContextResolvedEditorCommand(
        validating: .renameDocument(name: "After")
    )

    let result = try session.execute(command)

    #expect(result.didMutate)
    #expect(session.document.cadDocument.metadata.name == "After")
}

private struct EdgeOffsetResolverFixture {
    let session: EditorSession
    let edge: SelectionTarget
    let supportFace: SelectionTarget
    let firstFace: SelectionTarget
    let secondFace: SelectionTarget
}

@MainActor
private func makeEdgeOffsetResolverFixture() throws -> EdgeOffsetResolverFixture {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodySceneNodeID = try #require(
        session.document.productMetadata.sceneNodes.first { entry in
            entry.value.reference?.kind == .body
        }?.key
    )
    let topology = try TopologySnapshotService().snapshot(document: session.document)
    let faceTargets = topology.entries
        .filter {
            $0.kind == .face &&
                $0.sceneNodeID == bodySceneNodeID.description &&
                $0.selectionTarget() != nil
        }
        .compactMap { $0.selectionTarget() }
    let firstFace = try #require(faceTargets.first)
    let secondFace = try #require(faceTargets.dropFirst().first)
    let supportFace = try #require(
        topology.entries.first {
            $0.kind == .face &&
                $0.sceneNodeID == bodySceneNodeID.description &&
                $0.generatedRole == "startFace"
        }?.selectionTarget()
    )
    let edge = try #require(
        topology.entries.first {
            $0.kind == .edge &&
                $0.sceneNodeID == bodySceneNodeID.description &&
                $0.curveKind == "line"
        }?.selectionTarget()
    )
    return EdgeOffsetResolverFixture(
        session: session,
        edge: edge,
        supportFace: supportFace,
        firstFace: firstFace,
        secondFace: secondFace
    )
}

private func planningContext(for session: EditorSession) -> EditorCommandPlanningContext {
    EditorCommandPlanningContext(
        document: session.document,
        selection: session.selection,
        objectRegistry: session.objectRegistry,
        evaluationSnapshot: session.evaluationSnapshot
    )
}

private func edgeOffsetCommand(target: SelectionTarget) -> EditorCommand {
    .offsetCurve(
        target: target,
        distance: .length(1.0, .millimeter),
        options: OffsetCurveOptions(),
        vertexHandle: nil
    )
}

private struct RejectingCommandContextResolver: EditorCommandContextResolving {
    func resolve(
        _ command: EditorCommand,
        in context: EditorCommandPlanningContext
    ) throws -> EditorCommand {
        throw EditorError(
            code: .commandInvalid,
            message: "The session resolver must not re-resolve an immutable planned command."
        )
    }

    func requireFullyResolved(_ command: EditorCommand) throws {
        throw EditorError(
            code: .commandInvalid,
            message: "The session resolver must not revalidate an immutable planned command."
        )
    }
}
