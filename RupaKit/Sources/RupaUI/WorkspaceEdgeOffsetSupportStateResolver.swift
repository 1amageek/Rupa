import RupaCore

struct WorkspaceEdgeOffsetSupportStateResolver {
    var document: DesignDocument
    var selection: SelectionModel
    var objectRegistry: ObjectTypeRegistry

    /// The support face the offset runs over: the first edge's, which every selected edge of the
    /// chain is offset over together.
    func resolution(for targets: [SelectionTarget]) -> EdgeOffsetSupportFaceResolution {
        guard let target = targets.first else {
            return .unavailable("Offset Edge needs a selected edge.")
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
