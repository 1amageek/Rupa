import SwiftCAD
import Testing
@testable import RupaCore

/// Every object presenting a body presents one the document still evaluates: a feature that
/// consumes bodies (a Boolean, a Cut) takes their objects away, so the project, which evaluates
/// every object, never meets one whose body is gone.
func expectEveryBodyObjectPresentsAnEvaluatedBody(
    _ document: DesignDocument,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let evaluated = try DocumentEvaluationContextResolver().evaluatedDocument(
        document: document, objectRegistry: .builtIn, failurePrefix: "The presentation check needs the document evaluated"
    )
    for node in document.productMetadata.sceneNodes.values where node.reference?.kind == .body {
        let featureID = try #require(node.reference?.featureID, sourceLocation: sourceLocation)
        let body = SubshapeID(featureID: featureID, role: GeneratedSubshapeRole.body.rawValue, ordinal: 0)
        #expect(evaluated.subshapes.entries[body] != nil, "\(node.name) presents a body that is gone", sourceLocation: sourceLocation)
    }
}
