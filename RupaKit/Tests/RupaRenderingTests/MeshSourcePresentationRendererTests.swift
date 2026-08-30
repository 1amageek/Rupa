import Foundation
import RupaCoreTypes
import RupaEvaluation
import RupaProjectModel
import RupaViewportScene
import Testing
@testable import RupaRendering
@testable import RupaGeometry

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationRendererConsumesCADOnlyThroughTheConcreteProtocolPath() throws {
    let cadReference = GeometrySourceReference.cad(
        sourceID: "cad.presentation",
        outputID: "cad.output"
    )
    let translation = try translationTransform(x: 10, y: 20, z: 30)
    let (scene, source) = try presentationScene(
        references: [cadReference],
        transforms: [translation]
    )
    let initialTelemetry = scene.copyTelemetry
    let sourceChunkIdentities = sourceChunkIdentitySummary(source)
    let renderer: any MeshSourcePresentationRendering = MeshSourcePresentationRenderer()
    let plan = try renderer.makePlan(for: scene)

    #expect(plan.itemCount == 1)
    #expect(plan.triangleCount == 2)
    var emittedCount = 0
    var cadCount = 0
    var sawTranslatedOrigin = false
    var sawTranslatedOppositeCorner = false
    try renderer.render(plan: plan) { triangle in
        emittedCount += 1
        if triangle.sourceReference == cadReference {
            cadCount += 1
        }
        if triangle.firstPosition == GeometryPoint3D(x: 10, y: 20, z: 30)
            || triangle.secondPosition == GeometryPoint3D(x: 10, y: 20, z: 30)
            || triangle.thirdPosition == GeometryPoint3D(x: 10, y: 20, z: 30) {
            sawTranslatedOrigin = true
        }
        if triangle.firstPosition == GeometryPoint3D(x: 11, y: 21, z: 30)
            || triangle.secondPosition == GeometryPoint3D(x: 11, y: 21, z: 30)
            || triangle.thirdPosition == GeometryPoint3D(x: 11, y: 21, z: 30) {
            sawTranslatedOppositeCorner = true
        }
    }

    #expect(emittedCount == 2)
    #expect(cadCount == 2)
    #expect(sawTranslatedOrigin)
    #expect(sawTranslatedOppositeCorner)
    #expect(scene.copyTelemetry == initialTelemetry)
    #expect(scene.items.allSatisfy { $0.copyTelemetry == GeometryCopyTelemetry() })
    #expect(sourceChunkIdentitySummary(source) == sourceChunkIdentities)
    #expect(sourceChunkIdentitySummary(scene.items[0].mesh) == sourceChunkIdentities)
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationRendererConsumesMeshOnlyThroughTheSameTraversal() throws {
    let sourceReference = GeometrySourceReference.authoredMesh(
        GeometrySourceID(rawValue: "mesh.presentation")
    )
    let (scene, _) = try presentationScene(
        references: [sourceReference],
        transforms: [.identity]
    )
    let renderer: any MeshSourcePresentationRendering = MeshSourcePresentationRenderer()
    let plan = try renderer.makePlan(for: scene)

    var emittedCount = 0
    var meshCount = 0
    var vertexIDSum: UInt64 = 0
    try renderer.render(plan: plan) { triangle in
        emittedCount += 1
        if triangle.sourceReference == sourceReference {
            meshCount += 1
        }
        vertexIDSum += triangle.firstVertexID.rawValue
            + triangle.secondVertexID.rawValue
            + triangle.thirdVertexID.rawValue
    }

    #expect(emittedCount == 2)
    #expect(meshCount == 2)
    #expect(vertexIDSum > 0)
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationRendererUsesGeometryEarClippingForConcaveFaces() throws {
    let source = try presentationConcaveSource()
    let sourceReference = GeometrySourceReference.authoredMesh(source.identity)
    let (scene, _) = try presentationScene(
        source: source,
        references: [sourceReference],
        transforms: [.identity]
    )
    let initialTelemetry = scene.copyTelemetry
    let initialChunkIdentities = sourceChunkIdentitySummary(source)
    let faceID = try #require(source.faceIDs.first)
    let expectedTriangles = try source.triangulate(faceID: faceID)
    let expectedKeys = Set(expectedTriangles.map(triangleKey))
    let renderer = MeshSourcePresentationRenderer()
    let plan = try renderer.makePlan(for: scene)

    var actualKeys: Set<String> = []
    var triangleArea = 0.0
    var emittedCount = 0
    try renderer.render(plan: plan) { triangle in
        emittedCount += 1
        actualKeys.insert(triangleKey(triangle))
        triangleArea += projectedTriangleArea(
            triangle.firstPosition,
            triangle.secondPosition,
            triangle.thirdPosition
        )
    }

    #expect(emittedCount == expectedTriangles.count)
    #expect(actualKeys == expectedKeys)
    #expect(actualKeys.contains(triangleKey(
        first: source.vertexIDs[0],
        second: source.vertexIDs[2],
        third: source.vertexIDs[3]
    )) == false)
    #expect(abs(triangleArea - projectedPolygonArea(source)) < 1e-9)
    #expect(plan.triangleCount == expectedTriangles.count)
    #expect(scene.copyTelemetry == initialTelemetry)
    #expect(sourceChunkIdentitySummary(source) == initialChunkIdentities)
    #expect(sourceChunkIdentitySummary(scene.items[0].mesh) == initialChunkIdentities)

    var secondPassCount = 0
    try renderer.render(plan: plan) { _ in
        secondPassCount += 1
    }
    #expect(secondPassCount == emittedCount)
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationRendererConsumesMixedSelectionsAndReusesSnapshotPlan() throws {
    let meshReference = GeometrySourceReference.authoredMesh(
        GeometrySourceID(rawValue: "mesh.presentation")
    )
    let cadReference = GeometrySourceReference.cad(
        sourceID: "cad.presentation",
        outputID: "cad.output"
    )
    let (scene, source) = try presentationScene(
        references: [cadReference, meshReference],
        transforms: [.identity, try translationTransform(x: -2, y: 0, z: 0)]
    )
    let renderer: any MeshSourcePresentationRendering = MeshSourcePresentationRenderer()
    let plan = try renderer.makePlan(for: scene)
    let initialSourceChunkIdentities = sourceChunkIdentitySummary(source)

    var firstPassCount = 0
    var firstPassCadCount = 0
    var firstPassMeshCount = 0
    var firstPassPositionSum = GeometryPoint3D(x: 0, y: 0, z: 0)
    try renderer.render(plan: plan) { triangle in
        firstPassCount += 1
        firstPassPositionSum.x += triangle.firstPosition.x
        firstPassPositionSum.y += triangle.firstPosition.y
        firstPassPositionSum.z += triangle.firstPosition.z
        if triangle.sourceReference == cadReference {
            firstPassCadCount += 1
        } else if triangle.sourceReference == meshReference {
            firstPassMeshCount += 1
        } else {
            Issue.record("The mixed presentation path emitted an unexpected source reference.")
        }
    }

    var secondPassCount = 0
    var secondPassPositionSum = GeometryPoint3D(x: 0, y: 0, z: 0)
    try renderer.render(plan: plan) { triangle in
        secondPassCount += 1
        secondPassPositionSum.x += triangle.firstPosition.x
        secondPassPositionSum.y += triangle.firstPosition.y
        secondPassPositionSum.z += triangle.firstPosition.z
    }

    #expect(plan.itemCount == 2)
    #expect(plan.triangleCount == 4)
    #expect(firstPassCount == 4)
    #expect(firstPassCadCount == 2)
    #expect(firstPassMeshCount == 2)
    #expect(secondPassCount == firstPassCount)
    #expect(secondPassPositionSum == firstPassPositionSum)
    #expect(sourceChunkIdentitySummary(source) == initialSourceChunkIdentities)
    #expect(scene.items.allSatisfy { $0.copyTelemetry == GeometryCopyTelemetry() })
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationRendererRejectsAuthorityAndBufferFailuresAsTypedErrors() throws {
    let sourceReference = GeometrySourceReference.authoredMesh(
        GeometrySourceID(rawValue: "mesh.presentation")
    )
    let (scene, source) = try presentationScene(
        references: [sourceReference],
        transforms: [.identity]
    )
    let item = scene.items[0]
    let mismatchedItem = UniversalViewportSceneItem(
        id: item.id,
        definitionID: item.definitionID,
        displayName: item.displayName,
        representationID: item.representationID,
        reference: .authoredMesh(GeometrySourceID(rawValue: "mesh.other")),
        mesh: source,
        copyTelemetry: item.copyTelemetry,
        worldTransform: item.worldTransform,
        worldBounds: item.worldBounds
    )
    let mismatchedScene = UniversalViewportScene(
        snapshotID: scene.snapshotID,
        projectID: scene.projectID,
        items: [mismatchedItem],
        copyTelemetry: scene.copyTelemetry
    )
    var authorityError: MeshSourcePresentationRenderError?
    do {
        _ = try MeshSourcePresentationRenderPlan(scene: mismatchedScene)
    } catch let error as MeshSourcePresentationRenderError {
        authorityError = error
    }
    #expect(authorityError?.code == .sourceAuthorityMismatch)

    let malformedSource = try sourceWithMissingCornerVertex(source: source)
    let malformedItem = UniversalViewportSceneItem(
        id: item.id,
        definitionID: item.definitionID,
        displayName: item.displayName,
        representationID: item.representationID,
        reference: sourceReference,
        mesh: malformedSource,
        worldTransform: item.worldTransform,
        worldBounds: item.worldBounds
    )
    let malformedScene = UniversalViewportScene(
        snapshotID: scene.snapshotID,
        projectID: scene.projectID,
        items: [malformedItem],
        copyTelemetry: scene.copyTelemetry
    )
    var vertexError: MeshSourcePresentationRenderError?
    do {
        _ = try MeshSourcePresentationRenderPlan(scene: malformedScene)
    } catch let error as MeshSourcePresentationRenderError {
        vertexError = error
    }
    #expect(vertexError?.code == .invalidVertexReference)
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationRendererMapsGeometryTriangulationFailures() throws {
    let nonPlanarSource = try presentationNonPlanarSource()
    let nonPlanarReference = GeometrySourceReference.authoredMesh(nonPlanarSource.identity)
    let nonPlanarScene = try presentationScene(
        source: nonPlanarSource,
        references: [nonPlanarReference],
        transforms: [.identity]
    ).scene
    var nonPlanarError: MeshSourcePresentationRenderError?
    do {
        _ = try MeshSourcePresentationRenderPlan(scene: nonPlanarScene)
    } catch let error as MeshSourcePresentationRenderError {
        nonPlanarError = error
    }
    #expect(nonPlanarError?.code == .nonPlanar)

    let degenerateSource = try presentationDegenerateSource()
    let degenerateReference = GeometrySourceReference.authoredMesh(degenerateSource.identity)
    let degenerateScene = try presentationScene(
        source: degenerateSource,
        references: [degenerateReference],
        transforms: [.identity]
    ).scene
    var degenerateError: MeshSourcePresentationRenderError?
    do {
        _ = try MeshSourcePresentationRenderPlan(scene: degenerateScene)
    } catch let error as MeshSourcePresentationRenderError {
        degenerateError = error
    }
    #expect(degenerateError?.code == .degenerate)
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationRendererMapsFaceRangeArithmeticOverflow() throws {
    let (scene, source) = try presentationScene(
        references: [.authoredMesh(GeometrySourceID(rawValue: "mesh.presentation"))],
        transforms: [.identity]
    )
    let malformedSource = try sourceWithFaceCornerRange(
        source: source,
        range: MeshIndexRange(start: Int.max, count: 3)
    )
    let item = scene.items[0]
    let malformedItem = UniversalViewportSceneItem(
        id: item.id,
        definitionID: item.definitionID,
        displayName: item.displayName,
        representationID: item.representationID,
        reference: item.sourceReference,
        mesh: malformedSource,
        worldTransform: item.worldTransform,
        worldBounds: item.worldBounds
    )
    let malformedScene = UniversalViewportScene(
        snapshotID: scene.snapshotID,
        projectID: scene.projectID,
        items: [malformedItem],
        copyTelemetry: scene.copyTelemetry
    )
    var error: MeshSourcePresentationRenderError?

    do {
        _ = try MeshSourcePresentationRenderPlan(scene: malformedScene)
    } catch let caught as MeshSourcePresentationRenderError {
        error = caught
    }

    #expect(error?.code == .sizeOverflow)
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationRendererReportsTransformFailureDuringConsumption() throws {
    let sourceReference = GeometrySourceReference.authoredMesh(
        GeometrySourceID(rawValue: "mesh.presentation")
    )
    let (scene, source) = try presentationScene(
        references: [sourceReference],
        transforms: [.identity]
    )
    let item = scene.items[0]
    let pointAtInfinityTransform = try GeometryTransform3D(values: [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 0,
    ])
    let invalidTransformItem = UniversalViewportSceneItem(
        id: item.id,
        definitionID: item.definitionID,
        displayName: item.displayName,
        representationID: item.representationID,
        reference: sourceReference,
        mesh: source,
        worldTransform: pointAtInfinityTransform,
        worldBounds: item.worldBounds
    )
    let invalidTransformScene = UniversalViewportScene(
        snapshotID: scene.snapshotID,
        projectID: scene.projectID,
        items: [invalidTransformItem],
        copyTelemetry: scene.copyTelemetry
    )
    let renderer = MeshSourcePresentationRenderer()
    let plan = try renderer.makePlan(for: invalidTransformScene)

    var error: MeshSourcePresentationRenderError?
    do {
        try renderer.render(plan: plan) { _ in }
    } catch let caught as MeshSourcePresentationRenderError {
        error = caught
    }
    #expect(error?.code == .transformFailure)
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationRenderPlanUsesBoundedSourceOrderForHighSegmentCylinder() throws {
    let segmentCount = 6_284
    let source = try presentationHighSegmentCylinderSource(segmentCount: segmentCount)
    let sourceReference = GeometrySourceReference.authoredMesh(source.identity)
    let scene = try presentationScene(
        source: source,
        references: [sourceReference],
        transforms: [.identity]
    ).scene
    let initialChunkIdentities = sourceChunkIdentitySummary(source)
    let start = Date()
    let renderer = MeshSourcePresentationRenderer()
    let plan = try renderer.makePlan(for: scene)
    let elapsed = Date().timeIntervalSince(start)

    #expect(elapsed < 2.0)
    #expect(plan.itemCount == 1)
    #expect(plan.triangleCount == 4 * segmentCount - 4)
    #expect(plan.telemetry.faceVisits == segmentCount + 2)
    #expect(plan.telemetry.cornerVisits == 6 * segmentCount)
    #expect(plan.telemetry.indexedVertexLookups == 6 * segmentCount)
    #expect(plan.telemetry.positionReads == 6 * segmentCount)
    #expect(plan.telemetry.scratchPositionValues == 6 * segmentCount)
    #expect(plan.telemetry.nonConvexWorkUnits == 0)
    #expect(plan.telemetry.globalIdentifierScans == 0)
    #expect(plan.telemetry.sourcePositionMaterializations == 0)
    #expect(sourceChunkIdentitySummary(scene.items[0].mesh) == initialChunkIdentities)
    #expect(scene.items[0].copyTelemetry == GeometryCopyTelemetry())

    var emittedCount = 0
    try renderer.render(plan: plan) { triangle in
        emittedCount += 1
        #expect(triangle.sourceReference == sourceReference)
    }
    #expect(emittedCount == 4 * segmentCount - 4)
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationRenderPlanReportsConcaveBudgetFailureWithoutPartialPlan() throws {
    let source = try presentationConcaveSource()
    let sourceReference = GeometrySourceReference.authoredMesh(source.identity)
    let scene = try presentationScene(
        source: source,
        references: [sourceReference],
        transforms: [.identity]
    ).scene

    var error: MeshSourcePresentationRenderError?
    do {
        _ = try MeshSourcePresentationRenderPlan(
            scene: scene,
            limits: MeshTriangulationLimits(
                maxFaceCornerCount: 16_384,
                maxNonConvexWorkUnits: 0
            )
        )
    } catch let caught as MeshSourcePresentationRenderError {
        error = caught
    }

    #expect(error?.code == .budgetExceeded)
}

private func presentationHighSegmentCylinderSource(segmentCount: Int) throws -> MeshSource {
    let radius = 0.035
    let length = 0.45
    let centerX = 10.0
    let centerY = -7.0
    var builder = MeshSourceBuilder(identity: "mesh.presentation-high-segment-cylinder")
    try builder.reserveCapacity(
        vertexCount: 2 * segmentCount,
        faceCount: segmentCount + 2,
        cornerCount: 6 * segmentCount
    )
    var bottomVertices: [MeshVertexID] = []
    bottomVertices.reserveCapacity(segmentCount)
    var topVertices: [MeshVertexID] = []
    topVertices.reserveCapacity(segmentCount)
    for index in 0..<segmentCount {
        let angle = 2.0 * Double.pi * Double(index) / Double(segmentCount)
        let x = centerX + radius * cos(angle)
        let y = centerY + radius * sin(angle)
        bottomVertices.append(
            try builder.addVertex(
                GeometryPoint3D(
                    x: x,
                    y: y,
                    z: 0
                )
            )
        )
        topVertices.append(
            try builder.addVertex(
                GeometryPoint3D(
                    x: x,
                    y: y,
                    z: length
                )
            )
        )
    }
    _ = try builder.addFace(vertexIDs: bottomVertices.reversed())
    _ = try builder.addFace(vertexIDs: topVertices)
    for index in 0..<segmentCount {
        let nextIndex = (index + 1) % segmentCount
        _ = try builder.addFace(vertexIDs: [
            bottomVertices[index],
            bottomVertices[nextIndex],
            topVertices[nextIndex],
            topVertices[index],
        ])
    }
    return try builder.build()
}

private func presentationScene(
    source providedSource: MeshSource? = nil,
    references: [GeometrySourceReference],
    transforms: [GeometryTransform3D]
) throws -> (scene: UniversalViewportScene, source: MeshSource) {
    guard references.count == transforms.count, references.isEmpty == false else {
        throw MeshSourcePresentationRenderError(
            code: .invalidSceneItem,
            message: "Presentation test scenes require one transform per source reference."
        )
    }
    let source: MeshSource
    if let providedSource {
        source = providedSource
    } else {
        source = try presentationQuadSource()
    }
    let projectID = ProjectID(rawValue: "project.presentation-render")
    var objectDefinitions: [ObjectDefinitionID: ObjectDefinition] = [:]
    var occurrences: [SceneOccurrenceID: SceneOccurrence] = [:]
    var evaluatedOccurrences: [SceneOccurrenceID: EvaluatedOccurrenceSnapshot] = [:]
    var authoredMeshAssets: [GeometrySourceID: AuthoredMeshAsset] = [:]
    var rootOccurrenceIDs: [SceneOccurrenceID] = []

    for index in references.indices {
        let definitionID = ObjectDefinitionID(rawValue: "object.presentation-render.\(index)")
        let representationID = GeometryRepresentationID(rawValue: "representation.presentation-render.\(index)")
        let occurrenceID = SceneOccurrenceID(rawValue: "occurrence.presentation-render.\(index)")
        let reference = references[index]
        objectDefinitions[definitionID] = ObjectDefinition(
            id: definitionID,
            name: "Presentation \(index)",
            representations: presentationRepresentations(
                id: representationID,
                reference: reference
            )
        )
        occurrences[occurrenceID] = SceneOccurrence(
            id: occurrenceID,
            definitionID: definitionID
        )
        let transform = transforms[index]
        evaluatedOccurrences[occurrenceID] = EvaluatedOccurrenceSnapshot(
            occurrenceID: occurrenceID,
            definitionID: definitionID,
            representationID: representationID,
            reference: reference,
            mesh: source,
            worldTransform: transform,
            worldBounds: try source.bounds().transformed(by: transform)
        )
        rootOccurrenceIDs.append(occurrenceID)
        if case .authoredMesh(let sourceID) = reference {
            authoredMeshAssets[sourceID] = try AuthoredMeshAsset(
                source: source,
                provenance: .created
            )
        }
    }

    let project = try ProjectSourceModel(
        id: projectID,
        name: "Presentation rendering",
        authoredMeshAssets: authoredMeshAssets,
        objectDefinitions: objectDefinitions,
        occurrences: occurrences,
        rootOccurrenceIDs: rootOccurrenceIDs
    )
    let snapshot = EvaluatedProjectSnapshot(
        id: EvaluationSnapshotID(
            projectID: projectID,
            purpose: .presentation,
            sourceRevision: DocumentTransactionRevision()
        ),
        projectID: projectID,
        occurrences: evaluatedOccurrences,
        copyTelemetry: GeometryCopyTelemetry()
    )
    return (
        try UniversalViewportSceneBuilder().build(from: snapshot, project: project),
        source
    )
}

private func presentationQuadSource() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: GeometrySourceID(rawValue: "mesh.presentation"))
    try builder.reserveCapacity(vertexCount: 4, faceCount: 1, cornerCount: 4)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 1, y: 1, z: 0))
    let fourth = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [first, second, third, fourth])
    return try builder.build()
}

private func presentationConcaveSource() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: GeometrySourceID(rawValue: "mesh.concave"))
    let points = [
        GeometryPoint3D(x: 0, y: 0, z: 0),
        GeometryPoint3D(x: 3, y: 0, z: 0),
        GeometryPoint3D(x: 3, y: 3, z: 0),
        GeometryPoint3D(x: 1, y: 1, z: 0),
        GeometryPoint3D(x: 0, y: 3, z: 0),
    ]
    try builder.reserveCapacity(vertexCount: points.count, faceCount: 1, cornerCount: points.count)
    let vertices = try points.map { try builder.addVertex($0) }
    _ = try builder.addFace(vertexIDs: vertices)
    return try builder.build()
}

