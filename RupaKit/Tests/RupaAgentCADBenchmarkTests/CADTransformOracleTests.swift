import RupaCADDomain
import RupaGeometry
import SwiftCAD
import Testing

@testable import RupaAgentCADBenchmark

struct CADTransformOracleTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func transformProgramCreatesItsSourceAndPublishesPlacementAtomically() async throws {
        let preparedCase = CADTransformPreparedCase.transform001
        let entry = try preparedCase.catalogEntry
        let action = try CADTransformReferenceCandidate.action(for: entry.challenge)
        let plan = try DefaultCADSemanticProgramPlanner().plan(for: entry, action: action)

        #expect(plan.steps.map(\.symbol) == ["transform-source", "transform"])
        #expect(plan.steps.count == 2)
        #expect(plan.request.nodes.count == 2)
        guard case .local(let localReference) = plan.request.nodes[1].arguments
            .first(where: { $0.name == "scene" })?.value else {
            Issue.record("The transform node must consume the source scene through a local output.")
            return
        }
        #expect(localReference.node == "transform-source")
        #expect(localReference.output == "scene")

        let result = try await CADTransformCaseRunner(case: preparedCase).runReference()
        try result.validate()
        #expect(result.outcome == .realized)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
    }

    @Test
    func axisPointCompositionAndParentTimesLocalUseColumnVectorOrder() throws {
        let submission = CADTransformSubmission(
            translation: CADPoint3D(x: 25, y: 0, z: 0),
            axisPoint: CADPoint3D(x: 50, y: 0, z: 0),
            rotationAxis: CADDirection3D(x: 0, y: 0, z: 1),
            rotation: CADAngle(value: 90)
        )
        let local = try CADTransformGeometryMapping.localTransform(
            submission: submission,
            caseID: "TRN-001"
        )
        let localGeometry = try GeometryTransform3D(values: local.matrix.values)
        let rotatedPivot = try localGeometry.applying(
            to: GeometryPoint3D(x: 0.05, y: 0, z: 0)
        )
        #expect(abs(rotatedPivot.x - 0.075) < 1e-12)
        #expect(abs(rotatedPivot.y) < 1e-12)
        #expect(abs(rotatedPivot.z) < 1e-12)

        let parent = try GeometryTransform3D(values: [
            1, 0, 0, 1,
            0, 1, 0, 2,
            0, 0, 1, 3,
            0, 0, 0, 1,
        ])
        let composed = try CADTransformOracle.parentTimesLocal(
            parent: parent,
            local: local
        )
        let expected = try parent.multiplied(by: localGeometry)
        #expect(composed == expected)
    }
}
