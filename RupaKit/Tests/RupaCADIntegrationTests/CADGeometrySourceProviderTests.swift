import Foundation
import RupaCore
import RupaCADIntegration
import RupaEvaluation
import RupaProjectModel
import Synchronization
import SwiftCAD
import Testing

@Test(.timeLimit(.minutes(1)))
func cadProviderRejectsNonCADReferencesBeforeEvaluation() throws {
    let provider = CADGeometrySourceProvider(
        document: CADDocument(units: .meters),
        configuration: CADGeometryEvaluationConfiguration(
            tolerance: DocumentModelingSettings.standard.tolerance
        )
    )
    var error: CADIntegrationError?

    do {
        _ = try provider.evaluate(
            try GeometrySourceEvaluationRequest(
                references: [.authoredMesh("mesh.source")],
                sourceRevision: .init()
            ),
            in: try ProjectSourceModel(id: "project", name: "Project")
        )
    } catch let caught as CADIntegrationError {
        error = caught
    }

    #expect(error?.code == .unsupportedReference)
}

@Test(.timeLimit(.minutes(1)))
func cadProviderRejectsReferencesForAnotherDocument() throws {
    let document = CADDocument(units: .meters)
    let provider = CADGeometrySourceProvider(
        document: document,
        configuration: CADGeometryEvaluationConfiguration(
            tolerance: DocumentModelingSettings.standard.tolerance
        )
    )
    var error: CADIntegrationError?

    do {
        _ = try provider.evaluate(
            try GeometrySourceEvaluationRequest(
                references: [
                    .external(
                        providerID: CADGeometrySourceProvider.identifier,
                        sourceID: "another-document",
                        outputID: UUID().uuidString
                    ),
                ],
                sourceRevision: .init()
            ),
            in: try ProjectSourceModel(id: "project", name: "Project")
        )
    } catch let caught as CADIntegrationError {
        error = caught
    }

    #expect(error?.code == .sourceUnavailable)
}

@Test(.timeLimit(.minutes(1)))
func cadProviderTranslatesForeignResolverFailuresAtItsBoundary() throws {
    let provider = CADGeometrySourceProvider(
        resolver: FailingCADGeometrySourceResolver()
    )
    let reference = GeometrySourceReference.external(
        providerID: CADGeometrySourceProvider.identifier,
        sourceID: UUID().uuidString,
        outputID: UUID().uuidString
    )
    var error: CADIntegrationError?

    do {
        _ = try provider.evaluate(
            try GeometrySourceEvaluationRequest(
                references: [reference],
                sourceRevision: .init()
            ),
            in: try ProjectSourceModel(id: "project", name: "Project")
        )
    } catch let caught as CADIntegrationError {
        error = caught
    }

    #expect(error?.code == .sourceUnavailable)
}

@Test(.timeLimit(.minutes(1)))
func cadProviderConvertsEvaluatedBodyMeshIntoUniversalGeometrySource() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let evaluator = DocumentEvaluator(
        tolerance: session.document.modelingSettings.tolerance
    )
    let evaluatedDocument = try evaluator.evaluate(session.document.cadDocument)
    let bodyID = try #require(evaluatedDocument.meshes.keys.first)
    let provider = CADGeometrySourceProvider(
        document: session.document.cadDocument,
        configuration: CADGeometryEvaluationConfiguration(
            tolerance: session.document.modelingSettings.tolerance
        )
    )
    let project = try ProjectSourceModel(id: "project.cad", name: "CAD")
    let reference = GeometrySourceReference.external(
        providerID: CADGeometrySourceProvider.identifier,
        sourceID: session.document.cadDocument.id.description,
        outputID: bodyID.description
    )

    let results = try provider.evaluate(
        try GeometrySourceEvaluationRequest(
            references: [reference],
            sourceRevision: .init()
        ),
        in: project
    )
    let result = try #require(results[reference])

    #expect(result.mesh.vertexIDs.count > 0)
    #expect(result.mesh.faceIDs.count > 0)
    #expect(result.mesh.attributes.layer(for: "cad.normal") != nil)
    #expect(result.localBounds.maximum.x > result.localBounds.minimum.x)
}

