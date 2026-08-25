import Foundation
import Synchronization
import SwiftCAD
import Testing
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaGeometry
import RupaProjectModel
import RupaProjectPackage
@testable import RupaProject

@Test(.timeLimit(.minutes(1)))
func projectControllerPublishesCADPackageAndEvaluationAfterValidation() async throws {
    let controller = try makeController(document: .empty(named: "Before"))
    let result = try await controller.commit(
        ProjectSourceTransaction(
            name: "fixture.rename",
            commands: [.renameDocument(name: "After")],
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
    )

    #expect(result.baseTransactionRevision == DocumentTransactionRevision(0))
    #expect(result.transactionRevision == DocumentTransactionRevision(1))
    #expect(result.documentGeneration == DocumentGeneration(1))
    #expect(result.document.cadDocument.metadata.name == "After")
    #expect(try decodedProductName(result.package.productSource) == "After")
    #expect(result.evaluation.projectID == result.package.documentID)
    #expect(result.commandResults.count == 1)
    #expect(await controller.currentDocument().cadDocument.metadata.name == "After")
    #expect(await controller.currentEvaluationSource().name == "After")
    #expect(await controller.currentPackage().cadSource == result.package.cadSource)
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(1))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerLoadsEvaluatesAndResavesMeshOnlyPackageWithoutCADAuthority() async throws {
    try await withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("mesh-only.rupa")
        let resavedURL = directory.appendingPathComponent("mesh-only-resaved.rupa")
        let sourceDocument = try meshOnlyDocument(named: "Mesh Only")
        let controller = try makeController(document: sourceDocument)

        let initialEvaluation = try await controller.evaluateCurrent()
        let initialPackage = await controller.currentPackage()
        #expect(initialPackage.cadSource == nil)
        #expect(initialEvaluation.occurrences.values.contains {
            $0.reference == .authoredMesh("mesh.controller-only")
                && $0.mesh == sourceDocument.authoredMeshAssets["mesh.controller-only"]?.source
        })
        _ = try await controller.save(
            to: url,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )

        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.rename-mesh-only",
                commands: [.renameDocument(name: "Changed")],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
        let loaded = try await controller.load(
            from: url,
            expectedTransactionRevision: DocumentTransactionRevision(1)
        )

        #expect(loaded.document.cadDocument.metadata.name == "Mesh Only")
        #expect(loaded.document.id == sourceDocument.id)
        #expect(loaded.document.cadDocument.units == sourceDocument.cadDocument.units)
        #expect(loaded.document.hasAuthoritativeCADSource == false)
        #expect(loaded.package.cadSource == nil)
        #expect(loaded.document.authoredMeshAssets == sourceDocument.authoredMeshAssets)
        #expect(loaded.evaluation.occurrences.values.contains {
            $0.reference == .authoredMesh("mesh.controller-only")
        })
        let resaved = try await controller.save(
            to: resavedURL,
            expectedTransactionRevision: DocumentTransactionRevision(2)
        )
        #expect(resaved.document.cadSource == nil)
        #expect(resaved.document.authoredMeshAssets == sourceDocument.authoredMeshAssets)
    }
}

