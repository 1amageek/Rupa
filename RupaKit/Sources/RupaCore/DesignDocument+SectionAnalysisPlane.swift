import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Records the plane of the last Section Analysis slice, or clears it, so Previous restores it
    /// after the document is reopened.
    public mutating func setSectionAnalysisPlane(_ plane: SketchPlane?) throws {
        if let plane {
            do {
                _ = try SketchPlaneCoordinateSystem(plane: plane)
            } catch {
                throw EditorError(code: .commandInvalid, message: "A Section Analysis plane must be a valid plane.")
            }
        }
        productMetadata.sectionAnalysisPlane = plane
    }
}