@Test(.timeLimit(.minutes(1)))
func cadProviderEvaluatesTheDocumentOnceForAnEntireReferenceBatch() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let baseEvaluator = DocumentEvaluator(
        tolerance: session.document.modelingSettings.tolerance
    )
    let evaluatedDocument = try baseEvaluator.evaluate(session.document.cadDocument)
    let bodyID = try #require(evaluatedDocument.meshes.keys.first)
    let featureID = try #require(
        evaluatedDocument.subshapes.entries.compactMap { entry -> FeatureID? in
            let (subshapeID, reference) = entry
            guard case .body(let candidateBodyID) = reference,
                  candidateBodyID == bodyID else {
                return nil
            }
            return subshapeID.featureID
        }.first
    )
    let evaluator = RecordingCADDocumentEvaluator(result: evaluatedDocument)
    let provider = CADGeometrySourceProvider(
        document: session.document.cadDocument,
        evaluator: evaluator
    )
    let bodyReference = GeometrySourceReference.external(
        providerID: CADGeometrySourceProvider.identifier,
        sourceID: session.document.cadDocument.id.description,
        outputID: bodyID.description
    )
    let featureReference = GeometrySourceReference.external(
        providerID: CADGeometrySourceProvider.identifier,
        sourceID: session.document.cadDocument.id.description,
        outputID: featureID.description
    )

    let results = try provider.evaluate(
        try GeometrySourceEvaluationRequest(
            references: [bodyReference, featureReference],
            sourceRevision: .init()
        ),
        in: try ProjectSourceModel(id: "project.cad-batch", name: "CAD Batch")
    )

    #expect(results.count == 2)
    #expect(results[bodyReference]?.mesh.identity == results[featureReference]?.mesh.identity)
    #expect(evaluator.evaluationCount() == 1)
}

@Test(.timeLimit(.minutes(1)))
func cadProviderResolvesMultipleDocumentsInOneSourceTransaction() throws {
    let first = try makeCADProviderFixture()
    let second = try makeCADProviderFixture()
    let firstEvaluator = RecordingCADDocumentEvaluator(result: first.evaluatedDocument)
    let secondEvaluator = RecordingCADDocumentEvaluator(result: second.evaluatedDocument)
    let provider = try CADGeometrySourceProvider(
        sources: [
            CADGeometryEvaluationSource(
                document: first.document,
                evaluator: firstEvaluator
            ),
            CADGeometryEvaluationSource(
                document: second.document,
                evaluator: secondEvaluator
            ),
        ]
    )

    let results = try provider.evaluate(
        try GeometrySourceEvaluationRequest(
            references: [first.reference, second.reference],
            sourceRevision: DocumentTransactionRevision(1)
        ),
        in: first.project
    )

    #expect(results.count == 2)
    #expect(results[first.reference] != nil)
    #expect(results[second.reference] != nil)
    #expect(results[first.reference]?.mesh.identity != results[second.reference]?.mesh.identity)
    #expect(firstEvaluator.evaluationCount() == 1)
    #expect(secondEvaluator.evaluationCount() == 1)
}

@Test(.timeLimit(.minutes(1)))
func cadProviderRejectsInvalidMeshInsteadOfDroppingMalformedAttributes() throws {
    let fixture = try makeCADProviderFixture()
    let bodyID = try #require(fixture.evaluatedDocument.meshes.keys.first)
    let invalidEvaluation = try replacingMesh(
        bodyID: bodyID,
        in: fixture.evaluatedDocument
    ) { mesh in
        mesh.normals = [Vector3D(x: 1.0, y: 0.0, z: 0.0)]
    }
    let provider = CADGeometrySourceProvider(
        document: fixture.document,
        evaluator: RecordingCADDocumentEvaluator(result: invalidEvaluation)
    )

    var error: CADIntegrationError?
    do {
        _ = try provider.evaluate(
            try GeometrySourceEvaluationRequest(
                references: [fixture.reference],
                sourceRevision: DocumentTransactionRevision(2)
            ),
            in: fixture.project
        )
    } catch let caught as CADIntegrationError {
        error = caught
    }

    #expect(error?.code == .invalidMesh)
}

