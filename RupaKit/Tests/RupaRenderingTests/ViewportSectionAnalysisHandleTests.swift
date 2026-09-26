import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

/// The Section Analysis distance handle: a signed axis drag and the arrow the producer registers.
@Suite struct ViewportSectionAnalysisHandleTests {
    @Test func theHandleDragsASignedDistanceAndCommitsItOnRelease() throws {
        let input = try #require(try ViewportNativeAxisInput(record: .init(
            target: .sectionAnalysisDistance(axis: .init(origin: .origin, direction: .unitZ, baseValue: 0.02))
        )))
        let value = try input.value(forWorldDelta: -0.05)
        #expect(abs(value - (-0.03)) < 1e-12, "The plane may move to the other side of its source.")
        #expect(try input.commit(value: value) == .sectionAnalysisDistance(.init(distanceMeters: value)))
        #expect(try input.commit(value: try input.value(forWorldDelta: 0)) == nil)
    }

    @Test func theProducerRegistersTheArrowAndMovesItDuringADrag() throws {
        let section = ViewportSpatialOverlaySemanticSnapshot.Section(
            plane: .init(
                origin: Point3D(x: 0, y: 0, z: 0.01),
                normalEnd: Point3D(x: 0, y: 0, z: 0.11),
                corners: [
                    Point3D(x: -1, y: -1, z: 0.01), Point3D(x: 1, y: -1, z: 0.01),
                    Point3D(x: 1, y: 1, z: 0.01), Point3D(x: -1, y: 1, z: 0.01),
                ]
            ),
            segments: [], contours: [], hatches: [],
            sourceSegmentCount: 0, omittedSegmentCount: 0, sourceContourCount: 0, omittedContourCount: 0,
            hasTruncatedSourcePayload: false,
            handle: .init(distanceMeters: 0.01, sourceNormal: .unitZ, activeDistanceMeters: 0.03)
        )
        var paths: [ViewportSpatialOverlayInput.Path] = []
        var meshes: [ViewportSpatialOverlayInput.Mesh] = []
        var records: [ViewportSpatialInteractionRecord] = []
        var families: Set<ViewportSpatialOverlayFamily> = []
        try ViewportSpatialOverlayProducer.appendSection(
            section, paths: &paths, meshes: &meshes, interactionRecords: &records, activeFamilies: &families
        )
        #expect(records.map(\.identity) == [.sectionAnalysisDistance])
        let arrow = try #require(meshes.first { $0.value.handleIndex != nil })
        #expect(arrow.value.handleIndex == 0)
        // The drag in progress moves the arrow 0.02 along the normal.
        #expect(abs((arrow.value.positions.first?.z ?? 0) - 0.03) < 1e-12)
    }
}
