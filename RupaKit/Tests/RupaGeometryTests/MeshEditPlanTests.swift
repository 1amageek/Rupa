import Foundation
import RupaCoreTypes
import Testing
@testable import RupaGeometry

@Test(.timeLimit(.minutes(1)))
func meshEditPlanRejectsInvalidStructureAndCallerLimits() throws {
    #expect(throws: MeshEditError.self) {
        _ = try MeshEditPlan(steps: [])
    }

    let duplicateIDSteps = [
        MeshEditStep(
            id: MeshEditStepID("same"),
            operation: .primitive(
                .setVertexPositions([
                    try MeshVertexPositionEdit(
                        vertexID: MeshVertexID(0),
                        position: GeometryPoint3D(x: 0, y: 0, z: 0)
                    )
                ])
            )
        ),
        MeshEditStep(
            id: MeshEditStepID("same"),
            operation: .primitive(
                .setVertexPositions([
                    try MeshVertexPositionEdit(
                        vertexID: MeshVertexID(1),
                        position: GeometryPoint3D(x: 1, y: 0, z: 0)
                    )
                ])
            )
        ),
    ]
    #expect(throws: MeshEditError.self) {
        _ = try MeshEditPlan(steps: duplicateIDSteps)
    }

    let forwardReference = MeshEditStep(
        id: MeshEditStepID("first"),
        operation: .translateElements(
            .output(stepID: MeshEditStepID("second"), role: .affectedVertices),
            offset: GeometryVector3D(x: 1, y: 0, z: 0)
        )
    )
    let second = MeshEditStep(
        id: MeshEditStepID("second"),
        operation: .primitive(
            .setVertexPositions([
                try MeshVertexPositionEdit(
                    vertexID: MeshVertexID(0),
                    position: GeometryPoint3D(x: 0, y: 0, z: 0)
                )
            ])
        )
    )
    #expect(throws: MeshEditError.self) {
        _ = try MeshEditPlan(steps: [forwardReference, second])
    }

    #expect(throws: MeshEditError.self) {
        _ = try MeshEditLimits(maxSteps: 257)
    }
    #expect(throws: MeshEditError.self) {
        _ = try MeshEditLimits(maxCopiedBytes: MeshEditLimits.standard.maxCopiedBytes + 1)
    }
}

@Test(.timeLimit(.minutes(1)))
func meshEditPlanRejectsMissingInapplicableAndEmptySelectors() throws {
    let missingOutput = MeshEditStep(
        id: MeshEditStepID("missing"),
        operation: .translateElements(
            .output(stepID: MeshEditStepID("unknown"), role: .affectedVertices),
            offset: GeometryVector3D(x: 1, y: 0, z: 0)
        )
    )
    var error: MeshEditError?
    do {
        _ = try MeshEditPlan(steps: [missingOutput])
    } catch let caught as MeshEditError {
        error = caught
    }
    #expect(error?.code == .missingOutputReference)

    let producer = MeshEditStep(
        id: MeshEditStepID("producer"),
        operation: .primitive(
            .setVertexPositions([
                try MeshVertexPositionEdit(
                    vertexID: MeshVertexID(0),
                    position: GeometryPoint3D(x: 0, y: 0, z: 0)
                )
            ])
        )
    )
    let inapplicableOutput = MeshEditStep(
        id: MeshEditStepID("inapplicable"),
        operation: .translateElements(
            .output(stepID: producer.id, role: .createdFaces),
            offset: GeometryVector3D(x: 1, y: 0, z: 0)
        )
    )
    error = nil
    do {
        _ = try MeshEditPlan(steps: [producer, inapplicableOutput])
    } catch let caught as MeshEditError {
        error = caught
    }
    #expect(error?.code == .inapplicableOutputRole)

    let empty = MeshEditStep(
        id: MeshEditStepID("empty"),
        operation: .translateElements(
            .explicit(try MeshSelectionSet(elements: [])),
            offset: GeometryVector3D(x: 1, y: 0, z: 0)
        )
    )
    error = nil
    do {
        _ = try MeshEditPlan(steps: [empty])
    } catch let caught as MeshEditError {
        error = caught
    }
    #expect(error?.code == .emptySelection)
}

@Test(.timeLimit(.minutes(1)))
func meshEditPlanDecodingRevalidatesLimitsAndStructure() throws {
    let invalidLimits = Data(
        #"{"maxSteps":257,"maxScannedRecords":1048576,"maxSelectedIDs":8192,"maxGeneratedIDs":8192,"maxReceiptIDs":8192,"maxCopiedBytes":65536}"#.utf8
    )
    #expect(throws: MeshEditError.self) {
        _ = try JSONDecoder().decode(MeshEditLimits.self, from: invalidLimits)
    }

    let malformedPlan = Data(
        #"{"steps":[],"limits":{"maxSteps":256,"maxScannedRecords":1048576,"maxSelectedIDs":8192,"maxGeneratedIDs":8192,"maxReceiptIDs":8192,"maxCopiedBytes":65536}}"#.utf8
    )
    #expect(throws: MeshEditError.self) {
        _ = try JSONDecoder().decode(MeshEditPlan.self, from: malformedPlan)
    }
}

@Test(.timeLimit(.minutes(1)))
func meshEditPlanRejectsNonFinitePrimitivePositionsAtInitAndDecode() throws {
    var directError: MeshEditError?
    do {
        _ = try MeshVertexPositionEdit(
            vertexID: MeshVertexID(0),
            position: GeometryPoint3D(x: .nan, y: 0, z: 0)
        )
    } catch let caught as MeshEditError {
        directError = caught
    }
    #expect(directError?.code == .nonFiniteValue)

    let decoder = JSONDecoder()
    decoder.nonConformingFloatDecodingStrategy = .convertFromString(
        positiveInfinity: "INF",
        negativeInfinity: "-INF",
        nan: "NaN"
    )
    let encoded = Data(
        #"{"vertexID":{"rawValue":0},"position":{"x":"NaN","y":0,"z":0}}"#.utf8
    )
    var decodedError: MeshEditError?
    do {
        _ = try decoder.decode(MeshVertexPositionEdit.self, from: encoded)
    } catch let caught as MeshEditError {
        decodedError = caught
    }
    #expect(decodedError?.code == .nonFiniteValue)
}

