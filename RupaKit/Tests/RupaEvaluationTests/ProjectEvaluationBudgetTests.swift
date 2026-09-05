import RupaCoreTypes
import RupaEvaluation
import RupaProjectModel
import Testing
@testable import RupaGeometry

/// The engine is the authority on what one evaluation may produce, so these
/// contracts are stated against `ProjectEvaluationEngine` and the provider it
/// ships with, not against the budget arithmetic the resource suite covers.
@Suite("Project evaluation budget")
struct ProjectEvaluationBudgetTests {
    private static func meshRegistry() throws -> GeometrySourceEvaluationProviderRegistry {
        try GeometrySourceEvaluationProviderRegistry(
            providers: [MeshSourceEvaluationProvider()]
        )
    }

    private static func policy(
        narrowedTo limits: EvaluationResourceLimits
    ) throws -> EvaluationResourcePolicy {
        try EvaluationResourcePolicy.standard.lowered(to: limits)
    }

    private static func limits(
        sourceCount: Int = EvaluationResourceLimits.standard.maximumSourceCount,
        vertexCount: Int = EvaluationResourceLimits.standard.maximumVertexCount
    ) -> EvaluationResourceLimits {
        EvaluationResourceLimits(
            maximumSourceCount: sourceCount,
            maximumVertexCount: vertexCount,
            maximumFaceCount: EvaluationResourceLimits.standard.maximumFaceCount,
            maximumCornerCount: EvaluationResourceLimits.standard.maximumCornerCount,
            maximumTriangleCount: EvaluationResourceLimits.standard.maximumTriangleCount,
            maximumByteCount: EvaluationResourceLimits.standard.maximumByteCount
        )
    }

    /// A project with `count` distinct authored triangles, one occurrence each.
    private static func project(distinctMeshes count: Int) throws -> ProjectSourceModel {
        var assets: [GeometrySourceID: AuthoredMeshAsset] = [:]
        var definitions: [ObjectDefinitionID: ObjectDefinition] = [:]
        var occurrences: [SceneOccurrenceID: SceneOccurrence] = [:]

        for index in 0..<count {
            let mesh = try triangleSource(
                identity: GeometrySourceID(rawValue: "mesh.\(index)"),
                xOffset: Double(index) * 2
            )
            let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
            let definition = objectDefinition(
                id: ObjectDefinitionID(rawValue: "definition.\(index)"),
                name: "Mesh \(index)",
                source: .authoredMesh(mesh.identity)
            )
            let occurrence = SceneOccurrence(
                id: SceneOccurrenceID(rawValue: "occurrence.\(index)"),
                definitionID: definition.id
            )
            assets[asset.id] = asset
            definitions[definition.id] = definition
            occurrences[occurrence.id] = occurrence
        }

        return try ProjectSourceModel(
            id: "project.budget",
            name: "Budget",
            authoredMeshAssets: assets,
            objectDefinitions: definitions,
            occurrences: occurrences,
            rootOccurrenceIDs: occurrences.keys.sorted(by: { $0.rawValue < $1.rawValue })
        )
    }

    private static func evaluationError(
        _ body: () throws -> Void
    ) -> EvaluationError? {
        do {
            try body()
            return nil
        } catch let error as EvaluationError {
            return error
        } catch {
            Issue.record("Expected an EvaluationError but caught \(error).")
            return nil
        }
    }

    @Test("A project with more sources than the purpose admits is refused", .timeLimit(.minutes(1)))
    func moreSourcesThanAdmittedIsRefused() throws {
        let policy = try Self.policy(narrowedTo: Self.limits(sourceCount: 1))
        let engine = ProjectEvaluationEngine(registry: try Self.meshRegistry(), policy: policy)
        let project = try Self.project(distinctMeshes: 2)

        let error = Self.evaluationError {
            _ = try engine.evaluate(
                project: project,
                purpose: .presentation,
                revision: DocumentTransactionRevision(1)
            )
        }

        #expect(error?.code == .resourceExhausted)
        #expect(error?.message.contains(EvaluationResource.sourceCount.rawValue) == true)

        // The same project is admitted when the purpose states room for it, so
        // the refusal is the ceiling and not the project.
        let widened = ProjectEvaluationEngine(
            registry: try Self.meshRegistry(),
            policy: try Self.policy(narrowedTo: Self.limits(sourceCount: 2))
        )
        let snapshot = try widened.evaluate(
            project: project,
            purpose: .presentation,
            revision: DocumentTransactionRevision(1)
        )
        #expect(snapshot.occurrences.count == 2)
    }

    @Test("A provider that ignores its allowance is still refused", .timeLimit(.minutes(1)))
    func providerIgnoringItsAllowanceIsRefused() throws {
        // The recording provider returns its mesh whatever the request allows,
        // which is what makes this prove the engine charges independently.
        let provider = RecordingGeometrySourceEvaluationProvider(
            providerID: "fixture.ignores-allowance",
            mesh: try triangleSource()
        )
        let registry = try GeometrySourceEvaluationProviderRegistry(providers: [provider])
        let reference = GeometrySourceReference.external(
            providerID: provider.providerID,
            sourceID: "ignored.source",
            outputID: "ignored.output"
        )
        let definition = objectDefinition(
            id: "ignored.definition",
            name: "Ignored",
            source: reference
        )
        let occurrence = SceneOccurrence(id: "ignored.occurrence", definitionID: definition.id)
        let project = try ProjectSourceModel(
            id: "project.ignored-allowance",
            name: "Ignored Allowance",
            objectDefinitions: [definition.id: definition],
            occurrences: [occurrence.id: occurrence],
            rootOccurrenceIDs: [occurrence.id]
        )
        // One vertex, against a triangle's three.
        let engine = ProjectEvaluationEngine(
            registry: registry,
            policy: try Self.policy(narrowedTo: Self.limits(vertexCount: 1))
        )

        let error = Self.evaluationError {
            _ = try engine.evaluate(
                project: project,
                purpose: .presentation,
                revision: DocumentTransactionRevision(2)
            )
        }

        #expect(provider.callCount() == 1)
        #expect(error?.code == .resourceExhausted)
        #expect(error?.message.contains(EvaluationResource.vertexCount.rawValue) == true)
        // The provider saw the narrowed allowance, so it had what it needed to
        // refuse early and the engine caught it having declined to.
        #expect(provider.requests().first?.allowance.vertexCount == 1)
    }

