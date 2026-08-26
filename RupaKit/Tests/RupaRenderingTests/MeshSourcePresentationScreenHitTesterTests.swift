import CoreGraphics
import RupaCore
import RupaCoreTypes
import RupaProjectModel
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaGeometry
@testable import RupaRendering

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationScreenHitTesterSelectsNearestOverlappingOccurrenceWithoutCopies() throws {
    let source = try screenHitMeshSource()
    let basis = ViewportProjectionBasis.isometric
    let viewNormal = try #require(basis.viewNormal)
    let frontTransform = try GeometryTransform3D(values: [
        1, 0, 0, viewNormal.x * 0.1,
        0, 1, 0, viewNormal.y * 0.1,
        0, 0, 1, viewNormal.z * 0.1,
        0, 0, 0, 1,
    ])
    let projectID = ProjectID(rawValue: "project.presentation-screen-hit")
    let scene = UniversalViewportScene(
        snapshotID: EvaluationSnapshotID(
            projectID: projectID,
            purpose: .presentation,
            sourceRevision: DocumentTransactionRevision()
        ),
        projectID: projectID,
        items: [
            try screenHitItem(
                occurrenceID: "occurrence.back",
                source: source,
                transform: .identity
            ),
            try screenHitItem(
                occurrenceID: "occurrence.front",
                source: source,
                transform: frontTransform
            ),
        ]
    )
    let initialTelemetry = scene.copyTelemetry
    let initialChunkIdentities = screenHitChunkIdentities(source)
    let plan = try MeshSourcePresentationRenderer().makePlan(for: scene)
    let layout = ViewportLayout(
        modelBounds: CGRect(x: 0, y: 0, width: 1, height: 1),
        size: CGSize(width: 400, height: 400),
        basis: basis,
        verticalBounds: -1 ... 1
    )
    let sample = layout.project(Point3D(x: 0.25, y: 0, z: 0.25))

    let occurrenceID = try MeshSourcePresentationScreenHitTester().occurrenceID(
        at: sample,
        in: plan,
        layout: layout
    )

    #expect(occurrenceID == SceneOccurrenceID(rawValue: "occurrence.front"))
    #expect(scene.copyTelemetry == initialTelemetry)
    #expect(screenHitChunkIdentities(source) == initialChunkIdentities)
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationScreenHitTesterMatchesHiddenAndClippedSectionGeometry() throws {
    let source = try screenHitMeshSource()
    let occurrenceID = SceneOccurrenceID(rawValue: "occurrence.sectioned")
    let projectID = ProjectID(rawValue: "project.presentation-section-hit")
    let scene = UniversalViewportScene(
        snapshotID: EvaluationSnapshotID(
            projectID: projectID,
            purpose: .presentation,
            sourceRevision: DocumentTransactionRevision()
        ),
        projectID: projectID,
        items: [
            try screenHitItem(
                occurrenceID: occurrenceID,
                source: source,
                transform: .identity
            ),
        ]
    )
    let layout = ViewportLayout(
        modelBounds: CGRect(x: 0, y: 0, width: 1, height: 1),
        size: CGSize(width: 400, height: 400),
        basis: .isometric,
        verticalBounds: -1 ... 1
    )
    let plan = try MeshSourcePresentationRenderer().makePlan(for: scene)
    let initialChunkIdentities = screenHitChunkIdentities(source)
    let hiddenResolver = screenHitSectionResolver(
        plane: SectionAnalysisResult.Plane(
            sourceKind: .sketchPlane,
            sourceID: nil,
            sourceName: nil,
            origin: Point3D(x: 2.0, y: 0.0, z: 0.0),
            normal: .unitX,
            u: .unitY,
            v: .unitZ
        )
    )

    #expect(try MeshSourcePresentationScreenHitTester().occurrenceID(
        at: layout.project(Point3D(x: 0.25, y: 0, z: 0.25)),
        in: plan,
        layout: layout,
        sectionGeometryResolver: hiddenResolver
    ) == nil)

    let clippingPlane = SectionAnalysisResult.Plane(
        sourceKind: .sketchPlane,
        sourceID: nil,
        sourceName: nil,
        origin: Point3D(x: 0.5, y: 0.0, z: 0.0),
        normal: .unitX,
        u: .unitY,
        v: .unitZ
    )
    let clippedResolver = screenHitSectionResolver(
        plane: clippingPlane
    )
    #expect(try MeshSourcePresentationScreenHitTester().occurrenceID(
        at: layout.project(Point3D(x: 0.25, y: 0, z: 0.25)),
        in: plan,
        layout: layout,
        sectionGeometryResolver: clippedResolver
    ) == nil)
    #expect(try MeshSourcePresentationScreenHitTester().occurrenceID(
        at: layout.project(Point3D(x: 0.75, y: 0, z: 0.10)),
        in: plan,
        layout: layout,
        sectionGeometryResolver: clippedResolver
    ) == occurrenceID)
    #expect(screenHitChunkIdentities(source) == initialChunkIdentities)
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationScreenHitTesterFindsRectangleOccurrencesWithoutCopies() throws {
    let source = try screenHitMeshSource()
    let occurrenceID = SceneOccurrenceID(rawValue: "occurrence.rectangle")
    let projectID = ProjectID(rawValue: "project.presentation-rectangle-hit")
    let scene = UniversalViewportScene(
        snapshotID: EvaluationSnapshotID(
            projectID: projectID,
            purpose: .presentation,
            sourceRevision: DocumentTransactionRevision()
        ),
        projectID: projectID,
        items: [
            try screenHitItem(
                occurrenceID: occurrenceID,
                source: source,
                transform: .identity
            ),
        ]
    )
    let plan = try MeshSourcePresentationRenderer().makePlan(for: scene)
    let layout = ViewportLayout(
        modelBounds: CGRect(x: 0, y: 0, width: 1, height: 1),
        size: CGSize(width: 400, height: 400),
        basis: .isometric,
        verticalBounds: -1 ... 1
    )
    let sample = layout.project(Point3D(x: 0.25, y: 0, z: 0.25))
    let initialChunkIdentities = screenHitChunkIdentities(source)

    let occurrenceIDs = try MeshSourcePresentationScreenHitTester().occurrenceIDs(
        intersecting: CGRect(x: sample.x - 8, y: sample.y - 8, width: 16, height: 16),
        in: plan,
        layout: layout
    )

    #expect(occurrenceIDs == [occurrenceID])
    #expect(screenHitChunkIdentities(source) == initialChunkIdentities)
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationScreenHitTesterRejectsRectangleInsideTriangleBoundsButOutsideTriangle() throws {
    let source = try screenHitMeshSource()
    let occurrenceID = SceneOccurrenceID(rawValue: "occurrence.rectangle-aabb")
    let projectID = ProjectID(rawValue: "project.presentation-rectangle-aabb")
    let scene = UniversalViewportScene(
        snapshotID: EvaluationSnapshotID(
            projectID: projectID,
            purpose: .presentation,
            sourceRevision: DocumentTransactionRevision()
        ),
        projectID: projectID,
        items: [
            try screenHitItem(
                occurrenceID: occurrenceID,
                source: source,
                transform: .identity
            ),
        ]
    )
    let plan = try MeshSourcePresentationRenderer().makePlan(for: scene)
    let layout = ViewportLayout(
        modelBounds: CGRect(x: 0, y: 0, width: 1, height: 1),
        size: CGSize(width: 400, height: 400),
        basis: .isometric,
        verticalBounds: -1 ... 1
    )
    let projectedVertices = [
        layout.project(.origin),
        layout.project(Point3D(x: 1, y: 0, z: 0)),
        layout.project(Point3D(x: 0, y: 0, z: 1)),
    ]
    let minimumX = try #require(projectedVertices.map(\.x).min())
    let maximumX = try #require(projectedVertices.map(\.x).max())
    let minimumY = try #require(projectedVertices.map(\.y).min())
    let maximumY = try #require(projectedVertices.map(\.y).max())
    let insetX = (maximumX - minimumX) * 0.1
    let insetY = (maximumY - minimumY) * 0.1
    let candidates = [
        CGPoint(x: minimumX + insetX, y: minimumY + insetY),
        CGPoint(x: maximumX - insetX, y: minimumY + insetY),
        CGPoint(x: maximumX - insetX, y: maximumY - insetY),
        CGPoint(x: minimumX + insetX, y: maximumY - insetY),
    ]
    let hitTester = MeshSourcePresentationScreenHitTester()
    let outsidePoint = try #require(candidates.first { point in
        try hitTester.occurrenceID(at: point, in: plan, layout: layout) == nil
    })
    let probe = CGRect(
        x: outsidePoint.x - 0.25,
        y: outsidePoint.y - 0.25,
        width: 0.5,
        height: 0.5
    )
    let projectedBounds = CGRect(
        x: minimumX,
        y: minimumY,
        width: maximumX - minimumX,
        height: maximumY - minimumY
    )

    #expect(projectedBounds.intersects(probe))
    #expect(try hitTester.occurrenceIDs(
        intersecting: probe,
        in: plan,
        layout: layout
    ).isEmpty)
}

