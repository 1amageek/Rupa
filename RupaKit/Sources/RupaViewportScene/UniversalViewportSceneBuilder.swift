import RupaEvaluation
import RupaProjectModel

public struct UniversalViewportSceneBuilder: Sendable {
    public init() {}

    public func build(
        from snapshot: EvaluatedProjectSnapshot,
        project: ProjectSourceModel
    ) throws -> UniversalViewportScene {
        let items = try snapshot.occurrences.keys.sorted { $0.rawValue < $1.rawValue }.map { occurrenceID in
            guard let occurrence = snapshot.occurrences[occurrenceID],
                  let definition = project.objectDefinitions[occurrence.definitionID] else {
                throw UniversalViewportSceneError(
                    code: .missingDefinition,
                    message: "Viewport snapshot occurrence \(occurrenceID.rawValue) has no object definition."
                )
            }
            return UniversalViewportSceneItem(
                occurrence,
                displayName: definition.name
            )
        }
        return UniversalViewportScene(
            snapshotID: snapshot.id,
            projectID: snapshot.projectID,
            items: items
        )
    }
}