@Test(.timeLimit(.minutes(1)))
func cadProviderPreservesVertexColors() throws {
    let fixture = try makeCADProviderFixture()
    let bodyID = try #require(fixture.evaluatedDocument.meshes.keys.first)
    let coloredEvaluation = try replacingMesh(
        bodyID: bodyID,
        in: fixture.evaluatedDocument
    ) { mesh in
        mesh.vertexColors = Array(
            repeating: ColorRGBA(r: 0.2, g: 0.4, b: 0.6, a: 0.8),
            count: mesh.positions.count
        )
    }
    let provider = CADGeometrySourceProvider(
        document: fixture.document,
        evaluator: RecordingCADDocumentEvaluator(result: coloredEvaluation)
    )

    let results = try provider.evaluate(
        try GeometrySourceEvaluationRequest(
            references: [fixture.reference],
            sourceRevision: DocumentTransactionRevision(3)
        ),
        in: fixture.project
    )
    let colorLayer = try #require(
        results[fixture.reference]?.mesh.attributes.layer(for: "cad.color")
    )
    let coloredMesh = try #require(coloredEvaluation.meshes[bodyID])

    #expect(colorLayer.descriptor.valueType == .vector4)
    #expect(colorLayer.values.count == coloredMesh.positions.count)
}

@Test(.timeLimit(.minutes(1)))
func cadProviderRejectsMaterialLossUntilUniversalMaterialsAreRepresentable() throws {
    let fixture = try makeCADProviderFixture()
    let bodyID = try #require(fixture.evaluatedDocument.meshes.keys.first)
    let materialEvaluation = try replacingMesh(
        bodyID: bodyID,
        in: fixture.evaluatedDocument
    ) { mesh in
        mesh.material = MaterialID()
    }
    let provider = CADGeometrySourceProvider(
        document: fixture.document,
        evaluator: RecordingCADDocumentEvaluator(result: materialEvaluation)
    )

    var error: CADIntegrationError?
    do {
        _ = try provider.evaluate(
            try GeometrySourceEvaluationRequest(
                references: [fixture.reference],
                sourceRevision: DocumentTransactionRevision(4)
            ),
            in: fixture.project
        )
    } catch let caught as CADIntegrationError {
        error = caught
    }

    #expect(error?.code == .unsupportedFidelity)
}

@Test(.timeLimit(.minutes(1)))
func cadProviderDoesNotPublishPartialCacheStateWhenAnotherSourceFails() throws {
    let first = try makeCADProviderFixture()
    let second = try makeCADProviderFixture()
    let secondBodyID = try #require(second.evaluatedDocument.meshes.keys.first)
    let invalidSecondEvaluation = try replacingMesh(
        bodyID: secondBodyID,
        in: second.evaluatedDocument
    ) { mesh in
        mesh.textureCoordinates = [Point2D(x: 0.0, y: 0.0)]
    }
    let cache = CADDocumentEvaluationCache()
    let firstEvaluator = RecordingCADDocumentEvaluator(result: first.evaluatedDocument)
    let provider = try CADGeometrySourceProvider(
        sources: [
            CADGeometryEvaluationSource(
                document: first.document,
                evaluator: firstEvaluator
            ),
            CADGeometryEvaluationSource(
                document: second.document,
                evaluator: RecordingCADDocumentEvaluator(result: invalidSecondEvaluation)
            ),
        ],
        cache: cache
    )
    let revision = DocumentTransactionRevision(5)

    #expect(throws: CADIntegrationError.self) {
        _ = try provider.evaluate(
            try GeometrySourceEvaluationRequest(
                references: [first.reference, second.reference],
                sourceRevision: revision
            ),
            in: first.project
        )
    }
    let probeEvaluator = RecordingCADDocumentEvaluator(result: first.evaluatedDocument)
    let probeProvider = CADGeometrySourceProvider(
        document: first.document,
        evaluator: probeEvaluator,
        cache: cache
    )
    _ = try probeProvider.evaluate(
        try GeometrySourceEvaluationRequest(
            references: [first.reference],
            sourceRevision: revision
        ),
        in: first.project
    )

    #expect(firstEvaluator.evaluationCount() == 1)
    #expect(probeEvaluator.evaluationCount() == 1)
}

