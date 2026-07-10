import Testing
import RupaCore
import RupaCoreTypes
@testable import RupaDomainFoundation

@Suite
struct DomainQueryExecutionTests {
    @Test(.timeLimit(.minutes(1)))
    func queryReceivesSnapshotAndExecutorOwnsExecutionIdentity() throws {
        let registry = try registry(
            effect: .query,
            resultKind: .semanticPayload
        )
        let session = EditorSession(document: .empty(named: "Original"))
        let result = try DomainCommandExecutor(registry: registry).execute(
            request(),
            in: session
        )

        #expect(session.document.cadDocument.metadata.name == "Original")
        #expect(session.generation == DocumentGeneration())
        #expect(result.baseGeneration == DocumentGeneration())
        #expect(result.generation == DocumentGeneration())
        #expect(result.proposedGeneration == DocumentGeneration())
        #expect(!result.didMutate)
        #expect(!result.wouldMutate)
        #expect(result.payload == .object([
            "snapshotName": .string("Local Copy"),
        ]))
    }

    @Test(.timeLimit(.minutes(1)))
    func artifactCapabilityCannotExecuteThroughQueryPlan() throws {
        let registry = try registry(
            effect: .artifactGeneration,
            resultKind: .artifactReference
        )
        let session = EditorSession(document: .empty(named: "Original"))
        var caught: DomainRegistryError?

        do {
            _ = try DomainCommandExecutor(registry: registry).execute(
                request(),
                in: session
            )
        } catch let error as DomainRegistryError {
            caught = error
        }

        #expect(caught?.code == .invalidRegistration)
        #expect(caught?.message == "Domain capability effect is incompatible with its lowered execution plan.")
        #expect(session.document.cadDocument.metadata.name == "Original")
        #expect(session.generation == DocumentGeneration())
    }

    private func request() -> DomainCommandRequest {
        DomainCommandRequest(
            capabilityID: FixtureLowering.capabilityID,
            namespace: FixtureLowering.namespace,
            payload: .object([:]),
            expectedGeneration: DocumentGeneration()
        )
    }

    private func registry(
        effect: DomainCapabilityEffect,
        resultKind: DomainCapabilityResultKind
    ) throws -> DomainRegistry {
        try DomainRegistry(
            namespaces: [
                DomainNamespaceRegistration(
                    namespace: FixtureLowering.namespace,
                    supportedSchemaVersions: [
                        SemanticSchemaVersion(major: 0, minor: 1, patch: 0),
                    ]
                ),
            ],
            capabilityDescriptors: [
                DomainCapabilityDescriptor(
                    id: FixtureLowering.capabilityID,
                    namespace: FixtureLowering.namespace,
                    name: "Snapshot Query",
                    summary: "Reads one immutable domain snapshot.",
                    effect: effect,
                    resultKind: resultKind,
                    supportsDryRun: true,
                    failureMode: "Rejects incompatible execution effects."
                ),
            ],
            commandLowerings: [FixtureLowering()]
        )
    }

    private struct FixtureLowering: DomainCommandLowering {
        static let namespace: SemanticNamespaceID = "fixture"
        static let capabilityID: DomainCapabilityID = "fixture.snapshotQuery"

        var capabilityID: DomainCapabilityID {
            Self.capabilityID
        }

        func lower(_ request: DomainCommandRequest) throws -> DomainCommandPlan {
            .query(FixtureQuery())
        }
    }

    private struct FixtureQuery: DomainCommandQuery {
        func execute(
            _ request: DomainCommandRequest,
            in context: DomainQueryContext
        ) throws -> DomainQueryResult {
            var localDocument = context.document
            localDocument.rename("Local Copy")
            guard let snapshotName = localDocument.cadDocument.metadata.name else {
                throw DomainRegistryError(
                    code: .invalidRegistration,
                    message: "Fixture snapshot name is unavailable."
                )
            }
            return DomainQueryResult(
                message: "Snapshot query completed.",
                payload: .object([
                    "snapshotName": .string(snapshotName),
                ])
            )
        }
    }
}
