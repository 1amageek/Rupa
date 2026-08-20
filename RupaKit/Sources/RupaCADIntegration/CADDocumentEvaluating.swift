import SwiftCAD

/// The Swift-CAD document evaluation capability required by the CAD provider.
///
/// Implementations must return materialized body meshes for the declared
/// configuration and must accept a compatible prior immutable evaluation.
public protocol CADDocumentEvaluating: Sendable {
    /// The complete identity of settings that affect universal geometry output.
    var configuration: CADGeometryEvaluationConfiguration { get }

    /// Evaluates an already validated document, reusing prior immutable state.
    func evaluate(
        _ document: ValidatedCADDocument,
        reusing previous: EvaluatedDocument?
    ) throws -> EvaluatedDocument
}
