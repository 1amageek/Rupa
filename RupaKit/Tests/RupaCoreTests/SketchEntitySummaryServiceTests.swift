import Testing
import SwiftCAD
@testable import RupaCore

@MainActor
@Test func sketchEntitySummaryServiceReportsSourceCurvesAndSelectionTargets() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Guide Line",
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
    _ = try session.execute(
        .createCircleSketch(
            name: "Guide Circle",
            plane: .xy,
            center: SketchPoint(
                x: .length(5.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(4.0, .millimeter)
        )
    )
    _ = try session.execute(
        .createArcSketch(
            name: "Guide Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(6.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(90.0, .degree)
        )
    )
    _ = try session.execute(
        .createSplineSketch(
            name: "Guide Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )

    let result = try SketchEntitySummaryService().summarize(document: session.document)

    #expect(result.counts.sketchCount == 4)
    #expect(result.counts.entityCount == 4)
    #expect(result.entries.filter { $0.entityKind == "line" }.count == 1)
    #expect(result.entries.filter { $0.entityKind == "circle" }.count == 1)
    #expect(result.entries.filter { $0.entityKind == "arc" }.count == 1)
    #expect(result.entries.filter { $0.entityKind == "spline" }.count == 1)
    #expect(result.entries.allSatisfy { $0.sceneNodeID != nil })
    #expect(result.entries.allSatisfy { $0.selectionComponentID?.hasPrefix(SelectionComponentID.sketchEntityPrefix) == true })

    let line = try #require(result.entries.first { $0.entityKind == "line" })
    #expect(abs((line.start?.x ?? -1.0) - 0.0) < 0.000_000_001)
    #expect(abs((line.end?.x ?? -1.0) - 0.01) < 0.000_000_001)
    #expect(line.pointHandles.map(\.handle) == [.lineStart, .lineEnd])
    #expect(line.pointHandles.allSatisfy {
        $0.selectionComponentID.hasPrefix(SelectionComponentID.sketchPointHandlePrefix)
    })

    let circle = try #require(result.entries.first { $0.entityKind == "circle" })
    #expect(abs((circle.center?.x ?? -1.0) - 0.005) < 0.000_000_001)
    #expect(abs((circle.radius ?? -1.0) - 0.004) < 0.000_000_001)
    #expect(circle.pointHandles.map(\.handle) == [.circleCenter])

    let arc = try #require(result.entries.first { $0.entityKind == "arc" })
    #expect(abs((arc.radius ?? -1.0) - 0.006) < 0.000_000_001)
    #expect(abs((arc.end?.x ?? -1.0) - 0.0) < 0.000_000_001)
    #expect(abs((arc.end?.y ?? -1.0) - 0.006) < 0.000_000_001)
    #expect(arc.pointHandles.map(\.handle) == [.arcCenter, .arcStart, .arcEnd])

    let spline = try #require(result.entries.first { $0.entityKind == "spline" })
    #expect(spline.controlPoints.count == 4)
    #expect(spline.controlPointExpressions.count == 4)
    #expect(spline.controlPointTargets.map(\.index) == [0, 1, 2, 3])
    #expect(spline.controlPointTargets.allSatisfy {
        $0.selectionComponentID.hasPrefix(SelectionComponentID.sketchControlPointPrefix)
    })
    #expect(abs((spline.controlPoints.last?.x ?? -1.0) - 0.008) < 0.000_000_001)

    let target = try #require(spline.selectionTarget())
    #expect(session.selectTarget(target))
    #expect(session.selectedTarget == target)

    let lineTarget = try #require(line.selectionTarget())
    let lineEndHandle = try #require(line.pointHandles.first { $0.handle == .lineEnd })
    let lineEndTarget = SelectionTarget(
        sceneNodeID: lineTarget.sceneNodeID,
        component: .sketchEntity(SelectionComponentID(rawValue: lineEndHandle.selectionComponentID))
    )
    #expect(session.selectTarget(lineEndTarget))
    #expect(session.selectedTarget == lineEndTarget)

    let splineControl = try #require(spline.controlPointTargets.last)
    let splineControlTarget = SelectionTarget(
        sceneNodeID: target.sceneNodeID,
        component: .sketchEntity(SelectionComponentID(rawValue: splineControl.selectionComponentID))
    )
    #expect(session.selectTarget(splineControlTarget))
    #expect(session.selectedTarget == splineControlTarget)
}

@MainActor
@Test func sketchEntitySummaryServiceReportsClosedRegionSelectionTargets() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createRectangleSketch(
        name: "Selectable Region",
        plane: .xy,
        width: .length(10.0, .millimeter),
        height: .length(6.0, .millimeter)
    )
    let session = EditorSession(document: document)

    let result = try SketchEntitySummaryService().summarize(document: session.document)

    #expect(result.counts.regionCount == 1)
    let region = try #require(result.regions.first)
    #expect(region.sourceFeatureID == featureID.description)
    #expect(region.profileIndex == 0)
    #expect(region.selectionComponentID?.hasPrefix(SelectionComponentID.profileRegionPrefix) == true)
    #expect(abs(region.center.x) < 1.0e-12)
    #expect(abs(region.center.y) < 1.0e-12)
    #expect(abs(region.areaSquareMeters - 0.000_06) < 1.0e-12)
    #expect(region.boundaryPointCount == 4)
    #expect(region.boundarySegmentCount == 4)

    let target = try #require(region.selectionTarget())
    #expect(session.selectTarget(target))
    #expect(session.selectedTarget == target)

    let invalidTarget = SelectionTarget(
        sceneNodeID: target.sceneNodeID,
        component: .region(
            .profileRegion(
                featureID: featureID,
                profileIndex: 1
            )
        )
    )
    #expect(session.selectTarget(invalidTarget) == false)
    #expect(session.selectedTarget == target)
}

@MainActor
@Test func sketchEntitySelectionRejectsMissingSourceEntity() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createCircleSketch(
            name: "Selectable Circle",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter)
        )
    )
    let result = try SketchEntitySummaryService().summarize(document: session.document)
    let entry = try #require(result.entries.first)
    let target = try #require(entry.selectionTarget())
    let invalidTarget = SelectionTarget(
        sceneNodeID: target.sceneNodeID,
        component: .sketchEntity(
            .sketchEntity(
                featureID: FeatureID(),
                entityID: SketchEntityID()
            )
        )
    )

    #expect(session.selectTarget(target))
    #expect(session.selectTarget(invalidTarget) == false)
    #expect(session.selectedTarget == target)
}
