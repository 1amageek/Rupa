import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Test(.timeLimit(.minutes(1)))
func meshValidationRegionRoundTripsWithMaterializedArtifactIdentity() throws {
    let documentID = DocumentID()
    let firstBodyID = BodyID()
    let secondBodyID = BodyID()
    let artifact = try meshArtifact(documentID: documentID)
    let reference = ValidationRegionReference(
        id: "fixture.mesh-region",
        documentID: documentID,
        target: .meshTriangles(
            artifact: artifact,
            selections: [
                ValidationMeshTriangleSelection(
                    bodyID: firstBodyID,
                    triangleRanges: [
                        ValidationElementRange(startIndex: 0, count: 4),
                        ValidationElementRange(startIndex: 8, count: 2),
                    ]
                ),
                ValidationMeshTriangleSelection(
                    bodyID: secondBodyID,
                    triangleRanges: [
                        ValidationElementRange(startIndex: 3, count: 1),
                    ]
                ),
            ]
        )
    )

    try reference.validate()
    let data = try JSONEncoder().encode(reference)
    let decoded = try JSONDecoder().decode(ValidationRegionReference.self, from: data)

    #expect(decoded == reference)
    #expect(decoded.kind == .meshTriangles)
    #expect(artifact.artifact.kind == .mesh)
    #expect(artifact.producer.id == "fixture.mesh-evaluator")
    #expect(
        artifact.artifact.computation.configuration.fingerprint.algorithm
            == "sha256-artifact-configuration-v1"
    )
    #expect(artifact.artifact.contentFingerprint.algorithm == "fixture-mesh-content-v1")
}

@Test(.timeLimit(.minutes(1)))
func meshValidationRegionRejectsDocumentMismatch() throws {
    let artifactDocumentID = DocumentID()
    let artifact = try meshArtifact(documentID: artifactDocumentID)
    let selection = ValidationMeshTriangleSelection(
        bodyID: BodyID(),
        triangleRanges: [ValidationElementRange(startIndex: 0, count: 1)]
    )
    let reference = ValidationRegionReference(
        id: "fixture.mismatched-document",
        documentID: DocumentID(),
        target: .meshTriangles(artifact: artifact, selections: [selection])
    )

    var caught: ReferenceValidationError?
    do {
        try reference.validate()
    } catch let error as ReferenceValidationError {
        caught = error
    }
    #expect(caught?.code == .documentMismatch)
}

@Test(.timeLimit(.minutes(1)))
func meshArtifactDecodingRejectsConfigurationTampering() throws {
    let artifact = try meshArtifact(documentID: DocumentID())
    let encoded = try JSONEncoder().encode(artifact)
    var object = try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    var configuration = try #require(object["configuration"] as? [String: Any])
    var tolerance = try #require(configuration["modelingTolerance"] as? [String: Any])
    tolerance["distance"] = 0.25
    configuration["modelingTolerance"] = tolerance
    object["configuration"] = configuration
    let tampered = try JSONSerialization.data(withJSONObject: object)

    #expect(throws: ReferenceValidationError.self) {
        try JSONDecoder().decode(MeshArtifactReference.self, from: tampered)
    }
}

@Test(.timeLimit(.minutes(1)))
func meshValidationRegionRejectsDuplicateBodiesAndOverlappingRanges() throws {
    let documentID = DocumentID()
    let artifact = try meshArtifact(documentID: documentID)
    let bodyID = BodyID()
    let duplicateBodyReference = ValidationRegionReference(
        id: "fixture.duplicate-body",
        documentID: documentID,
        target: .meshTriangles(
            artifact: artifact,
            selections: [
                ValidationMeshTriangleSelection(
                    bodyID: bodyID,
                    triangleRanges: [ValidationElementRange(startIndex: 0, count: 1)]
                ),
                ValidationMeshTriangleSelection(
                    bodyID: bodyID,
                    triangleRanges: [ValidationElementRange(startIndex: 2, count: 1)]
                ),
            ]
        )
    )
    let overlappingRangeReference = ValidationRegionReference(
        id: "fixture.overlapping-ranges",
        documentID: documentID,
        target: .meshTriangles(
            artifact: artifact,
            selections: [
                ValidationMeshTriangleSelection(
                    bodyID: bodyID,
                    triangleRanges: [
                        ValidationElementRange(startIndex: 0, count: 3),
                        ValidationElementRange(startIndex: 2, count: 2),
                    ]
                ),
            ]
        )
    )

    #expect(throws: ReferenceValidationError.self) {
        try duplicateBodyReference.validate()
    }
    #expect(throws: ReferenceValidationError.self) {
        try overlappingRangeReference.validate()
    }
}

