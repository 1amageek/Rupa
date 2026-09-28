import SwiftCAD

public struct CutCurveOptions: Codable, Equatable, Sendable {
    public var extendsCutter: Bool
    /// Screen space (S): a cutter's surface runs along the view instead of its sketch's normal.
    public var usesScreenSpaceDirection: Bool
    /// The view direction in world space, which Screen space needs.
    public var screenDirection: Vector3D?

    public init(
        extendsCutter: Bool = false,
        usesScreenSpaceDirection: Bool = false,
        screenDirection: Vector3D? = nil
    ) {
        self.extendsCutter = extendsCutter
        self.usesScreenSpaceDirection = usesScreenSpaceDirection
        self.screenDirection = screenDirection
    }
}
