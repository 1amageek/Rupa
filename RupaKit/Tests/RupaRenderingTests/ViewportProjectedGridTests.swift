import CoreGraphics
import Testing
import RupaCore
import RupaViewportScene
@testable import RupaRendering

@Test func viewportProjectedGridCreatesCoordinateParallelLines() {
    let document = DesignDocument.empty()
    let ruler = RulerConfiguration.standard(for: .millimeter)

    let grid = ViewportProjectedGrid(
        document: document,
        ruler: ruler,
        size: CGSize(width: 800.0, height: 600.0)
    )
    let xLines = grid.lines(for: .x)
    let zLines = grid.lines(for: .z)
    let firstXVector = vector(for: xLines[0])
    let firstZVector = vector(for: zLines[0])
    let scaleLabelAxes = Set(grid.scaleLabels.map(\.axis))

    #expect(!xLines.isEmpty)
    #expect(!zLines.isEmpty)
    #expect(xLines.contains { $0.isMajor })
    #expect(zLines.contains { $0.isMajor })
    #expect(xLines.contains { $0.isOrigin })
    #expect(zLines.contains { $0.isOrigin })
    #expect(scaleLabelAxes.contains(.x))
    #expect(scaleLabelAxes.contains(.z))
    #expect(grid.scaleLabels.allSatisfy {
        let multiple = abs($0.valueMeters / grid.majorStepMeters)
        return abs(multiple - multiple.rounded()) < 1.0e-9
    })
    #expect(grid.scaleLabels.allSatisfy { $0.displayUnit.isMetric })
    #expect(grid.scaleLabels.allSatisfy { abs($0.displayValue) <= 1_000.0 })
    #expect(grid.scaleLabels.allSatisfy { abs($0.valueMeters) >= grid.majorStepMeters - 1.0e-12 })
    #expect(grid.scaleReadout.minorStep.meters == grid.minorStepMeters)
    #expect(grid.scaleReadout.majorStep.meters == grid.majorStepMeters)
    #expect(grid.scaleReadout.snapStep.meters == ruler.minorTickMeters)
    #expect(grid.scaleReadout.minorStepPixels == grid.minorStepPixels)
    #expect(grid.scaleReadout.visualSpacingMode == .adaptive)
    #expect(grid.scaleReadout.accessibilityText.contains("mode adaptive"))
    #expect(grid.scaleReadout.accessibilityText.contains(grid.scaleReadout.snapStep.text))
    #expect(grid.scaleReadout.accessibilityText.contains(grid.scaleReadout.visibleSpan.text))
    #expect(grid.scaleReadout.workspaceSpan.meters == ruler.visibleSpanMeters)
    #expect(grid.scaleReadout.accessibilityText.contains("workspace span"))
    #expect(grid.scaleReadout.accessibilityText.contains(grid.scaleReadout.workspaceSpan.text))
    #expect(grid.majorStepMeters >= ruler.majorTickMeters)
    #expect(grid.minorStepMeters >= ruler.minorTickMeters)
    #expect(grid.layout.viewportSize == CGSize(width: 800.0, height: 600.0))
    #expect(grid.layout.basis == grid.basis)
    #expect(abs(firstXVector.dx) > 0.0)
    #expect(abs(firstXVector.dy) > 0.0)
    #expect(abs(firstZVector.dx) > 0.0)
    #expect(abs(firstZVector.dy) > 0.0)
    #expect(firstXVector.dx * firstZVector.dx < 0.0)
    #expect(!isParallel(firstXVector, firstZVector))
    #expect(xLines.prefix(12).allSatisfy { isParallel(vector(for: $0), firstXVector) })
    #expect(zLines.prefix(12).allSatisfy { isParallel(vector(for: $0), firstZVector) })
}

