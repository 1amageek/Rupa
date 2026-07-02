import CoreGraphics
import Testing
import RupaCore
import RupaViewportScene
@testable import RupaRendering

@Test func viewportProjectedGridCreatesCoordinateParallelLines() {
    var document = DesignDocument.empty()
    document.setDisplayUnit(.millimeter)

    let grid = ViewportProjectedGrid(
        document: document,
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
    #expect(grid.scaleLabels.contains {
        abs(abs($0.valueMeters) - grid.majorStepMeters) < 1.0e-12
    })
    #expect(grid.scaleLabels.allSatisfy { $0.displayUnit.isMetric })
    #expect(grid.scaleLabels.allSatisfy { abs($0.displayValue) <= 1_000.0 })
    #expect(grid.scaleLabels.allSatisfy { abs($0.valueMeters) >= grid.majorStepMeters - 1.0e-12 })
    #expect(grid.scaleReadout.minorStep.meters == grid.minorStepMeters)
    #expect(grid.scaleReadout.majorStep.meters == grid.majorStepMeters)
    #expect(grid.scaleReadout.snapStep.meters == document.ruler.minorTickMeters)
    #expect(grid.scaleReadout.minorStepPixels == grid.minorStepPixels)
    #expect(grid.scaleReadout.visualSpacingMode == .adaptive)
    #expect(grid.scaleReadout.accessibilityText.contains("mode adaptive"))
    #expect(grid.scaleReadout.accessibilityText.contains(grid.scaleReadout.snapStep.text))
    #expect(grid.scaleReadout.accessibilityText.contains(grid.scaleReadout.visibleSpan.text))
    #expect(grid.majorStepMeters >= document.ruler.majorTickMeters)
    #expect(grid.minorStepMeters >= document.ruler.minorTickMeters)
    #expect(abs(firstXVector.dx) > 0.0)
    #expect(abs(firstXVector.dy) > 0.0)
    #expect(abs(firstZVector.dx) > 0.0)
    #expect(abs(firstZVector.dy) > 0.0)
    #expect(firstXVector.dx * firstZVector.dx < 0.0)
    #expect(!isParallel(firstXVector, firstZVector))
    #expect(xLines.prefix(12).allSatisfy { isParallel(vector(for: $0), firstXVector) })
    #expect(zLines.prefix(12).allSatisfy { isParallel(vector(for: $0), firstZVector) })
}

@Test func viewportProjectedGridSupportsArchitectureScaleRuler() throws {
    var document = DesignDocument.empty()
    try document.setRulerConfiguration(
        RulerConfiguration(
            displayUnit: .meter,
            minorTickMeters: 1.0,
            majorTickMeters: 10.0,
            visibleSpanMeters: RulerConfiguration.visibleSpanMetersRange.upperBound
        )
    )

    let grid = ViewportProjectedGrid(
        document: document,
        size: CGSize(width: 800.0, height: 600.0)
    )

    #expect(!grid.lines.isEmpty)
    #expect(grid.lines.count < 400)
    #expect(grid.minorStepMeters >= document.ruler.minorTickMeters)
    #expect(grid.majorStepMeters >= document.ruler.majorTickMeters)
    #expect(grid.scaleLabels.allSatisfy { $0.displayUnit.isMetric })
    #expect(grid.scaleLabels.allSatisfy { abs($0.displayValue) <= 1_000.0 })
    #expect(grid.scaleReadout.majorStep.displayUnit.isMetric)
    #expect(grid.scaleReadout.visibleSpan.displayUnit == .kilometer)
}

@Test func viewportProjectedGridReportsSitePlanningScaleReadout() throws {
    var document = DesignDocument.empty()
    try document.setRulerConfiguration(WorkspaceScalePreset.sitePlanning.rulerConfiguration)

    let grid = ViewportProjectedGrid(
        document: document,
        size: CGSize(width: 800.0, height: 600.0)
    )

    #expect(grid.scaleReadout.minorStep.meters == grid.minorStepMeters)
    #expect(grid.scaleReadout.majorStep.meters == grid.majorStepMeters)
    #expect(grid.scaleReadout.snapStep.meters == document.ruler.minorTickMeters)
    #expect(grid.scaleReadout.minorStep.displayUnit == .kilometer)
    #expect(grid.scaleReadout.majorStep.displayUnit == .kilometer)
    #expect(grid.scaleReadout.snapStep.displayUnit == .kilometer)
    #expect(grid.scaleReadout.visibleSpan.displayUnit == .kilometer)
    #expect(grid.scaleReadout.compactText.contains("Grid"))
    #expect(grid.scaleReadout.compactText.contains("Snap"))
    #expect(grid.scaleReadout.compactText.contains(grid.scaleReadout.snapStep.text))
    #expect(grid.scaleReadout.accessibilityText.contains("major"))
    #expect(grid.scaleReadout.accessibilityText.contains("snap"))
    #expect(grid.scaleReadout.accessibilityText.contains("visible span"))
}

