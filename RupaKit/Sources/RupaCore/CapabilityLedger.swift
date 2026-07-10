public struct CapabilityLedger: Codable, Equatable, Sendable {
    public var entries: [CapabilityLedgerEntry]

    public init(entries: [CapabilityLedgerEntry]) {
        self.entries = entries.sorted { lhs, rhs in
            lhs.id < rhs.id
        }
    }

    public var acceptedEntries: [CapabilityLedgerEntry] {
        entries.filter(\.isAccepted)
    }

    public func entries(category: CapabilityLedgerCategory) -> [CapabilityLedgerEntry] {
        entries.filter { $0.category == category }
    }

    public var blockingEntries: [CapabilityLedgerEntry] {
        entries.filter { !$0.blockingGateAssessments.isEmpty }
    }

    public var blockingGateCount: Int {
        blockingEntries.reduce(0) { count, entry in
            count + entry.blockingGateAssessments.count
        }
    }

    public func entry(id: String) -> CapabilityLedgerEntry? {
        entries.first { $0.id == id }
    }

    public func missingEntryIDs(requiredIDs: Set<String>) -> [String] {
        let existingIDs = Set(entries.map(\.id))
        return requiredIDs
            .subtracting(existingIDs)
            .sorted()
    }
}
