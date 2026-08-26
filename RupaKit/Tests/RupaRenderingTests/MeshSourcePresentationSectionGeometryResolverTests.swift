import Testing
import RupaCore
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel
import RupaViewportScene
import SwiftCAD
@testable import RupaRendering

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationSectionClipsMeshOnlyGeometryFromThePresentationTriangle() throws {
    let resolver = MeshSourcePresentationSectionGeometryResolver(
        sectionPlan: SectionAnalysisClippingPlan(retainedSide: .front, bodies: []),
        plane: sectionPlane(originX: 0.5),
        toleranceMeters: 0.0
    )

    let polygon = try #require(resolver.polygon(for: sectionTriangle(
        first: GeometryPoint3D(x: 0.0, y: 0.0, z: 0.0),
        second: GeometryPoint3D(x: 1.0, y: 0.0, z: 0.0),
        third: GeometryPoint3D(x: 1.0, y: 0.0, z: 1.0)
    )))

    #expect(polygon.points.allSatisfy { $0.x >= 0.5 })
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationSectionIgnoresDivergentCADBodyClassification() {
    let cadVisiblePlan = SectionAnalysisClippingPlan(
        retainedSide: .front,
        bodies: [sectionBody(action: .visible)]
    )
    let hiddenPresentationTriangle = sectionTriangle(
        first: GeometryPoint3D(x: 0.0, y: 0.0, z: 0.0),
        second: GeometryPoint3D(x: 0.25, y: 0.0, z: 0.0),
        third: GeometryPoint3D(x: 0.0, y: 0.0, z: 0.25)
    )
    let visiblePresentationTriangle = sectionTriangle(
        first: GeometryPoint3D(x: 0.75, y: 0.0, z: 0.0),
        second: GeometryPoint3D(x: 1.0, y: 0.0, z: 0.0),
        third: GeometryPoint3D(x: 0.75, y: 0.0, z: 0.25)
    )

    let visibleCADResolver = MeshSourcePresentationSectionGeometryResolver(
        sectionPlan: cadVisiblePlan,
        plane: sectionPlane(originX: 0.5),
        toleranceMeters: 0.0
    )
    let hiddenCADResolver = MeshSourcePresentationSectionGeometryResolver(
        sectionPlan: SectionAnalysisClippingPlan(
            retainedSide: .front,
            bodies: [sectionBody(action: .hidden)]
        ),
        plane: sectionPlane(originX: 0.5),
        toleranceMeters: 0.0
    )

    #expect(visibleCADResolver.polygon(for: hiddenPresentationTriangle) == nil)
    #expect(hiddenCADResolver.polygon(for: visiblePresentationTriangle) != nil)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationSectionGeometryCacheReusesPlaneResolutionUntilIdentityChanges() {
    let sectionPlan = SectionAnalysisClippingPlan(retainedSide: .front, bodies: [])
    let cache = MeshSourcePresentationSectionGeometryCache()
    let sceneSnapshotKey = ViewportSceneSnapshotKey(
        source: .document(id: DocumentID(), generation: DocumentGeneration(1)),
        currentEvaluationGeneration: nil,
        evaluationCacheGeneration: nil,
        workspaceRenderState: ViewportWorkspaceRenderState(
            revision: WorkspaceRevision(),
            ruler: .standard(for: .millimeter)
        ),
        renderInvalidation: RenderInvalidation(),
        sectionClippingPlan: sectionPlan,
        objectDefinitions: []
    )
    let projectID = ProjectID(rawValue: "project.cached-section")
    let firstKey = MeshSourcePresentationSectionGeometryCache.Key(
        presentationSnapshotID: EvaluationSnapshotID(
            projectID: projectID,
            purpose: .presentation,
            sourceRevision: DocumentTransactionRevision(1)
        ),
        sceneSnapshotKey: sceneSnapshotKey,
        plane: sectionPlane(originX: 0.5),
        toleranceMeters: 0.0
    )
    let build = {
        MeshSourcePresentationSectionGeometryResolver(
            sectionPlan: sectionPlan,
            plane: sectionPlane(originX: 0.5),
            toleranceMeters: 0.0
        )
    }

    _ = cache.resolver(for: firstKey, build: build)
    _ = cache.resolver(for: firstKey, build: build)
    #expect(cache.buildCount == 1)

    let secondKey = MeshSourcePresentationSectionGeometryCache.Key(
        presentationSnapshotID: EvaluationSnapshotID(
            projectID: projectID,
            purpose: .presentation,
            sourceRevision: DocumentTransactionRevision(2)
        ),
        sceneSnapshotKey: sceneSnapshotKey,
        plane: sectionPlane(originX: 0.5),
        toleranceMeters: 0.0
    )
    _ = cache.resolver(for: secondKey, build: build)
    #expect(cache.buildCount == 2)
}

private func sectionPlane(originX: Double) -> SectionAnalysisResult.Plane {
    SectionAnalysisResult.Plane(
        sourceKind: .sketchPlane,
        sourceID: nil,
        sourceName: nil,
        origin: Point3D(x: originX, y: 0.0, z: 0.0),
        normal: .unitX,
        u: .unitY,
        v: .unitZ
    )
}

private func sectionBody(
    action: SectionAnalysisClippingPlan.BodyAction
) -> SectionAnalysisClippingPlan.Body {
    SectionAnalysisClippingPlan.Body(
        bodyID: "cad.body",
        name: nil,
        classification: action == .visible ? .inFront : .behind,
        action: action
    )
}

private func sectionTriangle(
    first: GeometryPoint3D,
    second: GeometryPoint3D,
    third: GeometryPoint3D
) -> MeshSourcePresentationTriangle {
    MeshSourcePresentationTriangle(
        occurrenceID: SceneOccurrenceID(rawValue: "occurrence.section"),
        definitionID: ObjectDefinitionID(rawValue: "definition.section"),
        representationID: GeometryRepresentationID(rawValue: "representation.section"),
        sourceReference: .authoredMesh(GeometrySourceID(rawValue: "mesh.section")),
        faceID: MeshFaceID(0),
        firstVertexID: MeshVertexID(0),
        secondVertexID: MeshVertexID(1),
        thirdVertexID: MeshVertexID(2),
        firstPosition: first,
        secondPosition: second,
        thirdPosition: third
    )
}
