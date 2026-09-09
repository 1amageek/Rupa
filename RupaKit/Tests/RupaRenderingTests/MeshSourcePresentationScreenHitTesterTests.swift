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
func measurementSurfaceHitRoundTripsWorldPointsInBothLenses() throws {
    let source = try screenHitMeshSource()
    let projectID = ProjectID(rawValue: "measurement.ray")
    let scene = UniversalViewportScene(
        snapshotID: EvaluationSnapshotID(projectID: projectID, purpose: .presentation,
                                        sourceRevision: DocumentTransactionRevision()),
        projectID: projectID,
        items: [try screenHitItem(occurrenceID: "measurement.surface", source: source, transform: .identity)]
    )
    let plan = try MeshSourcePresentationRenderer().makePlan(for: scene)
    for projection in [ViewportCameraProjection.parallel, .standardPerspective] {
        let layout = ViewportLayout(
            modelBounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            size: CGSize(width: 800, height: 600), camera: ViewportCamera(projection: projection),
            basis: .isometric, verticalBounds: -1...1
        )
        let world = Point3D(x: 0.2, y: 0, z: 0.3)
        let screen = try #require(layout.projectedPoint(world)).point
        let hit = try #require(MeshSourcePresentationScreenHitTester().worldPoint(at: screen, in: plan, layout: layout))
        #expect(hit.point.isApproximatelyEqual(to: world, tolerance: 1.0e-9))
    }
}

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

    let occurrenceID = MeshSourcePresentationScreenHitTester().occurrenceID(
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

    #expect(MeshSourcePresentationScreenHitTester().occurrenceID(
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
    #expect(MeshSourcePresentationScreenHitTester().occurrenceID(
        at: layout.project(Point3D(x: 0.25, y: 0, z: 0.25)),
        in: plan,
        layout: layout,
        sectionGeometryResolver: clippedResolver
    ) == nil)
    #expect(MeshSourcePresentationScreenHitTester().occurrenceID(
        at: layout.project(Point3D(x: 0.75, y: 0, z: 0.10)),
        in: plan,
        layout: layout,
        sectionGeometryResolver: clippedResolver
    ) == occurrenceID)
    #expect(screenHitChunkIdentities(source) == initialChunkIdentities)
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

@Test(.timeLimit(.minutes(1)))
func meshElementPickingKeepsSourceProvenanceAndRejectsTriangulationDiagonal() throws {
    var builder = MeshSourceBuilder(identity: GeometrySourceID(rawValue: "mesh.quad-pick"))
    let a = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let b = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let c = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 1))
    let d = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 1))
    let face = try builder.addFace(vertexIDs: [a, b, c, d])
    let source = try builder.build()
    let projectID = ProjectID(rawValue: "mesh-pick")
    let scene = UniversalViewportScene(
        snapshotID: EvaluationSnapshotID(projectID: projectID, purpose: .presentation, sourceRevision: DocumentTransactionRevision()),
        projectID: projectID,
        items: [try screenHitItem(occurrenceID: "quad", source: source, transform: .identity)]
    )
    let plan = try MeshSourcePresentationRenderer().makePlan(for: scene)
    let layout = ViewportLayout(modelBounds: CGRect(x: 0, y: 0, width: 1, height: 1), size: CGSize(width: 500, height: 500), basis: .isometric, verticalBounds: -1...1)
    let tester = MeshSourcePresentationScreenHitTester()
    let center = layout.project(Point3D(x: 0.5, y: 0, z: 0.5))
    var preparedEdges: [MeshEdgeID] = []
    var diagonalCount = 0
    plan.forEachTriangle { triangle in
        for edge in [triangle.firstEdgeID, triangle.secondEdgeID, triangle.thirdEdgeID] {
            if let edge { preparedEdges.append(edge) } else { diagonalCount += 1 }
        }
    }
    #expect(Set(preparedEdges) == Set(source.edgeIDs))
    #expect(preparedEdges.count == 4)
    #expect(diagonalCount == 2)
    let faceHit = try #require(tester.meshElement(at: center, domain: .face, in: plan, scene: scene, layout: layout))
    #expect(faceHit.element == .face(face))
    #expect(faceHit.sourceID == source.identity)
    #expect(faceHit.snapshotID == scene.snapshotID)
    #expect(tester.meshElement(at: center, domain: .edge, in: plan, scene: scene, layout: layout) == nil)
    let vertex = layout.project(Point3D(x: 0.001, y: 0, z: 0.001))
    #expect(tester.meshElement(at: vertex, domain: .vertex, in: plan, scene: scene, layout: layout)?.element == .vertex(a))
    let boundary = layout.project(Point3D(x: 0.5, y: 0, z: 0.001))
    let edgeHit = try #require(tester.meshElement(at: boundary, domain: .edge, in: plan, scene: scene, layout: layout))
    guard case .edge(let edgeID) = edgeHit.element else { Issue.record("Expected a real boundary edge"); return }
    #expect(source.edgeIDs.contains(edgeID))
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
