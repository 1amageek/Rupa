import RupaDomainFoundation

/// The typed result of lowering a domain command for the project boundary.
public enum ProjectDomainCommandPlan: Sendable {
    case source(ProjectDomainCommandActionPlan)
    case interaction(ProjectDomainCommandActionPlan)
    case read(ProjectDomainCommandReadPlan)

    public var resolution: DomainCommandPlanResolution {
        switch self {
        case .source(let action), .interaction(let action):
            action.resolution
        case .read(let read):
            read.resolution
        }
    }

    public var route: DomainCommandRoute {
        switch self {
        case .source(let action), .interaction(let action):
            action.route
        case .read(let read):
            read.resolution.route
        }
    }

    public var dryRun: Bool {
        switch self {
        case .source(let action), .interaction(let action):
            action.dryRun
        case .read(let read):
            read.resolution.request.dryRun
        }
    }

    public var action: ProjectWorkspaceAction? {
        switch self {
        case .source(let action), .interaction(let action):
            action.action
        case .read:
            nil
        }
    }
}
