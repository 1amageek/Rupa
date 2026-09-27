import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Bridge reads its two ends from the selection: two curves meet at their nearest ends, two curve
/// ends meet where they are.
@MainActor
@Suite struct BridgeSelectionTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: mm(x), y: mm(y)) }

    private struct Fixture {
        var session: EditorSession
        var featureID: FeatureID
        var sceneNodeID: SceneNodeID
        var left: SketchEntityID
        var right: SketchEntityID
    }

    /// Two collinear-ish lines with a gap: the left one ends at (10, 0), the right one starts at
    /// (15, 5).
    private func fixture() throws -> Fixture {
        let (left, right) = (SketchEntityID(), SketchEntityID())
        let session = EditorSession()
        _ = try session.execute(.createSketch(
            name: "Bridge",
            sketch: Sketch(plane: .xy, entities: [
                left: .line(SketchLine(start: point(0, 0), end: point(10, 0))),
                right: .line(SketchLine(start: point(15, 5), end: point(25, 5))),
            ]),
            geometryRole: .curve
        ))
        let featureID = try #require(session.document.cadDocument.designGraph.order.last)
        let node = try #require(session.document.productMetadata.sceneNodes.values.first {
            $0.reference?.featureID == featureID
        })
        return Fixture(session: session, featureID: featureID, sceneNodeID: node.id, left: left, right: right)
    }

    private func curve(_ fixture: Fixture, _ entityID: SketchEntityID) -> SelectionTarget {
        SelectionTarget(sceneNodeID: fixture.sceneNodeID, component: .sketchEntity(
            .sketchEntity(featureID: fixture.featureID, entityID: entityID)
        ))
    }

    private func vertex(_ fixture: Fixture, _ entityID: SketchEntityID, _ handle: SketchEntityPointHandle) -> SelectionTarget {
        SelectionTarget(sceneNodeID: fixture.sceneNodeID, component: .sketchEntity(
            .sketchPointHandle(featureID: fixture.featureID, entityID: entityID, handle: handle)
        ))
    }

    @Test func twoCurvesMeetAtTheirNearestEnds() throws {
        let fixture = try fixture()
        let ends = try fixture.session.document.bridgeEndpoints(for: [
            curve(fixture, fixture.left), curve(fixture, fixture.right),
        ])
        #expect(ends.featureID == fixture.featureID)
        #expect(ends.first.reference == .lineEnd(fixture.left))
        #expect(ends.second.reference == .lineStart(fixture.right))
    }

    @Test func twoCurveEndsMeetWhereTheyAre() throws {
        let fixture = try fixture()
        // The far ends, which the nearest-end rule for curves would not pick.
        let ends = try fixture.session.document.bridgeEndpoints(for: [
            vertex(fixture, fixture.left, .lineStart), vertex(fixture, fixture.right, .lineEnd),
        ])
        #expect(ends.first.reference == .lineStart(fixture.left))
        #expect(ends.second.reference == .lineEnd(fixture.right))
    }

    @Test func aCreatedBridgeJoinsTheChosenEnds() throws {
        let fixture = try fixture()
        let ends = try fixture.session.document.bridgeEndpoints(for: [
            curve(fixture, fixture.left), curve(fixture, fixture.right),
        ])
        _ = try fixture.session.execute(.createBridgeCurve(
            featureID: ends.featureID, firstEndpoint: ends.first, secondEndpoint: ends.second, continuity: .g1
        ))
        let source = try #require(fixture.session.document.productMetadata.bridgeCurveSources.values.first)
        #expect(source.firstEndpoint.reference == .lineEnd(fixture.left))
        #expect(source.secondEndpoint.reference == .lineStart(fixture.right))
        #expect(source.continuity == .g1)
    }

    @Test func aCenterOrASingleTargetIsRefused() throws {
        let fixture = try fixture()
        #expect(throws: EditorError.self) {
            _ = try fixture.session.document.bridgeEndpoints(for: [curve(fixture, fixture.left)])
        }
        let (circle, line) = (SketchEntityID(), SketchEntityID())
        let session = EditorSession()
        _ = try session.execute(.createSketch(
            name: "Circle",
            sketch: Sketch(plane: .xy, entities: [
                circle: .circle(SketchCircle(center: point(0, 0), radius: mm(3))),
                line: .line(SketchLine(start: point(10, 0), end: point(20, 0))),
            ]),
            geometryRole: .curve
        ))
        let featureID = try #require(session.document.cadDocument.designGraph.order.last)
        let node = try #require(session.document.productMetadata.sceneNodes.values.first {
            $0.reference?.featureID == featureID
        })
        let center = SelectionTarget(sceneNodeID: node.id, component: .sketchEntity(
            .sketchPointHandle(featureID: featureID, entityID: circle, handle: .circleCenter)
        ))
        let lineCurve = SelectionTarget(sceneNodeID: node.id, component: .sketchEntity(
            .sketchEntity(featureID: featureID, entityID: line)
        ))
        #expect(throws: EditorError.self) {
            _ = try session.document.bridgeEndpoints(for: [center, lineCurve])
        }
    }

    @Test func curvesOfTwoSketchesAreRefused() throws {
        let fixture = try fixture()
        let other = SketchEntityID()
        _ = try fixture.session.execute(.createSketch(
            name: "Other",
            sketch: Sketch(plane: .xy, entities: [other: .line(SketchLine(start: point(0, 9), end: point(9, 9)))]),
            geometryRole: .curve
        ))
        let otherFeature = try #require(fixture.session.document.cadDocument.designGraph.order.last)
        let otherNode = try #require(fixture.session.document.productMetadata.sceneNodes.values.first {
            $0.reference?.featureID == otherFeature
        })
        let otherCurve = SelectionTarget(sceneNodeID: otherNode.id, component: .sketchEntity(
            .sketchEntity(featureID: otherFeature, entityID: other)
        ))
        #expect(throws: EditorError.self) {
            _ = try fixture.session.document.bridgeEndpoints(for: [curve(fixture, fixture.left), otherCurve])
        }
    }
}