@Test func viewportProjectedGridUsesExplicitWorkspaceRuler() {
    let document = DesignDocument.empty()
    let ruler = WorkspaceScalePreset.sitePlanning.rulerConfiguration

    let grid = ViewportProjectedGrid(
        document: document,
        ruler: ruler,
        size: CGSize(width: 800.0, height: 600.0)
    )

    #expect(ruler != RulerConfiguration.standard(for: .millimeter))
    #expect(grid.scaleReadout.workspaceSpan.meters == ruler.visibleSpanMeters)
    #expect(grid.scaleReadout.workspaceSpan.displayUnit == ruler.displayUnit)
    #expect(grid.scaleLabels.allSatisfy { $0.displayUnit == ruler.displayUnit })
}

@Test func viewportProjectedGridSupportsArchitectureScaleRuler() throws {
    let document = DesignDocument.empty()
    let ruler = RulerConfiguration(
        displayUnit: .meter,
        minorTickMeters: 1.0,
        majorTickMeters: 10.0,
        visibleSpanMeters: RulerConfiguration.visibleSpanMetersRange.upperBound
    )

    let grid = ViewportProjectedGrid(
        document: document,
        ruler: ruler,
        size: CGSize(width: 800.0, height: 600.0)
    )

    #expect(!grid.lines.isEmpty)
    #expect(grid.lines.count < 400)
    #expect(grid.minorStepMeters >= ruler.minorTickMeters)
    #expect(grid.majorStepMeters >= ruler.majorTickMeters)
    #expect(grid.scaleLabels.allSatisfy { $0.displayUnit.isMetric })
    #expect(grid.scaleLabels.allSatisfy { abs($0.displayValue) <= 1_000.0 })
    #expect(grid.scaleReadout.majorStep.displayUnit.isMetric)
    #expect(grid.scaleReadout.visibleSpan.displayUnit == .kilometer)
    #expect(grid.scaleReadout.workspaceSpan.displayUnit == .kilometer)
    #expect(grid.scaleReadout.workspaceSpan.meters == ruler.visibleSpanMeters)
}

@Test func viewportProjectedGridReportsSitePlanningScaleReadout() throws {
    let document = DesignDocument.empty()
    let ruler = WorkspaceScalePreset.sitePlanning.rulerConfiguration

    let grid = ViewportProjectedGrid(
        document: document,
        ruler: ruler,
        size: CGSize(width: 800.0, height: 600.0)
    )

    #expect(grid.scaleReadout.minorStep.meters == grid.minorStepMeters)
    #expect(grid.scaleReadout.majorStep.meters == grid.majorStepMeters)
    #expect(grid.scaleReadout.snapStep.meters == ruler.minorTickMeters)
    #expect(grid.scaleReadout.minorStep.displayUnit == .kilometer)
    #expect(grid.scaleReadout.majorStep.displayUnit == .kilometer)
    #expect(grid.scaleReadout.snapStep.displayUnit == .kilometer)
    #expect(grid.scaleReadout.visibleSpan.displayUnit == .kilometer)
    #expect(grid.scaleReadout.workspaceSpan.displayUnit == .kilometer)
    #expect(grid.scaleReadout.workspaceSpan.meters == ruler.visibleSpanMeters)
    #expect(grid.scaleReadout.workspaceSpan.text == "100km")
    #expect(grid.scaleReadout.minorStep.meters > grid.scaleReadout.snapStep.meters)
    #expect(grid.scaleReadout.accessibilityText.contains("major"))
    #expect(grid.scaleReadout.accessibilityText.contains("snap"))
    #expect(grid.scaleReadout.accessibilityText.contains("visible span"))
}

