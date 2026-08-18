import SwiftCAD
import Testing
@testable import RupaCore

@Suite("Projected curve command")
struct ProjectedCurveCommandTests {
    @Test(.timeLimit(.minutes(1)))
    func createsKernelCurveFeatureAndFeatureSceneNode() throws {
        var document = DesignDocument.empty()
        let sourceFeatureID = try document.createLineSketch(
            name: "Projection source",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )

        let projectedFeatureID = try document.createProjectedCurve(
            name: "Projected curve",
            source: CurveOutputReference(featureID: sourceFeatureID),
            planeOrigin: Point3D(x: 0.0, y: 0.0, z: 0.005),
            planeNormal: .unitZ
        )

        guard case let .projectCurve(feature) = document.cadDocument.designGraph
            .nodes[projectedFeatureID]?.operation else {
            Issue.record("Projected curve command must author a ProjectCurveFeature.")
            return
        }
        #expect(feature.source.featureID == sourceFeatureID)
        #expect(document.productMetadata.sceneNodes.values.contains { node in
            node.reference?.kind == .feature
                && node.reference?.featureID == projectedFeatureID
        })
        try document.validate()
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func editorCommandCommitsAndEvaluatesProjectedCurve() throws {
        var document = DesignDocument.empty()
        let sourceFeatureID = try document.createLineSketch(
            name: "Command projection source",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
        let session = EditorSession(document: document)

        let result = try session.execute(.createProjectedCurve(
            name: "Command projected curve",
            source: CurveOutputReference(featureID: sourceFeatureID),
            planeOrigin: Point3D(x: 0.0, y: 0.0, z: 0.005),
            planeNormal: .unitZ,
            direction: nil
        ))

        let projectedFeatureID = try #require(result.primaryFeatureID)
        let evaluatedCurves = try #require(
            session.currentEvaluation?.evaluatedDocument.curves[projectedFeatureID]
        )
        #expect(result.commandName == "createProjectedCurve")
        #expect(result.didMutate)
        #expect(session.evaluationStatus == .valid)
        #expect(evaluatedCurves.isEmpty == false)
    }
}
