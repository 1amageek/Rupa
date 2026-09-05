import Foundation
import RupaCore
import RupaCoreTypes
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
                sourceRevision: .init(),
                purpose: .presentation,
                allowance: EvaluationAllowance(.standard)
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
                    .cad(
                        sourceID: "another-document",
                        outputID: UUID().uuidString
                    ),
                ],
                sourceRevision: .init(),
                purpose: .presentation,
                allowance: EvaluationAllowance(.standard)
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
    let reference = GeometrySourceReference.cad(
        sourceID: UUID().uuidString,
        outputID: UUID().uuidString
    )
    var error: CADIntegrationError?

    do {
        _ = try provider.evaluate(
            try GeometrySourceEvaluationRequest(
                references: [reference],
                sourceRevision: .init(),
                purpose: .presentation,
                allowance: EvaluationAllowance(.standard)
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
    let reference = GeometrySourceReference.cad(
        sourceID: session.document.cadDocument.id.description,
        outputID: bodyID.description
    )

    let results = try provider.evaluate(
        try GeometrySourceEvaluationRequest(
            references: [reference],
            sourceRevision: .init(),
            purpose: .presentation,
            allowance: EvaluationAllowance(.standard)
        ),
        in: project
    )
    let result = try #require(results[reference])

    #expect(result.mesh.vertexIDs.count > 0)
    #expect(result.mesh.faceIDs.count > 0)
    #expect(result.mesh.attributes.layer(for: "cad.normal") != nil)
    #expect(result.localBounds.maximum.x > result.localBounds.minimum.x)
    #expect(result.copyTelemetry.didCopy)
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
    let bodyReference = GeometrySourceReference.cad(
        sourceID: session.document.cadDocument.id.description,
        outputID: bodyID.description
    )
    let featureReference = GeometrySourceReference.cad(
        sourceID: session.document.cadDocument.id.description,
        outputID: featureID.description
    )

    let results = try provider.evaluate(
        try GeometrySourceEvaluationRequest(
            references: [bodyReference, featureReference],
            sourceRevision: .init(),
            purpose: .presentation,
            allowance: EvaluationAllowance(.standard)
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
            sourceRevision: DocumentTransactionRevision(1),
            purpose: .presentation,
            allowance: EvaluationAllowance(.standard)
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
func cadProviderPassesRemainingKernelLimitsToEachFreshSource() throws {
    let first = try makeCADProviderFixture()
    let second = try makeCADProviderFixture()
    let firstVertexCount = try #require(first.evaluatedDocument.meshes.values.first?.positions.count)
    let secondVertexCount = try #require(second.evaluatedDocument.meshes.values.first?.positions.count)
    #expect(firstVertexCount == 24)
    #expect(secondVertexCount == 24)
    let baselineProvider = CADGeometrySourceProvider(
        document: first.document,
        evaluator: RecordingCADDocumentEvaluator(result: first.evaluatedDocument)
    )
    let baseline = try baselineProvider.evaluate(
        try GeometrySourceEvaluationRequest(
            references: [first.reference],
            sourceRevision: DocumentTransactionRevision(30),
            purpose: .presentation,
            allowance: EvaluationAllowance(.standard)
        ),
        in: first.project
    )
    let firstUniversalUsage = try #require(
        try baseline[first.reference]?.mesh.resourceUsage()
    )

    let firstEvaluator = RecordingCADDocumentEvaluator(
        result: first.evaluatedDocument,
        refusesResultExceedingLimits: true
    )
    let secondEvaluator = RecordingCADDocumentEvaluator(
        result: second.evaluatedDocument,
        refusesResultExceedingLimits: true
    )
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
    var allowance = EvaluationAllowance(.standard)
    allowance.vertexCount = 30
    allowance.cornerCount = TessellationLimits.standard.maximumIndexCount + 1
    allowance.faceCount = TessellationLimits.standard.maximumTriangleCount + 1
    allowance.triangleCount = TessellationLimits.standard.maximumTriangleCount + 1
    allowance.byteCount = firstUniversalUsage.byteCount + 1

    var error: EvaluationError?
    do {
        _ = try provider.evaluate(
            try GeometrySourceEvaluationRequest(
                references: [first.reference, second.reference],
                sourceRevision: DocumentTransactionRevision(31),
                purpose: .presentation,
                allowance: allowance
            ),
            in: first.project
        )
    } catch let caught as EvaluationError {
        error = caught
    }

    #expect(error?.code == .resourceExhausted)
    #expect(firstEvaluator.evaluationCount() == 1)
    #expect(secondEvaluator.evaluationCount() == 1)
    #expect(firstEvaluator.lastLimits()?.maximumVertexCount == 30)
    // The first source consumes 24 vertices. The second evaluator must receive
    // the six-vertex remainder and refuse before returning its 24-vertex mesh.
    #expect(secondEvaluator.lastLimits()?.maximumVertexCount == 6)
    #expect(
        secondEvaluator.lastLimits()?.maximumIndexCount
            == TessellationLimits.standard.maximumIndexCount
                - (first.evaluatedDocument.meshes.values.first?.indices.count ?? 0)
    )
    #expect(
        secondEvaluator.lastLimits()?.maximumTriangleCount
            == TessellationLimits.standard.maximumTriangleCount
                - ((first.evaluatedDocument.meshes.values.first?.indices.count ?? 0) / 3)
    )
    #expect(secondEvaluator.lastLimits()?.maximumByteCount == 1)
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
                sourceRevision: DocumentTransactionRevision(2),
                purpose: .presentation,
                allowance: EvaluationAllowance(.standard)
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
            sourceRevision: DocumentTransactionRevision(3),
            purpose: .presentation,
            allowance: EvaluationAllowance(.standard)
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
                sourceRevision: DocumentTransactionRevision(4),
                purpose: .presentation,
                allowance: EvaluationAllowance(.standard)
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
                sourceRevision: revision,
                purpose: .presentation,
                allowance: EvaluationAllowance(.standard)
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
            sourceRevision: revision,
            purpose: .presentation,
            allowance: EvaluationAllowance(.standard)
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
    let definition = cadObjectDefinition(
        id: "cad.definition",
        name: "CAD Body",
        source: .cad(
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

    let snapshot = try engine.evaluate(
        project: project,
        purpose: .presentation,
        revision: DocumentTransactionRevision()
    )
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
        sourceRevision: DocumentTransactionRevision(3),
        purpose: .presentation,
        allowance: EvaluationAllowance(.standard)
    )

    let firstResults = try firstProvider.evaluate(request, in: fixture.project)
    let secondResults = try secondProvider.evaluate(request, in: fixture.project)

    #expect(evaluator.evaluationCount() == 1)
    #expect(evaluator.reusedEvaluationCount() == 0)
    #expect(try #require(firstResults[fixture.reference]).copyTelemetry.didCopy)
    #expect(try #require(secondResults[fixture.reference]).copyTelemetry.didCopy == false)
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
            sourceRevision: DocumentTransactionRevision(8),
            purpose: .presentation,
            allowance: EvaluationAllowance(.standard)
        ),
        in: fixture.project
    )
    _ = try secondProvider.evaluate(
        try GeometrySourceEvaluationRequest(
            references: [fixture.reference],
            sourceRevision: DocumentTransactionRevision(9),
            purpose: .presentation,
            allowance: EvaluationAllowance(.standard)
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
            sourceRevision: revision,
            purpose: .presentation,
            allowance: EvaluationAllowance(.standard)
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
        sourceRevision: DocumentTransactionRevision(12),
        purpose: .presentation,
        allowance: EvaluationAllowance(.standard)
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
                sourceRevision: DocumentTransactionRevision(15),
                purpose: .presentation,
                allowance: EvaluationAllowance(.standard)
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
                sourceRevision: DocumentTransactionRevision(16),
                purpose: .presentation,
                allowance: EvaluationAllowance(.standard)
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
                        sourceRevision: revision,
                        purpose: .presentation,
                        allowance: EvaluationAllowance(.standard)
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
            sourceRevision: try #require(revisions.last),
            purpose: .presentation,
            allowance: EvaluationAllowance(.standard)
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

private func cadObjectDefinition(
    id: ObjectDefinitionID,
    name: String,
    source: GeometrySourceReference
) -> ObjectDefinition {
    let representationID = GeometryRepresentationID(
        rawValue: "representation.\(id.rawValue)"
    )
    return ObjectDefinition(
        id: id,
        name: name,
        representations: GeometryRepresentationSet(
            representations: [
                representationID: GeometryRepresentation(
                    id: representationID,
                    source: source
                ),
            ],
            selection: GeometryRepresentationSelection(
                modeling: representationID,
                presentation: representationID
            )
        )
    )
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
        reference: .cad(
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

@Test(.timeLimit(.minutes(1)))
func cadProviderServesBothRepresentationPurposesFromOneEvaluation() throws {
    let fixture = try makeCADProviderFixture()
    let evaluator = RecordingCADDocumentEvaluator(result: fixture.evaluatedDocument)
    let cache = CADDocumentEvaluationCache()
    let provider = CADGeometrySourceProvider(
        document: fixture.document,
        evaluator: evaluator,
        cache: cache
    )
    let revision = DocumentTransactionRevision(21)

    _ = try provider.evaluate(
        try GeometrySourceEvaluationRequest(
            references: [fixture.reference],
            sourceRevision: revision,
            purpose: .presentation,
            allowance: EvaluationAllowance(.standard)
        ),
        in: fixture.project
    )
    // Both purposes ask for the same fidelity of the same document, so the
    // second one must be served the artifact the first produced. Partitioning
    // the cache by purpose would cost a full kernel evaluation every time the
    // two alternate, which is what the publication path does on every edit.
    _ = try provider.evaluate(
        try GeometrySourceEvaluationRequest(
            references: [fixture.reference],
            sourceRevision: revision,
            purpose: .modeling,
            allowance: EvaluationAllowance(.standard)
        ),
        in: fixture.project
    )

    #expect(evaluator.evaluationCount() == 1)
}

@Test(.timeLimit(.minutes(1)))
func cadProviderLowersTheKernelLimitsToTheRemainingAllowance() throws {
    let fixture = try makeCADProviderFixture()
    let evaluator = RecordingCADDocumentEvaluator(result: fixture.evaluatedDocument)
    let provider = CADGeometrySourceProvider(
        document: fixture.document,
        evaluator: evaluator
    )
    var allowance = EvaluationAllowance(.standard)
    allowance.vertexCount = 64
    allowance.cornerCount = 192
    allowance.triangleCount = 64

    _ = try provider.evaluate(
        try GeometrySourceEvaluationRequest(
            references: [fixture.reference],
            sourceRevision: DocumentTransactionRevision(22),
            purpose: .presentation,
            allowance: allowance
        ),
        in: fixture.project
    )

    let limits = try #require(evaluator.lastLimits())
    #expect(limits.maximumVertexCount == 64)
    #expect(limits.maximumIndexCount == 192)
    #expect(limits.maximumTriangleCount == 64)
    #expect(
        limits.maximumByteCount
            == min(TessellationLimits.standard.maximumByteCount, allowance.byteCount)
    )
}

@Test(.timeLimit(.minutes(1)))
func cadProviderRefusesAnExhaustedAllowanceBeforeEvaluating() throws {
    let fixture = try makeCADProviderFixture()
    let evaluator = RecordingCADDocumentEvaluator(result: fixture.evaluatedDocument)
    let provider = CADGeometrySourceProvider(
        document: fixture.document,
        evaluator: evaluator
    )
    var error: EvaluationError?

    do {
        _ = try provider.evaluate(
            try GeometrySourceEvaluationRequest(
                references: [fixture.reference],
                sourceRevision: DocumentTransactionRevision(23),
                purpose: .presentation,
                allowance: .exhausted
            ),
            in: fixture.project
        )
    } catch let caught as EvaluationError {
        error = caught
    }

    #expect(error?.code == .resourceExhausted)
    #expect(evaluator.evaluationCount() == 0)
}

@Test(.timeLimit(.minutes(1)))
func cadProviderRefusesAnExactCachedRevisionTheAllowanceNoLongerAdmits() throws {
    let fixture = try makeCADProviderFixture()
    let evaluator = RecordingCADDocumentEvaluator(result: fixture.evaluatedDocument)
    let cache = CADDocumentEvaluationCache()
    let provider = CADGeometrySourceProvider(
        document: fixture.document,
        evaluator: evaluator,
        cache: cache
    )
    let revision = DocumentTransactionRevision(24)
    _ = try provider.evaluate(
        try GeometrySourceEvaluationRequest(
            references: [fixture.reference],
            sourceRevision: revision,
            purpose: .presentation,
            allowance: EvaluationAllowance(.standard)
        ),
        in: fixture.project
    )
    #expect(evaluator.evaluationCount() == 1)

    var narrowed = EvaluationAllowance(.standard)
    narrowed.vertexCount = 1
    narrowed.cornerCount = 1
    narrowed.triangleCount = 1
    var error: EvaluationError?
    do {
        _ = try provider.evaluate(
            try GeometrySourceEvaluationRequest(
                references: [fixture.reference],
                sourceRevision: revision,
                purpose: .presentation,
                allowance: narrowed
            ),
            in: fixture.project
        )
    } catch let caught as EvaluationError {
        error = caught
    }

    // The cached evaluation is returned by the cache, not by the kernel, so the
    // refusal must come from the provider without a second evaluation.
    #expect(error?.code == .resourceExhausted)
    #expect(evaluator.evaluationCount() == 1)
}

@Test(.timeLimit(.minutes(1)))
func cadProviderPreflightsUniversalStorageBeforeMaterialization() throws {
    let fixture = try makeCADProviderFixture()
    let baselineProvider = CADGeometrySourceProvider(
        document: fixture.document,
        evaluator: RecordingCADDocumentEvaluator(result: fixture.evaluatedDocument)
    )
    let baseline = try baselineProvider.evaluate(
        try GeometrySourceEvaluationRequest(
            references: [fixture.reference],
            sourceRevision: DocumentTransactionRevision(28),
            purpose: .presentation,
            allowance: EvaluationAllowance(.standard)
        ),
        in: fixture.project
    )
    let baselineResult = try #require(baseline[fixture.reference])
    let usage = try baselineResult.mesh.resourceUsage()

    var exactAllowance = EvaluationAllowance(.standard)
    exactAllowance.vertexCount = usage.vertexCount
    exactAllowance.faceCount = usage.faceCount
    exactAllowance.cornerCount = usage.cornerCount
    exactAllowance.triangleCount = usage.triangleCount
    exactAllowance.byteCount = usage.byteCount

    let cache = CADDocumentEvaluationCache()
    let exactEvaluator = RecordingCADDocumentEvaluator(result: fixture.evaluatedDocument)
    let exactProvider = CADGeometrySourceProvider(
        document: fixture.document,
        evaluator: exactEvaluator,
        cache: cache
    )
    _ = try exactProvider.evaluate(
        try GeometrySourceEvaluationRequest(
            references: [fixture.reference],
            sourceRevision: DocumentTransactionRevision(29),
            purpose: .presentation,
            allowance: exactAllowance
        ),
        in: fixture.project
    )

    var oneByteBelow = exactAllowance
    oneByteBelow.byteCount = usage.byteCount - 1
    let narrowedProvider = CADGeometrySourceProvider(
        document: fixture.document,
        evaluator: exactEvaluator,
        cache: cache
    )
    var error: EvaluationError?
    do {
        _ = try narrowedProvider.evaluate(
            try GeometrySourceEvaluationRequest(
                references: [fixture.reference],
                sourceRevision: DocumentTransactionRevision(30),
                purpose: .presentation,
                allowance: oneByteBelow
            ),
            in: fixture.project
        )
    } catch let caught as EvaluationError {
        error = caught
    }

    #expect(error?.code == .resourceExhausted)
    #expect(exactEvaluator.evaluationCount() == 2)

    // The refused request must not publish a replacement cache entry. A probe
    // with the failed revision therefore has to evaluate again.
    let probeEvaluator = RecordingCADDocumentEvaluator(result: fixture.evaluatedDocument)
    let probeProvider = CADGeometrySourceProvider(
        document: fixture.document,
        evaluator: probeEvaluator,
        cache: cache
    )
    _ = try probeProvider.evaluate(
            try GeometrySourceEvaluationRequest(
                references: [fixture.reference],
                sourceRevision: DocumentTransactionRevision(30),
                purpose: .presentation,
                allowance: exactAllowance
        ),
        in: fixture.project
    )
    #expect(probeEvaluator.evaluationCount() == 1)
}

@Test(.timeLimit(.minutes(1)))
func cadProviderReportsAKernelResourceRefusalAsResourceExhaustion() throws {
    let fixture = try makeCADProviderFixture()
    let evaluator = RecordingCADDocumentEvaluator(
        result: fixture.evaluatedDocument,
        failure: TessellationError.resourceExhausted(
            .vertexCount,
            requested: 4_096,
            limit: 64
        )
    )
    let provider = CADGeometrySourceProvider(
        document: fixture.document,
        evaluator: evaluator
    )
    var error: EvaluationError?

    do {
        _ = try provider.evaluate(
            try GeometrySourceEvaluationRequest(
                references: [fixture.reference],
                sourceRevision: DocumentTransactionRevision(25),
                purpose: .presentation,
                allowance: EvaluationAllowance(.standard)
            ),
            in: fixture.project
        )
    } catch let caught as EvaluationError {
        error = caught
    }

    #expect(error?.code == .resourceExhausted)
}

@Test(.timeLimit(.minutes(1)))
func cadProviderRethrowsCancellationUnchanged() throws {
    let fixture = try makeCADProviderFixture()
    let evaluator = RecordingCADDocumentEvaluator(
        result: fixture.evaluatedDocument,
        failure: CancellationError()
    )
    let provider = CADGeometrySourceProvider(
        document: fixture.document,
        evaluator: evaluator
    )

    #expect(throws: CancellationError.self) {
        _ = try provider.evaluate(
            try GeometrySourceEvaluationRequest(
                references: [fixture.reference],
                sourceRevision: DocumentTransactionRevision(26),
                purpose: .presentation,
                allowance: EvaluationAllowance(.standard)
            ),
            in: fixture.project
        )
    }
}

@Test(.timeLimit(.minutes(1)))
func cadProviderReportsAnUnrelatedEvaluationFailureAsEvaluationFailed() throws {
    struct EvaluatorFailure: Error {}
    let fixture = try makeCADProviderFixture()
    let evaluator = RecordingCADDocumentEvaluator(
        result: fixture.evaluatedDocument,
        failure: EvaluatorFailure()
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
                sourceRevision: DocumentTransactionRevision(27),
                purpose: .presentation,
                allowance: EvaluationAllowance(.standard)
            ),
            in: fixture.project
        )
    } catch let caught as CADIntegrationError {
        error = caught
    }

    #expect(error?.code == .evaluationFailed)
}

private final class RecordingCADDocumentEvaluator: CADDocumentEvaluating, Sendable {
    private struct State {
        var evaluationCount = 0
        var reusedEvaluationCount = 0
        var lastLimits: TessellationLimits?
    }

    let configuration: CADGeometryEvaluationConfiguration
    private let result: EvaluatedDocument
    private let failure: (any Error)?
    private let refusesResultExceedingLimits: Bool
    private let state = Mutex(State())

    init(
        result: EvaluatedDocument,
        configuration: CADGeometryEvaluationConfiguration =
            CADGeometryEvaluationConfiguration(
                tolerance: DocumentModelingSettings.standard.tolerance
            ),
        failure: (any Error)? = nil,
        refusesResultExceedingLimits: Bool = false
    ) {
        self.result = result
        self.configuration = configuration
        self.failure = failure
        self.refusesResultExceedingLimits = refusesResultExceedingLimits
    }

    func evaluate(
        _: ValidatedCADDocument,
        reusing previous: EvaluatedDocument?,
        admitting limits: TessellationLimits
    ) throws -> EvaluatedDocument {
        state.withLock { state in
            state.evaluationCount += 1
            if previous != nil {
                state.reusedEvaluationCount += 1
            }
            state.lastLimits = limits
        }
        if let failure {
            throw failure
        }
        if refusesResultExceedingLimits {
            for mesh in result.meshes.values {
                let usage = try TessellationUsage(mesh: mesh)
                if let exceeded = usage.firstResourceExceeding(limits) {
                    throw TessellationError.resourceExhausted(
                        exceeded,
                        requested: usage.amount(for: exceeded),
                        limit: limits.limit(for: exceeded)
                    )
                }
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

    func lastLimits() -> TessellationLimits? {
        state.withLock { $0.lastLimits }
    }
}

private struct FailingCADGeometrySourceResolver: CADGeometrySourceResolving {
    private struct ResolverFailure: Error {}

    func source(for _: String) throws -> CADGeometryEvaluationSource {
        throw ResolverFailure()
    }
}
