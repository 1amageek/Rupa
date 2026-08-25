import RupaCoreTypes
import RupaGeometry
import RupaProjectModel

public struct ProjectEvaluationEngine: ProjectEvaluating {
    private let registry: GeometrySourceEvaluationProviderRegistry

    public init() {
        self.registry = .meshSourceOnly
    }

    public init(registry: GeometrySourceEvaluationProviderRegistry) {
        self.registry = registry
    }

    public func evaluate(
        project: ProjectSourceModel,
        purpose: GeometryRepresentationPurpose,
        revision: DocumentTransactionRevision
    ) throws -> EvaluatedProjectSnapshot {
        do {
            try project.validate()
        } catch let error as ProjectModelError {
            let code: EvaluationError.Code = error.code == .hierarchyCycle
                ? .hierarchyCycle
                : .invalidProject
            throw EvaluationError(code: code, message: error.message)
        }

        let occurrenceIDs = project.occurrences.keys.sorted(by: { $0.rawValue < $1.rawValue })
        let resultsByReference = try evaluateGeometrySources(
            for: occurrenceIDs,
            in: project,
            purpose: purpose,
            sourceRevision: revision
        )

        var transformCache: [SceneOccurrenceID: GeometryTransform3D] = [:]
        var evaluated: [SceneOccurrenceID: EvaluatedOccurrenceSnapshot] = [:]
        for occurrenceID in occurrenceIDs {
            guard let occurrence = project.occurrences[occurrenceID],
                  let definition = project.objectDefinitions[occurrence.definitionID] else {
                continue
            }
            guard let representation = try selectedRepresentation(
                in: definition,
                purpose: purpose
            ) else {
                continue
            }
            let reference = representation.source
            let worldTransform = try worldTransform(
                for: occurrenceID,
                in: project,
                cache: &transformCache
            )
            guard let result = resultsByReference[reference] else {
                throw EvaluationError(
                    code: .invalidResult,
                    message: "Geometry evaluation produced no result for a referenced source."
                )
            }
            let worldBounds = try result.localBounds.transformed(by: worldTransform)
            evaluated[occurrenceID] = EvaluatedOccurrenceSnapshot(
                occurrenceID: occurrenceID,
                definitionID: occurrence.definitionID,
                representationID: representation.id,
                reference: reference,
                mesh: result.mesh,
                worldTransform: worldTransform,
                worldBounds: worldBounds
            )
        }

        let id = EvaluationSnapshotID(
            projectID: project.id,
            purpose: purpose,
            sourceRevision: revision
        )
        var copyTelemetry = GeometryCopyTelemetry()
        for result in resultsByReference.values {
            try copyTelemetry.record(contentsOf: result.copyTelemetry)
        }
        return EvaluatedProjectSnapshot(
            id: id,
            projectID: project.id,
            occurrences: evaluated,
            copyTelemetry: copyTelemetry
        )
    }

    private func evaluateGeometrySources(
        for occurrenceIDs: [SceneOccurrenceID],
        in project: ProjectSourceModel,
        purpose: GeometryRepresentationPurpose,
        sourceRevision: DocumentTransactionRevision
    ) throws -> [GeometrySourceReference: GeometryEvaluationResult] {
        var referencesByProvider: [String: [GeometrySourceReference]] = [:]
        var seenReferences: Set<GeometrySourceReference> = []

        for occurrenceID in occurrenceIDs {
            guard let occurrence = project.occurrences[occurrenceID],
                  let definition = project.objectDefinitions[occurrence.definitionID],
                  let representation = try selectedRepresentation(
                    in: definition,
                    purpose: purpose
                  ) else {
                continue
            }
            let reference = representation.source
            guard seenReferences.insert(reference).inserted else {
                continue
            }
            referencesByProvider[reference.providerID, default: []].append(reference)
        }

        var resultsByReference: [GeometrySourceReference: GeometryEvaluationResult] = [:]
        resultsByReference.reserveCapacity(seenReferences.count)
        for providerID in referencesByProvider.keys.sorted() {
            guard let references = referencesByProvider[providerID] else {
                continue
            }
            let provider = try registry.provider(identifiedBy: providerID)
            let request = try GeometrySourceEvaluationRequest(
                references: references,
                sourceRevision: sourceRevision
            )
            let providerResults = try provider.evaluate(request, in: project)
            try validate(
                providerResults,
                for: request,
                providerID: providerID
            )
            for (reference, result) in providerResults {
                resultsByReference[reference] = result
            }
        }
        return resultsByReference
    }

    private func selectedRepresentation(
        in definition: ObjectDefinition,
        purpose: GeometryRepresentationPurpose
    ) throws -> GeometryRepresentation? {
        guard definition.representations.representations.isEmpty == false else {
            return nil
        }
        guard let representation = definition.representations.representation(for: purpose) else {
            throw EvaluationError(
                code: .invalidProject,
                message: "Geometry object definitions must resolve the requested representation purpose."
            )
        }
        return representation
    }

    private func validate(
        _ results: [GeometrySourceReference: GeometryEvaluationResult],
        for request: GeometrySourceEvaluationRequest,
        providerID: String
    ) throws {
        let expectedReferences = Set(request.references)
        guard Set(results.keys) == expectedReferences else {
            throw EvaluationError(
                code: .invalidResult,
                message: "Geometry evaluation provider \(providerID) must return exactly one result for every requested reference."
            )
        }
        for (reference, result) in results where result.reference != reference {
            throw EvaluationError(
                code: .invalidResult,
                message: "Geometry evaluation provider \(providerID) returned a result keyed by a different source reference."
            )
        }
        for result in results.values {
            do {
                try result.mesh.validate()
                guard try result.mesh.bounds() == result.localBounds else {
                    throw EvaluationError(
                        code: .invalidResult,
                        message: "Geometry evaluation provider \(providerID) returned bounds that do not match its mesh."
                    )
                }
            } catch let error as EvaluationError {
                throw error
            } catch {
                throw EvaluationError(
                    code: .invalidResult,
                    message: "Geometry evaluation provider \(providerID) returned invalid mesh data: \(error)"
                )
            }
        }
    }

    private func worldTransform(
        for occurrenceID: SceneOccurrenceID,
        in project: ProjectSourceModel,
        cache: inout [SceneOccurrenceID: GeometryTransform3D]
    ) throws -> GeometryTransform3D {
        if let cached = cache[occurrenceID] {
            return cached
        }
        guard let occurrence = project.occurrences[occurrenceID] else {
            throw EvaluationError(
                code: .sourceUnavailable,
                message: "Scene occurrence \(occurrenceID.rawValue) is not present in the project."
            )
        }
        let transform: GeometryTransform3D
        if let parentID = occurrence.parentID {
            let parentTransform = try worldTransform(
                for: parentID,
                in: project,
                cache: &cache
            )
            transform = try parentTransform.multiplied(by: occurrence.localTransform)
        } else {
            transform = occurrence.localTransform
        }
        cache[occurrenceID] = transform
        return transform
    }
}
