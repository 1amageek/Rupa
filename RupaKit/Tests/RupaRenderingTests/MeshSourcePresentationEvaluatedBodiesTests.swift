import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

/// One index of an evaluation's bodies answers each feature as a scan of the subshape table
/// would, so resolving many presented items no longer scans the table once per item.
@MainActor
@Test func evaluatedBodiesAnswerEachFeatureAsAScanWould() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    _ = try #require(session.createDefaultExtrudedRectangle())
    let evaluated = try #require(session.currentEvaluation?.evaluatedDocument)
    let index = MeshSourcePresentationEvaluatedBodies(evaluated)
    let features = session.document.cadDocument.designGraph.order
    #expect(features.count >= 2)
    for featureID in features {
        var scanned: [BodyID] = []
        for (subshapeID, reference) in evaluated.subshapes.entries {
            guard subshapeID.featureID == featureID, case let .body(bodyID) = reference,
                  evaluated.brep.bodies[bodyID] != nil, !scanned.contains(bodyID) else { continue }
            scanned.append(bodyID)
        }
        #expect(Set(index.bodyIDs(for: featureID)) == Set(scanned))
        #expect(index.bodyIDs(for: featureID).count == scanned.count)
    }
    #expect(index.bodyIDs(for: FeatureID()).isEmpty)
}
