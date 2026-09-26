import Foundation
import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

/// A new array is shaped by clicked directions, axis keys and Shift-wheel counts in its own frame.
@Suite struct WorkspaceArrayCreationSessionTests {
    private func rectangular() -> PatternArraySource {
        PatternArraySource(
            name: "Rectangular Array",
            definitionID: ComponentDefinitionID(),
            distribution: .rectangular(RectangularPatternArray(firstAxis: PatternArrayLinearAxis(
                direction: .unitX, distance: .length(0.15, .meter), copyCount: 3
            ))),
            rootSceneNodeID: SceneNodeID()
        )
    }

    @Test func clickedDirectionsAreMeasuredFromTheSelectionInTheArrayFrame() throws {
        var session = WorkspaceArrayCreationSession(
            sourceID: PatternArraySourceID(), originWorld: Point3D(x: 1, y: 0, z: 0), isRectangular: true
        )
        #expect(session.pickingSlot == .first)
        // The array frame is turned a quarter about Z, so world +Y is the frame's +X.
        let frame = try Transform3D.rotation(axis: .unitZ, angleRadians: .pi / 2)
        let first = try session.distribution(of: rectangular(), toward: Point3D(x: 1, y: 0.4, z: 0), patternFrame: frame)
        guard case .rectangular(let array) = first else { Issue.record("Expected a rectangular array."); return }
        #expect((array.firstAxis.direction - .unitX).length < 1e-12)
        #expect(abs((try #require(array.firstAxis.distance.constantLengthMeters)) - 0.4) < 1e-12)
        #expect(array.firstAxis.copyCount == 3)
        #expect(session.pickingSlot == nil)

        var source = rectangular()
        source.distribution = first
        session.pickSecondDirection()
        let second = try session.distribution(of: source, toward: Point3D(x: 0.7, y: 0, z: 0), patternFrame: frame)
        guard case .rectangular(let both) = second, let axis = both.secondAxis else {
            Issue.record("The second click adds the second direction.")
            return
        }
        #expect((axis.direction - Vector3D(x: 0, y: 1, z: 0)).length < 1e-12)
        #expect(abs((try #require(axis.distance.constantLengthMeters)) - 0.3) < 1e-12)
        #expect(axis.copyCount == 1)

        #expect(throws: EditorError.self) {
            _ = try session.distribution(of: source, toward: .origin, patternFrame: frame)
        }
    }

    @Test func axisKeysKeepTheDistanceAndShiftWheelNeverDropsBelowOneCopy() throws {
        let session = WorkspaceArrayCreationSession(
            sourceID: PatternArraySourceID(), originWorld: .origin, isRectangular: true
        )
        let along = try session.distribution(of: rectangular(), alongWorldAxis: .z, patternFrame: .identity)
        guard case .rectangular(let array) = along else { Issue.record("Expected a rectangular array."); return }
        #expect(array.firstAxis.direction == .unitZ)
        #expect(array.firstAxis.distance == .length(0.15, .meter))

        var source = rectangular()
        source.distribution = try session.distribution(of: source, addingCopies: 2)
        guard case .rectangular(let more) = source.distribution else { return }
        #expect(more.firstAxis.copyCount == 5)
        source.distribution = try session.distribution(of: source, addingCopies: -10)
        guard case .rectangular(let fewest) = source.distribution else { return }
        #expect(fewest.firstAxis.copyCount == 1)

        let radial = PatternArraySource(
            name: "Radial Array", definitionID: ComponentDefinitionID(),
            distribution: .radial(RadialPatternArray(angularAxis: PatternArrayAngularAxis(
                center: .origin, axis: .unitZ, angle: .angle(60, .degree), copyCount: 5
            ))),
            rootSceneNodeID: SceneNodeID()
        )
        guard case .radial(let ring) = try session.distribution(of: radial, addingCopies: 1) else { return }
        #expect(ring.angularAxis.copyCount == 6)
        #expect(throws: EditorError.self) {
            _ = try session.distribution(of: radial, alongWorldAxis: .x, patternFrame: .identity)
        }
    }
}

private extension CADExpression {
    var constantLengthMeters: Double? {
        if case .constant(let quantity) = self, quantity.kind == .length { return quantity.value }
        return nil
    }
}
