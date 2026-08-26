import RupaAutomation
import RupaCore

/// One session-independent source mutation payload.
public enum ProjectSourceMutation: Sendable {
    case commands([ContextResolvedEditorCommand])
    case automation(PreparedAutomationBatch)
}
