import CoreGraphics
import Testing
import RupaCore
import RupaViewportScene
@testable import RupaRendering

@Test func viewportProjectedGridUsesKilometerReadoutForRegionalScale() throws {
    var document = DesignDocument.empty(named: "Regional Grid")
    try document.setRulerConfiguration(WorkspaceScalePreset.regionalPlanning.rulerConfiguration)

    let grid = ViewportProjectedGrid(
        document: document,
        size: CGSize(width: 1_200.0, height: 800.0),
        camera: .identity,
        basis: .isometric,
        visualSpacingMode: .adaptive
    )

    #expect(grid.lines.isEmpty == false)
    #expect(grid.lines.count <= 380)
    #expect(grid.scaleReadout.minorStep.displayUnit == .kilometer)
    #expect(grid.scaleReadout.majorStep.displayUnit == .kilometer)
    #expect(grid.scaleReadout.visibleSpan.displayUnit == .kilometer)
    #expect(grid.scaleReadout.minorStep.text.hasSuffix("km"))
    #expect(grid.scaleReadout.majorStep.text.hasSuffix("km"))
    #expect(grid.scaleReadout.visibleSpan.text.hasSuffix("km"))
    #expect(grid.scaleLabels.contains { label in
        label.displayUnit == .kilometer && label.text.hasSuffix("km")
    })
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

    #expect(grid.lines.isEmpty == false)
    #expect(grid.lines.count <= 380)
    #expect(grid.scaleReadout.visualSpacingMode == .fixed)
    #expect(grid.scaleReadout.isVisualStepCapped)
    #expect(grid.scaleReadout.snapStep.meters == 100.0)
    #expect(grid.scaleReadout.snapStep.text == "0.1km")
    #expect(grid.scaleReadout.minorStep.meters > grid.scaleReadout.snapStep.meters)
    #expect(grid.scaleReadout.compactText.contains("capped"))
    #expect(grid.scaleReadout.accessibilityText.contains("visual grid capped"))
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

    #expect(grid.lines.isEmpty == false)
    #expect(grid.scaleReadout.minorStep.displayUnit == .meter)
    #expect(grid.scaleReadout.snapStep.text == "0.1m")
    #expect(grid.scaleLabels.contains { label in
        label.displayUnit == .meter && label.text.hasSuffix("m")
    })
}
