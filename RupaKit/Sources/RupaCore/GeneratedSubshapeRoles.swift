import SwiftCAD

/// Composed subshape role strings the kernel assigns to generated topology.
///
/// The kernel composes roles as `"<generatedRole>.<subshapeRole>"`. RupaCore
/// matches these strings when a product workflow is restricted to a specific
/// generated subshape, so the accepted vocabulary lives in one place.
public enum GeneratedSubshapeRoles {
    public static let bSplineSurfacePrefix = "bSplineSurface."
    public static let bSplineSurfacePatchFace = "bSplineSurface.patch:0:face"

    public static func isBSplineSurfacePatchFace(_ subshapeID: SubshapeID) -> Bool {
        subshapeID.role == bSplineSurfacePatchFace && subshapeID.ordinal == 0
    }
}