private func presentationNonPlanarSource() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: GeometrySourceID(rawValue: "mesh.nonplanar"))
    let points = [
        GeometryPoint3D(x: 0, y: 0, z: 0),
        GeometryPoint3D(x: 1, y: 0, z: 0),
        GeometryPoint3D(x: 2, y: 1, z: 0.25),
        GeometryPoint3D(x: 0, y: 1, z: 0),
    ]
    try builder.reserveCapacity(vertexCount: points.count, faceCount: 1, cornerCount: points.count)
    let vertices = try points.map { try builder.addVertex($0) }
    _ = try builder.addFace(vertexIDs: vertices)
    return try builder.build()
}

private func presentationDegenerateSource() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: GeometrySourceID(rawValue: "mesh.degenerate"))
    let points = [
        GeometryPoint3D(x: 0, y: 0, z: 0),
        GeometryPoint3D(x: 1, y: 0, z: 0),
        GeometryPoint3D(x: 2, y: 0, z: 0),
        GeometryPoint3D(x: 3, y: 0, z: 0),
    ]
    try builder.reserveCapacity(vertexCount: points.count, faceCount: 1, cornerCount: points.count)
    let vertices = try points.map { try builder.addVertex($0) }
    _ = try builder.addFace(vertexIDs: vertices)
    return try builder.build()
}

