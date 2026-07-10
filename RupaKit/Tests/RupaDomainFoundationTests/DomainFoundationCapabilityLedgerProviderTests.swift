import RupaCore
import RupaDomainFoundation
import Testing

@Test(.timeLimit(.minutes(1)))
func domainFoundationCapabilityLedgerEntryTracksIncompleteFoundationGates() throws {
    let ledger = CapabilityLedgerService().ledger(
        additionalEntries: DomainFoundationCapabilityLedgerProvider.entries()
    )
    let entry = try #require(ledger.entry(id: "domainFoundation.contracts"))

    #expect(entry.category == .domainFoundation)
    #expect(entry.currentRating == .partial)
    #expect(entry.blockingGateAssessments.map(\.gate).contains(.inspectorAffordance))
    #expect(entry.blockingGateAssessments.map(\.gate).contains(.performanceBudget))
    #expect(entry.evidence.contains { !$0.sourceFiles.isEmpty && !$0.tests.isEmpty })
    #expect(!entry.nextRequiredResult.isEmpty)
}
