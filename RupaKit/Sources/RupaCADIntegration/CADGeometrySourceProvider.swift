import Foundation
import RupaCoreTypes
import RupaEvaluation
import RupaGeometry
import RupaProjectModel
import SwiftCAD

public struct CADGeometrySourceProvider: GeometrySourceEvaluationProvider {
    private struct ValidatedOutput {
        let reference: GeometrySourceReference
        let sourceID: String
        let outputID: String
    }

    private struct SourceEvaluation {
        let results: [GeometrySourceReference: GeometryEvaluationResult]
        let publication: CADDocumentEvaluationCache.Publication
    }

    public static let identifier = GeometrySourceReference.cadProviderID
    public let providerID = Self.identifier
    private let resolver: any CADGeometrySourceResolving
    private let cache: CADDocumentEvaluationCache

    public init(
        document: CADDocument,
        configuration: CADGeometryEvaluationConfiguration,
        cache: CADDocumentEvaluationCache = CADDocumentEvaluationCache()
    ) {
        self.init(
            document: document,
            evaluator: DefaultCADDocumentEvaluator(configuration: configuration),
            cache: cache
        )
    }

    public init(
        document: CADDocument,
        evaluator: any CADDocumentEvaluating,
        cache: CADDocumentEvaluationCache = CADDocumentEvaluationCache()
    ) {
        self.init(
            resolver: CADGeometrySourceRegistry(
                source: CADGeometryEvaluationSource(
                    document: document,
                    evaluator: evaluator
                )
            ),
            cache: cache
        )
    }

    public init(
        sources: [CADGeometryEvaluationSource],
        cache: CADDocumentEvaluationCache = CADDocumentEvaluationCache()
    ) throws {
        self.init(
            resolver: try CADGeometrySourceRegistry(sources: sources),
            cache: cache
        )
    }

    public init(
        resolver: any CADGeometrySourceResolving,
        cache: CADDocumentEvaluationCache = CADDocumentEvaluationCache()
    ) {
        self.resolver = resolver
        self.cache = cache
    }

    public func evaluate(
        _ request: GeometrySourceEvaluationRequest,
        in project: ProjectSourceModel
    ) throws -> [GeometrySourceReference: GeometryEvaluationResult] {
        try Task.checkCancellation()
        do {
            return try evaluate(admitted: request, in: project)
        } catch let error as CADIntegrationError where error.code == .resourceExhausted {
            // The engine's vocabulary is the provider boundary's contract, so a
            // refusal is reported as the resource exhaustion it is rather than
            // as an opaque provider failure the engine cannot classify.
            throw EvaluationError(
                code: .resourceExhausted,
                message: error.message
            )
        }
    }

    private func evaluate(
        admitted request: GeometrySourceEvaluationRequest,
        in _: ProjectSourceModel
    ) throws -> [GeometrySourceReference: GeometryEvaluationResult] {
        var outputs: [ValidatedOutput] = []
        outputs.reserveCapacity(request.references.count)
        for reference in request.references {
            try Task.checkCancellation()
            outputs.append(try validatedOutput(for: reference))
        }
        var admission = try CADTessellationAdmission(allowance: request.allowance)
        var sourceOrder: [String] = []
        var outputsBySourceID: [String: [ValidatedOutput]] = [:]
        outputsBySourceID.reserveCapacity(outputs.count)
        for output in outputs {
            try Task.checkCancellation()
            if outputsBySourceID[output.sourceID] == nil {
                sourceOrder.append(output.sourceID)
            }
            outputsBySourceID[output.sourceID, default: []].append(output)
        }

        var results: [GeometrySourceReference: GeometryEvaluationResult] = [:]
        var publications: [CADDocumentEvaluationCache.Publication] = []
        results.reserveCapacity(outputs.count)
        publications.reserveCapacity(sourceOrder.count)
        for sourceID in sourceOrder {
            try Task.checkCancellation()
            guard let sourceOutputs = outputsBySourceID[sourceID] else {
                continue
            }
            let source: CADGeometryEvaluationSource
            do {
                source = try resolver.source(for: sourceID)
            } catch let error as CADIntegrationError {
                throw error
            } catch {
                throw CADIntegrationError(
                    code: .sourceUnavailable,
                    message: "CAD source \(sourceID) could not be resolved: \(error)"
                )
            }
            guard source.sourceID == sourceID else {
                throw CADIntegrationError(
                    code: .invalidEvaluationResult,
                    message: "CAD source resolver returned \(source.sourceID) for \(sourceID)."
                )
            }
            let evaluation = try evaluate(
                source: source,
                outputs: sourceOutputs,
                sourceRevision: request.sourceRevision,
                admission: &admission
            )
            try Task.checkCancellation()
            results.merge(evaluation.results) { existing, _ in existing }
            publications.append(evaluation.publication)
        }

        try Task.checkCancellation()
        try cache.publish(publications)
        return results
    }

