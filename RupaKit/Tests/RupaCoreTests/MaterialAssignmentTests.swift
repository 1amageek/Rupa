import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Set, Fork and Remove Material, library edits and mass.
@Suite struct MaterialAssignmentTests {
    /// Two boxes, the second inside a group.
    private func document() throws -> (DesignDocument, first: SceneNodeID, second: SceneNodeID, group: SceneNodeID) {
        var document = DesignDocument.empty()
        var nodes: [SceneNodeID] = []
        for name in ["A", "B"] {
            let featureID = try document.createExtrudedRectangle(
                name: name, plane: .xy, width: .length(0.1, .meter), height: .length(0.1, .meter),
                depth: .length(0.1, .meter), direction: .normal
            )
            nodes.append(try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == featureID }).id)
        }
        let group = try document.groupSceneNodes(name: "Group", memberIDs: [nodes[1]], origin: nil)
        return (document, nodes[0], nodes[1], group)
    }

    @Test func setMaterialReachesGroupMembersAndReusesAMaterialTheyShare() throws {
        var (document, first, second, group) = try document()
        do {
            let reached = try document.materialTargets(for: [group])
            #expect(reached == [second], "\(reached.map { document.productMetadata.sceneNodes[$0]?.name ?? "?" })")
        } catch {
            Issue.record("materialTargets threw \(error)")
        }

        let material = try document.assignMaterial(ids: [first, group])
        #expect(document.productMetadata.sceneNodes[first]?.materialID == material)
        #expect(document.productMetadata.sceneNodes[second]?.materialID == material)
        #expect(document.productMetadata.sceneNodes[group]?.materialID == nil)
        let count = document.productMetadata.materialLibrary.materials.count
        #expect(try document.assignMaterial(ids: [first, second]) == material)
        #expect(document.productMetadata.materialLibrary.materials.count == count)

        try document.editMaterial(id: material, edit: .clearcoat(0.7))
        #expect(document.sceneNodeAppearance(id: second)?.clearcoat == 0.7)
        #expect(throws: EditorError.self) { try document.editMaterial(id: material, edit: .ior(4)) }
    }

    @Test func forkGivesAnIndependentCopyAndRemoveReturnsToTheDefault() throws {
        var (document, first, second, _) = try document()
        let shared = try document.assignMaterial(ids: [first, second])
        try document.editMaterial(id: shared, edit: .density(1000))
        let forked = try document.forkMaterial(ids: [second])
        #expect(forked != shared)
        #expect(document.productMetadata.materialLibrary.materials[forked]?.density == 1000)
        try document.editMaterial(id: forked, edit: .roughness(0.9))
        #expect(document.sceneNodeAppearance(id: first)?.roughness != 0.9)

        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        let face = try #require(topology.entries.compactMap { entry -> SelectionTarget? in
            guard entry.kind == .face, let target = entry.selectionTarget(), target.sceneNodeID == first else { return nil }
            return target
        }.first)
        try document.setTopologyMaterialBinding(target: face, materialID: forked, process: nil)
        try document.removeMaterial(ids: [first])
        #expect(document.productMetadata.sceneNodes[first]?.materialID == nil)
        #expect(!document.productMetadata.topologyMaterialBindings.values.contains { $0.target.sceneNodeID == first })
    }

    @Test func libraryRenameKeepsNamesUniqueAndDeleteUnassignsUsers() throws {
        var (document, first, _, _) = try document()
        let created = try document.createMaterial(name: "Steel")
        let other = try document.createMaterial(name: "Steel")
        #expect(document.productMetadata.materialLibrary.materials[other]?.name == "Steel 2")
        #expect(throws: EditorError.self) { try document.renameMaterial(id: other, name: " Steel ") }
        try document.renameMaterial(id: other, name: "Brass")
        #expect(document.productMetadata.materialLibrary.materials[other]?.name == "Brass")

        document.productMetadata.sceneNodes[first]?.materialID = created
        document.productMetadata.materialLibrary.defaultMaterialID = created
        try document.deleteMaterial(id: created)
        #expect(document.productMetadata.materialLibrary.materials[created] == nil)
        #expect(document.productMetadata.materialLibrary.defaultMaterialID == nil)
        #expect(document.productMetadata.sceneNodes[first]?.materialID == nil)
    }

    @Test func massWeighsSolidsWithADensityAndCountsTheRest() throws {
        var (document, first, second, _) = try document()
        let steel = try document.forkMaterial(ids: [first])
        try document.editMaterial(id: steel, edit: .density(7850))
        let measurement = try MeasurementService().measure(
            document: document,
            selection: SelectionModel(selectedTargets: [SelectionTarget(sceneNodeID: first), SelectionTarget(sceneNodeID: second)]),
            ruler: .standard(for: .millimeter)
        )
        let mass = try document.mass(of: measurement)
        #expect(abs(mass.kilograms - 0.001 * 7850) < 1e-9)
        #expect(mass.unweighedSolidCount == 1)
    }
}