@Test(.timeLimit(.minutes(1)))
func meshEditPlanEnforcesScanSelectionGenerationAndReceiptBoundaries() throws {
    let source = try makeTriangleSource(identity: "fixture.plan-limits")

    let scanLimitedPlan = try MeshEditPlan(
        steps: [
            MeshEditStep(
                id: MeshEditStepID("scan"),
                operation: .translateElements(
                    .explicit(try MeshSelectionSet(elements: [.vertex(source.vertexIDs[0])])),
                    offset: GeometryVector3D(x: 1, y: 0, z: 0)
                )
            )
        ],
        limits: try MeshEditLimits(maxScannedRecords: 9)
    )
    #expect(try meshEditErrorCode {
        _ = try DefaultMeshEditPlanExecutor().execute(plan: scanLimitedPlan, source: source)
    } == .limitExceeded)

    let thresholdAddFace = MeshEditStep(
        id: MeshEditStepID("threshold-add-face"),
        operation: .primitive(
            .addFace(vertexIDs: [source.vertexIDs[0], source.vertexIDs[2], source.vertexIDs[1]])
        )
    )
    let thresholdPlan = try MeshEditPlan(
        steps: [thresholdAddFace],
        limits: try MeshEditLimits(maxGeneratedIDs: 4, maxReceiptIDs: 4)
    )
    let thresholdResult = try DefaultMeshEditPlanExecutor().execute(
        plan: thresholdPlan,
        source: source
    )
    #expect(thresholdResult.source.faceIDs.count == source.faceIDs.count + 1)

    let selectionLimitedPlan = try MeshEditPlan(
        steps: [
            MeshEditStep(
                id: MeshEditStepID("select"),
                operation: .translateElements(
                    .explicit(try MeshSelectionSet(elements: [.vertex(source.vertexIDs[0])])),
                    offset: GeometryVector3D(x: 1, y: 0, z: 0)
                )
            )
        ],
        limits: try MeshEditLimits(maxSelectedIDs: 0)
    )
    #expect(try meshEditErrorCode {
        _ = try DefaultMeshEditPlanExecutor().execute(plan: selectionLimitedPlan, source: source)
    } == .limitExceeded)

    let generationLimitedPlan = try MeshEditPlan(
        steps: [
            MeshEditStep(
                id: MeshEditStepID("generate"),
                operation: .primitive(
                    .addFace(vertexIDs: [source.vertexIDs[0], source.vertexIDs[2], source.vertexIDs[1]])
                )
            )
        ],
        limits: try MeshEditLimits(maxGeneratedIDs: 3)
    )
    #expect(try meshEditErrorCode {
        _ = try DefaultMeshEditPlanExecutor().execute(plan: generationLimitedPlan, source: source)
    } == .limitExceeded)

    let extrusionStep = MeshEditStep(
        id: MeshEditStepID("receipt"),
        operation: .extrudeFaces(
            .explicit(try MeshSelectionSet(elements: [.face(source.faceIDs[0])])),
            offset: GeometryVector3D(x: 0, y: 0, z: 1)
        )
    )
    let receiptLimitedPlan = try MeshEditPlan(
        steps: [extrusionStep],
        limits: try MeshEditLimits(maxReceiptIDs: 27)
    )
    #expect(try meshEditErrorCode {
        _ = try DefaultMeshEditPlanExecutor().execute(plan: receiptLimitedPlan, source: source)
    } == .limitExceeded)
}

@Test(.timeLimit(.minutes(1)))
func meshEditPlanCountsDenseAndSparseAttributeRecordsBeforeValidation() throws {
    let source = try makeDenselyAndSparselyAttributedTriangle()
    let step = MeshEditStep(
        id: MeshEditStepID("attribute-scan"),
        operation: .translateElements(
            .explicit(try MeshSelectionSet(elements: [.vertex(source.vertexIDs[0])])),
            offset: GeometryVector3D(x: 1, y: 0, z: 0)
        )
    )

    let loweredPlan = try MeshEditPlan(
        steps: [step],
        limits: try MeshEditLimits(maxScannedRecords: 16)
    )
    #expect(try meshEditErrorCode {
        _ = try DefaultMeshEditPlanExecutor().execute(
            plan: loweredPlan,
            source: source
        )
    } == .limitExceeded)

    let thresholdPlan = try MeshEditPlan(
        steps: [step],
        limits: try MeshEditLimits(maxScannedRecords: 17)
    )
    let result = try DefaultMeshEditPlanExecutor().execute(
        plan: thresholdPlan,
        source: source
    )
    #expect(try result.source.position(of: source.vertexIDs[0]).x == 1)
}

@Test(.timeLimit(.minutes(1)))
func meshEditPlanChargesLargeTranslationExpansionBeforeMaterializingOutput() throws {
    var builder = MeshSourceBuilder(identity: "fixture.plan-large-translation")
    try builder.reserveCapacity(vertexCount: 9_000, faceCount: 1, cornerCount: 9_000)
    var vertexIDs: [MeshVertexID] = []
    vertexIDs.reserveCapacity(9_000)
    for index in 0..<9_000 {
        vertexIDs.append(
            try builder.addVertex(
                GeometryPoint3D(x: Double(index), y: 0, z: 0)
            )
        )
    }
    let faceID = try builder.addFace(vertexIDs: vertexIDs)
    let source = try builder.build()
    let step = MeshEditStep(
        id: MeshEditStepID("large-translation"),
        operation: .translateElements(
            .explicit(try MeshSelectionSet(elements: [.face(faceID)])),
            offset: GeometryVector3D(x: 1, y: 0, z: 0)
        )
    )
    let plan = try MeshEditPlan(
        steps: [step],
        limits: try MeshEditLimits(maxSelectedIDs: 8_192)
    )

    #expect(try meshEditErrorCode {
        _ = try DefaultMeshEditPlanExecutor().execute(plan: plan, source: source)
    } == .limitExceeded)
    #expect(try source.position(of: source.vertexIDs[0]).x == 0)
    #expect(source.faceIDs.count == 1)
}

