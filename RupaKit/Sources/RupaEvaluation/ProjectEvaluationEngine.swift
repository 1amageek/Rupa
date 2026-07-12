import RupaCoreTypes
import RupaGeometry
import RupaProjectModel

public struct ProjectEvaluationEngine: Sendable {
    private let providers: [String: any GeometrySourceEvaluationProvider]

    public init(
        providers: [any GeometrySourceEvaluationProvider] = [MeshSourceEvaluationProvider()]
    ) {
        var indexed: [String: any GeometrySourceEvaluationProvider] = [:]
        for provider in providers {
            indexed[provider.providerID] = provider
        }
        self.providers = indexed
    }

    public func evaluate(
        _ project: ProjectSourceModel,
        sourceRevision: DocumentTransactionRevision = DocumentTransactionRevision()
    ) throws -> EvaluatedProjectSnapshot {
        do {
            try project.validate()
        } catch let error as ProjectModelError {
            let code: EvaluationError.Code = error.code == .hierarchyCycle
                ? .hierarchyCycle
                : .invalidProject
            throw EvaluationError(code: code, message: error.message)
        }

        var transformCache: [SceneOccurrenceID: GeometryTransform3D] = [:]
        var evaluated: [SceneOccurrenceID: EvaluatedOccurrenceSnapshot] = [:]
        for occurrenceID in project.occurrences.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let occurrence = project.occurrences[occurrenceID],
                  let definition = project.objectDefinitions[occurrence.definitionID],
                  let reference = definition.geometry else {
                continue
            }
            let worldTransform = try worldTransform(
                for: occurrenceID,
                in: project,
                cache: &transformCache
            )
            guard let provider = providers[reference.providerID] else {
                throw EvaluationError(
                    code: .providerNotRegistered,
                    message: "No geometry evaluation provider is registered for \(reference.providerID)."
                )
            }
            let result = try provider.evaluate(reference: reference, in: project)
            guard result.reference == reference else {
                throw EvaluationError(
                    code: .invalidResult,
                    message: "Geometry evaluation provider returned a different source reference."
                )
            }
            let worldBounds = try result.localBounds.transformed(by: worldTransform)
            evaluated[occurrenceID] = EvaluatedOccurrenceSnapshot(
                occurrenceID: occurrenceID,
                definitionID: occurrence.definitionID,
                reference: reference,
                mesh: result.mesh,
                worldTransform: worldTransform,
                worldBounds: worldBounds
            )
        }

        let id = EvaluationSnapshotID(
            projectID: project.id,
            sourceRevision: sourceRevision
        )
        return EvaluatedProjectSnapshot(
            id: id,
            projectID: project.id,
            occurrences: evaluated
        )
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
