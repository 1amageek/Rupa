import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test func sketchDimensionSummaryListsLineLengthAndAngleCandidates() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Dimension Summary Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let sketchSummary = try SketchEntitySnapshotService().snapshot(document: session.document)
    let line = try #require(sketchSummary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    let summary = try SketchDimensionSnapshotService().snapshot(
        document: session.document,
        targets: [target]
    )

    #expect(summary.counts.targetCount == 1)
    #expect(summary.counts.entryCount == 2)
    #expect(summary.entries.map(\.kind) == [.length, .angle])
    #expect(summary.entries.first?.isPrimaryForTarget == true)
    let values = Dictionary(uniqueKeysWithValues: summary.entries.map { ($0.kind, $0.resolvedValue) })
    #expect(abs((values[.length] ?? -1.0) - 0.010) < 1.0e-12)
    #expect(abs((values[.angle] ?? -1.0) - 0.0) < 1.0e-12)
}

@Test func sketchDimensionSummaryExposesDocumentDisplayValues() async throws {
    var document = DesignDocument.empty()
    _ = try document.createLineSketch(
        name: "Dimension Summary Display Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .meter),
            y: .length(0.0, .meter)
        ),
        end: SketchPoint(
            x: .length(0.03, .meter),
            y: .length(0.04, .meter)
        )
    )
    let sketchSummary = try SketchEntitySnapshotService().snapshot(document: document)
    let line = try #require(sketchSummary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    let summary = try SketchDimensionSummaryService().summarize(
        document: document,
        targets: [target],
        displayUnit: .centimeter
    )

    let length = try #require(summary.entries.first { $0.kind == .length })
    let angle = try #require(summary.entries.first { $0.kind == .angle })
    #expect(summary.displayUnit == .centimeter)
    #expect(summary.displayUnitSymbol == "cm")
    #expect(length.valueKind == .length)
    #expect(abs(length.resolvedValue - 0.05) < 1.0e-12)
    #expect(abs(length.resolvedDisplayValue - 5.0) < 1.0e-12)
    #expect(length.resolvedDisplayUnitSymbol == "cm")
    #expect(angle.valueKind == .angle)
    #expect(abs(angle.resolvedValue - atan2(0.04, 0.03)) < 1.0e-12)
    #expect(abs(angle.resolvedDisplayValue - 53.130_102_354_155_98) < 1.0e-12)
    #expect(angle.resolvedDisplayUnitSymbol == "deg")
}

@MainActor
@Test func sketchDimensionSummaryListsCircleDiameterAndRadiusCandidates() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createCircleSketch(
            name: "Dimension Summary Circle",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter)
        )
    )
    let sketchSummary = try SketchEntitySnapshotService().snapshot(document: session.document)
    let circle = try #require(sketchSummary.entries.first { $0.entityKind == "circle" })
    let target = try #require(circle.selectionTarget())

    let summary = try SketchDimensionSnapshotService().snapshot(
        document: session.document,
        targets: [target]
    )

    #expect(summary.counts.targetCount == 1)
    #expect(summary.counts.entryCount == 2)
    #expect(summary.entries.map(\.kind) == [.diameter, .radius])
    #expect(summary.entries.first?.isPrimaryForTarget == true)
    let values = Dictionary(uniqueKeysWithValues: summary.entries.map { ($0.kind, $0.resolvedValue) })
    #expect(abs((values[.diameter] ?? -1.0) - 0.010) < 1.0e-12)
    #expect(abs((values[.radius] ?? -1.0) - 0.005) < 1.0e-12)
}

@MainActor
@Test func sketchDimensionSummaryListsArcCircularAndSpanCandidates() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Dimension Summary Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(90.0, .degree)
        )
    )
    let sketchSummary = try SketchEntitySnapshotService().snapshot(document: session.document)
    let arc = try #require(sketchSummary.entries.first { $0.entityKind == "arc" })
    let target = try #require(arc.selectionTarget())

    let summary = try SketchDimensionSnapshotService().snapshot(
        document: session.document,
        targets: [target]
    )

    #expect(summary.counts.targetCount == 1)
    #expect(summary.counts.entryCount == 3)
    #expect(summary.entries.map(\.kind) == [.diameter, .radius, .angle])
    #expect(summary.entries.first?.isPrimaryForTarget == true)
    let values = Dictionary(uniqueKeysWithValues: summary.entries.map { ($0.kind, $0.resolvedValue) })
    #expect(abs((values[.diameter] ?? -1.0) - 0.010) < 1.0e-12)
    #expect(abs((values[.radius] ?? -1.0) - 0.005) < 1.0e-12)
    #expect(abs((values[.angle] ?? -1.0) - (Double.pi / 2.0)) < 1.0e-12)
}

