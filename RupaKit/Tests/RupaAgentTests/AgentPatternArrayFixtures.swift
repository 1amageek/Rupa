import Darwin
import Foundation
import Testing
import RupaCore
import SwiftCAD
@testable import RupaAgent
@testable import RupaAgentTransport

func agentPoint(
    _ point: SketchPoint,
    in document: DesignDocument
) throws -> Point2D {
    Point2D(
        x: try document.cadDocument.parameters.resolvedValue(for: point.x).value,
        y: try document.cadDocument.parameters.resolvedValue(for: point.y).value
    )
}

func agentPatternArrayBodySceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference == .body(featureID)
    }?.key
}

struct AgentIndependentCopyCloneExtrudeFeature {
    var output: PatternArraySummary.IndependentCopyOutputStatus
    var featureID: FeatureID
}

func agentIndependentCopyCloneExtrudeFeature(
    server: AgentCommandController,
    sessionID: UUID,
    sourceID: PatternArraySourceID,
    expectedGeneration: DocumentGeneration
) throws -> AgentIndependentCopyCloneExtrudeFeature {
    let summaryResponse = server.handle(
        .patternArraySummary(
            sessionID: sessionID,
            expectedGeneration: expectedGeneration
        )
    )
    guard case .patternArraySummary(let summaryResult) = summaryResponse else {
        Issue.record("Agent must return a pattern array summary.")
        throw EditorError(
            code: .commandFailed,
            message: "Pattern array summary response was not returned."
        )
    }
    let summary = try #require(summaryResult.patternArrays.first { $0.sourceID == sourceID })
    let output = try #require(summary.independentCopyOutputs.first)

    let snapshotResponse = server.handle(
        .designDisplaySnapshot(
            sessionID: sessionID,
            expectedGeneration: expectedGeneration
        )
    )
    guard case .designDisplaySnapshot(let snapshot) = snapshotResponse else {
        Issue.record("Agent must return a design display snapshot.")
        throw EditorError(
            code: .commandFailed,
            message: "Design display snapshot response was not returned."
        )
    }
    let extrudeFeatureIDs = Set(snapshot.extrudes.map(\.featureID))
    let featureID = try #require(output.featureIDs.first { extrudeFeatureIDs.contains($0) })
    return AgentIndependentCopyCloneExtrudeFeature(
        output: output,
        featureID: featureID
    )
}

func agentFeatureID(
    inSceneSubtreeRootedAt rootSceneNodeID: SceneNodeID,
    document: DesignDocument
) -> FeatureID? {
    guard let sceneNode = document.productMetadata.sceneNodes[rootSceneNodeID] else {
        return nil
    }
    if let featureID = sceneNode.reference?.featureID {
        return featureID
    }
    for childID in sceneNode.childIDs {
        if let featureID = agentFeatureID(
            inSceneSubtreeRootedAt: childID,
            document: document
        ) {
            return featureID
        }
    }
    return nil
}

extension ObjectPropertyValue {
    var lengthValue: Double? {
        guard case .length(let value) = self else {
            return nil
        }
        return value
    }
}

extension UUID {
    var featureID: FeatureID {
        FeatureID(self)
    }

    var sketchEntityID: SketchEntityID {
        SketchEntityID(self)
    }
}