@Test func viewportProjectedGridReportsUrbanPlanningScaleReadout() throws {
    let document = DesignDocument.empty()
    let ruler = WorkspaceScalePreset.urbanPlanning.rulerConfiguration

    let grid = ViewportProjectedGrid(
        document: document,
        ruler: ruler,
        size: CGSize(width: 1_000.0, height: 720.0)
    )

    #expect(!grid.lines.isEmpty)
    #expect(grid.lines.count <= 380)
    #expect(grid.scaleReadout.snapStep.meters == ruler.minorTickMeters)
    #expect(grid.scaleReadout.snapStep.text == "10m")
    #expect(grid.scaleReadout.majorStep.displayUnit.isMetric)
    #expect(grid.scaleReadout.visibleSpan.displayUnit == .kilometer)
    #expect(grid.scaleReadout.workspaceSpan.displayUnit == .kilometer)
    #expect(grid.scaleReadout.workspaceSpan.meters == ruler.visibleSpanMeters)
    #expect(grid.scaleReadout.workspaceSpan.text == "25km")
    #expect(grid.scaleReadout.minorStep.meters >= grid.scaleReadout.snapStep.meters)
    #expect(grid.scaleReadout.accessibilityText.contains("workspace span 25km"))
}

@Test func viewportProjectedGridReportsRegionalPlanningScaleReadout() throws {
    let document = DesignDocument.empty(named: "Regional Grid")
    let ruler = WorkspaceScalePreset.regionalPlanning.rulerConfiguration

    let grid = ViewportProjectedGrid(
        document: document,
        ruler: ruler,
        size: CGSize(width: 1_200.0, height: 800.0),
        camera: .identity,
        basis: .isometric,
        visualSpacingMode: .adaptive
    )

    #expect(!grid.lines.isEmpty)
    #expect(grid.lines.count <= 380)
    #expect(grid.scaleReadout.minorStep.displayUnit == .kilometer)
    #expect(grid.scaleReadout.majorStep.displayUnit == .kilometer)
    #expect(grid.scaleReadout.snapStep.displayUnit == .kilometer)
    #expect(grid.scaleReadout.snapStep.meters == ruler.minorTickMeters)
    #expect(grid.scaleReadout.visibleSpan.displayUnit == .kilometer)
    #expect(grid.scaleReadout.workspaceSpan.displayUnit == .kilometer)
    #expect(grid.scaleReadout.workspaceSpan.meters == ruler.visibleSpanMeters)
    #expect(grid.scaleReadout.workspaceSpan.text == "1,000km")
    #expect(grid.scaleReadout.accessibilityText.contains(grid.scaleReadout.visibleSpan.text))
    #expect(grid.scaleReadout.minorStep.text.hasSuffix("km"))
    #expect(grid.scaleReadout.majorStep.text.hasSuffix("km"))
    #expect(grid.scaleReadout.visibleSpan.text.hasSuffix("km"))
    #expect(grid.scaleLabels.contains { label in
        label.displayUnit == .kilometer && label.text.hasSuffix("km")
    })
}

@Test func viewportProjectedGridPreservesFixedVisualSpacingWhenWithinLineBudget() throws {
    let document = DesignDocument.empty()
    let ruler = WorkspaceScalePreset.architectureImperial.rulerConfiguration
    let size = CGSize(width: 800.0, height: 600.0)
    let identityLayout = ViewportModelCoordinateMapper(
        document: document,
        ruler: ruler,
        size: size
    ).layout
    let maximumZoom = ViewportCameraZoomPolicy.maximumZoom(
        ruler: ruler,
        identityScale: identityLayout.scale
    )

    let grid = ViewportProjectedGrid(
        document: document,
        ruler: ruler,
        size: size,
        camera: ViewportCamera(zoom: maximumZoom * 2.0),
        visualSpacingMode: .fixed
    )

    #expect(!grid.lines.isEmpty)
    #expect(grid.lines.count < 400)
    #expect(grid.scaleReadout.visualSpacingMode == .fixed)
    #expect(!grid.scaleReadout.isVisualStepCapped)
    #expect(grid.minorStepMeters == ruler.minorTickMeters)
    #expect(grid.scaleReadout.minorStep.meters == ruler.minorTickMeters)
    #expect(grid.scaleReadout.snapStep.meters == ruler.minorTickMeters)
    #expect(grid.scaleReadout.minorStep.displayUnit == .foot)
    #expect(grid.scaleReadout.snapStep.displayUnit == .foot)
    #expect(grid.scaleReadout.minorStep.meters == grid.scaleReadout.snapStep.meters)
    #expect(grid.scaleReadout.accessibilityText.contains("mode fixed"))
}