@Test(.timeLimit(.minutes(1)))
func meshEditPlanPreflightsStaticSelectionsAndCumulativeAnalysisLimits() throws {
    let source = try makeTriangleSource(identity: "fixture.plan-static-preflight")
    let validTranslation = MeshEditStep(
        id: MeshEditStepID("valid-translation"),
        operation: .translateElements(
            .explicit(try MeshSelectionSet(elements: [.vertex(source.vertexIDs[0])])),
            offset: GeometryVector3D(x: 1, y: 0, z: 0)
        )
    )
    let invalidPosition = MeshEditStep(
        id: MeshEditStepID("invalid-position"),
        operation: .primitive(
            .setVertexPositions([
                try MeshVertexPositionEdit(
                    vertexID: MeshVertexID(99),
                    position: GeometryPoint3D(x: 0, y: 0, z: 0)
                )
            ])
        )
    )
    let staticLimitPlan = try MeshEditPlan(
        steps: [validTranslation, invalidPosition],
        limits: try MeshEditLimits(maxSelectedIDs: 1)
    )
    #expect(try meshEditErrorCode {
        _ = try DefaultMeshEditPlanExecutor().execute(
            plan: staticLimitPlan,
            source: source
        )
    } == .limitExceeded)
    #expect(try source.position(of: source.vertexIDs[0]) == GeometryPoint3D(x: 0, y: 0, z: 0))

    let first = MeshEditStep(
        id: MeshEditStepID("first-extrusion"),
        operation: .extrudeFaces(
            .explicit(try MeshSelectionSet(elements: [.face(source.faceIDs[0])])),
            offset: GeometryVector3D(x: 0, y: 0, z: 1)
        )
    )
    let second = MeshEditStep(
        id: MeshEditStepID("second-extrusion"),
        operation: .extrudeFaces(
            .output(stepID: first.id, role: .capFaces),
            offset: GeometryVector3D(x: 0, y: 0, z: 1)
        )
    )
    let cumulativeScanPlan = try MeshEditPlan(
        steps: [first, second],
        limits: try MeshEditLimits(maxScannedRecords: 20)
    )
    #expect(try meshEditErrorCode {
        _ = try DefaultMeshEditPlanExecutor().execute(
            plan: cumulativeScanPlan,
            source: source
        )
    } == .limitExceeded)
    #expect(try source.position(of: source.vertexIDs[0]) == GeometryPoint3D(x: 0, y: 0, z: 0))

    let firstStaticAdd = MeshEditStep(
        id: MeshEditStepID("first-static-add"),
        operation: .primitive(
            .addFace(vertexIDs: [source.vertexIDs[0], source.vertexIDs[2], source.vertexIDs[1]])
        )
    )
    let secondStaticAdd = MeshEditStep(
        id: MeshEditStepID("second-static-add"),
        operation: .primitive(
            .addFace(vertexIDs: [source.vertexIDs[0], source.vertexIDs[1], source.vertexIDs[2]])
        )
    )
    let cumulativeStaticGenerationPlan = try MeshEditPlan(
        steps: [firstStaticAdd, secondStaticAdd],
        limits: try MeshEditLimits(maxGeneratedIDs: 7)
    )
    #expect(try meshEditErrorCode {
        _ = try DefaultMeshEditPlanExecutor().execute(
            plan: cumulativeStaticGenerationPlan,
            source: source
        )
    } == .limitExceeded)

    let cumulativeStaticReceiptPlan = try MeshEditPlan(
        steps: [firstStaticAdd, secondStaticAdd],
        limits: try MeshEditLimits(maxReceiptIDs: 7)
    )
    #expect(try meshEditErrorCode {
        _ = try DefaultMeshEditPlanExecutor().execute(
            plan: cumulativeStaticReceiptPlan,
            source: source
        )
    } == .limitExceeded)
}

@Test(.timeLimit(.minutes(1)))
func meshEditPlanChainsOutputsAndDeduplicatesMixedTranslation() throws {
    let source = try makeTriangleSource(identity: "fixture.plan-chain")
    let faceID = source.faceIDs[0]
    let mixedSelection = try MeshSelectionSet(elements: [
        .vertex(source.vertexIDs[0]),
        .edge(source.edgeIDs[0]),
        .face(faceID),
        .corner(source.cornerIDs[0]),
    ])
    let first = MeshEditStep(
        id: MeshEditStepID("move-face"),
        operation: .translateElements(
            .explicit(mixedSelection),
            offset: GeometryVector3D(x: 1, y: 0, z: 0)
        )
    )
    let second = MeshEditStep(
        id: MeshEditStepID("move-again"),
        operation: .translateElements(
            .output(stepID: first.id, role: .affectedVertices),
            offset: GeometryVector3D(x: 0, y: 0, z: 2)
        )
    )
    let plan = try MeshEditPlan(steps: [first, second])
    let result = try DefaultMeshEditPlanExecutor().execute(plan: plan, source: source)

    let firstPosition = try result.source.position(of: MeshVertexID(0))
    let secondPosition = try result.source.position(of: MeshVertexID(1))
    #expect(firstPosition.x == 1)
    #expect(firstPosition.z == 2)
    #expect(secondPosition.x == 2)
    #expect(try result.source.position(of: MeshVertexID(2)).x == 1)
    #expect(result.receipt.stepReceipts.count == 2)
    #expect(result.receipt.stepReceipts[0].outputs[.affectedVertices]?.count == 3)
    #expect(result.receipt.stepReceipts[1].outputs[.affectedVertices]?.count == 3)
}

@Test(.timeLimit(.minutes(1)))
func meshEditPlanPrimitiveParityAndNoOpPreserveSourceStorage() throws {
    let source = try makeTriangleSource(identity: "fixture.plan-primitive")
    let addFaceStep = MeshEditStep(
        id: MeshEditStepID("add"),
        operation: .primitive(
            .addFace(vertexIDs: [MeshVertexID(0), MeshVertexID(2), MeshVertexID(1)])
        )
    )
    let added = try DefaultMeshEditPlanExecutor().execute(
        plan: MeshEditPlan(steps: [addFaceStep]),
        source: source
    )
    #expect(added.source.faceIDs.count == source.faceIDs.count + 1)
    #expect(added.receipt.stepReceipts[0].outputs[.createdFaces]?.count == 1)
    #expect(added.receipt.stepReceipts[0].outputs[.createdEdges] == [])

    let originalVertexChunkIDs = source.vertexIDs.storage.chunkIdentities
    let originalEdgeChunkIDs = source.edgeIDs.storage.chunkIdentities
    let noOpStep = MeshEditStep(
        id: MeshEditStepID("no-op"),
        operation: .translateElements(
            .explicit(try MeshSelectionSet(elements: [.vertex(MeshVertexID(0))])),
            offset: GeometryVector3D(x: 0, y: 0, z: 0)
        )
    )
    let noOp = try DefaultMeshEditPlanExecutor().execute(
        plan: MeshEditPlan(steps: [noOpStep]),
        source: source
    )
    #expect(noOp.source == source)
    #expect(!noOp.receipt.didChange)
    #expect(!noOp.receipt.telemetry.didCopy)
    #expect(noOp.source.vertexIDs.storage.chunkIdentities == originalVertexChunkIDs)
    #expect(noOp.source.edgeIDs.storage.chunkIdentities == originalEdgeChunkIDs)
}