private func presentationRepresentations(
    id: GeometryRepresentationID,
    reference: GeometrySourceReference
) -> GeometryRepresentationSet {
    GeometryRepresentationSet(
        representations: [id: GeometryRepresentation(id: id, source: reference)],
        selection: GeometryRepresentationSelection(modeling: id, presentation: id)
    )
}

private func translationTransform(x: Double, y: Double, z: Double) throws -> GeometryTransform3D {
    try GeometryTransform3D(values: [
        1, 0, 0, x,
        0, 1, 0, y,
        0, 0, 1, z,
        0, 0, 0, 1,
    ])
}

private func sourceWithMissingCornerVertex(source: MeshSource) throws -> MeshSource {
    let encoded = try JSONEncoder().encode(source)
    guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
        throw MeshSourcePresentationRenderError(
            code: .invalidVertexReference,
            message: "Presentation test source did not encode as an object."
        )
    }
    object["cornerVertexIDs"] = [
        ["rawValue": 0],
        ["rawValue": 1],
        ["rawValue": 2],
        ["rawValue": 99],
    ]
    let malformedData = try JSONSerialization.data(withJSONObject: object)
    return try JSONDecoder().decode(MeshSource.self, from: malformedData)
}

private func sourceWithFaceCornerRange(
    source: MeshSource,
    range: MeshIndexRange
) throws -> MeshSource {
    let encoded = try JSONEncoder().encode(source)
    guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any],
          var ranges = object["faceCornerRanges"] as? [[String: Any]],
          !ranges.isEmpty else {
        throw MeshSourcePresentationRenderError(
            code: .invalidFaceRange,
            message: "Presentation test source did not encode a face range."
        )
    }
    ranges[0] = ["start": range.start, "count": range.count]
    object["faceCornerRanges"] = ranges
    let malformedData = try JSONSerialization.data(withJSONObject: object)
    return try JSONDecoder().decode(MeshSource.self, from: malformedData)
}

