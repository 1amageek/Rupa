import RupaCoreTypes
import SwiftCAD

/// The complete Swift-CAD configuration that affects universal geometry output.
///
/// The configuration is the identity of a CAD artifact. It carries only the
/// fidelity the meshes were tessellated at, because that is the only input that
/// changes the meshes ``CADDocumentEvaluationCache`` may serve. Modeling and
/// presentation requests for one document ask for the same fidelity, so they
/// share one artifact and one incremental evaluation rather than each paying a
/// full kernel evaluation whenever the other purpose was served last.
///
/// It deliberately does not carry `TessellationLimits`. The cache scope is
/// `(documentID, configuration)`, and the effective limits shrink with the
/// allowance still open when a provider is called, so a limit stored here would
/// move the scope on every edit and evict the incremental evaluation the kernel
/// reuses. Limits are per-request admission instead, passed to
/// ``CADDocumentEvaluating/evaluate(_:reusing:admitting:)``.
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
