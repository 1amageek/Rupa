import SwiftCAD

/// The complete Swift-CAD configuration that affects universal geometry output.
public struct CADGeometryEvaluationConfiguration: Hashable, Sendable {
    public let tolerance: ModelingTolerance
    public let tessellationOptions: TessellationOptions

    public init(
        tolerance: ModelingTolerance,
        tessellationOptions: TessellationOptions = .standard
    ) {
        self.tolerance = tolerance
        self.tessellationOptions = tessellationOptions
    }

    public func validate() throws {
        try tolerance.validate()
        try tessellationOptions.validate()
    }
}