@Test(.timeLimit(.minutes(1)))
func cadProviderParticipatesInProjectEvaluationThroughProviderBoundary() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let evaluator = DocumentEvaluator(
        tolerance: session.document.modelingSettings.tolerance
    )
    let evaluatedDocument = try evaluator.evaluate(session.document.cadDocument)
    let bodyID = try #require(evaluatedDocument.meshes.keys.first)
    let definition = ObjectDefinition(
        id: "cad.definition",
        name: "CAD Body",
        geometry: .external(
            providerID: CADGeometrySourceProvider.identifier,
            sourceID: session.document.cadDocument.id.description,
            outputID: bodyID.description
        )
    )
    let occurrence = SceneOccurrence(id: "cad.occurrence", definitionID: definition.id)
    let project = try ProjectSourceModel(
        id: "project.cad-evaluation",
        name: "CAD Evaluation",
        objectDefinitions: [definition.id: definition],
        occurrences: [occurrence.id: occurrence],
        rootOccurrenceIDs: [occurrence.id]
    )
    let registry = try GeometrySourceEvaluationProviderRegistry(
        providers: [
            CADGeometrySourceProvider(
                document: session.document.cadDocument,
                configuration: CADGeometryEvaluationConfiguration(
                    tolerance: session.document.modelingSettings.tolerance
                )
            ),
        ]
    )
    let engine = ProjectEvaluationEngine(registry: registry)

    let snapshot = try engine.evaluate(project)
    #expect(snapshot.occurrences[occurrence.id]?.mesh.faceIDs.count ?? 0 > 0)
}

@Test(.timeLimit(.minutes(1)))
func cadProviderReturnsAnExactCachedRevisionWithoutReevaluating() throws {
    let fixture = try makeCADProviderFixture()
    let evaluator = RecordingCADDocumentEvaluator(result: fixture.evaluatedDocument)
    let cache = CADDocumentEvaluationCache()
    let firstProvider = CADGeometrySourceProvider(
        document: fixture.document,
        evaluator: evaluator,
        cache: cache
    )
    let secondProvider = CADGeometrySourceProvider(
        document: fixture.document,
        evaluator: evaluator,
        cache: cache
    )
    let request = try GeometrySourceEvaluationRequest(
        references: [fixture.reference],
        sourceRevision: DocumentTransactionRevision(3)
    )

    _ = try firstProvider.evaluate(request, in: fixture.project)
    _ = try secondProvider.evaluate(request, in: fixture.project)

    #expect(evaluator.evaluationCount() == 1)
    #expect(evaluator.reusedEvaluationCount() == 0)
}

@Test(.timeLimit(.minutes(1)))
func cadProviderCarriesThePreviousEvaluationIntoTheNextSourceRevision() throws {
    let fixture = try makeCADProviderFixture()
    let evaluator = RecordingCADDocumentEvaluator(result: fixture.evaluatedDocument)
    let cache = CADDocumentEvaluationCache()
    let firstProvider = CADGeometrySourceProvider(
        document: fixture.document,
        evaluator: evaluator,
        cache: cache
    )
    let secondProvider = CADGeometrySourceProvider(
        document: fixture.document,
        evaluator: evaluator,
        cache: cache
    )

    _ = try firstProvider.evaluate(
        try GeometrySourceEvaluationRequest(
            references: [fixture.reference],
            sourceRevision: DocumentTransactionRevision(8)
        ),
        in: fixture.project
    )
    _ = try secondProvider.evaluate(
        try GeometrySourceEvaluationRequest(
            references: [fixture.reference],
            sourceRevision: DocumentTransactionRevision(9)
        ),
        in: fixture.project
    )

    #expect(evaluator.evaluationCount() == 2)
    #expect(evaluator.reusedEvaluationCount() == 1)
}