@Test(.timeLimit(.minutes(1)))
func meshEditPlanRetainsApplicableEmptyOutputsAndRollsBack() throws {
    let source = try makeTriangleSource(identity: "fixture.plan-empty-output")
    let addFace = MeshEditStep(
        id: MeshEditStepID("add-existing-edges"),
        operation: .primitive(
            .addFace(vertexIDs: [source.vertexIDs[0], source.vertexIDs[2], source.vertexIDs[1]])
        )
    )
    let consumeEmptyEdges = MeshEditStep(
        id: MeshEditStepID("consume-empty-edges"),
        operation: .translateElements(
            .output(stepID: addFace.id, role: .createdEdges),
            offset: GeometryVector3D(x: 1, y: 0, z: 0)
        )
    )
    let plan = try MeshEditPlan(steps: [addFace, consumeEmptyEdges])

    var error: MeshEditError?
    do {
        _ = try DefaultMeshEditPlanExecutor().execute(plan: plan, source: source)
    } catch let caught as MeshEditError {
        error = caught
    }
    #expect(error?.code == .emptySelection)
    #expect(try source.position(of: source.vertexIDs[0]) == GeometryPoint3D(x: 0, y: 0, z: 0))
    #expect(source.faceIDs.count == 1)
}

@Test(.timeLimit(.minutes(1)))
func meshEditPlanExtrudesConnectedRegionWithPersistentTopologyOutputs() throws {
    let source = try makeTriangleSource(identity: "fixture.plan-extrude")
    let faceID = source.faceIDs[0]
    let step = MeshEditStep(
        id: MeshEditStepID("extrude"),
        operation: .extrudeFaces(
            .explicit(try MeshSelectionSet(elements: [.face(faceID)])),
            offset: GeometryVector3D(x: 0, y: 0, z: 1)
        )
    )
    let result = try DefaultMeshEditPlanExecutor().execute(
        plan: MeshEditPlan(steps: [step]),
        source: source
    )
    let output = result.receipt.stepReceipts[0]
    #expect(output.outputs[.createdVertices]?.count == 3)
    #expect(output.outputs[.createdEdges]?.count == 6)
    #expect(output.outputs[.createdFaces]?.count == 3)
    #expect(output.outputs[.capFaces] == [.face(faceID)])
    #expect(output.outputs[.sideFaces] == output.outputs[.createdFaces])
    #expect(output.outputs[.createdCorners]?.count == 12)
    #expect(output.outputs[.createdVertices] == [
        .vertex(MeshVertexID(3)),
        .vertex(MeshVertexID(4)),
        .vertex(MeshVertexID(5)),
    ])
    #expect(output.outputs[.createdEdges] == [
        .edge(MeshEdgeID(3)),
        .edge(MeshEdgeID(4)),
        .edge(MeshEdgeID(5)),
        .edge(MeshEdgeID(6)),
        .edge(MeshEdgeID(7)),
        .edge(MeshEdgeID(8)),
    ])
    #expect(output.outputs[.createdFaces] == [
        .face(MeshFaceID(1)),
        .face(MeshFaceID(2)),
        .face(MeshFaceID(3)),
    ])
    #expect(output.outputs[.createdCorners] == (3..<15).map {
        .corner(MeshCornerID($0))
    })
    #expect(result.source.vertexIDs.count == 6)
    #expect(result.source.faceIDs.count == 4)
    #expect(try result.source.position(of: MeshVertexID(3)) == GeometryPoint3D(x: 0, y: 0, z: 1))
    #expect(try result.source.faceLoop(for: faceID).map {
        try result.source.vertexID(of: $0)
    } == [MeshVertexID(3), MeshVertexID(4), MeshVertexID(5)])
    #expect(result.receipt.telemetry.copiedBytes <= MeshEditLimits.standard.maxCopiedBytes)

    let repeated = try DefaultMeshEditPlanExecutor().execute(
        plan: MeshEditPlan(steps: [step]),
        source: source
    )
    #expect(repeated.source == result.source)
    #expect(repeated.receipt == result.receipt)
}

