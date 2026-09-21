import CoreGraphics

/// The canvas header's declared metrics.
///
/// The bar's height is declared here and never measured from its content: the
/// selection readout, the plane name and the scale-fit prompt come and go, and
/// a bar whose height followed them would move the canvas under the pointer
/// every time one of them arrived.
///
/// Width is the dimension that can run out instead. `fixedSeatsWidth` is the
/// width the header needs before a single readout is placed, and it has to fit
/// inside `WorkspaceEditorSplitLayout.minimumCanvasWidth`, which is the
/// narrowest the canvas column is ever laid out at. The readouts take what is
/// left and stand down when it is not enough, so they add nothing to this
/// number.
enum WorkspaceCanvasHeaderLayout {
    static let controlSize = CGSize(width: 25.0, height: 26.0)
    static let verticalPadding: CGFloat = 4.0
    static let horizontalPadding: CGFloat = 6.0
    static let itemSpacing: CGFloat = 4.0
    static let seatItemSpacing: CGFloat = 2.0
    static let dividerWidth: CGFloat = 1.0
    static let dividerHeight: CGFloat = 16.0
    static let dividerCount = 3
    static let viewControlCount = 3

    /// The gaps `itemSpacing` fills in the header's fixed row: six around the
    /// three dividers, one before the surface-analysis button, one before the
    /// readout cluster and one before the overflow button. The two inside the
    /// view group are counted by `viewGroupWidth`, and the gaps between
    /// readouts fall in the width the cluster yields.
    static let itemSpacingCount = 9

    static var height: CGFloat {
        controlSize.height + verticalPadding * 2
    }

    /// The fit, display-mode and shading controls, which stand together.
    static var viewGroupWidth: CGFloat {
        CGFloat(viewControlCount) * controlSize.width
            + CGFloat(viewControlCount - 1) * itemSpacing
    }

    /// Every seat that is laid out at the width it declares and never shrinks,
    /// plus the separators between them. The two `controlSize.width` terms are
    /// the surface-analysis button and the overflow button.
    ///
    /// Whatever is left of the canvas column's width after this is what the
    /// readout cluster is offered, and the cluster leaves the row rather than
    /// compress below what it is offered.
    static var fixedSeatsWidth: CGFloat {
        let seats = WorkspaceSelectionScopeControlLayout.contentWidth
            + WorkspaceSnapControlLayout.contentWidth
            + WorkspacePlaneModeControlLayout.contentWidth
            + viewGroupWidth
            + controlSize.width
            + controlSize.width
        let separators = CGFloat(dividerCount) * dividerWidth
            + CGFloat(itemSpacingCount) * itemSpacing
        return seats + separators + horizontalPadding * 2
    }
}
