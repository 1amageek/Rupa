import Foundation
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Test func viewportSlotWidthSourceTargetResolverNormalizesLineEndpointSelection() async throws {
    let fixture = try slotWidthSourceTargetResolverFixture(kind: .line)
    let lineEnd = try #require(fixture.entry.pointHandles.first { $0.handle == .lineEnd })
    let endpointTarget = SelectionTarget(
        sceneNodeID: fixture.sourceTarget.sceneNodeID,
        component: .sketchEntity(SelectionComponentID(rawValue: lineEnd.selectionComponentID))
    )

    let resolved = try #require(
        ViewportSlotWidthSourceTargetResolver(document: fixture.document)
            .sourceTarget(for: endpointTarget)
    )

    #expect(resolved.featureID == fixture.featureID)
    #expect(resolved.entityID == fixture.entityID)
    #expect(resolved.target == fixture.sourceTarget)
}

@MainActor
@Test func viewportSlotWidthSourceTargetResolverNormalizesSplineControlPointSelection() async throws {
    let fixture = try slotWidthSourceTargetResolverFixture(kind: .spline)
    let controlPoint = try #require(fixture.entry.controlPointTargets.first { $0.index == 2 })
    let controlPointTarget = SelectionTarget(
        sceneNodeID: fixture.sourceTarget.sceneNodeID,
        component: .sketchEntity(SelectionComponentID(rawValue: controlPoint.selectionComponentID))
    )

    let resolved = try #require(
        ViewportSlotWidthSourceTargetResolver(document: fixture.document)
            .sourceTarget(for: controlPointTarget)
    )

    #expect(resolved.featureID == fixture.featureID)
    #expect(resolved.entityID == fixture.entityID)
    #expect(resolved.target == fixture.sourceTarget)
}

@MainActor
@Test func viewportSlotWidthSourceTargetResolverRejectsObjectSelection() async throws {
    let fixture = try slotWidthSourceTargetResolverFixture(kind: .line)
    let objectTarget = SelectionTarget(sceneNodeID: fixture.sourceTarget.sceneNodeID)

    #expect(
        ViewportSlotWidthSourceTargetResolver(document: fixture.document)
            .sourceTarget(for: objectTarget) == nil
    )
}

private enum SlotWidthSourceTargetResolverFixtureKind {
    case line
    case spline
}

private struct SlotWidthSourceTargetResolverFixture {
    var document: DesignDocument
    var featureID: FeatureID
    var entityID: SketchEntityID
    var entry: SketchEntitySummaryResult.EntityEntry
    var sourceTarget: SelectionTarget
}

@MainActor
private func slotWidthSourceTargetResolverFixture(
    kind: SlotWidthSourceTargetResolverFixtureKind
) throws -> SlotWidthSourceTargetResolverFixture {
    let session = EditorSession()
    let entityID = SketchEntityID()
    let entity: SketchEntity
    switch kind {
    case .line:
        entity = .line(SketchLine(
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        ))
    case .spline:
        entity = .spline(SketchSpline(controlPoints: [
            SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
            SketchPoint(x: .length(3.0, .millimeter), y: .length(2.0, .millimeter)),
            SketchPoint(x: .length(7.0, .millimeter), y: .length(2.0, .millimeter)),
            SketchPoint(x: .length(10.0, .millimeter), y: .length(0.0, .millimeter)),
        ]))
    }

    _ = try session.execute(
        .createSketch(
            name: "Slot Width Source",
            sketch: Sketch(plane: .xy, entities: [entityID: entity]),
            geometryRole: .curve
        )
    )
    let summary = try SketchEntitySnapshotService().snapshot(document: session.document)
    let entry = try #require(summary.entries.first { $0.entityID == entityID.description })
    let sourceTarget = try #require(entry.selectionTarget())
    guard let featureUUID = UUID(uuidString: entry.sourceFeatureID) else {
        throw EditorError(code: .referenceUnresolved, message: "Missing sketch feature ID.")
    }
    return SlotWidthSourceTargetResolverFixture(
        document: session.document,
        featureID: FeatureID(featureUUID),
        entityID: entityID,
        entry: entry,
        sourceTarget: sourceTarget
    )
}