@Test(.timeLimit(.minutes(1)))
func meshEditPlanExtrusionOutputsCanDriveTranslationAndRepeatedCapExtrusion() throws {
    let source = try makeTriangleSource(identity: "fixture.plan-extrude-chain")
    let faceID = source.faceIDs[0]
    let extrusion = MeshEditStep(
        id: MeshEditStepID("extrude-once"),
        operation: .extrudeFaces(
            .explicit(try MeshSelectionSet(elements: [.face(faceID)])),
            offset: GeometryVector3D(x: 0, y: 0, z: 1)
        )
    )
    let translate = MeshEditStep(
        id: MeshEditStepID("translate-created"),
        operation: .translateElements(
            .output(stepID: extrusion.id, role: .createdVertices),
            offset: GeometryVector3D(x: 1, y: 0, z: 0)
        )
    )
    let translated = try DefaultMeshEditPlanExecutor().execute(
        plan: MeshEditPlan(steps: [extrusion, translate]),
        source: source
    )
    #expect(try translated.source.position(of: MeshVertexID(3)) == GeometryPoint3D(x: 1, y: 0, z: 1))
    #expect(try translated.source.position(of: MeshVertexID(4)) == GeometryPoint3D(x: 2, y: 0, z: 1))
    #expect(try translated.source.position(of: MeshVertexID(5)) == GeometryPoint3D(x: 1, y: 1, z: 1))
    #expect(translated.receipt.stepReceipts[1].outputs[.affectedVertices] == [
        .vertex(MeshVertexID(3)),
        .vertex(MeshVertexID(4)),
        .vertex(MeshVertexID(5)),
    ])

    let repeatedExtrusion = MeshEditStep(
        id: MeshEditStepID("extrude-cap"),
        operation: .extrudeFaces(
            .output(stepID: extrusion.id, role: .capFaces),
            offset: GeometryVector3D(x: 0, y: 0, z: 1)
        )
    )
    let repeated = try DefaultMeshEditPlanExecutor().execute(
        plan: MeshEditPlan(steps: [extrusion, repeatedExtrusion]),
        source: source
    )
    #expect(repeated.source.vertexIDs.count == 9)
    #expect(repeated.source.faceIDs.count == 7)
    #expect(try repeated.source.position(of: MeshVertexID(6)) == GeometryPoint3D(x: 0, y: 0, z: 2))
    #expect(try repeated.source.position(of: MeshVertexID(7)) == GeometryPoint3D(x: 1, y: 0, z: 2))
    #expect(try repeated.source.position(of: MeshVertexID(8)) == GeometryPoint3D(x: 0, y: 1, z: 2))
    #expect(repeated.receipt.stepReceipts[1].outputs[.createdVertices] == [
        .vertex(MeshVertexID(6)),
        .vertex(MeshVertexID(7)),
        .vertex(MeshVertexID(8)),
    ])
}

@Test(.timeLimit(.minutes(1)))
func meshEditPlanExtrudesConnectedMultiFaceRegionWithSharedTopology() throws {
    let source = try makeQuadTrianglePair()
    let selection = try MeshSelectionSet(elements: source.faceIDs.map(MeshSelectionElement.face))
    let step = MeshEditStep(
        id: MeshEditStepID("extrude-region"),
        operation: .extrudeFaces(
            .explicit(selection),
            offset: GeometryVector3D(x: 0, y: 0, z: 1)
        )
    )
    let result = try DefaultMeshEditPlanExecutor().execute(
        plan: MeshEditPlan(steps: [step]),
        source: source
    )
    let output = result.receipt.stepReceipts[0].outputs
    #expect(output[.createdVertices] == (4..<8).map { .vertex(MeshVertexID($0)) })
    #expect(output[.createdEdges] == (5..<13).map { .edge(MeshEdgeID($0)) })
    #expect(output[.createdFaces] == (2..<6).map { .face(MeshFaceID($0)) })
    #expect(output[.capFaces] == [.face(MeshFaceID(0)), .face(MeshFaceID(1))])
    #expect(output[.createdCorners] == (6..<22).map { .corner(MeshCornerID($0)) })
    #expect(result.source.vertexIDs.count == 8)
    #expect(result.source.faceIDs.count == 6)
    #expect(try result.source.position(of: MeshVertexID(7)) == GeometryPoint3D(x: 0, y: 1, z: 1))
}

@Test(.timeLimit(.minutes(1)))
func meshEditPlanExtrudesConnectedRegionWithMultipleBoundaryLoops() throws {
    let source = try makeAnnulusRegion()
    let selection = try MeshSelectionSet(
        elements: source.faceIDs.map(MeshSelectionElement.face)
    )
    let step = MeshEditStep(
        id: MeshEditStepID("extrude-annulus"),
        operation: .extrudeFaces(
            .explicit(selection),
            offset: GeometryVector3D(x: 0, y: 0, z: 1)
        )
    )
    let result = try DefaultMeshEditPlanExecutor().execute(
        plan: MeshEditPlan(steps: [step]),
        source: source
    )
    let outputs = result.receipt.stepReceipts[0].outputs
    #expect(outputs[.createdVertices]?.count == 8)
    #expect(outputs[.createdEdges]?.count == 16)
    #expect(outputs[.createdFaces]?.count == 8)
    #expect(outputs[.capFaces]?.count == 4)
    #expect(outputs[.sideFaces]?.count == 8)
    #expect(outputs[.createdCorners]?.count == 32)
    #expect(result.source.vertexIDs.count == source.vertexIDs.count + 8)
    #expect(result.source.faceIDs.count == source.faceIDs.count + 8)
}

@Test(.timeLimit(.minutes(1)))
func meshEditPlanRejectsClosedFaceRegions() throws {
    let source = try makeClosedTetrahedron()
    let selection = try MeshSelectionSet(
        elements: source.faceIDs.map(MeshSelectionElement.face)
    )
    let step = MeshEditStep(
        id: MeshEditStepID("extrude-closed"),
        operation: .extrudeFaces(
            .explicit(selection),
            offset: GeometryVector3D(x: 0, y: 0, z: 1)
        )
    )
    #expect(try meshEditErrorCode {
        _ = try DefaultMeshEditPlanExecutor().execute(
            plan: MeshEditPlan(steps: [step]),
            source: source
        )
    } == .invalidFaceRegion)
}

