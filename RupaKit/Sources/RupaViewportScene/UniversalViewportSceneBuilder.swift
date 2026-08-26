import RupaEvaluation
import RupaProjectModel

public struct UniversalViewportSceneBuilder: Sendable {
    public init() {}

    public func build(
        from snapshot: EvaluatedProjectSnapshot,
        project: ProjectSourceModel
    ) throws -> UniversalViewportScene {
        guard snapshot.projectID == project.id,
              snapshot.id.projectID == project.id else {
            throw UniversalViewportSceneError(
                code: .projectMismatch,
                message: "Viewport snapshot and source model belong to different projects."
            )
        }
        guard snapshot.id.purpose == .presentation else {
            throw UniversalViewportSceneError(
                code: .purposeMismatch,
                message: "A universal viewport scene requires a presentation-purpose evaluation."
            )
        }
        let items = try snapshot.occurrences.keys.sorted { $0.rawValue < $1.rawValue }.map { occurrenceID in
            guard let occurrence = snapshot.occurrences[occurrenceID] else {
                throw UniversalViewportSceneError(
                    code: .occurrenceMismatch,
                    message: "Viewport snapshot is missing occurrence \(occurrenceID.rawValue)."
                )
            }
            guard occurrence.occurrenceID == occurrenceID else {
                throw UniversalViewportSceneError(
                    code: .occurrenceMismatch,
                    message: "Viewport snapshot occurrence identity does not match its dictionary key."
                )
            }
            guard let sourceOccurrence = project.occurrences[occurrenceID],
                  sourceOccurrence.id == occurrenceID else {
                throw UniversalViewportSceneError(
                    code: .occurrenceMismatch,
                    message: "Viewport snapshot occurrence \(occurrenceID.rawValue) is missing from the source model."
                )
            }
            guard sourceOccurrence.definitionID == occurrence.definitionID else {
                throw UniversalViewportSceneError(
                    code: .occurrenceMismatch,
                    message: "Viewport occurrence \(occurrenceID.rawValue) has a different source and evaluated definition."
                )
            }
            guard let definition = project.objectDefinitions[occurrence.definitionID] else {
                throw UniversalViewportSceneError(
                    code: .missingDefinition,
                    message: "Viewport snapshot occurrence \(occurrenceID.rawValue) has no object definition."
                )
            }
            guard let presentation = definition.representations.representation(for: .presentation),
                  presentation.id == occurrence.representationID,
                  presentation.source == occurrence.reference else {
                throw UniversalViewportSceneError(
                    code: .sourceMismatch,
                    message: "Viewport occurrence does not match its selected presentation authority."
                )
            }
            let item = UniversalViewportSceneItem(
                occurrence,
                displayName: definition.name
            )
            try item.validate()
            return item
        }
        return UniversalViewportScene(
            snapshotID: snapshot.id,
            projectID: snapshot.projectID,
            items: items,
            copyTelemetry: snapshot.copyTelemetry
        )
    }
}
