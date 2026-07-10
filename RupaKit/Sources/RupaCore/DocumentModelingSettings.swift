import SwiftCAD

public struct DocumentModelingSettings: Codable, Hashable, Sendable {
    public var tolerance: ModelingTolerance
    public var tessellationOptions: TessellationOptions

    public init(
        tolerance: ModelingTolerance = .standard,
        tessellationOptions: TessellationOptions = .standard
    ) {
        self.tolerance = tolerance
        self.tessellationOptions = tessellationOptions
    }

    public static let standard = DocumentModelingSettings()

    public func validate() throws {
        try tolerance.validate()
        try tessellationOptions.validate()
    }
}