@Test func viewportProjectedGridCapsVisualLinesWithoutChangingSnapStep() throws {
    let document = DesignDocument.empty(named: "Site Grid")
    let ruler = WorkspaceScalePreset.sitePlanning.rulerConfiguration

    let grid = ViewportProjectedGrid(
        document: document,
        ruler: ruler,
        size: CGSize(width: 1_200.0, height: 800.0),
        camera: ViewportCamera(zoom: ViewportCamera.minimumZoom),
        basis: .isometric,
        visualSpacingMode: .fixed
    )

    #expect(!grid.lines.isEmpty)
    #expect(grid.lines.count <= 380)
    #expect(grid.scaleReadout.visualSpacingMode == .fixed)
    #expect(grid.scaleReadout.isVisualStepCapped)
    #expect(grid.scaleReadout.snapStep.meters == 100.0)
    #expect(grid.scaleReadout.snapStep.text == "0.1km")
    #expect(grid.scaleReadout.minorStep.meters > grid.scaleReadout.snapStep.meters)
    #expect(grid.scaleReadout.accessibilityText.contains("visual grid capped"))
    #expect(grid.scaleReadout.accessibilityText.contains("workspace span 100km"))
}

@Test func viewportProjectedGridCapsFixedVisualSpacingForDenseRegionalViews() throws {
    let document = DesignDocument.empty()
    let ruler = WorkspaceScalePreset.regionalPlanning.rulerConfiguration

    let grid = ViewportProjectedGrid(
        document: document,
        ruler: ruler,
        size: CGSize(width: 800.0, height: 600.0),
        visualSpacingMode: .fixed
    )

    #expect(!grid.lines.isEmpty)
    #expect(grid.lines.count < 400)
    #expect(grid.scaleReadout.visualSpacingMode == .fixed)
    #expect(grid.scaleReadout.isVisualStepCapped)
    #expect(grid.minorStepMeters > ruler.minorTickMeters)
    #expect(grid.scaleReadout.minorStep.meters == grid.minorStepMeters)
    #expect(grid.scaleReadout.snapStep.meters == ruler.minorTickMeters)
    #expect(grid.scaleReadout.minorStep.meters > grid.scaleReadout.snapStep.meters)
    #expect(grid.scaleReadout.accessibilityText.contains("visual grid capped by line budget"))
    #expect(grid.scaleReadout.accessibilityText.contains("workspace span 1,000km"))
}

@Test func viewportProjectedGridUsesReadableOneTwoFiveStepProgression() {
    #expect(ViewportProjectedGrid.readableStep(atLeast: 0.000_25) == 0.000_5)
    #expect(ViewportProjectedGrid.readableStep(atLeast: 0.001) == 0.001)
    #expect(ViewportProjectedGrid.readableStep(atLeast: 0.003) == 0.005)
    #expect(ViewportProjectedGrid.readableStep(atLeast: 300.0) == 500.0)
    #expect(ViewportProjectedGrid.nextReadableStep(after: 500.0) == 1_000.0)
    #expect(ViewportProjectedGrid.nextReadableStep(after: 1_000.0) == 2_000.0)
    #expect(ViewportProjectedGrid.nextReadableStep(after: 2_000.0) == 5_000.0)
}

