import Testing
import RupaCore
import SwiftCAD

@MainActor
@Test func featureSuppressionCommandSuppressesAndUnsuppressesStandaloneFeature() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketch(
            name: "Suppressible Profile",
            plane: .xy,
            width: .length(8.0, .millimeter),
            height: .length(4.0, .millimeter)
        )
    )
    let featureID = try #require(session.document.cadDocument.designGraph.order.first)

    let suppressResult = try session.execute(
        .setFeatureSuppression(featureID: featureID, isSuppressed: true)
    )
    let suppressedFeature = try #require(session.document.cadDocument.designGraph.nodes[featureID])

    #expect(suppressResult.commandName == "setFeatureSuppression")
    #expect(suppressResult.didMutate)
    #expect(suppressResult.primaryFeatureID == featureID)
    #expect(suppressResult.generation == DocumentGeneration(2))
    #expect(suppressedFeature.isSuppressed)
    #expect(session.evaluationStatus == .valid)

    let noOpResult = try session.execute(
        .setFeatureSuppression(featureID: featureID, isSuppressed: true)
    )

    #expect(!noOpResult.didMutate)
    #expect(noOpResult.generation == DocumentGeneration(2))

    let unsuppressResult = try session.execute(
        .setFeatureSuppression(featureID: featureID, isSuppressed: false)
    )
    let unsuppressedFeature = try #require(session.document.cadDocument.designGraph.nodes[featureID])

    #expect(unsuppressResult.didMutate)
    #expect(unsuppressResult.primaryFeatureID == featureID)
    #expect(unsuppressResult.generation == DocumentGeneration(3))
    #expect(!unsuppressedFeature.isSuppressed)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func featureSuppressionCommandRejectsActiveDependentFeatureBeforeMutation() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketch(
            name: "Dependent Profile",
            plane: .xy,
            width: .length(8.0, .millimeter),
            height: .length(4.0, .millimeter)
        )
    )
    let profileFeatureID = try #require(session.document.cadDocument.designGraph.order.first)
    _ = try session.execute(
        .extrudeProfile(
            name: "Dependent Body",
            profile: ProfileReference(featureID: profileFeatureID),
            distance: .length(2.0, .millimeter),
            direction: .normal
        )
    )

    do {
        _ = try session.execute(
            .setFeatureSuppression(featureID: profileFeatureID, isSuppressed: true)
        )
        Issue.record("Expected suppression of an active dependency source to fail.")
    } catch FeatureEvaluationError.invalidGraph(let message) {
        #expect(message.contains("Active feature input references a suppressed feature."))
    } catch {
        Issue.record("Expected invalidGraph, got \(error).")
    }

    let profileFeature = try #require(session.document.cadDocument.designGraph.nodes[profileFeatureID])
    #expect(!profileFeature.isSuppressed)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}