@Test(.timeLimit(.minutes(1)))
func meshEditPlanRejectsInvalidExtrusionRegionsAndAttributes() throws {
    let disconnected = try makeDisconnectedTriangles()
    let disconnectedSelection = try MeshSelectionSet(
        elements: disconnected.faceIDs.map(MeshSelectionElement.face)
    )
    let disconnectedStep = MeshEditStep(
        id: MeshEditStepID("disconnected"),
        operation: .extrudeFaces(
            .explicit(disconnectedSelection),
            offset: GeometryVector3D(x: 0, y: 0, z: 1)
        )
    )
    var error: MeshEditError?
    do {
        _ = try DefaultMeshEditPlanExecutor().execute(
            plan: MeshEditPlan(steps: [disconnectedStep]),
            source: disconnected
        )
    } catch let caught as MeshEditError {
        error = caught
    }
    #expect(error?.code == .disconnectedFaceRegion)

    let inconsistent = try makeInconsistentlyOrientedPair()
    let inconsistentStep = MeshEditStep(
        id: MeshEditStepID("inconsistent"),
        operation: .extrudeFaces(
            .explicit(try MeshSelectionSet(elements: inconsistent.faceIDs.map(MeshSelectionElement.face))),
            offset: GeometryVector3D(x: 0, y: 0, z: 1)
        )
    )
    error = nil
    do {
        _ = try DefaultMeshEditPlanExecutor().execute(
            plan: MeshEditPlan(steps: [inconsistentStep]),
            source: inconsistent
        )
    } catch let caught as MeshEditError {
        error = caught
    }
    #expect(error?.code == .inconsistentFaceOrientation)

    let attributed = try makeAttributedTriangle()
    let topologyStep = MeshEditStep(
        id: MeshEditStepID("topology"),
        operation: .primitive(
            .addFace(vertexIDs: [MeshVertexID(0), MeshVertexID(2), MeshVertexID(1)])
        )
    )
    error = nil
    do {
        _ = try DefaultMeshEditPlanExecutor().execute(
            plan: MeshEditPlan(steps: [topologyStep]),
            source: attributed
        )
    } catch let caught as MeshEditError {
        error = caught
    }
    #expect(error?.code == .topologyAttributeRemappingUnsupported)

    var directBuffer = MeshEditBuffer(source: attributed)
    var directError: MeshSourceError?
    do {
        _ = try directBuffer.addVertex(GeometryPoint3D(x: 0, y: 0, z: 1))
    } catch let caught as MeshSourceError {
        directError = caught
    }
    #expect(directError?.code == .unsupportedOperation)
    #expect(!directBuffer.hasEdits)
    directError = nil
    do {
        _ = try directBuffer.addFace(vertexIDs: [
            attributed.vertexIDs[0],
            attributed.vertexIDs[1],
            attributed.vertexIDs[2],
        ])
    } catch let caught as MeshSourceError {
        directError = caught
    }
    #expect(directError?.code == .unsupportedOperation)
    #expect(!directBuffer.hasEdits)
    directError = nil
    do {
        try directBuffer.deleteFace(attributed.faceIDs[0])
    } catch let caught as MeshSourceError {
        directError = caught
    }
    #expect(directError?.code == .unsupportedOperation)
    #expect(!directBuffer.hasEdits)

    let nonManifold = try makeNonManifoldTriangleFan()
    let nonManifoldStep = MeshEditStep(
        id: MeshEditStepID("non-manifold"),
        operation: .extrudeFaces(
            .explicit(try MeshSelectionSet(elements: [.face(nonManifold.faceIDs[0])])),
            offset: GeometryVector3D(x: 0, y: 0, z: 1)
        )
    )
    error = nil
    do {
        _ = try DefaultMeshEditPlanExecutor().execute(
            plan: MeshEditPlan(steps: [nonManifoldStep]),
            source: nonManifold
        )
    } catch let caught as MeshEditError {
        error = caught
    }
    #expect(error?.code == .nonManifoldFaceRegion)
}

@Test(.timeLimit(.minutes(1)))
func meshEditPlanRollsBackWhenAnyPersistentIDDomainIsExhausted() throws {
    let states: [(String, MeshElementIDAllocationState)] = [
        (
            "vertex",
            MeshElementIDAllocationState(
                nextVertexID: nil,
                nextEdgeID: MeshEdgeID(3),
                nextFaceID: MeshFaceID(1),
                nextCornerID: MeshCornerID(3)
            )
        ),
        (
            "edge",
            MeshElementIDAllocationState(
                nextVertexID: MeshVertexID(3),
                nextEdgeID: nil,
                nextFaceID: MeshFaceID(1),
                nextCornerID: MeshCornerID(3)
            )
        ),
        (
            "face",
            MeshElementIDAllocationState(
                nextVertexID: MeshVertexID(3),
                nextEdgeID: MeshEdgeID(3),
                nextFaceID: nil,
                nextCornerID: MeshCornerID(3)
            )
        ),
        (
            "corner",
            MeshElementIDAllocationState(
                nextVertexID: MeshVertexID(3),
                nextEdgeID: MeshEdgeID(3),
                nextFaceID: MeshFaceID(1),
                nextCornerID: nil
            )
        ),
    ]

    for (label, allocationState) in states {
        let source = try makeTriangleSource(
            identity: GeometrySourceID(rawValue: "fixture.plan-exhausted-\(label)"),
            allocationState: allocationState
        )
        let preflightBuffer = MeshEditBuffer(source: source)
        var preflightError: MeshSourceError?
        do {
            try preflightBuffer.preflightAllocation(
                vertexCount: 3,
                edgeCount: 6,
                faceCount: 3,
                cornerCount: 12
            )
        } catch let caught as MeshSourceError {
            preflightError = caught
        }
        #expect(preflightError?.code == .idSpaceExhausted)
        #expect(!preflightBuffer.hasEdits)

        let step = MeshEditStep(
            id: MeshEditStepID("extrude-\(label)"),
            operation: .extrudeFaces(
                .explicit(try MeshSelectionSet(elements: [.face(source.faceIDs[0])])),
                offset: GeometryVector3D(x: 0, y: 0, z: 1)
            )
        )
        #expect(try meshEditErrorCode {
            _ = try DefaultMeshEditPlanExecutor().execute(
                plan: MeshEditPlan(steps: [step]),
                source: source
            )
        } == .sourceMutation)
        #expect(source.vertexIDs.count == 3)
        #expect(source.edgeIDs.count == 3)
        #expect(source.faceIDs.count == 1)
        #expect(source.cornerIDs.count == 3)
    }
}

@Test(.timeLimit(.minutes(1)))
func meshEditPlanRollbackAndCopyBudgetAreTypedFailures() throws {
    let source = try makeTriangleSource(identity: "fixture.plan-rollback")
    let plan = try MeshEditPlan(steps: [
        MeshEditStep(
            id: MeshEditStepID("valid"),
            operation: .translateElements(
                .explicit(try MeshSelectionSet(elements: [.vertex(MeshVertexID(0))])),
                offset: GeometryVector3D(x: 1, y: 0, z: 0)
            )
        ),
        MeshEditStep(
            id: MeshEditStepID("invalid"),
            operation: .primitive(
                .setVertexPositions([
                    try MeshVertexPositionEdit(
                        vertexID: MeshVertexID(99),
                        position: GeometryPoint3D(x: 0, y: 0, z: 0)
                    )
                ])
            )
        ),
    ])
    var error: MeshEditError?
    do {
        _ = try DefaultMeshEditPlanExecutor().execute(plan: plan, source: source)
    } catch let caught as MeshEditError {
        error = caught
    }
    #expect(error?.code == .sourceMutation)
    #expect(try source.position(of: MeshVertexID(0)).x == 0)

    let constrainedLimits = try MeshEditLimits(maxCopiedBytes: 0)
    let constrainedPlan = try MeshEditPlan(
        steps: [
            MeshEditStep(
                id: MeshEditStepID("move"),
                operation: .translateElements(
                    .explicit(try MeshSelectionSet(elements: [.vertex(MeshVertexID(0))])),
                    offset: GeometryVector3D(x: 1, y: 0, z: 0)
                )
            )
        ],
        limits: constrainedLimits
    )
    error = nil
    do {
        _ = try DefaultMeshEditPlanExecutor().execute(plan: constrainedPlan, source: source)
    } catch let caught as MeshEditError {
        error = caught
    }
    #expect(error?.code == .copyBudgetExceeded)
}