private func screenHitSectionResolver(
    plane: SectionAnalysisResult.Plane?
) -> MeshSourcePresentationSectionGeometryResolver {
    MeshSourcePresentationSectionGeometryResolver(
        sectionPlan: SectionAnalysisClippingPlan(
            retainedSide: .front,
            bodies: []
        ),
        plane: plane,
        toleranceMeters: 0.0
    )
}

private func screenHitItem(
    occurrenceID: SceneOccurrenceID,
    source: MeshSource,
    transform: GeometryTransform3D
) throws -> UniversalViewportSceneItem {
    let reference = GeometrySourceReference.authoredMesh(source.identity)
    return UniversalViewportSceneItem(
        id: occurrenceID,
        definitionID: ObjectDefinitionID(rawValue: "definition.\(occurrenceID.rawValue)"),
        displayName: occurrenceID.rawValue,
        representationID: GeometryRepresentationID(rawValue: "representation.\(occurrenceID.rawValue)"),
        reference: reference,
        mesh: source,
        worldTransform: transform,
        worldBounds: try source.bounds().transformed(by: transform)
    )
}

private func screenHitMeshSource() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: GeometrySourceID(rawValue: "mesh.presentation-screen-hit"))
    try builder.reserveCapacity(vertexCount: 3, faceCount: 1, cornerCount: 3)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 1))
    _ = try builder.addFace(vertexIDs: [first, second, third])
    return try builder.build()
}

private func screenHitChunkIdentities(_ source: MeshSource) -> [[ObjectIdentifier]] {
    [
        source.vertexIDs.storage.chunkIdentities,
        source.vertexPositions.storage.chunkIdentities,
        source.faceIDs.storage.chunkIdentities,
        source.faceCornerRanges.storage.chunkIdentities,
        source.cornerIDs.storage.chunkIdentities,
        source.cornerVertexIDs.storage.chunkIdentities,
    ]
}
