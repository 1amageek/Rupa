import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Suite struct PatternArrayInstanceSourceTests {
    private func distribution(_ kind: Int) -> PatternArrayDistribution {
        switch kind {
        case 0: .rectangular(.init(firstAxis: .init(direction: .unitX, distance: .length(0.5, .meter), copyCount: 2)))
        case 1: .radial(.init(angularAxis: .init(center: .origin, axis: .unitZ, angle: .angle(.pi / 2, .radian), copyCount: 2)))
        default: .curve(.init(path: .polyline(points: [.origin, Point3D(x: 1, y: 0, z: 0)], normal: .unitZ), copyCount: 2))
        }
    }

    private func source() throws -> (DesignDocument, SceneNodeID, SceneNodeID) {
        var document = DesignDocument.empty()
        let feature = try document.createExtrudedRectangle(name: "Source", plane: .xy,
            width: .length(0.1, .meter), height: .length(0.1, .meter), depth: .length(0.1, .meter), direction: .normal)
        let body = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == feature }).id
        try document.setSceneNodeTransform(id: body, localTransform: .translation(Vector3D(x: 0.1, y: 0, z: 0)))
        let first = try document.placeSceneNodes(ids: [body], placements: [.translation(Vector3D(x: 0, y: 0.2, z: 0))], output: .componentInstance)
        let second = try document.placeSceneNodes(ids: first, placements: [.translation(Vector3D(x: 0, y: 0, z: 0.3))], output: .componentInstance)
        let selected = try #require(second.first)
        let parent = try document.groupSceneNodes(name: "Parent", memberIDs: [selected])
        try document.setSceneNodeTransform(id: parent, localTransform:
            Transform3D.translation(Vector3D(x: 2, y: 0, z: 0)).composed(with:
                Transform3D.rotation(axis: .unitZ, angleRadians: .pi / 3)))
        return (document, body, selected)
    }

    @MainActor @Test(.timeLimit(.minutes(1)), arguments: [0, 1, 2], [false, true])
    func nestedInstanceArraysKeepPlacementAndOwnership(_ kind: Int, _ shared: Bool) throws {
        let (before, body, selected) = try source()
        let session = EditorSession(document: before)
        let distribution = distribution(kind)
        let originalFeature = try #require(before.productMetadata.sceneNodes[body]?.reference?.featureID)
        let originalPlacement = try #require(try SceneNodeHierarchy(metadata: before.productMetadata).resolvedOccurrences()
            .first { $0.sceneNodeID == selected && $0.sourceSceneNodeID == body }).worldTransform
        let result = try session.execute(.createPatternArrayFromSceneNodes(name: "Copies", rootSceneNodeIDs: [selected],
            distribution: distribution, outputMode: shared ? .componentInstance : .independentCopy))
        var document = session.document
        let id = try #require(result.generatedIdentities.patternArraySourceIDs.first)
        let array = try #require(document.productMetadata.patternArrays[id])
        let hierarchy = try SceneNodeHierarchy(metadata: document.productMetadata)
        let transforms = try PatternArrayInstancePlanner().transforms(for: distribution,
            parameters: document.cadDocument.parameters, cadDocument: document.cadDocument)
        let outputs = try #require(document.productMetadata.sceneNodes[array.rootSceneNodeID]).childIDs
        #expect(outputs.count == 2)
        let occurrences = try hierarchy.resolvedOccurrences()
        for (index, output) in outputs.enumerated() {
            let descendants = Set(hierarchy.subtreeIDs(of: output))
            let occurrence = try #require(occurrences.first {
                descendants.contains($0.sceneNodeID) && document.productMetadata.sceneNodes[$0.sourceSceneNodeID]?.reference?.kind == .body
            })
            let frame = try hierarchy.parentWorldTransform(of: selected)
            let expected = try frame.composed(with: transforms[index])
                .composed(with: frame.inverse()).composed(with: originalPlacement)
            for (actual, expected) in zip(occurrence.worldTransform.matrix.values, expected.matrix.values) {
                #expect(abs(actual - expected) < 1e-10)
            }
            let copiedFeature = document.productMetadata.sceneNodes[occurrence.sourceSceneNodeID]?.reference?.featureID
            #expect(shared ? copiedFeature == originalFeature : copiedFeature != originalFeature)
            #expect(occurrence.isVisible)
            if !shared {
                #expect(descendants.allSatisfy { document.productMetadata.sceneNodes[$0]?.reference?.kind != .componentInstance })
            }
        }
        #expect(document.productMetadata.componentInstances.count == before.productMetadata.componentInstances.count + (shared ? 2 : 0))
        _ = try document.validate()
        let metadata = try JSONDecoder().decode(ProductMetadata.self, from: JSONEncoder().encode(document.productMetadata))
        #expect(metadata == document.productMetadata)
        _ = try session.undo()
        #expect(session.document.productMetadata == before.productMetadata)
        _ = try session.redo()
        #expect(session.document.productMetadata == document.productMetadata)

        if !shared {
            try document.updatePatternArray(id: id, distribution: distribution)
            #expect(document.productMetadata.patternArrays[id]?.outputSceneNodeIDs == array.outputSceneNodeIDs)
            try document.setSceneNodeTransform(id: body, localTransform: .translation(Vector3D(x: 0.4, y: 0, z: 0)))
            try document.updatePatternArray(id: id)
            let updated = try #require(document.productMetadata.patternArrays[id])
            #expect(updated.definitionIdentity != array.definitionIdentity)
            #expect(Set(updated.outputFeatureIDs).isDisjoint(with: array.outputFeatureIDs))
            #expect(array.outputFeatureIDs.allSatisfy { document.cadDocument.designGraph.nodes[$0] == nil })
            #expect(document.productMetadata.componentInstances == before.productMetadata.componentInstances)
            _ = try document.validate()
        }
    }

    @Test func recursiveDefinitionFailsExplicitly() throws {
        var (document, _, selected) = try source()
        let instanceID = try #require(document.productMetadata.sceneNodes[selected]?.reference?.componentInstanceID)
        let definitionID = try #require(document.productMetadata.componentInstances[instanceID]?.definitionID)
        document.productMetadata.componentDefinitions[definitionID]?.rootSceneNodeIDs = [selected]
        let definition = try #require(document.productMetadata.componentDefinitions[definitionID])
        #expect(throws: EditorError.self) {
            try PatternArrayDefinitionIdentityService().identity(for: definition,
                metadata: document.productMetadata, cadDocument: document.cadDocument)
        }
    }
}
