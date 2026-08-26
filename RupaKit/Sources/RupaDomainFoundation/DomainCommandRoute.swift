/// The execution route selected by a lowered domain command plan.
///
/// `source` and `workspace` are mutation routes. `query` and `readOnly` are
/// read routes and must never be lowered into a project mutation action.
public enum DomainCommandRoute: String, Codable, Equatable, Sendable {
    case source
    case workspace
    case readOnly
    case query

    public var isReadOnly: Bool {
        switch self {
        case .readOnly, .query:
            true
        case .source, .workspace:
            false
        }
    }
}
