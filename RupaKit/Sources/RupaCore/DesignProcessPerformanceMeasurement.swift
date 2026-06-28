public struct DesignProcessPerformanceMeasurement: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var metric: String
    public var unit: String
    public var measuredValue: Double?
    public var budgetValue: Double?
    public var status: DesignProcessPerformanceMeasurementStatus
    public var source: String
    public var notes: [String]

    public init(
        id: String,
        title: String,
        metric: String,
        unit: String,
        measuredValue: Double? = nil,
        budgetValue: Double? = nil,
        status: DesignProcessPerformanceMeasurementStatus,
        source: String,
        notes: [String] = []
    ) {
        self.id = id
        self.title = title
        self.metric = metric
        self.unit = unit
        self.measuredValue = measuredValue
        self.budgetValue = budgetValue
        self.status = status
        self.source = source
        self.notes = notes
    }
}