@Test(.timeLimit(.minutes(1)))
func meshEditPlanTranslationPreservesAttributedMeshAndDeterministicIDs() throws {
    let source = try makeAttributedTriangle()
    let selection = try MeshSelectionSet(elements: [.face(source.faceIDs[0])])
    let step = MeshEditStep(
        id: MeshEditStepID("translate"),
        operation: .translateElements(
            .explicit(selection),
            offset: GeometryVector3D(x: 0, y: 0, z: 2)
        )
    )
    let plan = try MeshEditPlan(steps: [step])
    let first = try DefaultMeshEditPlanExecutor().execute(plan: plan, source: source)
    let second = try DefaultMeshEditPlanExecutor().execute(plan: plan, source: source)

    #expect(first.source.attributes == source.attributes)
    #expect(try first.source.position(of: MeshVertexID(0)).z == 2)
    #expect(first.source == second.source)
    #expect(first.receipt == second.receipt)
}

@Test(.timeLimit(.minutes(1)))
func meshEditPlanTranslationPreservesUnchangedTopologyStorage() throws {
    let source = try makeTriangleSource(identity: "fixture.plan-storage")
    let step = MeshEditStep(
        id: MeshEditStepID("move-one"),
        operation: .translateElements(
            .explicit(try MeshSelectionSet(elements: [.vertex(source.vertexIDs[0])])),
            offset: GeometryVector3D(x: 0, y: 0, z: 1)
        )
    )
    let result = try DefaultMeshEditPlanExecutor().execute(
        plan: MeshEditPlan(steps: [step]),
        source: source
    )

    #expect(result.source.vertexIDs.storage.chunkIdentities == source.vertexIDs.storage.chunkIdentities)
    #expect(result.source.edgeIDs.storage.chunkIdentities == source.edgeIDs.storage.chunkIdentities)
    #expect(result.source.edgeEndpoints.storage.chunkIdentities == source.edgeEndpoints.storage.chunkIdentities)
    #expect(result.source.faceIDs.storage.chunkIdentities == source.faceIDs.storage.chunkIdentities)
    #expect(result.source.faceCornerRanges.storage.chunkIdentities == source.faceCornerRanges.storage.chunkIdentities)
    #expect(result.source.cornerIDs.storage.chunkIdentities == source.cornerIDs.storage.chunkIdentities)
    #expect(result.source.cornerVertexIDs.storage.chunkIdentities == source.cornerVertexIDs.storage.chunkIdentities)
    #expect(result.source.cornerEdgeIDs.storage.chunkIdentities == source.cornerEdgeIDs.storage.chunkIdentities)
}

@Test(.timeLimit(.minutes(1)))
func meshEditPlanTopologyAppendPreservesEarlierChunksAndMeasuresTailCopies() throws {
    var builder = MeshSourceBuilder(identity: "fixture.plan-multi-chunk-topology")
    try builder.reserveCapacity(vertexCount: 6_150, faceCount: 2_050, cornerCount: 6_150)
    for index in 0..<2_050 {
        let first = try builder.addVertex(
            GeometryPoint3D(x: Double(index * 3), y: 0, z: 0)
        )
        let second = try builder.addVertex(
            GeometryPoint3D(x: Double(index * 3 + 1), y: 0, z: 0)
        )
        let third = try builder.addVertex(
            GeometryPoint3D(x: Double(index * 3), y: 1, z: 0)
        )
        _ = try builder.addTriangle(first, second, third)
    }
    let source = try builder.build()
    let addFace = MeshEditStep(
        id: MeshEditStepID("append-tail"),
        operation: .primitive(
            .addFace(vertexIDs: [source.vertexIDs[0], source.vertexIDs[2], source.vertexIDs[1]])
        )
    )
    let result = try DefaultMeshEditPlanExecutor().execute(
        plan: MeshEditPlan(steps: [addFace]),
        source: source
    )

    #expect(result.source.faceIDs.count == source.faceIDs.count + 1)
    #expect(result.source.cornerIDs.count == source.cornerIDs.count + 3)
    #expect(result.receipt.telemetry.copiedBytes > 0)
    #expect(result.receipt.telemetry.copiedBytes <= MeshEditLimits.standard.maxCopiedBytes)
    #expect(result.receipt.telemetry.events.allSatisfy { $0.reason == .sourceEdit })
    #expect(result.source.vertexIDs.storage.chunkIdentities == source.vertexIDs.storage.chunkIdentities)
    #expect(result.source.vertexPositions.storage.chunkIdentities == source.vertexPositions.storage.chunkIdentities)
    #expect(result.source.edgeIDs.storage.chunkIdentities == source.edgeIDs.storage.chunkIdentities)
    #expect(result.source.edgeEndpoints.storage.chunkIdentities == source.edgeEndpoints.storage.chunkIdentities)
    #expect(result.source.faceIDs.storage.chunkIdentities.first == source.faceIDs.storage.chunkIdentities.first)
    #expect(result.source.faceCornerRanges.storage.chunkIdentities.first == source.faceCornerRanges.storage.chunkIdentities.first)
    #expect(result.source.cornerIDs.storage.chunkIdentities.first == source.cornerIDs.storage.chunkIdentities.first)
    #expect(result.source.cornerVertexIDs.storage.chunkIdentities.first == source.cornerVertexIDs.storage.chunkIdentities.first)
    #expect(result.source.cornerEdgeIDs.storage.chunkIdentities.first == source.cornerEdgeIDs.storage.chunkIdentities.first)
}