    @Test("The mesh provider refuses an authored mesh its allowance excludes", .timeLimit(.minutes(1)))
    func meshProviderRefusesAnInadmissibleAuthoredMesh() throws {
        let mesh = try triangleSource()
        let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
        let project = try ProjectSourceModel(
            id: "project.mesh-allowance",
            name: "Mesh Allowance",
            authoredMeshAssets: [asset.id: asset]
        )
        let reference = GeometrySourceReference.authoredMesh(mesh.identity)
        let provider = MeshSourceEvaluationProvider()

        let admitted = try provider.evaluate(
            try GeometrySourceEvaluationRequest(
                references: [reference],
                sourceRevision: DocumentTransactionRevision(3),
                purpose: .presentation,
                allowance: EvaluationAllowance(.standard)
            ),
            in: project
        )
        #expect(admitted[reference] != nil)

        let error = Self.evaluationError {
            _ = try provider.evaluate(
                try GeometrySourceEvaluationRequest(
                    references: [reference],
                    sourceRevision: DocumentTransactionRevision(3),
                    purpose: .presentation,
                    allowance: EvaluationAllowance(Self.limits(vertexCount: 1))
                ),
                in: project
            )
        }

        #expect(error?.code == .resourceExhausted)
        #expect(error?.message.contains(EvaluationResource.vertexCount.rawValue) == true)
    }

    @Test("A later provider sees what the earlier one consumed", .timeLimit(.minutes(1)))
    func laterProviderSeesTheRemainder() throws {
        let mesh = try triangleSource()
        // Providers run in sorted identifier order, so "a" is charged first.
        let first = RecordingGeometrySourceEvaluationProvider(
            providerID: "fixture.a",
            mesh: mesh
        )
        let second = RecordingGeometrySourceEvaluationProvider(
            providerID: "fixture.b",
            mesh: mesh
        )
        let registry = try GeometrySourceEvaluationProviderRegistry(
            providers: [first, second]
        )

        var definitions: [ObjectDefinitionID: ObjectDefinition] = [:]
        var occurrences: [SceneOccurrenceID: SceneOccurrence] = [:]
        for provider in [first, second] {
            let reference = GeometrySourceReference.external(
                providerID: provider.providerID,
                sourceID: "\(provider.providerID).source",
                outputID: "\(provider.providerID).output"
            )
            let definition = objectDefinition(
                id: ObjectDefinitionID(rawValue: "\(provider.providerID).definition"),
                name: provider.providerID,
                source: reference
            )
            let occurrence = SceneOccurrence(
                id: SceneOccurrenceID(rawValue: "\(provider.providerID).occurrence"),
                definitionID: definition.id
            )
            definitions[definition.id] = definition
            occurrences[occurrence.id] = occurrence
        }
        let project = try ProjectSourceModel(
            id: "project.remainder",
            name: "Remainder",
            objectDefinitions: definitions,
            occurrences: occurrences,
            rootOccurrenceIDs: occurrences.keys.sorted(by: { $0.rawValue < $1.rawValue })
        )

        _ = try ProjectEvaluationEngine(registry: registry).evaluate(
            project: project,
            purpose: .modeling,
            revision: DocumentTransactionRevision(4)
        )

        let usage = try mesh.resourceUsage()
        let firstAllowance = try #require(first.requests().first?.allowance)
        let secondAllowance = try #require(second.requests().first?.allowance)
        let standard = EvaluationResourceLimits.standard

        // Both sources are charged before any provider runs, so neither request
        // may still claim the source allowance the other consumed.
        #expect(firstAllowance.sourceCount == standard.maximumSourceCount - 2)
        #expect(secondAllowance.sourceCount == standard.maximumSourceCount - 2)

        #expect(firstAllowance.vertexCount == standard.maximumVertexCount)
        #expect(secondAllowance.vertexCount == standard.maximumVertexCount - usage.vertexCount)
        #expect(secondAllowance.faceCount == standard.maximumFaceCount - usage.faceCount)
        #expect(secondAllowance.cornerCount == standard.maximumCornerCount - usage.cornerCount)
        #expect(
            secondAllowance.triangleCount == standard.maximumTriangleCount - usage.triangleCount
        )
        #expect(secondAllowance.byteCount == standard.maximumByteCount - usage.byteCount)

        // The purpose the caller asked for reaches the provider, so a provider
        // can narrow its own generation to it.
        #expect(firstAllowance.vertexCount > 0)
        #expect(first.requests().first?.purpose == .modeling)
        #expect(second.requests().first?.purpose == .modeling)
    }
}
