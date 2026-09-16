import SwiftUI

/// Lays out the chrome the canvas carries on its trailing side.
///
/// The top bar holds the trailing corner and the utility rail sits beside the
/// canvas. Both are drawn over the same canvas, so they share one vertical
/// budget rather than being laid out independently: the bar takes the height
/// it asks for at the top, and the rail is offered the height between the band
/// the bar occupies and that same band mirrored at the bottom.
///
/// Reserving the band at both ends is what lets the rail stay centred on the
/// canvas, which is where the tool palette on the leading side is centred too,
/// while still leaving the corner to the bar once the canvas is too short for
/// the height the rail declares. Laying the two out as independent overlays
/// instead lets the rail grow through the corner, and stacking them without
/// the mirrored band moves the rail off the canvas's centre line by half the
/// band at every height.
///
/// The band is measured here rather than published by the bar and read back,
/// because a rectangle one view both produces and reads inside a single update
/// has no owner outside the layout that produced it.
struct WorkspaceTrailingChromeLayout: Layout {
    /// The gap between the band the bar occupies and the rail's own slot.
    var spacing: CGFloat

    /// The measured rows, and the band at each end of the rail's slot.
    private struct Rows {
        var bar: CGSize
        var rail: CGSize
        var band: CGFloat
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let rows = measure(proposal: proposal, subviews: subviews)
        return CGSize(
            width: max(rows.bar.width, rows.rail.width),
            height: proposal.height ?? (rows.band * 2.0 + rows.rail.height)
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = measure(
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height),
            subviews: subviews
        )
        subviews[barIndex].place(
            at: CGPoint(x: bounds.maxX, y: bounds.minY),
            anchor: .topTrailing,
            proposal: ProposedViewSize(width: bounds.width, height: rows.bar.height)
        )
        // The rail is centred on the bounds, and the slot it is offered is
        // symmetric about that centre, so a rail that fills its slot still
        // starts below the band the bar holds.
        subviews[railIndex].place(
            at: CGPoint(x: bounds.maxX, y: bounds.midY),
            anchor: .trailing,
            proposal: ProposedViewSize(
                width: bounds.width,
                height: min(rows.rail.height, slotHeight(in: bounds.height, band: rows.band))
            )
        )
    }

    /// Measures the bar at the height it asks for, then offers the rail the
    /// height left between the two bands.
    private func measure(proposal: ProposedViewSize, subviews: Subviews) -> Rows {
        let bar = subviews[barIndex].sizeThatFits(
            ProposedViewSize(width: proposal.width, height: nil)
        )
        let band = bar.height + spacing
        let rail = subviews[railIndex].sizeThatFits(
            ProposedViewSize(
                width: proposal.width,
                height: proposal.height.map { slotHeight(in: $0, band: band) }
            )
        )
        return Rows(bar: bar, rail: rail, band: band)
    }

    private func slotHeight(in height: CGFloat, band: CGFloat) -> CGFloat {
        max(height - band * 2.0, 0.0)
    }

    /// The host passes exactly two rows, the bar and then the rail, and each is
    /// a single `View`, so each row is one subview.
    private var barIndex: Int { 0 }
    private var railIndex: Int { 1 }
}