@MainActor
@Test func sketchDimensionSummaryMapsGeneratedRectangleCapEdgeToSourceLine() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let topology = try TopologySnapshotService().snapshot(document: session.document)
    let capEdge = try #require(topology.entries.first {
        $0.kind == .edge &&
            $0.generatedRole == "edge" &&
            $0.curveKind == "line" &&
            ($0.index ?? Int.max) < 4
    })
    let target = try #require(capEdge.selectionTarget())

    let summary = try SketchDimensionSnapshotService().snapshot(
        document: session.document,
        targets: [target]
    )

    #expect(summary.counts.targetCount == 1)
    #expect(summary.counts.entryCount == 2)
    #expect(summary.entries.map(\.kind) == [.length, .angle])
    #expect(summary.entries.allSatisfy { $0.requestedTarget == target })
    #expect(summary.entries.allSatisfy { $0.target != target })
    #expect(summary.entries.allSatisfy { $0.entityKind == "line" })
    guard case .sketchEntity = summary.entries[0].target.component else {
        Issue.record("Generated edge dimensions must resolve to an editable sketch entity target.")
        return
    }
}

@MainActor
@Test func sketchDimensionSummaryMapsGeneratedCylinderCapEdgeToSourceCircle() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedCircle())
    let topology = try TopologySnapshotService().snapshot(document: session.document)
    let capEdge = try #require(topology.entries.first {
        $0.kind == .edge &&
            $0.generatedRole == "edge" &&
            $0.curveKind == "circle" &&
            ($0.index ?? Int.max) < 8
    })
    let target = try #require(capEdge.selectionTarget())

    let summary = try SketchDimensionSnapshotService().snapshot(
        document: session.document,
        targets: [target]
    )

    #expect(summary.counts.targetCount == 1)
    #expect(summary.counts.entryCount == 2)
    #expect(summary.entries.map(\.kind) == [.diameter, .radius])
    #expect(summary.entries.allSatisfy { $0.requestedTarget == target })
    #expect(summary.entries.allSatisfy { $0.target != target })
    #expect(summary.entries.allSatisfy { $0.entityKind == "circle" })
    guard case .sketchEntity = summary.entries[0].target.component else {
        Issue.record("Generated circular edge dimensions must resolve to an editable sketch entity target.")
        return
    }
}

@MainActor
@Test func sketchDimensionSummaryMapsGeneratedFilletArcEdgeToSourceArcRadius() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(sceneNodeID(forBody: bodyFeatureID, in: session.document))
    _ = try session.execute(
        .filletBodyEdges(
            targets: [
                SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
            ],
            radius: .length(1.0, .millimeter),
            segmentCount: 8
        )
    )
    let topology = try TopologySnapshotService().snapshot(document: session.document)
    let filletArcEdge = try #require(topology.entries.first {
        guard let radius = $0.curveRadius else {
            return false
        }
        return $0.kind == .edge &&
            $0.generatedRole == "edge" &&
            $0.curveKind == "circle" &&
            abs(radius - 0.001) < 1.0e-12
    })
    let target = try #require(filletArcEdge.selectionTarget())

    let summary = try SketchDimensionSnapshotService().snapshot(
        document: session.document,
        targets: [target]
    )

    #expect(summary.counts.targetCount == 1)
    #expect(summary.counts.entryCount == 3)
    #expect(summary.entries.map(\.kind) == [.diameter, .radius, .angle])
    #expect(summary.entries.allSatisfy { $0.requestedTarget == target })
    #expect(summary.entries.allSatisfy { $0.target != target })
    #expect(summary.entries.allSatisfy { $0.entityKind == "arc" })
    let primary = try #require(summary.entries.first { $0.isPrimaryForTarget })
    #expect(primary.kind == .radius)
    #expect(abs(primary.resolvedValue - 0.001) < 1.0e-12)
    guard case .sketchEntity = primary.target.component else {
        Issue.record("Generated fillet arc edge dimensions must resolve to an editable sketch arc target.")
        return
    }
}

private func sceneNodeID(
    forBody featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference == .body(featureID)
    }?.key
}
