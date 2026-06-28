public enum DesignProcessPerformanceMeasurementStatus: String, Codable, Equatable, Sendable {
    case withinBudget
    case exceedsBudget
    case missingBudget
    case unmeasured
}
