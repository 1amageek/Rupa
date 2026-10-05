import RupaCore
import SwiftCAD

/// Explicit preparation limits for the saved view's authored selected cutting planes.
public struct DrawingPageSectionPolicy: Codable, Equatable, Sendable {
    public let maximumCuttingSupports: Int
    public let maximumSections: Int
    public let maximumSourceFaces: Int
    public let maximumComponents: Int
    public let maximumSourceEntities: Int
    public let hatch: DrawingPageHatchPolicy?

    public init(maximumCuttingSupports: Int, maximumSections: Int, maximumSourceFaces: Int,
        maximumComponents: Int, maximumSourceEntities: Int, hatch: DrawingPageHatchPolicy?) {
        self.maximumCuttingSupports = maximumCuttingSupports; self.maximumSections = maximumSections
        self.maximumSourceFaces = maximumSourceFaces; self.maximumComponents = maximumComponents
        self.maximumSourceEntities = maximumSourceEntities; self.hatch = hatch
    }
    func validate() throws {
        guard maximumCuttingSupports > 0, maximumSections > 0, maximumSourceFaces > 0,
              maximumComponents > 0, maximumSourceEntities > 0 else {
            throw EditorError(code: .commandInvalid, message: "Original section limits must be positive.")
        }
        try hatch?.validate()
    }
}