@Test func viewportProjectedGridReportsRegionalPlanningScaleReadout() throws {
    var document = DesignDocument.empty(named: "Regional Grid")
    try document.setRulerConfiguration(WorkspaceScalePreset.regionalPlanning.rulerConfiguration)

    let grid = ViewportProjectedGrid(
        document: document,
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
    #expect(grid.scaleReadout.snapStep.meters == document.ruler.minorTickMeters)
    #expect(grid.scaleReadout.visibleSpan.displayUnit == .kilometer)
    #expect(grid.scaleReadout.compactText.contains("Grid"))
    #expect(grid.scaleReadout.compactText.contains("km"))
    #expect(grid.scaleReadout.accessibilityText.contains(grid.scaleReadout.visibleSpan.text))
    #expect(grid.scaleReadout.minorStep.text.hasSuffix("km"))
    #expect(grid.scaleReadout.majorStep.text.hasSuffix("km"))
    #expect(grid.scaleReadout.visibleSpan.text.hasSuffix("km"))
    #expect(grid.scaleLabels.contains { label in
        label.displayUnit == .kilometer && label.text.hasSuffix("km")
    })
}

@Test func viewportProjectedGridPreservesFixedVisualSpacingWhenWithinLineBudget() throws {
    var document = DesignDocument.empty()
    try document.setRulerConfiguration(WorkspaceScalePreset.architectureImperial.rulerConfiguration)
    let size = CGSize(width: 800.0, height: 600.0)
    let identityLayout = ViewportModelCoordinateMapper(
        document: document,
        size: size
    ).layout
    let maximumZoom = ViewportCameraZoomPolicy.maximumZoom(
        for: document,
        identityScale: identityLayout.scale
    )

    let grid = ViewportProjectedGrid(
        document: document,
        size: size,
        camera: ViewportCamera(zoom: maximumZoom * 2.0),
        visualSpacingMode: .fixed
    )

    #expect(!grid.lines.isEmpty)
    #expect(grid.lines.count < 400)
    #expect(grid.scaleReadout.visualSpacingMode == .fixed)
    #expect(!grid.scaleReadout.isVisualStepCapped)
    #expect(grid.minorStepMeters == document.ruler.minorTickMeters)
    #expect(grid.scaleReadout.minorStep.meters == document.ruler.minorTickMeters)
    #expect(grid.scaleReadout.snapStep.meters == document.ruler.minorTickMeters)
    #expect(grid.scaleReadout.minorStep.displayUnit == .foot)
    #expect(grid.scaleReadout.snapStep.displayUnit == .foot)
    #expect(!grid.scaleReadout.showsSeparateSnapStep)
    #expect(grid.scaleReadout.compactText == "Grid \(grid.scaleReadout.minorStep.text) · \(grid.scaleReadout.visibleSpan.text)")
    #expect(grid.scaleReadout.accessibilityText.contains("mode fixed"))
}

@Test func viewportProjectedGridCapsVisualLinesWithoutChangingSnapStep() throws {
    var document = DesignDocument.empty(named: "Site Grid")
    try document.setRulerConfiguration(WorkspaceScalePreset.sitePlanning.rulerConfiguration)

    let grid = ViewportProjectedGrid(
        document: document,
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
    #expect(grid.scaleReadout.compactText.contains("capped"))
    #expect(grid.scaleReadout.compactText.contains(grid.scaleReadout.snapStep.text))
    #expect(grid.scaleReadout.accessibilityText.contains("visual grid capped"))
}

@Test func viewportProjectedGridCapsFixedVisualSpacingForDenseRegionalViews() throws {
    var document = DesignDocument.empty()
    try document.setRulerConfiguration(WorkspaceScalePreset.regionalPlanning.rulerConfiguration)

    let grid = ViewportProjectedGrid(
        document: document,
        size: CGSize(width: 800.0, height: 600.0),
        visualSpacingMode: .fixed
    )

    #expect(!grid.lines.isEmpty)
    #expect(grid.lines.count < 400)
    #expect(grid.scaleReadout.visualSpacingMode == .fixed)
    #expect(grid.scaleReadout.isVisualStepCapped)
    #expect(grid.minorStepMeters > document.ruler.minorTickMeters)
    #expect(grid.scaleReadout.minorStep.meters == grid.minorStepMeters)
    #expect(grid.scaleReadout.snapStep.meters == document.ruler.minorTickMeters)
    #expect(grid.scaleReadout.showsSeparateSnapStep)
    #expect(grid.scaleReadout.compactText.contains("capped"))
    #expect(grid.scaleReadout.compactText.contains(grid.scaleReadout.snapStep.text))
    #expect(grid.scaleReadout.accessibilityText.contains("visual grid capped by line budget"))
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
    var document = DesignDocument.empty(named: "Signed Grid")
    try document.setRulerConfiguration(WorkspaceScalePreset.sitePlanning.rulerConfiguration)

    let grid = ViewportProjectedGrid(
        document: document,
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
    var document = DesignDocument.empty(named: "Architecture Grid")
    try document.setRulerConfiguration(WorkspaceScalePreset.architecture.rulerConfiguration)

    let grid = ViewportProjectedGrid(
        document: document,
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

private func vector(for line: ViewportProjectedGrid.Line) -> CGVector {
    CGVector(
        dx: line.end.x - line.start.x,
        dy: line.end.y - line.start.y
    )
}
