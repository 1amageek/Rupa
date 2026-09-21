import CoreGraphics
import RupaRendering

/// What the canvas header says the canvas is currently drawn at.
///
/// The step is the grid's own resolved minor cell, and it arrives already
/// carrying the unit `ViewportProjectedGrid` resolved it in. The ruler's
/// configured display unit is deliberately not consulted: the grid decides
/// which unit a length reads best in, so a header that paired the ruler's
/// symbol with the grid's number could name one unit while showing another.
///
/// Both a step and a zoom are required. A readout that filled in a zero step
/// or a flat 100% would be publishing a reading that has not arrived.
struct WorkspaceCanvasScaleReadout: Equatable {
    var text: String
    var accessibilityValue: String

    init?(
        minorStep: ViewportProjectedGrid.ScaleReadout.Length?,
        zoom: CGFloat?
    ) {
        guard let minorStep, let zoom else {
            return nil
        }
        let zoomText = "\(Int((zoom * 100.0).rounded()))%"
        self.text = "\(minorStep.text) · \(zoomText)"
        self.accessibilityValue = "Grid \(minorStep.text), zoom \(zoomText)"
    }
}