    private func evaluate(
        source: CADGeometryEvaluationSource,
        outputs: [ValidatedOutput],
        sourceRevision: DocumentTransactionRevision,
        admission: inout CADTessellationAdmission
    ) throws -> SourceEvaluation {
        try Task.checkCancellation()
        let evaluator = source.evaluator
        // One evaluator and one cache serve both representation purposes for the
        // same document. Both ask for the same fidelity, so they share one
        // artifact and one incremental evaluation. The request's purpose reaches
        // this call only as the allowance the result is admitted under.
        let configuration = evaluator.configuration
        do {
            try configuration.validate()
        } catch {
            throw CADIntegrationError(
                code: .invalidConfiguration,
                message: "CAD geometry evaluation configuration is invalid: \(error)"
            )
        }

        let validatedDocument: ValidatedCADDocument
        let sourceFingerprint: CADDocumentSourceFingerprint
        do {
            validatedDocument = try ValidatedCADDocument(
                source.document,
                tolerance: configuration.tolerance
            )
            sourceFingerprint = try validatedDocument.sourceFingerprint()
        } catch {
            throw CADIntegrationError(
                code: .evaluationFailed,
                message: "CAD source validation or identity computation failed: \(error)"
            )
        }

        let lookup = try cache.lookup(
            documentID: source.document.id,
            sourceRevision: sourceRevision,
            sourceFingerprint: sourceFingerprint,
            configuration: configuration
        )
        try Task.checkCancellation()
        let evaluatedDocument: EvaluatedDocument
        if lookup.isExactRevision, let exact = lookup.evaluatedDocument {
            evaluatedDocument = exact
        } else {
            let limits = try admission.limitsForNextSource()
            do {
                evaluatedDocument = try evaluator.evaluate(
                    validatedDocument,
                    reusing: lookup.evaluatedDocument,
                    admitting: limits
                )
            } catch let error as CancellationError {
                // Cancellation is the caller's own decision, not a failure of
                // this document, so it must reach the caller unchanged.
                throw error
            } catch let error as TessellationError {
                throw makeTessellationFailure(error)
            } catch {
                throw CADIntegrationError(
                    code: .evaluationFailed,
                    message: "CAD document evaluation failed: \(error)"
                )
            }
            try Task.checkCancellation()
            try validate(
                evaluatedDocument: evaluatedDocument,
                configuration: configuration,
                sourceFingerprint: sourceFingerprint,
                source: source
            )
        }

        var results: [GeometrySourceReference: GeometryEvaluationResult] = [:]
        var meshSourcesByBodyID: [BodyID: CADDocumentEvaluationCache.CachedMeshSource] = [:]
        for (bodyID, cached) in lookup.meshSourcesByBodyID
        where evaluatedDocument.meshes[bodyID] == cached.mesh {
            meshSourcesByBodyID[bodyID] = cached
        }
        results.reserveCapacity(outputs.count)
        meshSourcesByBodyID.reserveCapacity(outputs.count)
        for output in outputs {
            try Task.checkCancellation()
            guard let bodyID = CADGeometryExchange.resolvedBodyID(
                outputID: output.outputID,
                in: evaluatedDocument
            ) else {
                throw CADIntegrationError(
                    code: .bodyUnavailable,
                    message: "CAD evaluation produced no body for output \(output.outputID)."
                )
            }
            guard let mesh = evaluatedDocument.meshes[bodyID] else {
                throw CADIntegrationError(
                    code: .bodyUnavailable,
                    message: "CAD evaluation produced no mesh for body \(bodyID.description)."
                )
            }
            try validate(mesh: mesh, tolerance: configuration.tolerance)
            guard mesh.material == nil else {
                throw CADIntegrationError(
                    code: .unsupportedFidelity,
                    message: "CAD material identity cannot be represented by the universal geometry contract."
                )
            }
            // Charged before materialization, and for a cached mesh as well as a
            // freshly tessellated one, because the engine charges every result
            // this call returns while the kernel budget covers only what this
            // invocation tessellated.
            let predictedUsage = try admission.admit(mesh)
            let meshSource: MeshSource
            let copyTelemetry: GeometryCopyTelemetry
            if let cached = meshSourcesByBodyID[bodyID] {
                meshSource = cached.source
                copyTelemetry = GeometryCopyTelemetry()
            } else {
                let materialized: CADMeshSourceMaterialization
                do {
                    materialized = try CADMeshSourceConverter.makeMeshSource(
                        identity: GeometrySourceID(
                            rawValue: "cad.\(source.sourceID).\(bodyID.description)"
                        ),
                        mesh: mesh
                    )
                } catch let error as CADMeshSourceConversionError {
                    switch error {
                    case .unsupportedMaterial:
                        throw CADIntegrationError(
                            code: .unsupportedFidelity,
                            message: "CAD material identity cannot be represented by the universal geometry contract."
                        )
                    case .invalidMesh(let message):
                        throw CADIntegrationError(
                            code: .invalidMesh,
                            message: message
                        )
                    case let .faceIdentityMismatch(triangleIndex, faceID):
                        throw CADIntegrationError(
                            code: .invalidMesh,
                            message: "CAD mesh triangle \(triangleIndex) became mesh face \(faceID), "
                                + "so a mesh hit cannot resolve back to the generating CAD face."
                        )
                    }
                }
                meshSource = materialized.source
                copyTelemetry = materialized.copyTelemetry
                meshSourcesByBodyID[bodyID] = CADDocumentEvaluationCache.CachedMeshSource(
                    mesh: mesh,
                    source: meshSource
                )
            }
            try Task.checkCancellation()
            do {
                try admission.verify(
                    actual: meshSource.resourceUsage(),
                    predicted: predictedUsage
                )
            } catch let error as CADIntegrationError {
                throw error
            } catch {
                throw CADIntegrationError(
                    code: .invalidMesh,
                    message: "CAD mesh resource usage could not be verified: \(error)"
                )
            }
            results[output.reference] = GeometryEvaluationResult(
                reference: output.reference,
                mesh: meshSource,
                localBounds: try meshSource.bounds(),
                copyTelemetry: copyTelemetry
            )
        }

        try Task.checkCancellation()
        return SourceEvaluation(
            results: results,
            publication: CADDocumentEvaluationCache.Publication(
                documentID: source.document.id,
                sourceRevision: sourceRevision,
                sourceFingerprint: sourceFingerprint,
                configuration: configuration,
                evaluatedDocument: evaluatedDocument,
                meshSourcesByBodyID: meshSourcesByBodyID
            )
        )
    }

