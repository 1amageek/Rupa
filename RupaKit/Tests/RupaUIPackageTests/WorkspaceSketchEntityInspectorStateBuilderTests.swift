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
        displayUnit: .millimeter,
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
        displayUnit: .millimeter,
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

@MainActor
@Test func workspaceSketchEntityInspectorStateBuilderExposesBridgeCurvatureDisplayTarget() async throws {
    let fixture = try workspaceBridgeCurveInspectorFixture()
    var workspaceState = WorkspaceState()
    _ = try workspaceState.apply(
        .setCurveCurvatureDisplay(
            target: fixture.bridgeTarget,
            isVisible: true,
            combScale: 0.35
        ),
        document: fixture.document
    )
    let builder = WorkspaceSketchEntityInspectorStateBuilder(
        document: fixture.document,
        selection: SelectionModel(selectedTargets: [fixture.bridgeTarget]),
        displayUnit: workspaceState.displayUnit,
        objectRegistry: .builtIn,
        curveCurvatureDisplays: workspaceState.curveCurvatureDisplays
    )

    let entity = try #require(try builder.selectedEntity())
    let bridgeCurve = try #require(entity.bridgeCurve)

    #expect(entity.entityID == fixture.bridgeEntityID)
    #expect(bridgeCurve.target == fixture.bridgeTarget)
    #expect(bridgeCurve.curvatureDisplay == CurveCurvatureDisplay(
        componentID: fixture.bridgeComponentID,
        combScale: 0.35
    ))
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
    let summary = try SketchEntitySnapshotService().snapshot(document: session.document)
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

private struct WorkspaceBridgeCurveInspectorFixture {
    var document: DesignDocument
    var featureID: FeatureID
    var firstLineID: SketchEntityID
    var secondLineID: SketchEntityID
    var bridgeEntityID: SketchEntityID
    var bridgeTarget: SelectionTarget
    var bridgeComponentID: SelectionComponentID
}

@MainActor
private func workspaceBridgeCurveInspectorFixture() throws -> WorkspaceBridgeCurveInspectorFixture {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Inspector Bridge",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .meter),
            y: .length(0.0, .meter)
        ),
        end: SketchPoint(
            x: .length(0.003, .meter),
            y: .length(0.0, .meter)
        )
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstLineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Bridge inspector setup requires a source line sketch."
        )
    }
    let secondLineID = SketchEntityID()
    sketch.entities[secondLineID] = .line(SketchLine(
        start: SketchPoint(
            x: .length(0.006, .meter),
            y: .length(0.003, .meter)
        ),
        end: SketchPoint(
            x: .length(0.006, .meter),
            y: .length(0.006, .meter)
        )
    ))
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()

    let bridgeEntityID = try document.createBridgeCurve(
        featureID: featureID,
        firstEndpoint: BridgeCurveEndpoint(reference: .lineEnd(firstLineID)),
        secondEndpoint: BridgeCurveEndpoint(reference: .lineStart(secondLineID)),
        continuity: .g1
    )
    let summary = try SketchEntitySnapshotService().snapshot(document: document)
    let bridgeEntry = try #require(summary.entries.first { $0.entityID == bridgeEntityID.description })
    let bridgeTarget = try #require(bridgeEntry.selectionTarget())
    let bridgeComponentID = try #require(sketchEntityComponentID(from: bridgeTarget))

    return WorkspaceBridgeCurveInspectorFixture(
        document: document,
        featureID: featureID,
        firstLineID: firstLineID,
        secondLineID: secondLineID,
        bridgeEntityID: bridgeEntityID,
        bridgeTarget: bridgeTarget,
        bridgeComponentID: bridgeComponentID
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

private func sketchEntityComponentID(from target: SelectionTarget) -> SelectionComponentID? {
    guard case .sketchEntity(let componentID) = target.component else {
        return nil
    }
    return componentID
}