private func makeTriangleSource(identity: GeometrySourceID) throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: identity)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addTriangle(first, second, third)
    return try builder.build()
}

private func makeTriangleSource(
    identity: GeometrySourceID,
    allocationState: MeshElementIDAllocationState
) throws -> MeshSource {
    let source = try makeTriangleSource(identity: identity)
    return try MeshSource(
        identity: source.identity,
        allocationState: allocationState,
        vertexIDs: source.vertexIDs,
        vertexPositions: source.vertexPositions,
        edgeIDs: source.edgeIDs,
        edgeEndpoints: source.edgeEndpoints,
        faceIDs: source.faceIDs,
        faceCornerRanges: source.faceCornerRanges,
        cornerIDs: source.cornerIDs,
        cornerVertexIDs: source.cornerVertexIDs,
        cornerEdgeIDs: source.cornerEdgeIDs,
        attributes: source.attributes
    )
}

private func makeAnnulusRegion() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: "fixture.plan-annulus")
    let outer = try [
        GeometryPoint3D(x: -2, y: -2, z: 0),
        GeometryPoint3D(x: 2, y: -2, z: 0),
        GeometryPoint3D(x: 2, y: 2, z: 0),
        GeometryPoint3D(x: -2, y: 2, z: 0),
    ].map { try builder.addVertex($0) }
    let inner = try [
        GeometryPoint3D(x: -1, y: -1, z: 0),
        GeometryPoint3D(x: 1, y: -1, z: 0),
        GeometryPoint3D(x: 1, y: 1, z: 0),
        GeometryPoint3D(x: -1, y: 1, z: 0),
    ].map { try builder.addVertex($0) }
    for index in 0..<4 {
        let next = (index + 1) % 4
        _ = try builder.addFace(vertexIDs: [
            outer[index],
            outer[next],
            inner[next],
            inner[index],
        ])
    }
    return try builder.build()
}

private func makeClosedTetrahedron() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: "fixture.plan-closed")
    let v0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let v1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let v2 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    let v3 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 1))
    _ = try builder.addTriangle(v0, v2, v1)
    _ = try builder.addTriangle(v0, v1, v3)
    _ = try builder.addTriangle(v1, v2, v3)
    _ = try builder.addTriangle(v0, v3, v2)
    return try builder.build()
}

private func makeDisconnectedTriangles() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: "fixture.plan-disconnected")
    let a0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let a1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let a2 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    let b0 = try builder.addVertex(GeometryPoint3D(x: 4, y: 0, z: 0))
    let b1 = try builder.addVertex(GeometryPoint3D(x: 5, y: 0, z: 0))
    let b2 = try builder.addVertex(GeometryPoint3D(x: 4, y: 1, z: 0))
    _ = try builder.addTriangle(a0, a1, a2)
    _ = try builder.addTriangle(b0, b1, b2)
    return try builder.build()
}

private func makeInconsistentlyOrientedPair() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: "fixture.plan-inconsistent")
    let v0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let v1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let v2 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    let v3 = try builder.addVertex(GeometryPoint3D(x: 1, y: 1, z: 0))
    _ = try builder.addTriangle(v0, v1, v2)
    _ = try builder.addTriangle(v0, v1, v3)
    return try builder.build()
}

private func makeAttributedTriangle() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: "fixture.plan-attributed")
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addTriangle(first, second, third)
    try builder.setAttribute(
        GeometryAttributeLayer(
            descriptor: GeometryAttributeDescriptor(
                id: "normal",
                name: "Normal",
                domain: .vertex,
                valueType: .vector3,
                interpolation: .linear
            ),
            values: .vector3(GeometryBuffer([
                GeometryPoint3D(x: 0, y: 0, z: 1),
                GeometryPoint3D(x: 0, y: 0, z: 1),
                GeometryPoint3D(x: 0, y: 0, z: 1),
            ]))
        )
    )
    return try builder.build()
}

private func makeDenselyAndSparselyAttributedTriangle() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: "fixture.plan-attribute-scan")
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addTriangle(first, second, third)
    try builder.setAttribute(
        GeometryAttributeLayer(
            descriptor: GeometryAttributeDescriptor(
                id: "dense.normal",
                name: "Dense Normal",
                domain: .vertex,
                valueType: .vector3,
                interpolation: .linear
            ),
            values: .vector3(GeometryBuffer([
                GeometryPoint3D(x: 0, y: 0, z: 1),
                GeometryPoint3D(x: 0, y: 0, z: 1),
                GeometryPoint3D(x: 0, y: 0, z: 1),
            ]))
        )
    )
    try builder.setAttribute(
        GeometryAttributeLayer(
            descriptor: GeometryAttributeDescriptor(
                id: "sparse.color",
                name: "Sparse Color",
                domain: .vertex,
                valueType: .vector4,
                interpolation: .linear,
                isSparse: true
            ),
            values: .vector4(GeometryBuffer([
                GeometryVector4D(x: 1, y: 2, z: 3, w: 4),
                GeometryVector4D(x: 5, y: 6, z: 7, w: 8),
            ])),
            indices: GeometryBuffer([UInt32(0), UInt32(2)])
        )
    )
    return try builder.build()
}

private func makeNonManifoldTriangleFan() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: "fixture.plan-non-manifold")
    let v0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let v1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let v2 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    let v3 = try builder.addVertex(GeometryPoint3D(x: 0, y: -1, z: 0))
    let v4 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 1))
    _ = try builder.addTriangle(v0, v1, v2)
    _ = try builder.addTriangle(v1, v0, v3)
    _ = try builder.addTriangle(v0, v1, v4)
    return try builder.build()
}

private func makeQuadTrianglePair() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: "fixture.plan-quad-region")
    let v0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let v1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let v2 = try builder.addVertex(GeometryPoint3D(x: 1, y: 1, z: 0))
    let v3 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addTriangle(v0, v1, v2)
    _ = try builder.addTriangle(v0, v2, v3)
    return try builder.build()
}

private func meshEditErrorCode(
    _ operation: () throws -> Void
) throws -> MeshEditError.Code? {
    do {
        try operation()
        return nil
    } catch let error as MeshEditError {
        return error.code
    } catch {
        return nil
    }
}
