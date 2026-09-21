import CoreGraphics
import Testing
import RupaCore
import RupaViewportScene
@testable import RupaRendering

@Test func viewportProjectedGridNativeFrameUsesNativeProjectionAndCompleteWorldLines() throws {
    let ruler = RulerConfiguration(
        displayUnit: .meter,
        minorTickMeters: 0.1,
        majorTickMeters: 1.0,
        visibleSpanMeters: 100.0
    )
    let input = makeNativeGridInput(
        ruler: ruler,
        projectedScale: 20.0,
        pan: .zero,
        projection: .orthographic
    )

    let frame = try #require(try ViewportProjectedGrid.makeNativeFrame(input))

    #expect(!frame.worldLines.isEmpty)
    #expect(frame.worldLines.count <= ViewportProjectedGrid.maximumGridLineCount)
    #expect(frame.worldLines.contains { $0.isOrigin })
    #expect(frame.worldLines.contains { $0.isMajor })
    #expect(frame.worldLines.allSatisfy { line in
        line.start.isFinite && line.end.isFinite
    })
    #expect(frame.worldLines.allSatisfy { line in
        let start = input.project(line.start)
        let end = input.project(line.end)
        return start?.x.isFinite == true && start?.y.isFinite == true
            && end?.x.isFinite == true && end?.y.isFinite == true
    })
    #expect(!frame.screenLabels.isEmpty)
    #expect(frame.screenLabels.contains { $0.valueMeters < 0.0 })
    #expect(frame.screenLabels.contains { $0.valueMeters > 0.0 })
    #expect(frame.screenLabels.allSatisfy { !$0.text.isEmpty })
    #expect(frame.scaleReadout.minorStep.meters == frame.minorStepMeters)
    #expect(frame.scaleReadout.majorStep.meters == frame.majorStepMeters)
    #expect(frame.scaleReadout.snapStep.meters == ruler.minorTickMeters)
}

@Test func viewportProjectedGridNativeFrameRespondsToPanZoomAndProjectionMode() throws {
    let ruler = RulerConfiguration(
        displayUnit: .meter,
        minorTickMeters: 0.1,
        majorTickMeters: 1.0,
        visibleSpanMeters: 100.0
    )
    let baseInput = makeNativeGridInput(
        ruler: ruler,
        projectedScale: 20.0,
        pan: .zero,
        projection: .orthographic
    )
    let pannedInput = makeNativeGridInput(
        ruler: ruler,
        projectedScale: 20.0,
        pan: CGPoint(x: 120.0, y: -40.0),
        projection: .orthographic
    )
    let zoomedInput = makeNativeGridInput(
        ruler: ruler,
        projectedScale: 80.0,
        pan: .zero,
        projection: .orthographic
    )
    let perspectiveInput = makeNativeGridInput(
        ruler: ruler,
        projectedScale: 20.0,
        pan: .zero,
        projection: .perspective
    )

    let base = try #require(try ViewportProjectedGrid.makeNativeFrame(baseInput))
    let panned = try #require(try ViewportProjectedGrid.makeNativeFrame(pannedInput))
    let zoomed = try #require(try ViewportProjectedGrid.makeNativeFrame(zoomedInput))
    let perspective = try #require(try ViewportProjectedGrid.makeNativeFrame(perspectiveInput))

    #expect(base.worldBounds.origin != panned.worldBounds.origin)
    #expect(base.worldBounds.size != zoomed.worldBounds.size)
    #expect(base.worldLines.map(\.start) != perspective.worldLines.map(\.start))
    #expect(base.worldLines.count <= ViewportProjectedGrid.maximumGridLineCount)
    #expect(zoomed.worldLines.count <= ViewportProjectedGrid.maximumGridLineCount)
    #expect(perspective.worldLines.count <= ViewportProjectedGrid.maximumGridLineCount)
}

@Test func viewportProjectedGridNativeFrameSeparatesFixedAndAdaptiveSpacing() throws {
    let ruler = RulerConfiguration(
        displayUnit: .meter,
        minorTickMeters: 0.1,
        majorTickMeters: 1.0,
        visibleSpanMeters: 100.0
    )
    let fixedInput = makeNativeGridInput(
        ruler: ruler,
        projectedScale: 20.0,
        pan: .zero,
        projection: .orthographic,
        visualSpacingMode: .fixed
    )
    let adaptiveInput = makeNativeGridInput(
        ruler: ruler,
        projectedScale: 20.0,
        pan: .zero,
        projection: .orthographic,
        visualSpacingMode: .adaptive
    )

    let fixed = try #require(try ViewportProjectedGrid.makeNativeFrame(fixedInput))
    let adaptive = try #require(try ViewportProjectedGrid.makeNativeFrame(adaptiveInput))

    #expect(fixed.scaleReadout.visualSpacingMode == .fixed)
    #expect(adaptive.scaleReadout.visualSpacingMode == .adaptive)
    #expect(fixed.scaleReadout.snapStep.meters == ruler.minorTickMeters)
    #expect(adaptive.minorStepMeters >= ruler.minorTickMeters)
    #expect(fixed.worldLines.count <= ViewportProjectedGrid.maximumGridLineCount)
    #expect(adaptive.worldLines.count <= ViewportProjectedGrid.maximumGridLineCount)
}

