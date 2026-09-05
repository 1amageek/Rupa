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

    private struct MaterializedMeshSource {
        let source: MeshSource
        let copyTelemetry: GeometryCopyTelemetry
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
        let outputs = try request.references.map { reference in
            try validatedOutput(for: reference)
        }
        var admission = try CADTessellationAdmission(allowance: request.allowance)
        var sourceOrder: [String] = []
        var outputsBySourceID: [String: [ValidatedOutput]] = [:]
        outputsBySourceID.reserveCapacity(outputs.count)
        for output in outputs {
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
            results.merge(evaluation.results) { existing, _ in existing }
            publications.append(evaluation.publication)
        }

        try cache.publish(publications)
        return results
    }

    private func evaluate(
        source: CADGeometryEvaluationSource,
        outputs: [ValidatedOutput],
        sourceRevision: DocumentTransactionRevision,
        admission: inout CADTessellationAdmission
    ) throws -> SourceEvaluation {
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
        let evaluatedDocument: EvaluatedDocument
        if lookup.isExactRevision, let exact = lookup.evaluatedDocument {
            evaluatedDocument = exact
        } else {
            do {
                evaluatedDocument = try evaluator.evaluate(
                    validatedDocument,
                    reusing: lookup.evaluatedDocument,
                    admitting: admission.limits
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
            guard let bodyID = resolveBodyID(
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
            // Charged before materialization, and for a cached mesh as well as a
            // freshly tessellated one, because the engine charges every result
            // this call returns while the kernel budget covers only what this
            // invocation tessellated.
            try admission.admit(mesh)
            let meshSource: MeshSource
            let copyTelemetry: GeometryCopyTelemetry
            if let cached = meshSourcesByBodyID[bodyID] {
                meshSource = cached.source
                copyTelemetry = GeometryCopyTelemetry()
            } else {
                let materialized = try makeMeshSource(
                    sourceID: source.sourceID,
                    bodyID: bodyID,
                    mesh: mesh,
                    tolerance: configuration.tolerance
                )
                meshSource = materialized.source
                copyTelemetry = materialized.copyTelemetry
                meshSourcesByBodyID[bodyID] = CADDocumentEvaluationCache.CachedMeshSource(
                    mesh: mesh,
                    source: meshSource
                )
            }
            results[output.reference] = GeometryEvaluationResult(
                reference: output.reference,
                mesh: meshSource,
                localBounds: try meshSource.bounds(),
                copyTelemetry: copyTelemetry
            )
        }

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

    private func resolveBodyID(
        outputID: String,
        in evaluatedDocument: EvaluatedDocument
    ) -> BodyID? {
        guard let uuid = UUID(uuidString: outputID) else {
            return nil
        }
        let directBodyID = BodyID(uuid)
        if evaluatedDocument.meshes[directBodyID] != nil {
            return directBodyID
        }

        let featureID = FeatureID(uuid)
        let bodyIDs = evaluatedDocument.subshapes.entries.compactMap {
            entry -> BodyID? in
            let (subshapeID, reference) = entry
            guard subshapeID.featureID == featureID,
                  case .body(let bodyID) = reference else {
                return nil
            }
            return bodyID
        }
        let uniqueBodyIDs = Set(bodyIDs)
        guard uniqueBodyIDs.count == 1 else {
            return nil
        }
        return uniqueBodyIDs.first
    }

    private func makeMeshSource(
        sourceID: String,
        bodyID: BodyID,
        mesh: Mesh,
        tolerance: ModelingTolerance
    ) throws -> MaterializedMeshSource {
        do {
            try mesh.validate(tolerance: tolerance)
        } catch {
            throw CADIntegrationError(
                code: .invalidMesh,
                message: "CAD body mesh failed validation: \(error)"
            )
        }
        guard mesh.material == nil else {
            throw CADIntegrationError(
                code: .unsupportedFidelity,
                message: "CAD material identity cannot be represented by the universal geometry contract."
            )
        }

        do {
            // Universal editable topology owns stable element IDs, so this adapter
            // materializes Swift-CAD arrays once. The cache reuses the result while
            // the immutable evaluated mesh remains identical.
            var builder = MeshSourceBuilder(
                identity: GeometrySourceID(
                    rawValue: "cad.\(sourceID).\(bodyID.description)"
                )
            )
            try builder.reserveCapacity(
                vertexCount: mesh.positions.count,
                faceCount: mesh.indices.count / 3,
                cornerCount: mesh.indices.count
            )
            var vertices: [MeshVertexID] = []
            vertices.reserveCapacity(mesh.positions.count)
            for position in mesh.positions {
                vertices.append(
                    try builder.addVertex(
                        GeometryPoint3D(x: position.x, y: position.y, z: position.z)
                    )
                )
            }
            for triangleStart in stride(from: 0, to: mesh.indices.count, by: 3) {
                _ = try builder.addTriangle(
                    vertices[Int(mesh.indices[triangleStart])],
                    vertices[Int(mesh.indices[triangleStart + 1])],
                    vertices[Int(mesh.indices[triangleStart + 2])]
                )
            }
            if !mesh.normals.isEmpty {
                try builder.setAttribute(
                    GeometryAttributeLayer(
                        descriptor: GeometryAttributeDescriptor(
                            id: "cad.normal",
                            name: "CAD Normal",
                            domain: .vertex,
                            valueType: .vector3,
                            interpolation: .linear
                        ),
                        values: .vector3(GeometryBuffer(mesh.normals.map {
                            GeometryPoint3D(x: $0.x, y: $0.y, z: $0.z)
                        }))
                    )
                )
            }
            if !mesh.textureCoordinates.isEmpty {
                try builder.setAttribute(
                    GeometryAttributeLayer(
                        descriptor: GeometryAttributeDescriptor(
                            id: "cad.uv",
                            name: "CAD UV",
                            domain: .vertex,
                            valueType: .vector2,
                            interpolation: .linear
                        ),
                        values: .vector2(GeometryBuffer(mesh.textureCoordinates.map {
                            GeometryVector2D(x: $0.x, y: $0.y)
                        }))
                    )
                )
            }
            if !mesh.vertexColors.isEmpty {
                try builder.setAttribute(
                    GeometryAttributeLayer(
                        descriptor: GeometryAttributeDescriptor(
                            id: "cad.color",
                            name: "CAD Vertex Color",
                            domain: .vertex,
                            valueType: .vector4,
                            interpolation: .linear
                        ),
                        values: .vector4(GeometryBuffer(mesh.vertexColors.map {
                            GeometryVector4D(x: $0.r, y: $0.g, z: $0.b, w: $0.a)
                        }))
                    )
                )
            }
            var copyTelemetry = GeometryCopyTelemetry()
            let source = try builder.build(telemetry: &copyTelemetry)
            return MaterializedMeshSource(
                source: source,
                copyTelemetry: copyTelemetry
            )
        } catch {
            throw CADIntegrationError(
                code: .invalidMesh,
                message: "CAD body mesh could not be converted without loss: \(error)"
            )
        }
    }
}
