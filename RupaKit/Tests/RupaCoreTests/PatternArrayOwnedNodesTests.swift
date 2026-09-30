import SwiftCAD
import Testing
@testable import RupaCore

/// The nodes pattern arrays own, found once, are exactly the nodes the one-node question names.
@MainActor
@Test func patternOwnedNodesMatchTheOneNodeQuestionForEveryNode() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let body = try #require(session.document.productMetadata.sceneNodes.values.first { $0.reference?.kind == .body }).id
    _ = try session.execute(.createPatternArrayFromSceneNodes(name: "Copies", rootSceneNodeIDs: [body],
        distribution: .rectangular(.init(firstAxis: .init(direction: .unitX, distance: .length(0.5, .meter), copyCount: 3))),
        outputMode: .independentCopy))
    let metadata = session.document.productMetadata
    #expect(!metadata.patternArrays.isEmpty)
    let resolver = PatternArrayOwnershipResolver()
    let owned = resolver.outputSceneNodeIDs(in: metadata)
    #expect(!owned.isEmpty)
    for id in metadata.sceneNodes.keys {
        #expect(owned.contains(id) == (resolver.sourceID(containingOutputSceneNode: id, in: metadata) != nil))
    }
}