@Test(.timeLimit(.minutes(1)))
func cadProviderUsesASeededCurrentEvaluationWithoutReevaluating() throws {
    let fixture = try makeCADProviderFixture()
    let configuration = CADGeometryEvaluationConfiguration(
        tolerance: DocumentModelingSettings.standard.tolerance
    )
    let evaluator = RecordingCADDocumentEvaluator(
        result: fixture.evaluatedDocument,
        configuration: configuration
    )
    let cache = CADDocumentEvaluationCache()
    let revision = DocumentTransactionRevision(10)
    try cache.seed(
        validatedDocument: ValidatedCADDocument(
            fixture.document,
            tolerance: configuration.tolerance
        ),
        evaluatedDocument: fixture.evaluatedDocument,
        sourceRevision: revision,
        configuration: configuration
    )
    let provider = CADGeometrySourceProvider(
        document: fixture.document,
        evaluator: evaluator,
        cache: cache
    )

    _ = try provider.evaluate(
        try GeometrySourceEvaluationRequest(
            references: [fixture.reference],
            sourceRevision: revision
        ),
        in: fixture.project
    )

    #expect(evaluator.evaluationCount() == 0)
}

@Test(.timeLimit(.minutes(1)))
func cadProviderRejectsDifferentSourceContentAtTheSameRevision() throws {
    let fixture = try makeCADProviderFixture()
    let evaluator = RecordingCADDocumentEvaluator(result: fixture.evaluatedDocument)
    let cache = CADDocumentEvaluationCache()
    let initialProvider = CADGeometrySourceProvider(
        document: fixture.document,
        evaluator: evaluator,
        cache: cache
    )
    let request = try GeometrySourceEvaluationRequest(
        references: [fixture.reference],
        sourceRevision: DocumentTransactionRevision(12)
    )
    _ = try initialProvider.evaluate(request, in: fixture.project)

    var conflictingDocument = fixture.document
    conflictingDocument.units = .millimeters
    let conflictingProvider = CADGeometrySourceProvider(
        document: conflictingDocument,
        evaluator: evaluator,
        cache: cache
    )
    var error: CADIntegrationError?
    do {
        _ = try conflictingProvider.evaluate(request, in: fixture.project)
    } catch let caught as CADIntegrationError {
        error = caught
    }

    #expect(error?.code == .sourceRevisionConflict)
    #expect(evaluator.evaluationCount() == 1)
}

@Test(.timeLimit(.minutes(1)))
func cadProviderRejectsInvalidEvaluationConfigurationBeforeEvaluation() throws {
    let fixture = try makeCADProviderFixture()
    let invalidConfiguration = CADGeometryEvaluationConfiguration(
        tolerance: ModelingTolerance(
            distance: -1.0,
            angle: DocumentModelingSettings.standard.tolerance.angle
        )
    )
    let evaluator = RecordingCADDocumentEvaluator(
        result: fixture.evaluatedDocument,
        configuration: invalidConfiguration
    )
    let provider = CADGeometrySourceProvider(
        document: fixture.document,
        evaluator: evaluator
    )
    var error: CADIntegrationError?
    do {
        _ = try provider.evaluate(
            try GeometrySourceEvaluationRequest(
                references: [fixture.reference],
                sourceRevision: DocumentTransactionRevision(15)
            ),
            in: fixture.project
        )
    } catch let caught as CADIntegrationError {
        error = caught
    }

    #expect(error?.code == .invalidConfiguration)
    #expect(evaluator.evaluationCount() == 0)
}

@Test(.timeLimit(.minutes(1)))
func cadProviderRejectsAnEvaluationForDifferentSourceContent() throws {
    let fixture = try makeCADProviderFixture()
    var differentDocument = fixture.document
    differentDocument.units = .millimeters
    let evaluator = RecordingCADDocumentEvaluator(result: fixture.evaluatedDocument)
    let provider = CADGeometrySourceProvider(
        document: differentDocument,
        evaluator: evaluator
    )
    var error: CADIntegrationError?
    do {
        _ = try provider.evaluate(
            try GeometrySourceEvaluationRequest(
                references: [fixture.reference],
                sourceRevision: DocumentTransactionRevision(16)
            ),
            in: fixture.project
        )
    } catch let caught as CADIntegrationError {
        error = caught
    }

    #expect(error?.code == .invalidEvaluationResult)
    #expect(evaluator.evaluationCount() == 1)
}