@Test(.timeLimit(.minutes(1)))
func projectControllerCADTransactionPreservesAuthoredMeshAuthorityAndPresentationSelection() async throws {
    let sourceDocument = try cadAndMeshDocument(named: "Hybrid")
    let sourceAsset = try #require(sourceDocument.authoredMeshAssets["mesh.controller-presentation"])
    let sourceNode = try #require(sourceDocument.productMetadata.sceneNodes.first {
        $0.value.object?.geometryRepresentations.source(for: .presentation)
            == .authoredMesh(sourceAsset.id)
    })
    let sourceSelection = try #require(
        sourceNode.value.object?.geometryRepresentations.selection
    )
    let controller = try makeController(document: sourceDocument)
    let beforePackage = await controller.currentPackage()

    let result = try await controller.commit(
        ProjectSourceTransaction(
            name: "fixture.rename-hybrid",
            commands: [.renameDocument(name: "Hybrid Renamed")],
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
    )

    let resultAsset = try #require(
        result.package.authoredMeshAssets[sourceAsset.id]
    )
    let resultSelection = try #require(
        result.document.productMetadata.sceneNodes[sourceNode.key]?
            .object?.geometryRepresentations.selection
    )
    #expect(beforePackage.cadSource != nil)
    #expect(result.package.cadSource != nil)
    #expect(result.package.cadSource != beforePackage.cadSource)
    #expect(resultAsset.id == sourceAsset.id)
    #expect(resultAsset.source == sourceAsset.source)
    #expect(resultAsset.provenance == sourceAsset.provenance)
    #expect(resultSelection == sourceSelection)
    let usesPresentationMesh = result.evaluation.occurrences.values.contains {
        $0.representationID == sourceSelection.presentation
            && $0.reference == .authoredMesh(sourceAsset.id)
    }
    #expect(usesPresentationMesh)
    #expect(result.evaluation.copyTelemetry.didCopy == false)
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRejectsLossyProductCodecBeforePublishing() async throws {
    let controller = try makeController(
        document: try meshOnlyDocument(named: "Before"),
        productSourceCodec: NameCorruptingProductSourceCodec(triggerName: "After")
    )
    let retainedPackage = await controller.currentPackage()
    var caught: ProjectControllerError?

    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.lossy-product",
                commands: [.renameDocument(name: "After")],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
    } catch let error as ProjectControllerError {
        caught = error
    }

    #expect(caught?.code == .sourceMismatch)
    #expect(await controller.currentDocument().cadDocument.metadata.name == "Before")
    #expect(await controller.currentPackage().productSource == retainedPackage.productSource)
    #expect(await controller.currentEvaluationSource().name == "Before")
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRejectsLossyCADCodecBeforePublishing() async throws {
    let sourceDocument = try cadAndMeshDocument(named: "Before")
    let controller = try makeController(
        document: sourceDocument,
        cadSourceCodec: NameCorruptingCADSourceCodec(triggerName: "After")
    )
    let retainedPackage = await controller.currentPackage()
    var caught: ProjectControllerError?

    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.lossy-cad",
                commands: [.renameDocument(name: "After")],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
    } catch let error as ProjectControllerError {
        caught = error
    }

    #expect(caught?.code == .sourceMismatch)
    #expect(await controller.currentDocument().cadDocument.metadata.name == "Before")
    #expect(await controller.currentPackage().cadSource == retainedPackage.cadSource)
    #expect(
        await controller.currentPackage().authoredMeshAssets
            == retainedPackage.authoredMeshAssets
    )
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRejectsLostProductModelingSettingsBeforePublishing() async throws {
    let sourceDocument = try meshOnlyDocument(named: "Before")
    let controller = try makeController(
        document: sourceDocument,
        productSourceCodec: ModelingSettingsCorruptingProductSourceCodec(
            triggerName: "After"
        )
    )
    let retainedPackage = await controller.currentPackage()
    var caught: ProjectControllerError?

    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.lossy-product-settings",
                commands: [.renameDocument(name: "After")],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
    } catch let error as ProjectControllerError {
        caught = error
    }

    #expect(caught?.code == .sourceMismatch)
    #expect(await controller.currentDocument().modelingSettings == sourceDocument.modelingSettings)
    #expect(await controller.currentPackage().productSource == retainedPackage.productSource)
    #expect(await controller.currentEvaluationSource().name == "Before")
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRejectsLostCADParametersBeforePublishing() async throws {
    let sourceDocument = DesignDocument.empty(named: "Parameters")
    let controller = try makeController(
        document: sourceDocument,
        cadSourceCodec: ParameterDroppingCADSourceCodec()
    )
    let retainedPackage = await controller.currentPackage()
    var caught: ProjectControllerError?

    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.lossy-cad-parameters",
                commands: [
                    .upsertParameter(
                        name: "width",
                        expression: .constant(.length(1.0, unit: .meter)),
                        kind: .length
                    ),
                ],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
    } catch let error as ProjectControllerError {
        caught = error
    }

    #expect(caught?.code == .sourceMismatch)
    #expect(await controller.currentDocument().cadDocument.parameters.parameters.isEmpty)
    #expect(await controller.currentPackage().productSource == retainedPackage.productSource)
    #expect(await controller.currentPackage().cadSource == nil)
    #expect(await controller.currentEvaluationSource().name == "Parameters")
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRejectsUnsavableStagedPackageBeforePublishing() async throws {
    let sourceDocument = try meshOnlyDocument(named: "Before")
    let initialProductByteCount = try JSONProjectProductSourceCodec()
        .encode(sourceDocument).data.count
    var limits = ProjectPackageResourceLimits.standard
    limits.maximumProductSourceByteCount = initialProductByteCount
    let validator = ProjectPackageStore(limits: limits)
    let controller = try makeController(
        document: sourceDocument,
        packageValidator: validator
    )
    let retainedPackage = await controller.currentPackage()
    var caught: ProjectControllerError?

    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.unsavable-package",
                commands: [.renameDocument(name: "A much longer staged Product name")],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
    } catch let error as ProjectControllerError {
        caught = error
    }

    #expect(caught?.code == .packageFailed)
    #expect(await controller.currentDocument().cadDocument.metadata.name == "Before")
    #expect(await controller.currentPackage().productSource == retainedPackage.productSource)
    #expect(await controller.currentEvaluationSource().name == "Before")
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRejectsProductCADMismatchWithoutPublishing() async throws {
    try await withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("mismatch.rupa")
        let sourceController = try makeController(
            document: try cadAndMeshDocument(named: "Matched")
        )
        let sourcePackage = await sourceController.currentPackage()
        let sourceCAD = try #require(sourcePackage.cadSource)
        var mismatchedCAD = try JSONProjectCADSourceCodec().decode(sourceCAD)
        mismatchedCAD.metadata.name = "Mismatched"
        let mismatchedPackage = try sourcePackage.replacingSources(
            documentID: sourcePackage.documentID,
            product: sourcePackage.productSource,
            cad: JSONProjectCADSourceCodec().encode(mismatchedCAD),
            authoredMeshAssets: sourcePackage.authoredMeshAssets
        )
        _ = try ProjectPackageStore().save(mismatchedPackage, to: url)

        let retainedDocument = try meshOnlyDocument(named: "Retained")
        let controller = try makeController(document: retainedDocument)
        let retainedPackage = await controller.currentPackage()
        var caught: ProjectControllerError?
        do {
            _ = try await controller.load(
                from: url,
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        } catch let error as ProjectControllerError {
            caught = error
        }

        #expect(caught?.code == .sourceMismatch)
        #expect(await controller.currentDocument().cadDocument.metadata.name == "Retained")
        #expect(await controller.currentPackage().productSource == retainedPackage.productSource)
        #expect(await controller.currentEvaluationSource().name == "Retained")
        #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
    }
}

