import Foundation
import Testing
import SwiftCAD
@testable import RupaCore

@MainActor
@Suite struct JoinCurveChainTests {
    /// A sketch of unconstrained lines, one per consecutive pair of `points` (meters), plus any
    /// `extra` lines given by their end points.
    private func lines(
        _ points: [(Double, Double)],
        extra: [((Double, Double), (Double, Double))] = []
    ) throws -> (session: EditorSession, featureID: FeatureID, lineIDs: [SketchEntityID]) {
        func point(_ p: (Double, Double)) -> SketchPoint {
            SketchPoint(x: .length(p.0, .meter), y: .length(p.1, .meter))
        }
        var document = DesignDocument.empty()
        let featureID = try document.createLineSketch(name: "Chain", plane: .xy, start: point(points[0]), end: point(points[1]))
        var ids: [SketchEntityID] = []
        var entities: [SketchEntityID: SketchEntity] = [:]
        for index in 0..<(points.count - 1) {
            let id = SketchEntityID()
            ids.append(id)
            entities[id] = .line(SketchLine(start: point(points[index]), end: point(points[index + 1])))
        }
        for (start, end) in extra {
            let id = SketchEntityID()
            ids.append(id)
            entities[id] = .line(SketchLine(start: point(start), end: point(end)))
        }
        var feature = try #require(document.cadDocument.designGraph.nodes[featureID])
        feature.operation = .sketch(Sketch(plane: .xy, entities: entities, constraints: []))
        document.cadDocument.designGraph.nodes[featureID] = feature
        document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
        return (EditorSession(document: document), featureID, ids)
    }

    private func targets(_ session: EditorSession, _ ids: [SketchEntityID]) throws -> [SelectionTarget] {
        let snapshot = try SketchEntitySnapshotService().snapshot(document: session.document)
        return try ids.map { id in
            let entry = try #require(snapshot.entries.first { $0.entityID == id.description })
            return try #require(entry.selectionTarget())
        }
    }

    private func sketch(_ session: EditorSession, _ featureID: FeatureID) throws -> Sketch {
        let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
        guard case .sketch(let sketch) = feature.operation else {
            Issue.record("The joined feature must stay a sketch.")
            throw EditorError(code: .commandInvalid, message: "not a sketch")
        }
        return sketch
    }

    @Test func threeCornerLinesJoinIntoOneCurveWithTwoJoints() throws {
        let setup = try lines([(0, 0), (0.01, 0), (0.01, 0.01), (0, 0.02)])
        let ids = setup.lineIDs
        let result = try setup.session.execute(.joinSketchCurveChain(targets: try targets(setup.session, ids)))

        #expect(result.commandName == "joinSketchCurveChain")
        let sources = setup.session.document.productMetadata.joinedCurveGroupSources
        #expect(sources.count == 1)
        let joined = try #require(sources.values.first)
        #expect(joined.memberEntityIDs == ids)
        #expect(joined.joints.map(\.firstReference) == [.lineEnd(ids[0]), .lineEnd(ids[1])])
        #expect(joined.joints.map(\.secondReference) == [.lineStart(ids[1]), .lineStart(ids[2])])
        let constraints = try sketch(setup.session, setup.featureID).constraints
        #expect(constraints.contains(.coincident(.lineEnd(ids[0]), .lineStart(ids[1]))))
        #expect(constraints.contains(.coincident(.lineEnd(ids[1]), .lineStart(ids[2]))))
        #expect(setup.session.evaluationStatus == .valid)
    }

    @Test func twoCornerLinesHoldTogetherInsteadOfBeingRefused() throws {
        let setup = try lines([(0, 0), (0.01, 0), (0.01, 0.01)])
        let ids = setup.lineIDs
        let pair = try targets(setup.session, ids)
        _ = try setup.session.execute(.joinSketchCurves(target: pair[0], adjacentTarget: pair[1]))

        let joined = try #require(setup.session.document.productMetadata.joinedCurveGroupSources.values.first)
        #expect(joined.memberEntityIDs == ids)
        #expect(joined.firstJoinedReference == .lineEnd(ids[0]))
        #expect(joined.secondJoinedReference == .lineStart(ids[1]))
        #expect(try sketch(setup.session, setup.featureID).entities.count == 2)
    }

    @Test func aCurveJoinsOntoAnExistingJoinedCurve() throws {
        let setup = try lines([(0, 0), (0.01, 0), (0.01, 0.01), (0, 0.02)])
        let ids = setup.lineIDs
        let all = try targets(setup.session, ids)
        _ = try setup.session.execute(.joinSketchCurves(target: all[0], adjacentTarget: all[1]))
        let firstGroup = try #require(setup.session.document.productMetadata.joinedCurveGroupSources.values.first)

        _ = try setup.session.execute(.joinSketchCurves(target: all[1], adjacentTarget: all[2]))

        let sources = setup.session.document.productMetadata.joinedCurveGroupSources
        #expect(sources.count == 1)
        let joined = try #require(sources.values.first)
        #expect(joined.id == firstGroup.id)
        #expect(joined.memberEntityIDs == ids)
        #expect(joined.joints.count == 2)
        #expect(joined.additionalJoints.first?.firstReference == .lineEnd(ids[1]))
        #expect(joined.additionalJoints.first?.secondReference == .lineStart(ids[2]))
    }

