import RupaCore
import Testing

@Test(.timeLimit(.minutes(1)))
func capabilityLedgerMirrorsCurrentQualityAssessmentEntries() {
    let assessment = CADInteractionQualityAssessmentService().assess()
    let ledger = CapabilityLedgerService().ledger()

    #expect(ledger.entries.map(\.id) == assessment.entries.map(\.area.rawValue).sorted())
    #expect(ledger.blockingGateCount == assessment.counts.blockingGapCount)
    #expect(!ledger.blockingEntries.isEmpty)
}

@Test(.timeLimit(.minutes(1)))
func capabilityLedgerReportsMissingRequiredCapabilityIDs() {
    let ledger = CapabilityLedger(
        entries: [
            CapabilityLedgerEntry(
                id: "implemented.capability",
                area: .agentOperability,
                title: "Implemented Capability",
                currentRating: .verified,
                gateAssessments: CADInteractionQualityGate.allCases.map { gate in
                    CADInteractionQualityGateAssessment(
                        gate: gate,
                        rating: .verified
                    )
                },
                evidence: [],
                openWork: [],
                nextRequiredResult: "No work."
            ),
        ]
    )

    #expect(ledger.acceptedEntries.map(\.id) == ["implemented.capability"])
    #expect(ledger.missingEntryIDs(requiredIDs: [
        "implemented.capability",
        "missing.capability",
    ]) == ["missing.capability"])
}

@Test(.timeLimit(.minutes(1)))
func capabilityLedgerMergesAdditionalDomainEntriesByCategory() throws {
    let domainEntry = CapabilityLedgerEntry(
        id: "domain.fixture",
        category: .domainModule,
        title: "Domain Fixture",
        currentRating: .planned,
        gateAssessments: [
            CADInteractionQualityGateAssessment(
                gate: .referenceContract,
                rating: .planned,
                openWork: ["Define the domain contract."]
            ),
        ],
        evidence: [],
        openWork: ["Implement the domain."],
        nextRequiredResult: "Domain fixture must become executable."
    )
    let ledger = CapabilityLedgerService().ledger(additionalEntries: [domainEntry])

    let entry = try #require(ledger.entry(id: "domain.fixture"))
    #expect(entry.category == .domainModule)
    #expect(entry.area == nil)
    #expect(ledger.entries(category: .domainModule).map(\.id) == ["domain.fixture"])
    #expect(ledger.blockingEntries.contains { $0.id == "domain.fixture" })
}

@Test(.timeLimit(.minutes(1)))
func capabilityLedgerKeepsBlockingGateEvidenceVisible() throws {
    let ledger = CapabilityLedgerService().ledger()
    let sketchPrecision = try #require(ledger.entry(id: "sketchPrecision"))

    #expect(sketchPrecision.title == "Sketch constraints, dimensions, numeric input, and precision construction")
    #expect(!sketchPrecision.blockingGateAssessments.isEmpty)
    #expect(!sketchPrecision.openWork.isEmpty)
    #expect(!sketchPrecision.nextRequiredResult.isEmpty)
}