@Test(.timeLimit(.minutes(1)))
func projectControllerProductDecodeFailureDoesNotPublishLoadedPackage() async throws {
    try await withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("invalid-product.rupa")
        let sourceController = try makeController(
            document: try meshOnlyDocument(named: "Invalid")
        )
        let sourcePackage = await sourceController.currentPackage()
        let invalidProduct = try ProjectPackageProductSource(
            data: Data("{\"schemaVersion\":99}".utf8)
        )
        let invalidPackage = try sourcePackage.replacingSources(
            documentID: sourcePackage.documentID,
            product: invalidProduct,
            cad: sourcePackage.cadSource,
            authoredMeshAssets: sourcePackage.authoredMeshAssets
        )
        _ = try ProjectPackageStore().save(invalidPackage, to: url)

        let controller = try makeController(
            document: try meshOnlyDocument(named: "Retained")
        )
        let retainedPackage = await controller.currentPackage()
        var caught: ProjectControllerError?
        do {
            _ = try await controller.load(
                from: url,
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        } catch let error as ProjectControllerError {
            caught = error
        }

        #expect(caught?.code == .productSourceFailed)
        #expect(await controller.currentDocument().cadDocument.metadata.name == "Retained")
        #expect(await controller.currentPackage().productSource == retainedPackage.productSource)
        #expect(await controller.currentEvaluationSource().name == "Retained")
        #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
    }
}

