import RupaCore

struct WorkspaceEdgeOffsetSupportStateResolver {
    var document: DesignDocument
    var selection: SelectionModel
    var objectRegistry: ObjectTypeRegistry

    func resolution(for targets: [SelectionTarget]) -> EdgeOffsetSupportFaceResolution {
        guard targets.count == 1,
              let target = targets.first else {
            return .unavailable("Offset Edge currently supports one selected edge.")
        }
        do {
            return try EdgeOffsetSupportFaceResolver().resolve(
                edgeTarget: target,
                selection: selection,
                document: document,
                objectRegistry: objectRegistry
            )
        } catch let error as EditorError {
            return .unavailable(error.message)
        } catch {
            return .unavailable(String(describing: error))
        }
    }

    func supportTitle(for resolution: EdgeOffsetSupportFaceResolution) -> String {
        switch (resolution.status, resolution.source) {
        case (.supported, .selectedFace):
            return "Selected Face"
        case (.supported, .inferredCapFace):
            return "Cap Face"
        case (.ambiguous, _):
            return "Ambiguous"
        case (.unavailable, _):
            return "Missing"
        case (.notApplicable, _):
            return "Unsupported"
        case (.supported, nil):
            return "Ready"
        }
    }
}