private func triangleKey(_ triangle: MeshSourcePresentationTriangle) -> String {
    triangleKey(
        first: triangle.firstVertexID,
        second: triangle.secondVertexID,
        third: triangle.thirdVertexID
    )
}

private func triangleKey(_ triangle: MeshTriangle) -> String {
    triangleKey(
        first: triangle.vertexIDs.0,
        second: triangle.vertexIDs.1,
        third: triangle.vertexIDs.2
    )
}

private func triangleKey(
    first: MeshVertexID,
    second: MeshVertexID,
    third: MeshVertexID
) -> String {
    "\(first.rawValue),\(second.rawValue),\(third.rawValue)"
}

private func projectedTriangleArea(
    _ first: GeometryPoint3D,
    _ second: GeometryPoint3D,
    _ third: GeometryPoint3D
) -> Double {
    abs(
        (second.x - first.x) * (third.y - first.y)
            - (second.y - first.y) * (third.x - first.x)
    ) / 2
}

private func projectedPolygonArea(_ source: MeshSource) -> Double {
    var area = 0.0
    for index in source.vertexPositions.indices {
        let current = source.vertexPositions[index]
        let next = source.vertexPositions[(index + 1) % source.vertexPositions.count]
        area += current.x * next.y - next.x * current.y
    }
    return abs(area) / 2
}

private func sourceChunkIdentitySummary(_ source: MeshSource) -> [[ObjectIdentifier]] {
    [
        source.vertexIDs.storage.chunkIdentities,
        source.vertexPositions.storage.chunkIdentities,
        source.edgeIDs.storage.chunkIdentities,
        source.edgeEndpoints.storage.chunkIdentities,
        source.faceIDs.storage.chunkIdentities,
        source.faceCornerRanges.storage.chunkIdentities,
        source.cornerIDs.storage.chunkIdentities,
        source.cornerVertexIDs.storage.chunkIdentities,
        source.cornerEdgeIDs.storage.chunkIdentities,
    ]
}
