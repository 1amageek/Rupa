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
        in _: ProjectSourceModel
    ) throws -> [GeometrySourceReference: GeometryEvaluationResult] {
        let outputs = try request.references.map { reference in
            try validatedOutput(for: reference)
        }
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
                sourceRevision: request.sourceRevision
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
        sourceRevision: DocumentTransactionRevision
    ) throws -> SourceEvaluation {
        let evaluator = source.evaluator
        do {
            try evaluator.configuration.validate()
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
                tolerance: evaluator.configuration.tolerance
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
            configuration: evaluator.configuration
        )
        let evaluatedDocument: EvaluatedDocument
        if lookup.isExactRevision, let exact = lookup.evaluatedDocument {
            evaluatedDocument = exact
        } else {
            do {
                evaluatedDocument = try evaluator.evaluate(
                    validatedDocument,
                    reusing: lookup.evaluatedDocument
                )
            } catch {
                throw CADIntegrationError(
                    code: .evaluationFailed,
                    message: "CAD document evaluation failed: \(error)"
                )
            }
            try validate(
                evaluatedDocument: evaluatedDocument,
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
            let meshSource: MeshSource
            let copyTelemetry: GeometryCopyTelemetry
            if let cached = meshSourcesByBodyID[bodyID] {
                meshSource = cached.source
                copyTelemetry = GeometryCopyTelemetry()
            } else {
                guard let mesh = evaluatedDocument.meshes[bodyID] else {
                    throw CADIntegrationError(
                        code: .bodyUnavailable,
                        message: "CAD evaluation produced no mesh for body \(bodyID.description)."
                    )
                }
                let materialized = try makeMeshSource(
                    sourceID: source.sourceID,
                    bodyID: bodyID,
                    mesh: mesh,
                    tolerance: evaluator.configuration.tolerance
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
                configuration: evaluator.configuration,
                evaluatedDocument: evaluatedDocument,
                meshSourcesByBodyID: meshSourcesByBodyID
            )
        )
    }

    private func validate(
        evaluatedDocument: EvaluatedDocument,
        sourceFingerprint: CADDocumentSourceFingerprint,
        source: CADGeometryEvaluationSource
    ) throws {
        let configuration = source.evaluator.configuration
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
