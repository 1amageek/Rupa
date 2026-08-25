import Foundation
import RupaCoreTypes
import Testing

@Test(.timeLimit(.minutes(1)))
func stableIdentifiersValidateTheirPersistenceContract() throws {
    let project = try ProjectID(validating: "project.primary")
    let scene = try SceneID(validating: "scene.primary")
    let occurrence = try SceneOccurrenceID(validating: "occurrence.primary")
    let definition = try ObjectDefinitionID(validating: "definition.primary")
    let sourceKind = try GeometrySourceKindID(validating: "geometry.mesh")
    let source = try GeometrySourceID(validating: "source.primary")
    let output = try GeometryOutputID(validating: "output.primary")
    let attribute = try GeometryAttributeID(validating: "attribute.uv")
    let capability = try CapabilityID(validating: "modeling.createBox")
    let property = try PropertyID(validating: "dimensions.width")
    let asset = try AssetID(validating: "asset.primary")
    let program = try ModelingProgramID(validating: "program.primary")

    #expect(identityKind(project) == "project")
    #expect(identityKind(scene) == "scene")
    #expect(identityKind(occurrence) == "occurrence")
    #expect(identityKind(definition) == "definition")
    #expect(identityKind(sourceKind) == "source-kind")
    #expect(identityKind(source) == "source")
    #expect(identityKind(output) == "output")
    #expect(identityKind(attribute) == "attribute")
    #expect(identityKind(capability) == "capability")
    #expect(identityKind(property) == "property")
    #expect(identityKind(asset) == "asset")
    #expect(identityKind(program) == "program")

    try expectRoundTrip(project)
    try expectRoundTrip(scene)
    try expectRoundTrip(occurrence)
    try expectRoundTrip(definition)
    try expectRoundTrip(sourceKind)
    try expectRoundTrip(source)
    try expectRoundTrip(output)
    try expectRoundTrip(attribute)
    try expectRoundTrip(capability)
    try expectRoundTrip(property)
    try expectRoundTrip(asset)
    try expectRoundTrip(program)
}

@Test(.timeLimit(.minutes(1)))
func stableIdentifiersRejectInvalidAndUnqualifiedValues() {
    #expect(throws: EditorError.self) {
        _ = try ProjectID(validating: "")
    }
    #expect(throws: EditorError.self) {
        _ = try ProjectID(validating: " project.primary")
    }
    #expect(throws: EditorError.self) {
        _ = try ProjectID(validating: "project\nprimary")
    }
    #expect(throws: EditorError.self) {
        _ = try ProjectID(validating: String(repeating: "a", count: 1_025))
    }
    #expect(throws: EditorError.self) {
        _ = try CapabilityID(validating: "unqualified")
    }
    #expect(throws: EditorError.self) {
        _ = try CapabilityID(validating: "modeling. createBox")
    }
    #expect(throws: EditorError.self) {
        _ = try GeometrySourceKindID(validating: "geometry..mesh")
    }
    #expect(throws: EditorError.self) {
        _ = try JSONDecoder().decode(ProjectID.self, from: Data("\" padded\"".utf8))
    }
}

@Test(.timeLimit(.minutes(1)))
func numericGeometryIdentifiersRemainDistinctAndOrdered() throws {
    let vertex = MeshVertexID(1)
    let edge = MeshEdgeID(1)
    let face = MeshFaceID(1)
    let corner = MeshCornerID(1)

    #expect(elementKind(vertex) == "vertex")
    #expect(elementKind(edge) == "edge")
    #expect(elementKind(face) == "face")
    #expect(elementKind(corner) == "corner")
    #expect(MeshVertexID(1) < MeshVertexID(2))

    try expectRoundTrip(vertex)
    try expectRoundTrip(edge)
    try expectRoundTrip(face)
    try expectRoundTrip(corner)

    let evaluation = EvaluationSnapshotID(
        projectID: "project.primary",
        purpose: .presentation,
        sourceRevision: DocumentTransactionRevision(42)
    )
    try expectRoundTrip(evaluation)
}

private func identityKind(_: ProjectID) -> String { "project" }
private func identityKind(_: SceneID) -> String { "scene" }
private func identityKind(_: SceneOccurrenceID) -> String { "occurrence" }
private func identityKind(_: ObjectDefinitionID) -> String { "definition" }
private func identityKind(_: GeometrySourceKindID) -> String { "source-kind" }
private func identityKind(_: GeometrySourceID) -> String { "source" }
private func identityKind(_: GeometryOutputID) -> String { "output" }
private func identityKind(_: GeometryAttributeID) -> String { "attribute" }
private func identityKind(_: CapabilityID) -> String { "capability" }
private func identityKind(_: PropertyID) -> String { "property" }
private func identityKind(_: AssetID) -> String { "asset" }
private func identityKind(_: ModelingProgramID) -> String { "program" }

private func elementKind(_: MeshVertexID) -> String { "vertex" }
private func elementKind(_: MeshEdgeID) -> String { "edge" }
private func elementKind(_: MeshFaceID) -> String { "face" }
private func elementKind(_: MeshCornerID) -> String { "corner" }

private func expectRoundTrip<Value>(_ value: Value) throws
where Value: Codable & Equatable {
    let data = try JSONEncoder().encode(value)
    #expect(try JSONDecoder().decode(Value.self, from: data) == value)
}
