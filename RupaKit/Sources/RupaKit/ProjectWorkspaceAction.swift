import RupaProject

/// A mutation that can pass through the project authority boundary.
public enum ProjectWorkspaceAction: Sendable {
    case source(ProjectSourceTransaction)
    case interaction(ProjectInteractionTransaction)
}
