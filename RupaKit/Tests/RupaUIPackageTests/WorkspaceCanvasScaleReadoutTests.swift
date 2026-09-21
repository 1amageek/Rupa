import CoreGraphics
import RupaCore
import RupaCoreTypes
import RupaRendering
import RupaViewportScene
import Testing
@testable import RupaUI

/// The header's scale seat states what the canvas is drawn at, and that
/// statement only exists once both halves of it have arrived. A seat that
/// filled in a zero step or a flat 100% would be reporting a scale nobody
/// measured, so the readout refuses to exist until the grid has published a
/// minor step and the camera a zoom.
@Test func workspaceCanvasScaleReadoutRefusesToReadBeforeBothHalvesArrive() {
    let step = gridMinorStep()
    #expect(WorkspaceCanvasScaleReadout(minorStep: nil, zoom: nil) == nil)
    #expect(WorkspaceCanvasScaleReadout(minorStep: nil, zoom: 1.0) == nil)
    #expect(WorkspaceCanvasScaleReadout(minorStep: step, zoom: nil) == nil)
    #expect(WorkspaceCanvasScaleReadout(minorStep: step, zoom: 1.0) != nil)
}

/// The step reads in the unit the grid resolved it in, not the unit the ruler
/// is configured in. `ViewportProjectedGrid` escalates a cell that has grown
/// past what its unit reads well and hands the text down already carrying the
/// larger symbol, so a header that paired the ruler's symbol with the grid's
/// number would name one unit while showing another. The fixture is a real
/// grid on a room-interior ruler drawn far enough out that its cell has left
/// centimetres: the header must carry the grid's unit and not the ruler's.
@Test func workspaceCanvasScaleReadoutRepeatsTheStepTextTheGridResolved() throws {
    let ruler = WorkspaceScalePreset.roomInterior.rulerConfiguration
    let zoom: CGFloat = 0.125
    let step = ViewportProjectedGrid(
        document: DesignDocument.empty(),
        ruler: ruler,
        size: CGSize(width: 800.0, height: 600.0),
        camera: ViewportCamera(zoom: zoom)
    ).scaleReadout.minorStep

    try #require(step.displayUnit != ruler.displayUnit)

    let readout = try #require(WorkspaceCanvasScaleReadout(minorStep: step, zoom: zoom))

    #expect(readout.text == "\(step.text) · 13%")
    #expect(!readout.text.contains(ruler.displayUnit.symbol))
    #expect(readout.accessibilityValue == "Grid \(step.text), zoom 13%")
}

/// Zoom reads as a whole percent. The camera's zoom is continuous, and a seat
/// that showed its fraction would change on every frame of a drag while
/// telling the reader nothing more than the rounded number does.
@Test func workspaceCanvasScaleReadoutRoundsZoomToAWholePercent() throws {
    let step = gridMinorStep()
    let zoomedIn = try #require(WorkspaceCanvasScaleReadout(minorStep: step, zoom: 2.5))
    let awkward = try #require(WorkspaceCanvasScaleReadout(minorStep: step, zoom: 0.7549))
    let zoomedOut = try #require(WorkspaceCanvasScaleReadout(minorStep: step, zoom: 0.125))

    #expect(zoomedIn.text == "\(step.text) · 250%")
    #expect(awkward.text == "\(step.text) · 75%")
    #expect(zoomedOut.text == "\(step.text) · 13%")
}

/// A grid whose visible cell still reads in the unit its ruler asked for, so
/// the tests that are not about unit escalation carry a step the ruler and the
/// grid agree on.
private func gridMinorStep() -> ViewportProjectedGrid.ScaleReadout.Length {
    ViewportProjectedGrid(
        document: DesignDocument.empty(),
        ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration,
        size: CGSize(width: 800.0, height: 600.0)
    ).scaleReadout.minorStep
}
