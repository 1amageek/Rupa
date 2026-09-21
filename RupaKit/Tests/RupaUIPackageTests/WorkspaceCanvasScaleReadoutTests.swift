import CoreGraphics
import RupaRendering
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
    ViewportProjectedGrid.ScaleReadout.Length(
        meters: 0.1,
        displayValue: 10.0,
        displayUnit: .centimeter,
        text: "10cm"
    )
}