    @Test func twoJoinedCurvesMergeThroughANewJoint() throws {
        let setup = try lines([(0, 0), (0.01, 0), (0.01, 0.01), (0, 0.02), (0, 0.03)])
        let ids = setup.lineIDs
        let all = try targets(setup.session, ids)
        _ = try setup.session.execute(.joinSketchCurves(target: all[0], adjacentTarget: all[1]))
        _ = try setup.session.execute(.joinSketchCurves(target: all[2], adjacentTarget: all[3]))
        #expect(setup.session.document.productMetadata.joinedCurveGroupSources.count == 2)

        _ = try setup.session.execute(.joinSketchCurves(target: all[1], adjacentTarget: all[2]))

        let sources = setup.session.document.productMetadata.joinedCurveGroupSources
        #expect(sources.count == 1)
        let joined = try #require(sources.values.first)
        #expect(Set(joined.memberEntityIDs) == Set(ids))
        #expect(joined.joints.count == 3)
        #expect(setup.session.evaluationStatus == .valid)
    }

    @Test func unjoinAfterAnEditRemovesOnlyTheJoinConstraints() throws {
        let setup = try lines([(0, 0), (0.01, 0), (0.01, 0.01), (0, 0.02)])
        let ids = setup.lineIDs
        _ = try setup.session.execute(.joinSketchCurveChain(targets: try targets(setup.session, ids)))
        _ = try setup.session.execute(.addSketchConstraint(featureID: setup.featureID, constraint: .horizontal(ids[0])))
        let member = try targets(setup.session, [ids[2]])[0]
        _ = try setup.session.execute(.moveSketchEntityPoint(
            target: member,
            handle: .lineEnd,
            deltaX: .length(0.001, .meter),
            deltaY: .length(0.0, .meter)
        ))

        _ = try setup.session.execute(.unjoinSketchCurve(target: try targets(setup.session, [ids[1]])[0]))

        #expect(setup.session.document.productMetadata.joinedCurveGroupSources.isEmpty)
        let constraints = try sketch(setup.session, setup.featureID).constraints
        #expect(constraints == [.horizontal(ids[0])])
        #expect(setup.session.evaluationStatus == .valid)
    }

    @Test func threeEndsMeetingAtOnePointAreRefused() throws {
        let setup = try lines([(0, 0), (0.01, 0), (0.02, 0.01)], extra: [((0.01, 0), (0.01, -0.01))])
        let before = setup.session.generation
        #expect(throws: EditorError.self) {
            try setup.session.execute(.joinSketchCurveChain(targets: try targets(setup.session, setup.lineIDs)))
        }
        #expect(setup.session.generation == before)
        #expect(setup.session.document.productMetadata.joinedCurveGroupSources.isEmpty)
    }

    @Test func curvesThatDoNotMeetInOneChainAreRefused() throws {
        let setup = try lines([(0, 0), (0.01, 0), (0.01, 0.01)], extra: [((0.05, 0.05), (0.06, 0.05))])
        do {
            _ = try setup.session.execute(.joinSketchCurveChain(targets: try targets(setup.session, setup.lineIDs)))
            Issue.record("A curve that meets no other must refuse the join.")
        } catch let error as EditorError {
            #expect(error.message == "Join Curves requires the selected curves to meet end to end in one chain.")
        }
        #expect(setup.session.document.productMetadata.joinedCurveGroupSources.isEmpty)
    }

    @Test func aJoinedCurveSavedBeforeChainsDecodesWithOneJoint() throws {
        let setup = try lines([(0, 0), (0.01, 0), (0.01, 0.01)])
        let pair = try targets(setup.session, setup.lineIDs)
        _ = try setup.session.execute(.joinSketchCurves(target: pair[0], adjacentTarget: pair[1]))
        let joined = try #require(setup.session.document.productMetadata.joinedCurveGroupSources.values.first)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(joined)) as? [String: Any])
        object.removeValue(forKey: "additionalJoints")

        let decoded = try JSONDecoder().decode(JoinedCurveGroupSource.self, from: JSONSerialization.data(withJSONObject: object))

        #expect(decoded == joined)
        #expect(decoded.joints.count == 1)
        #expect(decoded.joints[0].addedConstraints == [.coincident(.lineEnd(setup.lineIDs[0]), .lineStart(setup.lineIDs[1]))])
    }
}
