public enum ProjectSemanticProgramResult: Sendable {
    case preview(ProjectSemanticProgramPreview)
    case committed(ProjectSemanticProgramCommit)
    case committedFailure(ProjectSemanticProgramCommittedFailure)
}
