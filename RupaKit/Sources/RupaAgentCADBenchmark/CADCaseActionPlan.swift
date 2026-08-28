import RupaAutomation

/// The bounded production mutation selected by one candidate action.
enum CADCaseActionPlan {
    case command(AutomationCommand)
    case batch([AutomationCommand])

    var commandCount: Int {
        switch self {
        case .command:
            1
        case .batch(let commands):
            commands.count
        }
    }
}
