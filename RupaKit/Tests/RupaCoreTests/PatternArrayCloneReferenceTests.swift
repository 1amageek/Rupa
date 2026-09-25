import SwiftCAD
import Testing
@testable import RupaCore

/// Independent-copy pattern outputs clone feature references through Swift-CAD's remapping.
@Suite struct PatternArrayCloneReferenceTests {
    @MainActor
    @Test func clonedAllEdgeFilletKeepsItsAllEdgesSourceAndReferencesOnlyClones() throws {
        let session = EditorSession()
        _ = try session.execute(.createExtrudedRectangle(
            name: "Box", plane: .xy,
            width: .length(0.1, .meter), height: .length(0.08, .meter),
            depth: .length(0.06, .meter), direction: .normal
        ))
        let bodyNode = try #require(session.document.productMetadata.sceneNodes.values.first {
            $0.reference?.kind == .body
        })
        _ = try session.execute(.setSceneNodeObjectProperty(
            id: bodyNode.id, propertyID: .init(rawValue: "corner.radius"), value: .length(0.01)
        ))
        let sourceFeatureIDs = Set(session.document.cadDocument.designGraph.nodes.keys)
        let sourceFillet = try #require(session.document.cadDocument.designGraph.nodes.values.first {
            if case .fillet = $0.operation { return true }
            return false
        })
        guard case .fillet(let sourceFeature) = sourceFillet.operation else {
            Issue.record("The corner radius must be an all-edge fillet.")
            return
        }
        #expect(sourceFeature.allEdges)

        let definition = try session.execute(.createComponentDefinition(
            name: "Rounded", rootSceneNodeIDs: [bodyNode.id]
        ))
        let definitionID = try #require(definition.generatedIdentities.componentDefinitionIDs.first)
        _ = try session.execute(.createPatternArray(
            name: "Copies",
            definitionID: definitionID,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(direction: .unitX, distance: .length(0.2, .meter), copyCount: 2)
            )),
            outputMode: .independentCopy
        ))

        let clonedFillets = session.document.cadDocument.designGraph.nodes.values.filter {
            guard !sourceFeatureIDs.contains($0.id), case .fillet = $0.operation else { return false }
            return true
        }
        #expect(clonedFillets.count == 2)
        for clone in clonedFillets {
            guard case .fillet(let feature) = clone.operation else { continue }
            #expect(feature.allEdges)
            #expect(clone.operation.referencedFeatureIDs.isDisjoint(with: sourceFeatureIDs))
            #expect(Set(clone.inputs.map(\.featureID)).isDisjoint(with: sourceFeatureIDs))
        }
    }
}
