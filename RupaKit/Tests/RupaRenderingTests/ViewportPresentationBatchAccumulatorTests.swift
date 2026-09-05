import CoreGraphics
import SwiftUI
import Testing
@testable import RupaRendering

private typealias BatchState = MeshSourcePresentationInteractionStateResolver.State

@Test
func presentationBatchMergesEveryPolygonOfAStateIntoOnePath() {
    var accumulator = ViewportPresentationBatchAccumulator()
    for index in 0..<64 {
        let offset = CGFloat(index)
        accumulator.append(
            [
                CGPoint(x: offset, y: 0.0),
                CGPoint(x: offset + 1.0, y: 0.0),
                CGPoint(x: offset, y: 1.0),
            ],
            state: .normal
        )
    }

    var batchCount = 0
    accumulator.forEachBatch { state, _ in
        batchCount += 1
        #expect(state == .normal)
    }
    #expect(batchCount == 1)
}

@Test
func presentationBatchSkipsStatesThatAccumulatedNothing() {
    var accumulator = ViewportPresentationBatchAccumulator()
    accumulator.append(
        [
            CGPoint(x: 0.0, y: 0.0),
            CGPoint(x: 1.0, y: 0.0),
            CGPoint(x: 0.0, y: 1.0),
        ],
        state: .selected
    )

    var states: [BatchState] = []
    accumulator.forEachBatch { state, _ in
        states.append(state)
    }
    #expect(states == [.selected])
}

@Test
func presentationBatchVisitsStatesInDrawOrder() {
    var accumulator = ViewportPresentationBatchAccumulator()
    let triangle = [
        CGPoint(x: 0.0, y: 0.0),
        CGPoint(x: 1.0, y: 0.0),
        CGPoint(x: 0.0, y: 1.0),
    ]
    accumulator.append(triangle, state: .selected)
    accumulator.append(triangle, state: .normal)
    accumulator.append(triangle, state: .hovered)

    var states: [BatchState] = []
    accumulator.forEachBatch { state, _ in
        states.append(state)
    }
    #expect(states == [.normal, .hovered, .selected])
}

@Test
func presentationBatchNormalizesWindingSoOneNonZeroFillCoversTheUnion() {
    let clockwise = [
        CGPoint(x: 0.0, y: 0.0),
        CGPoint(x: 10.0, y: 0.0),
        CGPoint(x: 0.0, y: 10.0),
    ]
    let counterClockwise = [
        CGPoint(x: 0.0, y: 0.0),
        CGPoint(x: 0.0, y: 10.0),
        CGPoint(x: 10.0, y: 0.0),
    ]
    let overlap = CGPoint(x: 2.0, y: 2.0)

    // Without normalization the two windings cancel under a non-zero fill, so
    // the shared area would be a hole rather than a covered surface.
    var unnormalized = Path()
    for points in [clockwise, counterClockwise] {
        unnormalized.move(to: points[0])
        unnormalized.addLine(to: points[1])
        unnormalized.addLine(to: points[2])
        unnormalized.closeSubpath()
    }
    #expect(unnormalized.contains(overlap, eoFill: false) == false)

    var accumulator = ViewportPresentationBatchAccumulator()
    accumulator.append(clockwise, state: .normal)
    accumulator.append(counterClockwise, state: .normal)

    var merged: Path?
    accumulator.forEachBatch { _, path in
        merged = path
    }
    let path = try! #require(merged)
    #expect(path.contains(overlap, eoFill: false))
}

@Test
func presentationBatchAppendsAQuadrilateralAsOneSubpath() {
    var accumulator = ViewportPresentationBatchAccumulator()
    accumulator.append(
        [
            CGPoint(x: 0.0, y: 0.0),
            CGPoint(x: 4.0, y: 0.0),
            CGPoint(x: 4.0, y: 4.0),
            CGPoint(x: 0.0, y: 4.0),
        ],
        state: .hovered
    )

    var merged: Path?
    accumulator.forEachBatch { _, path in
        merged = path
    }
    let path = try! #require(merged)
    #expect(path.contains(CGPoint(x: 2.0, y: 2.0), eoFill: false))
    #expect(path.contains(CGPoint(x: 5.0, y: 2.0), eoFill: false) == false)
}

@Test
func presentationBatchDropsAPolygonThatBoundsNoArea() {
    var accumulator = ViewportPresentationBatchAccumulator()
    accumulator.append([CGPoint(x: 0.0, y: 0.0), CGPoint(x: 1.0, y: 0.0)], state: .normal)

    var batchCount = 0
    accumulator.forEachBatch { _, _ in
        batchCount += 1
    }
    #expect(batchCount == 0)
}
