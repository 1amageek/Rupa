public struct CapabilityLedgerService: Sendable {
    public init() {}

    public func ledger(
        additionalEntries: [CapabilityLedgerEntry] = []
    ) -> CapabilityLedger {
        let assessment = CADInteractionQualityAssessmentService().assess()
        return CapabilityLedger(
            entries: assessment.entries.map(CapabilityLedgerEntry.init(assessmentEntry:))
                + additionalEntries
        )
    }
}