    private func validate(mesh: Mesh, tolerance: ModelingTolerance) throws {
        do {
            try mesh.validate(tolerance: tolerance)
        } catch {
            throw CADIntegrationError(
                code: .invalidMesh,
                message: "CAD body mesh failed validation: \(error)"
            )
        }
    }

    private func validate(
        evaluatedDocument: EvaluatedDocument,
        configuration: CADGeometryEvaluationConfiguration,
        sourceFingerprint: CADDocumentSourceFingerprint,
        source: CADGeometryEvaluationSource
    ) throws {
        guard evaluatedDocument.document.id == source.document.id,
              evaluatedDocument.configuration.tolerance == configuration.tolerance,
              evaluatedDocument.configuration.tessellationOptions
                == configuration.tessellationOptions,
              let brepCache = evaluatedDocument.caches.brep,
              brepCache.tolerance == configuration.tolerance,
              brepCache.sourceFingerprint == sourceFingerprint,
              Set(evaluatedDocument.meshes.keys)
                == Set(evaluatedDocument.brep.bodies.keys) else {
            throw CADIntegrationError(
                code: .invalidEvaluationResult,
                message: "CAD evaluator returned a result for different source content or configuration."
            )
        }
    }

    /// The typed provider failure a kernel tessellation error reports as.
    ///
    /// Exhaustion is the admitted refusal this request asked for. An invalid
    /// limit cannot follow from an admitted allowance, so it is a defect in the
    /// configuration this provider supplied rather than a refusal of the
    /// geometry, and every other tessellation error is an evaluation failure.
    private func makeTessellationFailure(
        _ error: TessellationError
    ) -> CADIntegrationError {
        switch error {
        case .resourceExhausted:
            CADIntegrationError(
                code: .resourceExhausted,
                message: "CAD tessellation exceeded the admitted resources: \(error)"
            )
        case .invalidLimit:
            CADIntegrationError(
                code: .invalidConfiguration,
                message: "CAD tessellation limits are invalid: \(error)"
            )
        default:
            CADIntegrationError(
                code: .evaluationFailed,
                message: "CAD document evaluation failed: \(error)"
            )
        }
    }

    private func validatedOutput(
        for reference: GeometrySourceReference
    ) throws -> ValidatedOutput {
        guard case let .cad(sourceID, outputID) = reference else {
            throw CADIntegrationError(
                code: .unsupportedReference,
                message: "CAD provider received a non-CAD geometry reference."
            )
        }
        guard !sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CADIntegrationError(
                code: .sourceUnavailable,
                message: "CAD geometry references require a source ID."
            )
        }
        guard UUID(uuidString: outputID) != nil else {
            throw CADIntegrationError(
                code: .bodyUnavailable,
                message: "CAD geometry references require a valid body or feature output ID."
            )
        }
        return ValidatedOutput(
            reference: reference,
            sourceID: sourceID,
            outputID: outputID
        )
    }

}
