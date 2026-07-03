import CoreGraphics

enum WorkspaceChromeControlMetrics {
    static let controlHeight: CGFloat = 22.0
    static let horizontalPadding: CGFloat = 6.0
    static let cornerRadius: CGFloat = 6.0
    static let dividerHeight: CGFloat = 20.0

    static var iconButtonSize: CGSize {
        CGSize(width: controlHeight, height: controlHeight)
    }
}