@Test func viewportProjectedGridNativeFrameReturnsNoVisibleResultWithoutPlaneIntersection() throws {
    let input = ViewportProjectedGrid.NativeFrameInput(
        ruler: RulerConfiguration.standard(for: .meter),
        basis: .isometric,
        viewportSize: CGSize(width: 800.0, height: 600.0),
        projectedScale: 20.0,
        project: { _ in nil },
        unproject: { _, _ in nil }
    )

    let frame = try ViewportProjectedGrid.makeNativeFrame(input)

    #expect(frame == nil)
}

@Test func viewportProjectedGridNativeFrameAcceptsPartialCoverageAtPerspectiveHorizon() throws {
    let ruler = RulerConfiguration.standard(for: .meter)
    var unprojectCallCount = 0
    let partialCoverageInput = ViewportProjectedGrid.NativeFrameInput(
        ruler: ruler,
        basis: .isometric,
        viewportSize: CGSize(width: 800.0, height: 600.0),
        projectedScale: 20.0,
        project: { point in CGPoint(x: point.x, y: point.z) },
        unproject: { point, plane in
            unprojectCallCount += 1
            guard unprojectCallCount > 1 else { return nil }
            return plane.worldPoint(
                first: Double(point.x),
                second: Double(point.y)
            )
        }
    )

    let frame = try ViewportProjectedGrid.makeNativeFrame(partialCoverageInput)

    #expect(frame != nil)
    #expect((frame?.worldLines.count ?? 0) <= ViewportProjectedGrid.maximumGridLineCount)
}

@Test func viewportProjectedGridNativeFrameRejectsNonFiniteUnprojection() throws {
    let input = ViewportProjectedGrid.NativeFrameInput(
        ruler: RulerConfiguration.standard(for: .meter),
        basis: .isometric,
        viewportSize: CGSize(width: 800.0, height: 600.0),
        projectedScale: 20.0,
        project: { point in CGPoint(x: point.x, y: point.z) },
        unproject: { _, _ in Point3D(x: .nan, y: 0.0, z: 0.0) }
    )

    #expect(throws: ViewportProjectedGrid.NativeFrameError.unprojectionFailed) {
        _ = try ViewportProjectedGrid.makeNativeFrame(input)
    }
}

private enum NativeGridProjectionFixture {
    case orthographic
    case perspective
}

private func makeNativeGridInput(
    ruler: RulerConfiguration,
    projectedScale: CGFloat,
    pan: CGPoint,
    projection: NativeGridProjectionFixture,
    visualSpacingMode: ViewportGridVisualSpacingMode = .adaptive
) -> ViewportProjectedGrid.NativeFrameInput {
    let viewportSize = CGSize(width: 800.0, height: 600.0)
    let center = CGPoint(x: viewportSize.width / 2.0, y: viewportSize.height / 2.0)
    let focalDepth = 10.0
    let perspectiveSlope = 0.025

    let project: (Point3D) -> CGPoint? = { point in
        let depth: Double
        switch projection {
        case .orthographic:
            depth = 1.0
        case .perspective:
            depth = focalDepth + perspectiveSlope * point.x
        }
        guard depth.isFinite, depth > 0.0 else { return nil }
        return CGPoint(
            x: center.x + pan.x + CGFloat(point.x / depth) * projectedScale,
            y: center.y + pan.y - CGFloat(point.z / depth) * projectedScale
        )
    }
    let unproject: (CGPoint, ViewportCanvasPlane) -> Point3D? = { point, plane in
        guard plane.firstAxis == .x, plane.secondAxis == .z else { return nil }
        let normalizedX = Double(point.x - center.x - pan.x) / Double(projectedScale)
        let normalizedZ = Double(center.y + pan.y - point.y) / Double(projectedScale)
        switch projection {
        case .orthographic:
            return plane.worldPoint(first: normalizedX, second: normalizedZ)
        case .perspective:
            let denominator = 1.0 - normalizedX * perspectiveSlope
            guard denominator.isFinite, abs(denominator) > 1.0e-9 else { return nil }
            let first = normalizedX * focalDepth / denominator
            let depth = focalDepth + perspectiveSlope * first
            return plane.worldPoint(
                first: first,
                second: normalizedZ * depth
            )
        }
    }
    return ViewportProjectedGrid.NativeFrameInput(
        ruler: ruler,
        basis: .isometric,
        viewportSize: viewportSize,
        projectedScale: projectedScale,
        project: project,
        unproject: unproject,
        visualSpacingMode: visualSpacingMode
    )
}