@Test(.timeLimit(.minutes(1)))
func meshContentFingerprintIsOrderIndependentAndContentSensitive() throws {
    let firstUUID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let secondUUID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
    let firstBodyID = BodyID(firstUUID)
    let secondBodyID = BodyID(secondUUID)
    let firstMesh = triangleMesh(offset: 0.0)
    let secondMesh = triangleMesh(offset: 2.0)
    let service = MeshContentFingerprintService()

    var firstOrder: [BodyID: Mesh] = [:]
    firstOrder[firstBodyID] = firstMesh
    firstOrder[secondBodyID] = secondMesh
    var secondOrder: [BodyID: Mesh] = [:]
    secondOrder[secondBodyID] = secondMesh
    secondOrder[firstBodyID] = firstMesh

    let firstFingerprint = try service.fingerprint(for: firstOrder)
    let secondFingerprint = try service.fingerprint(for: secondOrder)
    var changedMesh = firstMesh
    changedMesh.positions[0].x = changedMesh.positions[0].x.nextUp
    let changedFingerprint = try service.fingerprint(
        for: [firstBodyID: changedMesh, secondBodyID: secondMesh]
    )

    #expect(firstFingerprint == secondFingerprint)
    #expect(firstFingerprint != changedFingerprint)
}

@Test(.timeLimit(.minutes(1)))
func artifactIdentitySeparatesComputationConfigurationFromOutputContent() throws {
    let documentID = DocumentID()
    let sourceDependencies = try fixtureSourceDependencies(documentID: documentID)
    let contentFingerprint = try MeshContentFingerprintService().fingerprint(
        for: [BodyID(): triangleMesh(offset: 0.0)]
    )
    let standard = try MeshArtifactConfiguration(
        kernelVersion: SchemaVersion(major: 1, minor: 0, patch: 0),
        modelingTolerance: .standard,
        tessellationOptions: .standard
    )
    let refined = try MeshArtifactConfiguration(
        kernelVersion: SchemaVersion(major: 1, minor: 0, patch: 0),
        modelingTolerance: .standard,
        tessellationOptions: TessellationOptions(
            linearTolerance: TessellationOptions.standard.linearTolerance * 0.5,
            angularTolerance: TessellationOptions.standard.angularTolerance
        )
    )
    let producer = ArtifactProducerReference(id: "fixture.mesh-evaluator", version: "1.0.0")
    let first = try MeshArtifactReference(
        documentID: documentID,
        sourceDependencies: sourceDependencies,
        producer: producer,
        configuration: standard,
        contentFingerprint: contentFingerprint
    )
    let second = try MeshArtifactReference(
        documentID: documentID,
        sourceDependencies: sourceDependencies,
        producer: producer,
        configuration: refined,
        contentFingerprint: contentFingerprint
    )

    #expect(first.artifact.contentFingerprint == second.artifact.contentFingerprint)
    #expect(first.artifact.computation.fingerprint != second.artifact.computation.fingerprint)
    #expect(first.artifact.fingerprint != second.artifact.fingerprint)
}

@Test(.timeLimit(.minutes(1)))
func projectionDependencyIdentityMatchesAcrossUnrelatedGenerationChanges() throws {
    let documentID = DocumentID()
    let first = ProjectionDependencyIdentity(
        documentID: documentID,
        generation: DocumentGeneration(2),
        fingerprint: try .init(
            algorithm: "fixture-dependency-v1",
            value: "same-dependencies"
        )
    )
    let second = ProjectionDependencyIdentity(
        documentID: documentID,
        generation: DocumentGeneration(9),
        fingerprint: first.fingerprint
    )
    let otherDocument = ProjectionDependencyIdentity(
        documentID: DocumentID(),
        generation: DocumentGeneration(9),
        fingerprint: first.fingerprint
    )

    #expect(first.matchesDependencies(of: second))
    #expect(!first.matchesDependencies(of: otherDocument))
}

private func meshArtifact(documentID: DocumentID) throws -> MeshArtifactReference {
    try MeshArtifactReference(
        documentID: documentID,
        sourceDependencies: fixtureSourceDependencies(documentID: documentID),
        producer: ArtifactProducerReference(
            id: "fixture.mesh-evaluator",
            version: "1.2.3"
        ),
        configuration: MeshArtifactConfiguration(
            kernelVersion: .current,
            modelingTolerance: .standard,
            tessellationOptions: .standard
        ),
        contentFingerprint: .init(
            algorithm: "fixture-mesh-content-v1",
            value: "fixture-mesh-content"
        )
    )
}

private func fixtureSourceDependencies(
    documentID: DocumentID
) throws -> SourceDependencySetIdentity {
    try SourceDependencySetIdentity(
        dependencies: [
            SourceDependencyIdentity(
                subject: .cadDocument(documentID),
                contentFingerprint: .init(
                    algorithm: "fixture-source-v1",
                    value: "fixture-source"
                )
            ),
        ]
    )
}

private func triangleMesh(offset: Double) -> Mesh {
    Mesh(
        positions: [
            Point3D(x: offset, y: 0.0, z: 0.0),
            Point3D(x: offset + 1.0, y: 0.0, z: 0.0),
            Point3D(x: offset, y: 1.0, z: 0.0),
        ],
        normals: [
            .unitZ,
            .unitZ,
            .unitZ,
        ],
        indices: [0, 1, 2],
        textureCoordinates: [
            Point2D(x: 0.0, y: 0.0),
            Point2D(x: 1.0, y: 0.0),
            Point2D(x: 0.0, y: 1.0),
        ],
        vertexColors: [
            ColorRGBA(r: 1.0, g: 0.0, b: 0.0, a: 1.0),
            ColorRGBA(r: 0.0, g: 1.0, b: 0.0, a: 1.0),
            ColorRGBA(r: 0.0, g: 0.0, b: 1.0, a: 1.0),
        ]
    )
}
