import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

@MainActor
@Test func workspaceSketchEntityInspectorStateBuilderResolvesEndpointSelection() async throws {
    let fixture = try workspaceSketchEntityInspectorFixture()
    let referenceEnd = try pointHandleSelectionTarget(fixture.referenceLine, handle: .lineEnd)
    let selectedStart = try pointHandleSelectionTarget(fixture.selectedLine, handle: .lineStart)
    let builder = WorkspaceSketchEntityInspectorStateBuilder(
        document: fixture.document,
        selection: SelectionModel(selectedTargets: [referenceEnd, selectedStart]),
        objectRegistry: .builtIn
    )

    let entity = try #require(try builder.selectedEntity())
    let operationState = builder.operationState(for: entity)

    #expect(entity.entityKind == "line")
    #expect(entity.entityID == fixture.selectedLineID)
    #expect(builder.vertexOffsetHandle(for: entity) == .lineStart)
    #expect(builder.vertexAlignmentReferenceTarget(for: entity) == referenceEnd)
    #expect(operationState.canExtend)
    #expect(operationState.canOffsetVertex)
    #expect(operationState.canApplyCornerTreatment)
    #expect(operationState.canAlignVertex)
    #expect(operationState.canProject)
}

@MainActor
@Test func workspaceSketchEntityInspectorStateBuilderKeepsWholeCurveSelectionForJoinAndCut() async throws {
    let fixture = try workspaceSketchEntityInspectorFixture()
    let referenceTarget = try #require(fixture.referenceLine.selectionTarget())
    let selectedTarget = try #require(fixture.selectedLine.selectionTarget())
    let builder = WorkspaceSketchEntityInspectorStateBuilder(
        document: fixture.document,
        selection: SelectionModel(selectedTargets: [referenceTarget, selectedTarget]),
        objectRegistry: .builtIn
    )

    let entity = try #require(try builder.selectedEntity())
    let joinState = builder.joinState(for: entity)
    let operationState = builder.operationState(for: entity)

    #expect(entity.entityKind == "line")
    #expect(builder.entityKind(for: referenceTarget) == "line")
    #expect(builder.cutterTarget(excluding: selectedTarget) == referenceTarget)
    #expect(builder.cornerTreatmentAdjacentTarget(excluding: selectedTarget) == referenceTarget)
    #expect(joinState.joinAdjacentTarget == referenceTarget)
    #expect(operationState.canJoin)
    #expect(operationState.canApplyCornerTreatment)
    #expect(!operationState.canExtend)
    #expect(!operationState.canOffsetVertex)
}

private struct WorkspaceSketchEntityInspectorFixture {
    var document: DesignDocument
    var referenceLineID: SketchEntityID
    var selectedLineID: SketchEntityID
    var referenceLine: SketchEntitySummaryResult.EntityEntry
    var selectedLine: SketchEntitySummaryResult.EntityEntry
}

@MainActor
private func workspaceSketchEntityInspectorFixture() throws -> WorkspaceSketchEntityInspectorFixture {
    let session = EditorSession()
    let referenceLineID = SketchEntityID()
    let selectedLineID = SketchEntityID()
    _ = try session.execute(
        .createSketch(
            name: "Inspector Lines",
            sketch: Sketch(
                plane: .xy,
                entities: [
                    referenceLineID: .line(SketchLine(
                        start: SketchPoint(
                            x: .length(0.0, .millimeter),
                            y: .length(0.0, .millimeter)
                        ),
                        end: SketchPoint(
                            x: .length(5.0, .millimeter),
                            y: .length(0.0, .millimeter)
                        )
                    )),
                    selectedLineID: .line(SketchLine(
                        start: SketchPoint(
                            x: .length(5.0, .millimeter),
                            y: .length(0.0, .millimeter)
                        ),
                        end: SketchPoint(
                            x: .length(10.0, .millimeter),
                            y: .length(2.0, .millimeter)
                        )
                    )),
                ]
            ),
            geometryRole: .curve
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let referenceLine = try #require(summary.entries.first { $0.entityID == referenceLineID.description })
    let selectedLine = try #require(summary.entries.first { $0.entityID == selectedLineID.description })
    return WorkspaceSketchEntityInspectorFixture(
        document: session.document,
        referenceLineID: referenceLineID,
        selectedLineID: selectedLineID,
        referenceLine: referenceLine,
        selectedLine: selectedLine
    )
}

private func pointHandleSelectionTarget(
    _ entry: SketchEntitySummaryResult.EntityEntry,
    handle: SketchEntityPointHandle
) throws -> SelectionTarget {
    let sourceTarget = try #require(entry.selectionTarget())
    let pointHandle = try #require(entry.pointHandles.first { $0.handle == handle })
    return SelectionTarget(
        sceneNodeID: sourceTarget.sceneNodeID,
        component: .sketchEntity(SelectionComponentID(rawValue: pointHandle.selectionComponentID))
    )
}
