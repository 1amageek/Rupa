import CoreGraphics

public struct ViewportCamera: Equatable, Sendable {
    public var zoom: CGFloat
    public var pan: CGSize

    public init(
        zoom: CGFloat = 1.0,
        pan: CGSize = .zero
    ) {
        self.zoom = max(zoom, Self.minimumZoom)
        self.pan = pan
    }

    public static let minimumZoom: CGFloat = 0.04
    public static let maximumZoom: CGFloat = 256.0
    public static let identity = ViewportCamera()

    public func clamped() -> ViewportCamera {
        ViewportCamera(
            zoom: min(max(zoom, Self.minimumZoom), Self.maximumZoom),
            pan: pan
        )
    }
}