@Test func viewportProjectedGridFormatsLargeScaleLabelsWithGrouping() {
    #expect(
        ViewportProjectedGrid.formattedScaleLabel(
            valueMeters: 1_000.0,
            unit: .meter
        ) == "1km"
    )
    #expect(
        ViewportProjectedGrid.formattedScaleLabel(
            valueMeters: 1.0,
            unit: .millimeter
        ) == "1m"
    )
    #expect(
        ViewportProjectedGrid.formattedScaleLabel(
            valueMeters: 1.0,
            unit: .kilometer
        ) == "1m"
    )
    #expect(
        ViewportProjectedGrid.formattedScaleLabel(
            valueMeters: 0.000_25,
            unit: .meter
        ) == "250μm"
    )
    #expect(
        ViewportProjectedGrid.formattedScaleLabel(
            valueMeters: -0.000_25,
            unit: .meter
        ) == "-250μm"
    )
    #expect(
        ViewportProjectedGrid.formattedScaleLabel(
            valueMeters: 30_480.0,
            unit: .foot
        ) == "100,000ft"
    )
    #expect(
        ViewportProjectedGrid.formattedScaleLabel(
            valueMeters: -1_000.0,
            unit: .meter
        ) == "-1km"
    )
    #expect(
        ViewportProjectedGrid.formattedScaleLabel(
            valueMeters: 100_000.0,
            unit: .kilometer
        ) == "100km"
    )
}

@Test func viewportProjectedGridPreservesSignedCoordinateScaleLabels() throws {
    let document = DesignDocument.empty(named: "Signed Grid")
    let ruler = WorkspaceScalePreset.sitePlanning.rulerConfiguration

    let grid = ViewportProjectedGrid(
        document: document,
        ruler: ruler,
        size: CGSize(width: 1_200.0, height: 800.0),
        camera: .identity,
        basis: .isometric,
        visualSpacingMode: .adaptive
    )
    let negativeLabel = try #require(grid.scaleLabels.first { $0.valueMeters < 0.0 })
    let positiveLabel = try #require(grid.scaleLabels.first { $0.valueMeters > 0.0 })

    #expect(negativeLabel.displayValue < 0.0)
    #expect(negativeLabel.text.hasPrefix("-"))
    #expect(negativeLabel.displayUnit == .kilometer)
    #expect(positiveLabel.displayValue > 0.0)
    #expect(!positiveLabel.text.hasPrefix("-"))
}

@Test func viewportProjectedGridKeepsReadableMeterLabelsForArchitectureScale() throws {
    let document = DesignDocument.empty(named: "Architecture Grid")
    let ruler = WorkspaceScalePreset.architecture.rulerConfiguration

    let grid = ViewportProjectedGrid(
        document: document,
        ruler: ruler,
        size: CGSize(width: 1_000.0, height: 720.0),
        camera: .identity,
        basis: .axisFront(.y),
        visualSpacingMode: .adaptive
    )

    #expect(!grid.lines.isEmpty)
    #expect(grid.scaleReadout.minorStep.displayUnit == .meter)
    #expect(grid.scaleReadout.snapStep.text == "0.1m")
    #expect(grid.scaleLabels.contains { label in
        label.displayUnit == .meter && label.text.hasSuffix("m")
    })
}

@Test func viewportProjectedGridKeepsScaleLabelsVisuallySeparated() throws {
    let document = DesignDocument.empty(named: "Dense Label Grid")
    let ruler = WorkspaceScalePreset.architecture.rulerConfiguration

    let grid = ViewportProjectedGrid(
        document: document,
        ruler: ruler,
        size: CGSize(width: 360.0, height: 240.0),
        camera: .identity,
        basis: .isometric,
        visualSpacingMode: .adaptive
    )
    let labelsByAxis = Dictionary(grouping: grid.scaleLabels, by: \.axis)

    #expect(!grid.scaleLabels.isEmpty)
    for labels in labelsByAxis.values {
        let sorted = labels.sorted { $0.valueMeters < $1.valueMeters }
        for (previous, current) in zip(sorted, sorted.dropFirst()) {
            #expect(distance(previous.position, current.position) >= 70.0)
        }
    }
}

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
    #expect(frame.screenLabels.allSatisfy { label in
        label.text == ViewportProjectedGrid.formattedScaleLabel(
            valueMeters: label.valueMeters,
            unit: ruler.displayUnit
        )
    })
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

private func vector(for line: ViewportProjectedGrid.Line) -> CGVector {
    CGVector(
        dx: line.end.x - line.start.x,
        dy: line.end.y - line.start.y
    )
}

private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
    hypot(first.x - second.x, first.y - second.y)
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