@Test(.timeLimit(.minutes(1)))
func projectControllerLoadEvaluationFailureDoesNotPublishStagedSources() async throws {
    try await withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("evaluation-failure.rupa")
        let sourceController = try makeController(
            document: try meshOnlyDocument(named: "Rejected")
        )
        _ = try await sourceController.save(
            to: url,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
        let controller = try makeController(
            document: try meshOnlyDocument(named: "Retained"),
            evaluator: NameRejectingProjectEvaluator(rejectedName: "Rejected")
        )
        let retainedPackage = await controller.currentPackage()
        var caught: ProjectControllerError?

        do {
            _ = try await controller.load(
                from: url,
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        } catch let error as ProjectControllerError {
            caught = error
        }

        #expect(caught?.code == .evaluationFailed)
        #expect(await controller.currentDocument().cadDocument.metadata.name == "Retained")
        #expect(await controller.currentPackage().productSource == retainedPackage.productSource)
        #expect(await controller.currentEvaluationSource().name == "Retained")
        #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
    }
}

@Test(.timeLimit(.minutes(1)))
func projectControllerCancelledLoadDoesNotPublishStagedSources() async throws {
    try await withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("cancelled-load.rupa")
        let sourceController = try makeController(
            document: try meshOnlyDocument(named: "Blocked")
        )
        _ = try await sourceController.save(
            to: url,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
        let gate = BlockingEvaluationGate(blockedSourceName: "Blocked")
        defer { gate.releaseFirstEvaluation() }
        let controller = try makeController(
            document: try meshOnlyDocument(named: "Retained"),
            evaluator: BlockingProjectEvaluator(gate: gate)
        )
        let retainedPackage = await controller.currentPackage()
        let load = Task {
            try await controller.load(
                from: url,
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        }
        while !gate.didStartFirstEvaluation {
            try await Task.sleep(for: .milliseconds(1))
        }
        load.cancel()
        gate.releaseFirstEvaluation()

        var wasCancelled = false
        do {
            _ = try await load.value
        } catch is CancellationError {
            wasCancelled = true
        }
        #expect(wasCancelled)
        #expect(await controller.currentDocument().cadDocument.metadata.name == "Retained")
        #expect(await controller.currentPackage().productSource == retainedPackage.productSource)
        #expect(await controller.currentEvaluationSource().name == "Retained")
        #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
    }
}

@Test(.timeLimit(.minutes(1)))
func projectControllerDoesNotPublishWhenEvaluationFails() async throws {
    let initial = DesignDocument.empty(named: "Before")
    let controller = try makeController(
        document: initial,
        evaluator: FailingProjectEvaluator()
    )
    let initialPackage = await controller.currentPackage()
    var caught: ProjectControllerError?

    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.failure",
                commands: [.renameDocument(name: "Never Published")],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
    } catch let error as ProjectControllerError {
        caught = error
    }

    #expect(caught?.code == .evaluationFailed)
    #expect(await controller.currentDocument().cadDocument.metadata.name == "Before")
    #expect(await controller.currentEvaluationSource().name == "Before")
    #expect(await controller.currentPackage().cadSource == initialPackage.cadSource)
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRejectsStaleRequestBeforeStaging() async throws {
    let controller = try makeController(document: .empty(named: "Before"))
    _ = try await controller.commit(
        ProjectSourceTransaction(
            name: "fixture.first",
            commands: [.renameDocument(name: "Committed")],
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
    )
    var caught: ProjectControllerError?

    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.stale",
                commands: [.renameDocument(name: "Rejected")],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
    } catch let error as ProjectControllerError {
        caught = error
    }

    #expect(caught?.code == .revisionConflict)
    #expect(await controller.currentDocument().cadDocument.metadata.name == "Committed")
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(1))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRejectsPublicationWhenConcurrentCallerWins() async throws {
    let gate = BlockingEvaluationGate()
    let controller = try makeController(
        document: .empty(named: "Before"),
        evaluator: BlockingProjectEvaluator(gate: gate)
    )
    let first = Task {
        try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.first",
                commands: [.renameDocument(name: "First")],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
    }
    while !gate.didStartFirstEvaluation {
        try await Task.sleep(for: .milliseconds(1))
    }

    let second = try await controller.commit(
        ProjectSourceTransaction(
            name: "fixture.second",
            commands: [.renameDocument(name: "Second")],
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
    )
    gate.releaseFirstEvaluation()

    var firstError: ProjectControllerError?
    do {
        _ = try await first.value
    } catch let error as ProjectControllerError {
        firstError = error
    }
    #expect(firstError?.code == .revisionConflict)
    #expect(second.transactionRevision == DocumentTransactionRevision(1))
    #expect(await controller.currentDocument().cadDocument.metadata.name == "Second")
    #expect(await controller.currentEvaluationSource().name == "Second")
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(1))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRoutesSaveAndLoadThroughCoherentPackageState() async throws {
    try await withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("project.swcad")
        let controller = try makeController(document: .empty(named: "Saved"))
        let saved = try await controller.save(
            to: url,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
        #expect(try decodedProductName(saved.document.productSource) == "Saved")

        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.change",
                commands: [.renameDocument(name: "Changed")],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
        let loaded = try await controller.load(
            from: url,
            expectedTransactionRevision: DocumentTransactionRevision(1)
        )

        #expect(loaded.document.cadDocument.metadata.name == "Saved")
        #expect(try decodedProductName(loaded.package.productSource) == "Saved")
        #expect(loaded.transactionRevision == DocumentTransactionRevision(2))
        #expect(await controller.currentDocument().cadDocument.metadata.name == "Saved")
        #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(2))
    }
}

@Test(.timeLimit(.minutes(1)))
func projectControllerLoadInvalidatesPreLoadTransactionRevisions() async throws {
    try await withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("project.swcad")
        let controller = try makeController(document: .empty(named: "Loaded"))
        _ = try await controller.save(
            to: url,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
        let loaded = try await controller.load(
            from: url,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )

        #expect(loaded.transactionRevision == DocumentTransactionRevision(1))
        var caught: ProjectControllerError?
        do {
            _ = try await controller.commit(
                ProjectSourceTransaction(
                    name: "fixture.stale-after-load",
                    commands: [.renameDocument(name: "Rejected")],
                    expectedTransactionRevision: DocumentTransactionRevision(0)
                )
            )
        } catch let error as ProjectControllerError {
            caught = error
        }
        #expect(caught?.code == .revisionConflict)
        #expect(await controller.currentDocument().cadDocument.metadata.name == "Loaded")
        #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(1))
    }
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRejectsLateCommitAfterPackageLoadPublishes() async throws {
    try await withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("project.swcad")
        let gate = BlockingEvaluationGate()
        defer { gate.releaseFirstEvaluation() }
        let controller = try makeController(
            document: .empty(named: "Loaded"),
            evaluator: BlockingProjectEvaluator(gate: gate)
        )
        _ = try await controller.save(
            to: url,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
        let commit = Task {
            try await controller.commit(
                ProjectSourceTransaction(
                    name: "fixture.late",
                    commands: [.renameDocument(name: "First")],
                    expectedTransactionRevision: DocumentTransactionRevision(0)
                )
            )
        }
        while !gate.didStartFirstEvaluation {
            try await Task.sleep(for: .milliseconds(1))
        }

        let loaded = try await controller.load(
            from: url,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
        gate.releaseFirstEvaluation()

        var commitError: ProjectControllerError?
        do {
            _ = try await commit.value
        } catch let error as ProjectControllerError {
            commitError = error
        }
        #expect(commitError?.code == .revisionConflict)
        #expect(loaded.transactionRevision == DocumentTransactionRevision(1))
        #expect(await controller.currentDocument().cadDocument.metadata.name == "Loaded")
        #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(1))
    }
}

@Test(.timeLimit(.minutes(1)))
func projectControllerFailedSaveRetainsCurrentAggregate() async throws {
    try await withTemporaryDirectory { directory in
        let controller = try makeController(
            document: .empty(named: "Retained"),
            packageWriter: FailingPackageWriter()
        )
        let before = await controller.currentPackage()
        var caught: ProjectControllerError?

        do {
            _ = try await controller.save(
                to: directory.appendingPathComponent("failed.swcad"),
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        } catch let error as ProjectControllerError {
            caught = error
        }

        #expect(caught?.code == .packageFailed)
        #expect(await controller.currentPackage().productSource == before.productSource)
        #expect(await controller.currentPackage().cadSource == before.cadSource)
        #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
    }
}

private func makeController(
    document: DesignDocument,
    evaluator: any ProjectEvaluating = ProjectEvaluationEngine(),
    productSourceCodec: any ProjectProductSourceCoding = JSONProjectProductSourceCodec(),
    cadSourceCodec: any ProjectCADSourceCoding = JSONProjectCADSourceCodec(),
    packageWriter: any ProjectPackageWriting = ProjectPackageStore(),
    packageValidator: any ProjectPackageValidating = ProjectPackageStore()
) throws -> ProjectController {
    try ProjectController(
        document: document,
        evaluator: evaluator,
        projector: FixtureProjector(),
        productSourceCodec: productSourceCodec,
        cadSourceCodec: cadSourceCodec,
        packageWriter: packageWriter,
        packageValidator: packageValidator
    )
}

private struct FixtureProjector: ProjectSourceProjecting {
    func project(_ document: DesignDocument) throws -> ProjectSourceModel {
        var parentByChild: [SceneNodeID: SceneNodeID] = [:]
        for parent in document.productMetadata.sceneNodes.values {
            for childID in parent.childIDs {
                parentByChild[childID] = parent.id
            }
        }
        var definitions: [ObjectDefinitionID: ObjectDefinition] = [:]
        var occurrences: [SceneOccurrenceID: SceneOccurrence] = [:]
        for node in document.productMetadata.sceneNodes.values {
            let definitionID = ObjectDefinitionID(rawValue: "object.\(node.id.description)")
            let occurrenceID = SceneOccurrenceID(rawValue: "scene.\(node.id.description)")
            definitions[definitionID] = ObjectDefinition(
                id: definitionID,
                name: node.name,
                representations: node.object?.category == .body
                    ? node.object?.geometryRepresentations ?? .empty
                    : .empty
            )
            occurrences[occurrenceID] = SceneOccurrence(
                id: occurrenceID,
                definitionID: definitionID,
                parentID: parentByChild[node.id].map {
                    SceneOccurrenceID(rawValue: "scene.\($0.description)")
                },
                localTransform: .identity
            )
        }
        return try ProjectSourceModel(
            id: ProjectID(rawValue: "project.\(document.id.description)"),
            name: document.cadDocument.metadata.name ?? "Untitled",
            authoredMeshAssets: document.authoredMeshAssets,
            objectDefinitions: definitions,
            occurrences: occurrences,
            rootOccurrenceIDs: document.productMetadata.rootSceneNodeIDs.map {
                SceneOccurrenceID(rawValue: "scene.\($0.description)")
            }
        )
    }
}

private func decodedProductName(_ source: ProjectPackageProductSource) throws -> String? {
    try JSONProjectProductSourceCodec().decode(source).name
}

private struct NameCorruptingProductSourceCodec: ProjectProductSourceCoding {
    let triggerName: String

    func encode(_ document: DesignDocument) throws -> ProjectPackageProductSource {
        guard document.cadDocument.metadata.name == triggerName else {
            return try JSONProjectProductSourceCodec().encode(document)
        }
        var corrupted = document
        corrupted.cadDocument.metadata.name = "Corrupted"
        return try JSONProjectProductSourceCodec().encode(corrupted)
    }

    func decode(_ source: ProjectPackageProductSource) throws -> ProjectProductSourceModel {
        try JSONProjectProductSourceCodec().decode(source)
    }
}

private struct NameCorruptingCADSourceCodec: ProjectCADSourceCoding {
    let triggerName: String

    func encode(_ document: CADDocument) throws -> ProjectPackageCADSource {
        guard document.metadata.name == triggerName else {
            return try JSONProjectCADSourceCodec().encode(document)
        }
        var corrupted = document
        corrupted.metadata.name = "Corrupted"
        return try JSONProjectCADSourceCodec().encode(corrupted)
    }

    func decode(_ source: ProjectPackageCADSource) throws -> CADDocument {
        try JSONProjectCADSourceCodec().decode(source)
    }
}

private struct ModelingSettingsCorruptingProductSourceCodec: ProjectProductSourceCoding {
    let triggerName: String

    func encode(_ document: DesignDocument) throws -> ProjectPackageProductSource {
        try JSONProjectProductSourceCodec().encode(document)
    }

    func decode(_ source: ProjectPackageProductSource) throws -> ProjectProductSourceModel {
        let decoded = try JSONProjectProductSourceCodec().decode(source)
        guard decoded.name == triggerName else {
            return decoded
        }
        let current = decoded.modelingSettings.tessellationOptions
        return try ProjectProductSourceModel(
            documentID: decoded.documentID,
            name: decoded.name,
            units: decoded.units,
            modelingSettings: DocumentModelingSettings(
                tolerance: decoded.modelingSettings.tolerance,
                tessellationOptions: TessellationOptions(
                    linearTolerance: current.linearTolerance * 2.0,
                    angularTolerance: current.angularTolerance,
                    maxEdgeLength: current.maxEdgeLength
                )
            ),
            productMetadata: decoded.productMetadata
        )
    }
}

private struct ParameterDroppingCADSourceCodec: ProjectCADSourceCoding {
    func encode(_ document: CADDocument) throws -> ProjectPackageCADSource {
        var corrupted = document
        corrupted.parameters = ParameterTable(revision: document.parameters.revision)
        return try JSONProjectCADSourceCodec().encode(corrupted)
    }

    func decode(_ source: ProjectPackageCADSource) throws -> CADDocument {
        try JSONProjectCADSourceCodec().decode(source)
    }
}

private struct FailingProjectEvaluator: ProjectEvaluating {
    func evaluate(
        project _: ProjectSourceModel,
        purpose _: GeometryRepresentationPurpose,
        revision _: DocumentTransactionRevision
    ) throws -> EvaluatedProjectSnapshot {
        throw EvaluationError(
            code: .sourceUnavailable,
            message: "Fixture evaluation failed."
        )
    }
}

private struct NameRejectingProjectEvaluator: ProjectEvaluating {
    let rejectedName: String

    func evaluate(
        project: ProjectSourceModel,
        purpose: GeometryRepresentationPurpose,
        revision: DocumentTransactionRevision
    ) throws -> EvaluatedProjectSnapshot {
        guard project.name != rejectedName else {
            throw EvaluationError(
                code: .sourceUnavailable,
                message: "Fixture rejected the staged source."
            )
        }
        return try ProjectEvaluationEngine().evaluate(
            project: project,
            purpose: purpose,
            revision: revision
        )
    }
}

private final class BlockingEvaluationGate: Sendable {
    private struct State {
        var didStartFirstEvaluation = false
        var canFinishFirstEvaluation = false
    }

    private let state = Mutex(State())
    private let blockedSourceName: String

    init(blockedSourceName: String = "First") {
        self.blockedSourceName = blockedSourceName
    }

    var didStartFirstEvaluation: Bool {
        state.withLock { $0.didStartFirstEvaluation }
    }

    func waitIfNeeded(for sourceName: String) {
        guard sourceName == blockedSourceName else {
            return
        }
        state.withLock { $0.didStartFirstEvaluation = true }
        while !state.withLock({ $0.canFinishFirstEvaluation }) {
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    func releaseFirstEvaluation() {
        state.withLock { $0.canFinishFirstEvaluation = true }
    }
}

private struct BlockingProjectEvaluator: ProjectEvaluating {
    let gate: BlockingEvaluationGate

    func evaluate(
        project source: ProjectSourceModel,
        purpose: GeometryRepresentationPurpose,
        revision: DocumentTransactionRevision
    ) throws -> EvaluatedProjectSnapshot {
        gate.waitIfNeeded(for: source.name)
        return try ProjectEvaluationEngine().evaluate(
            project: source,
            purpose: purpose,
            revision: revision
        )
    }
}

private struct FailingPackageWriter: ProjectPackageWriting {
    func save(
        _: ProjectPackageDocument,
        to _: URL
    ) throws -> ProjectPackageSaveResult {
        throw ProjectPackageError(
            code: .atomicSaveFailure,
            message: "Fixture save failure."
        )
    }
}

private func meshOnlyDocument(named name: String) throws -> DesignDocument {
    var document = DesignDocument.empty(named: name)
    let mesh = try triangleMesh(identity: "mesh.controller-only")
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    let representationID: GeometryRepresentationID = "representation.controller-only"
    document.authoredMeshAssets[asset.id] = asset
    _ = try document.productMetadata.appendSceneNodeToFirstRoot(
        name: "Mesh",
        reference: .authoredMesh(asset.id),
        object: ObjectDescriptor(
            category: .body,
            geometryRole: .mesh,
            geometryRepresentations: representationSet(
                representationID: representationID,
                source: .authoredMesh(asset.id)
            )
        )
    )
    _ = try document.validate()
    return document
}

private func cadAndMeshDocument(named name: String) throws -> DesignDocument {
    var document = DesignDocument.empty(named: name)
    let bodyFeatureID = try document.createExtrudedRectangle(
        name: "Body",
        plane: .xy,
        width: .length(1, .meter),
        height: .length(1, .meter),
        depth: .length(1, .meter),
        direction: .normal
    )
    let bodyNodeID = try #require(document.productMetadata.sceneNodes.first {
        $0.value.reference == .body(bodyFeatureID)
    }?.key)
    var object = try #require(document.productMetadata.sceneNodes[bodyNodeID]?.object)
    let cadRepresentationID = try #require(
        object.geometryRepresentations.selection?.modeling
    )
    let mesh = try triangleMesh(identity: "mesh.controller-presentation")
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    let meshRepresentationID: GeometryRepresentationID =
        "representation.controller-presentation"
    document.authoredMeshAssets[asset.id] = asset
    object.geometryRepresentations.representations[meshRepresentationID] =
        GeometryRepresentation(
            id: meshRepresentationID,
            source: .authoredMesh(asset.id)
        )
    object.geometryRepresentations.selection = GeometryRepresentationSelection(
        modeling: cadRepresentationID,
        presentation: meshRepresentationID
    )
    document.productMetadata.sceneNodes[bodyNodeID]?.object = object
    _ = try document.validate()
    return document
}

private func representationSet(
    representationID: GeometryRepresentationID,
    source: GeometrySourceReference
) -> GeometryRepresentationSet {
    GeometryRepresentationSet(
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
}

private func triangleMesh(identity: GeometrySourceID) throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: identity)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [first, second, third])
    return try builder.build()
}

private func withTemporaryDirectory<Result: Sendable>(
    _ body: (URL) async throws -> Result
) async throws -> Result {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "rupa-project-controller-tests-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    do {
        let result = try await body(directory)
        try FileManager.default.removeItem(at: directory)
        return result
    } catch {
        let primaryError = error
        do {
            try FileManager.default.removeItem(at: directory)
        } catch let cleanupError {
            throw ProjectControllerError(
                code: .packageFailed,
                message: "Test failed and temporary cleanup also failed: "
                    + "\(primaryError); \(cleanupError)."
            )
        }
        throw primaryError
    }
}
