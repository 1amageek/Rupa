import RupaCore

/// The committed selection state change staged by one interaction publication.
public enum ProjectSelectionOperation: Sendable {
    case replace(SelectionModel)
    case clear
}
