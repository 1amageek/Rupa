import RupaProject

/// A non-publishing action result that cannot be used as a planning snapshot.
public enum ProjectWorkspacePreviewResult: Sendable {
    case source(ProjectSourcePreviewResult)
    case interaction(ProjectInteractionPreviewResult)
}
