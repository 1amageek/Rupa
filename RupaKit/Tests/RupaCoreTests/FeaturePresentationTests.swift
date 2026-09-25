import SwiftCAD
import Testing
@testable import RupaCore

/// Covers the one-presenting-node contract that viewport, measurement, section and topology share.
@Suite struct FeaturePresentationTests {
    @MainActor
    private func boxDocument() throws -> (DesignDocument, FeatureID, SceneNodeID) {
        let session = EditorSession()
        _ = try session.execute(.createExtrudedRectangle(
            name: "Box", plane: .xy,
            width: .length(1, .meter), height: .length(1, .meter),
            depth: .length(1, .meter), direction: .normal
        ))
        let document = session.document
        let featureID = try #require(document.cadDocument.designGraph.order.last)
        let sceneNodeID = try #require(document.productMetadata.sceneNodes.first { _, node in
            node.reference?.featureID == featureID
        }?.key)
        return (document, featureID, sceneNodeID)
    }

    @MainActor
    @Test func aSecondPresentingNodeIsRejectedByValidationAndHierarchy() throws {
        var (document, featureID, _) = try boxDocument()
        // A different reference kind still presents the same feature geometry.
        let duplicate = SceneNode(name: "Duplicate", reference: .feature(featureID))
        document.productMetadata.sceneNodes[duplicate.id] = duplicate
        let rootID = try #require(document.productMetadata.rootSceneNodeIDs.first)
        document.productMetadata.sceneNodes[rootID]?.childIDs.append(duplicate.id)

        #expect(throws: DocumentValidationError.self) {
            try document.productMetadata.validate(
                against: document.cadDocument,
                objectRegistry: .builtIn
            )
        }
        #expect(throws: EditorError.self) {
            _ = try SceneNodeHierarchy(metadata: document.productMetadata)
        }
    }

    @MainActor
    @Test func presentationOccurrencesIncludeComponentExpansionsOfThePresentingNode() throws {
        var (document, featureID, sceneNodeID) = try boxDocument()
        let definition = try document.createComponentDefinition(name: "Part", rootSceneNodeIDs: [sceneNodeID])
        let instance = try document.createComponentInstance(
            name: "Instance", definitionID: definition,
            localTransform: .translation(Vector3D(x: 5, y: 0, z: 0))
        )
        let hierarchy = try SceneNodeHierarchy(metadata: document.productMetadata)
        let occurrences = try hierarchy.resolvedOccurrences()

        let presented = hierarchy.presentationOccurrences(of: featureID, in: occurrences)

        #expect(hierarchy.presentingSceneNodeID(for: featureID) == sceneNodeID)
        #expect(presented.allSatisfy { $0.sourceSceneNodeID == sceneNodeID })
        #expect(presented.contains { $0.componentInstanceID == nil })
        #expect(presented.contains { $0.componentInstanceID == instance })
        #expect(hierarchy.presentationOccurrences(of: FeatureID(), in: occurrences).isEmpty)
    }

    @MainActor
    @Test func topologyOfAnUnpresentedFeatureCarriesNoSceneNode() throws {
        var (document, featureID, sceneNodeID) = try boxDocument()
        let presented = try TopologySnapshotService().snapshot(document: document)
        let presentedEntries = presented.entries.filter { $0.sourceFeatureID == featureID.description }
        #expect(presentedEntries.isEmpty == false)
        #expect(presentedEntries.allSatisfy { $0.sceneNodeID == sceneNodeID.description })

        // The node stays in the tree as a plain group, so the feature is no longer presented.
        document.productMetadata.sceneNodes[sceneNodeID]?.reference = nil
        document.productMetadata.sceneNodes[sceneNodeID]?.object = .group()
        let unpresented = try TopologySnapshotService().snapshot(document: document)

        let unpresentedEntries = unpresented.entries.filter { $0.sourceFeatureID == featureID.description }
        #expect(unpresentedEntries.count == presentedEntries.count)
        #expect(unpresentedEntries.allSatisfy { $0.sceneNodeID == nil })
    }
}
