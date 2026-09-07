import Foundation
import RupaCADIntegration
import RupaCore
import RupaCoreTypes
@testable import RupaKit
import RupaProject
import SwiftCAD
import Testing

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectGeometryImportAppendsMultipleMeshesWithOneUndoAndSanitizedProvenance() async throws {
    try await withGeometryExchangeDirectory { directory in
        let input = directory.appendingPathComponent("two-bodies.obj")
        try Data(geometryExchangeOBJ.utf8).write(to: input)
        let workspace = try geometryExchangeWorkspace()
        let initial = try await workspace.evaluate()
        let imported = try await workspace.importGeometry(from: input, format: .obj, unitForUnmarkedData: nil).view
        #expect(imported.document.document.authoredMeshAssets.count == 2)
        #expect(imported.viewport.items.count == 2)
        #expect(imported.transactionRevision.value == initial.transactionRevision.value + 1)
        #expect(imported.workspaceState.displayUnit == initial.workspaceState.displayUnit)
        for asset in imported.document.document.authoredMeshAssets.values {
            guard case .imported(let provenance) = asset.provenance else {
                Issue.record("Imported Mesh must retain file provenance.")
                continue
            }
            #expect(provenance.domain == "rupa.exchange.obj.millimeter")
            #expect(!provenance.fingerprint.value.contains(directory.path))
        }
        let repeated = try await workspace.importGeometry(from: input, format: .obj, unitForUnmarkedData: nil).view
        #expect(repeated.document.document.authoredMeshAssets.count == 4)
        let undone = try await workspace.undo(from: repeated)
        #expect(undone.document.document.authoredMeshAssets == imported.document.document.authoredMeshAssets)
        let redone = try await workspace.redo(from: undone)
        #expect(redone.document.document.authoredMeshAssets == repeated.document.document.authoredMeshAssets)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectGeometryImportFailureCancellationAndStaleInputDoNotPublish() async throws {
    try await withGeometryExchangeDirectory { directory in
        let input = directory.appendingPathComponent("input.obj")
        let workspace = try geometryExchangeWorkspace()
        let initial = try await workspace.evaluate()
        try Data("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n".utf8).write(to: input)
        do {
            _ = try await workspace.importGeometry(from: input, format: .obj, unitForUnmarkedData: nil)
            Issue.record("Unmarked coordinates need an explicit unit.")
        } catch is ImportError {}
        #expect(workspace.view?.publicationSequence == initial.publicationSequence)
        try Data(geometryExchangeOBJ.utf8).write(to: input)
        let task = Task { @MainActor in
            try await workspace.importGeometry(from: input, format: .obj, unitForUnmarkedData: nil)
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled import published.") }
        catch is CancellationError {}
        #expect(workspace.view?.publicationSequence == initial.publicationSequence)
        let prepared = try ProjectGeometryImport.transaction(from: input, format: .obj, unitForUnmarkedData: nil, snapshot: initial)
        let committed = try await workspace.importGeometry(from: input, format: .obj, unitForUnmarkedData: nil).view
        do { _ = try await workspace.perform(.source(prepared)); Issue.record("Stale import published.") }
        catch let error as ProjectControllerError { #expect(error.code == .revisionConflict) }
        #expect(workspace.view?.publicationSequence == committed.publicationSequence)
        #expect(workspace.view?.document.document.authoredMeshAssets.count == 2)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectGeometryExportBakesWorldPlacementAndPreservesOBJAttributes() async throws {
    try await withGeometryExchangeDirectory { directory in
        let input = directory.appendingPathComponent("input.obj")
        try Data(geometryExchangeOBJ.utf8).write(to: input)
        let workspace = try geometryExchangeWorkspace()
        _ = try await workspace.evaluate()
        let imported = try await workspace.importGeometry(from: input, format: .obj, unitForUnmarkedData: nil).view
        let root = try #require(imported.document.document.productMetadata.rootSceneNodeIDs.first)
        let transform = Transform3D(matrix: try Matrix4x4(values: [
            -2, 0, 0, 1, 0, 3, 0, 2, 0, 0, 4, 3, 0, 0, 0, 1,
        ]))
        let placed = try await workspace.perform(DefaultProjectWorkspaceActionPlanner().source(
            name: "Place imported geometry", commands: [.setSceneNodeTransform(id: root, localTransform: transform)], from: imported
        )).view
        for format in [ProjectGeometryFileFormat.obj, .stl] {
            let output = directory.appendingPathComponent("placed.\(format.rawValue)")
            try Data("old output".utf8).write(to: output)
            try await workspace.exportGeometry(to: output, format: format, unit: .centimeter)
            let read = try CADGeometryExchange().import(from: output, format: format.nativeFormat, tolerance: .standard)
            let positions = read.meshes.flatMap { Array($0.vertexPositions) }
            #expect(positions.allSatisfy { abs($0.z - 3) < 1e-6 })
            #expect(abs(try #require(positions.map(\.x).max()) - 1) < 1e-6)
            #expect(abs(try #require(positions.map(\.y).min()) - 2) < 1e-6)
            #expect(read.units.length == .centimeter)
            if format == .obj {
                #expect(read.meshes.allSatisfy { $0.attributes.layer(for: "cad.normal") != nil })
                #expect(read.meshes.allSatisfy { $0.attributes.layer(for: "cad.uv") != nil })
            }
            for mesh in read.meshes {
                let layer = try #require(mesh.attributes.layer(for: "cad.normal"))
                guard case .vector3(let normals) = layer.values else { Issue.record("Invalid normal storage."); continue }
                #expect(normals.allSatisfy { abs($0.z - 1) < 1e-6 })
            }
        }
        #expect(workspace.view?.publicationSequence == placed.publicationSequence)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectGeometryExportAcceptsLargeUniformScaleAndPreservesWindingAndNormals() async throws {
    try await withGeometryExchangeDirectory { directory in
        let input = directory.appendingPathComponent("input.obj")
        try Data(geometryExchangeOBJ.utf8).write(to: input)
        let workspace = try geometryExchangeWorkspace()
        _ = try await workspace.evaluate()
        let imported = try await workspace.importGeometry(from: input, format: .obj, unitForUnmarkedData: nil).view
        let root = try #require(imported.document.document.productMetadata.rootSceneNodeIDs.first)
        let scale = 1_000_000_000_000.0
        let transform = Transform3D(matrix: try Matrix4x4(values: [
            scale, 0, 0, 0,
            0, scale, 0, 0,
            0, 0, scale, 0,
            0, 0, 0, 1,
        ]))
        let scaled = try await workspace.perform(DefaultProjectWorkspaceActionPlanner().source(
            name: "Place at large uniform scale",
            commands: [.setSceneNodeTransform(id: root, localTransform: transform)],
            from: imported
        )).view
        let output = directory.appendingPathComponent("large-scale.obj")
        try await workspace.exportGeometry(to: output, format: .obj, unit: .meter)

        let read = try CADGeometryExchange().import(
            from: output,
            format: ProjectGeometryFileFormat.obj.nativeFormat,
            tolerance: .standard
        )
        let mesh = try #require(read.meshes.first)
        let normalLayer = try #require(mesh.attributes.layer(for: "cad.normal"))
        guard case .vector3(let normals) = normalLayer.values else {
            Issue.record("Large-scale OBJ export lost dense vertex normals.")
            return
        }
        #expect(!normals.isEmpty)
        #expect(normals.allSatisfy { $0.z > 0.999 })

        let faceRange = try #require(mesh.faceCornerRanges.first)
        let cornerIDs = Array((faceRange.start ..< faceRange.end).prefix(3))
            .map { mesh.cornerVertexIDs[$0] }
        guard cornerIDs.count == 3,
              let first = mesh.vertexIDs.firstIndex(of: cornerIDs[0]),
              let second = mesh.vertexIDs.firstIndex(of: cornerIDs[1]),
              let third = mesh.vertexIDs.firstIndex(of: cornerIDs[2]) else {
            Issue.record("Large-scale OBJ export did not retain a valid triangle.")
            return
        }
        let a = mesh.vertexPositions[first]
        let b = mesh.vertexPositions[second]
        let c = mesh.vertexPositions[third]
        let signedArea = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        #expect(signedArea > 0)
        #expect(scaled.viewport.items.count == imported.viewport.items.count)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectGeometrySTEPExactImportRetainsUnitsAndReidentifiesRepeatedBodies() async throws {
    try await withGeometryExchangeDirectory { directory in
        var document = DesignDocument.empty(named: "Exact source")
        _ = try document.createExtrudedRectangle(name: "Box", plane: .xy, width: .length(10, .millimeter), height: .length(20, .millimeter), depth: .length(30, .millimeter), direction: .normal)
        let sourceWorkspace = try geometryExchangeWorkspace(document: document)
        _ = try await sourceWorkspace.evaluate()
        let input = directory.appendingPathComponent("body.step")
        try await sourceWorkspace.exportGeometry(to: input, format: .step, unit: .millimeter)
        let workspace = try geometryExchangeWorkspace()
        let initial = try await workspace.evaluate()
        let first = try await workspace.importGeometry(from: input, format: .step, unitForUnmarkedData: nil).view
        let bounds = try #require(first.viewport.worldBounds)
        #expect(abs(bounds.maximum.x - bounds.minimum.x - 0.01) < 1e-8)
        #expect(abs(bounds.maximum.y - bounds.minimum.y - 0.02) < 1e-8)
        #expect(abs(bounds.maximum.z - bounds.minimum.z - 0.03) < 1e-8)
        let second = try await workspace.importGeometry(from: input, format: .step, unitForUnmarkedData: nil).view
        #expect(second.viewport.items.count == 2)
        #expect(second.workspaceState.displayUnit == initial.workspaceState.displayUnit)
        for feature in second.document.document.cadDocument.designGraph.nodes.values {
            guard case .importedBRep(let imported) = feature.operation else { Issue.record("STEP lost exact source."); continue }
            #expect(imported.sourceUnits.length == .millimeter)
            #expect(imported.model.bodies.count == 1)
        }
        let output = directory.appendingPathComponent("round-trip.step")
        try await workspace.exportGeometry(to: output, format: .step, unit: .millimeter)
        let roundTrip = try STEPExchange(tolerance: .standard).import(MappedFileByteSource(url: output))
        #expect(roundTrip.brep?.bodies.count == 2)
        let undone = try await workspace.undo(from: second)
        #expect(try undone.document.document.cadDocument.sourceFingerprint(tolerance: .standard)
                == first.document.document.cadDocument.sourceFingerprint(tolerance: .standard))
        #expect(undone.document.document.productMetadata == first.document.document.productMetadata)
        let packageURL = directory.appendingPathComponent("imported.rupa")
        _ = try await workspace.save(to: packageURL)
        let loadedWorkspace = try geometryExchangeWorkspace()
        _ = try await loadedWorkspace.evaluate()
        let loaded = try await loadedWorkspace.load(from: packageURL)
        #expect(try loaded.document.document.cadDocument.sourceFingerprint(tolerance: .standard)
                == first.document.document.cadDocument.sourceFingerprint(tolerance: .standard))
        #expect(loaded.viewport.items.count == 1)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectGeometryExportRefusalAndCancellationPreserveDestination() async throws {
    try await withGeometryExchangeDirectory { directory in
        let input = directory.appendingPathComponent("input.obj")
        try Data(geometryExchangeOBJ.utf8).write(to: input)
        let workspace = try geometryExchangeWorkspace()
        _ = try await workspace.evaluate()
        _ = try await workspace.importGeometry(from: input, format: .obj, unitForUnmarkedData: nil)
        let output = directory.appendingPathComponent("existing.step")
        let original = Data("Existing destination must survive.".utf8)
        try original.write(to: output)
        do { try await workspace.exportGeometry(to: output, format: .step, unit: .meter); Issue.record("Mesh exported as exact STEP.") }
        catch let error as EditorError { #expect(error.code == .commandUnsupported) }
        #expect(try Data(contentsOf: output) == original)
        let task = Task { @MainActor in try await workspace.exportGeometry(to: output, format: .obj, unit: .meter) }
        task.cancel()
        do { try await task.value; Issue.record("Cancelled export wrote a file.") }
        catch is CancellationError {}
        #expect(try Data(contentsOf: output) == original)
    }
}

@MainActor
private func geometryExchangeWorkspace(document: DesignDocument = .empty()) throws -> ProjectWorkspace {
    ProjectWorkspace(project: try ProjectController(document: document, evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(), projector: DesignDocumentProjectBridge()))
}

@MainActor
private func withGeometryExchangeDirectory(_ body: (URL) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rupa-exchange-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer {
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record("Could not remove test directory: \(error)") }
    }
    try await body(directory)
}

private let geometryExchangeOBJ = """
# unit millimeter
v 0 0 0
v 10 0 0
v 0 20 0
v 20 0 0
v 30 0 0
v 20 20 0
vt 0 0
vt 1 0
vt 0 1
vn 0 0 1
o first
f 1/1/1 2/2/1 3/3/1
o second
f 4/1/1 5/2/1 6/3/1
"""