@Test(.timeLimit(.minutes(1)))
func cadEvaluationCachePreservesTheNewestRevisionUnderConcurrentPublication() async throws {
    let fixture = try makeCADProviderFixture()
    let evaluator = RecordingCADDocumentEvaluator(result: fixture.evaluatedDocument)
    let cache = CADDocumentEvaluationCache()
    let revisions = (1...16).map(DocumentTransactionRevision.init)

    try await withThrowingTaskGroup(of: Void.self) { group in
        for revision in revisions {
            group.addTask {
                let provider = CADGeometrySourceProvider(
                    document: fixture.document,
                    evaluator: evaluator,
                    cache: cache
                )
                _ = try provider.evaluate(
                    try GeometrySourceEvaluationRequest(
                        references: [fixture.reference],
                        sourceRevision: revision
                    ),
                    in: fixture.project
                )
            }
        }
        try await group.waitForAll()
    }

    let probeEvaluator = RecordingCADDocumentEvaluator(result: fixture.evaluatedDocument)
    let probeProvider = CADGeometrySourceProvider(
        document: fixture.document,
        evaluator: probeEvaluator,
        cache: cache
    )
    _ = try probeProvider.evaluate(
        try GeometrySourceEvaluationRequest(
            references: [fixture.reference],
            sourceRevision: try #require(revisions.last)
        ),
        in: fixture.project
    )

    #expect(probeEvaluator.evaluationCount() == 0)
}

private struct CADProviderFixture {
    let document: CADDocument
    let evaluatedDocument: EvaluatedDocument
    let reference: GeometrySourceReference
    let project: ProjectSourceModel
}

private func makeCADProviderFixture() throws -> CADProviderFixture {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let evaluator = DocumentEvaluator(
        tolerance: session.document.modelingSettings.tolerance
    )
    let evaluatedDocument = try evaluator.evaluate(session.document.cadDocument)
    let bodyID = try #require(evaluatedDocument.meshes.keys.first)
    return CADProviderFixture(
        document: session.document.cadDocument,
        evaluatedDocument: evaluatedDocument,
        reference: .external(
            providerID: CADGeometrySourceProvider.identifier,
            sourceID: session.document.cadDocument.id.description,
            outputID: bodyID.description
        ),
        project: try ProjectSourceModel(id: "project.cache", name: "CAD Cache")
    )
}

private func replacingMesh(
    bodyID: BodyID,
    in evaluatedDocument: EvaluatedDocument,
    transform: (inout Mesh) -> Void
) throws -> EvaluatedDocument {
    var mesh = try #require(evaluatedDocument.meshes[bodyID])
    transform(&mesh)
    var meshes = evaluatedDocument.meshes
    meshes[bodyID] = mesh
    return EvaluatedDocument(
        document: evaluatedDocument.document,
        parameters: evaluatedDocument.parameters,
        brep: evaluatedDocument.brep,
        meshes: meshes,
        curves: evaluatedDocument.curves,
        caches: evaluatedDocument.caches,
        subshapes: evaluatedDocument.subshapes,
        lineage: evaluatedDocument.lineage,
        configuration: evaluatedDocument.configuration,
        evaluationMetrics: evaluatedDocument.evaluationMetrics
    )
}

private final class RecordingCADDocumentEvaluator: CADDocumentEvaluating, Sendable {
    private struct State {
        var evaluationCount = 0
        var reusedEvaluationCount = 0
    }

    let configuration: CADGeometryEvaluationConfiguration
    private let result: EvaluatedDocument
    private let state = Mutex(State())

    init(
        result: EvaluatedDocument,
        configuration: CADGeometryEvaluationConfiguration =
            CADGeometryEvaluationConfiguration(
                tolerance: DocumentModelingSettings.standard.tolerance
            )
    ) {
        self.result = result
        self.configuration = configuration
    }

    func evaluate(
        _: ValidatedCADDocument,
        reusing previous: EvaluatedDocument?
    ) throws -> EvaluatedDocument {
        state.withLock { state in
            state.evaluationCount += 1
            if previous != nil {
                state.reusedEvaluationCount += 1
            }
        }
        return result
    }

    func evaluationCount() -> Int {
        state.withLock { $0.evaluationCount }
    }

    func reusedEvaluationCount() -> Int {
        state.withLock { $0.reusedEvaluationCount }
    }
}

private struct FailingCADGeometrySourceResolver: CADGeometrySourceResolving {
    private struct ResolverFailure: Error {}

    func source(for _: String) throws -> CADGeometryEvaluationSource {
        throw ResolverFailure()
    }
}
