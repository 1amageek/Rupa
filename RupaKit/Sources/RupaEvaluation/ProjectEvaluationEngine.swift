import RupaCoreTypes
import RupaGeometry
import RupaProjectModel

public struct ProjectEvaluationEngine: ProjectEvaluating {
    private let registry: GeometrySourceEvaluationProviderRegistry
    private let policy: EvaluationResourcePolicy

    public init() {
        self.init(registry: .meshSourceOnly)
    }

    public init(
        registry: GeometrySourceEvaluationProviderRegistry,
        policy: EvaluationResourcePolicy = .standard
    ) {
        self.registry = registry
        self.policy = policy
    }

    public func evaluate(
        project: ProjectSourceModel,
        purpose: GeometryRepresentationPurpose,
        revision: DocumentTransactionRevision
    ) throws -> EvaluatedProjectSnapshot {
        try Task.checkCancellation()
        do {
            try project.validate()
        } catch let error as ProjectModelError {
            let code: EvaluationError.Code = error.code == .hierarchyCycle
                ? .hierarchyCycle
                : .invalidProject
            throw EvaluationError(code: code, message: error.message)
        }
        try Task.checkCancellation()

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
            try Task.checkCancellation()
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
                copyTelemetry: result.copyTelemetry,
                worldTransform: worldTransform,
                worldBounds: worldBounds
            )
        }

        try Task.checkCancellation()
        let id = EvaluationSnapshotID(
            projectID: project.id,
            purpose: purpose,
            sourceRevision: revision
        )
        var copyTelemetry = GeometryCopyTelemetry()
        for result in resultsByReference.values {
            try Task.checkCancellation()
            try copyTelemetry.record(contentsOf: result.copyTelemetry)
        }
        try Task.checkCancellation()
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
        try Task.checkCancellation()
        var budget = try EvaluationBudget(limits: policy.limits(for: purpose))
        var referencesByProvider: [String: [GeometrySourceReference]] = [:]
        var seenReferences: Set<GeometrySourceReference> = []

        for occurrenceID in occurrenceIDs {
            try Task.checkCancellation()
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
            // Every distinct source is charged before any provider runs, so a
            // project with more sources than the purpose admits is refused
            // before the first mesh is produced.
            try budget.chargeSource()
            referencesByProvider[reference.providerID, default: []].append(reference)
        }

        var resultsByReference: [GeometrySourceReference: GeometryEvaluationResult] = [:]
        resultsByReference.reserveCapacity(seenReferences.count)
        for providerID in referencesByProvider.keys.sorted() {
            try Task.checkCancellation()
            guard let references = referencesByProvider[providerID] else {
                continue
            }
            let provider = try registry.provider(identifiedBy: providerID)
            // The allowance is what is still open now, so a later provider sees
            // what the earlier providers already consumed.
            let request = try GeometrySourceEvaluationRequest(
                references: references,
                sourceRevision: sourceRevision,
                purpose: purpose,
                allowance: budget.remaining
            )
            try Task.checkCancellation()
            let providerResults = try provider.evaluate(request, in: project)
            try Task.checkCancellation()
            try validate(
                providerResults,
                for: request,
                providerID: providerID
            )
            // Charging is the engine's authority, not the provider's: the
            // request's allowance only lets a provider refuse early, so every
            // returned mesh is charged here even when the provider ignored it.
            // Charging follows the request order so exhaustion is deterministic.
            for reference in request.references {
                try Task.checkCancellation()
                guard let result = providerResults[reference] else {
                    continue
                }
                try charge(result, from: providerID, against: &budget)
                resultsByReference[reference] = result
            }
        }
        try Task.checkCancellation()
        return resultsByReference
    }

    private func charge(
        _ result: GeometryEvaluationResult,
        from providerID: String,
        against budget: inout EvaluationBudget
    ) throws {
        let usage: MeshResourceUsage
        do {
            usage = try result.mesh.resourceUsage()
        } catch {
            throw EvaluationError(
                code: .invalidResult,
                message: "Geometry evaluation provider \(providerID) returned a mesh whose resource usage cannot be accounted: \(error)"
            )
        }
        try budget.charge(usage)
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
        try Task.checkCancellation()
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
            try Task.checkCancellation()
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
        try Task.checkCancellation()
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
