import Testing

@Test(.timeLimit(.minutes(1)))
func productionMainViewActionManifestHasDurableRows() {
    let rows = ProductionMainViewActionManifest.rows
    let actionIDs = rows.map(\.actionID)
    let fixtureIDs = rows.map(\.plannerFixtureID)
    let coverageKeys = rows.map { "\($0.actionID)|\($0.productionEntry)|\($0.finalOperation)" }

    #expect(Set(actionIDs).count == rows.count)
    #expect(Set(fixtureIDs).count == rows.count)
    #expect(Set(coverageKeys).count == rows.count)
    #expect(rows.allSatisfy {
        !$0.actionID.isEmpty
            && !$0.productionEntry.isEmpty
            && !$0.inputOwner.isEmpty
            && !$0.finalOperation.isEmpty
            && !$0.plannerFixtureID.isEmpty
            && !$0.expectedSuccessEvidence.isEmpty
            && !$0.expectedFailureEvidence.isEmpty
            && !$0.transientSideEffect.isEmpty
            && !$0.markers.isEmpty
            && !$0.coveredSessionIdentifiers.isEmpty
    })
}

@Test(.timeLimit(.minutes(1)))
func productionMainViewActionManifestCountsAreFixed() {
    let rows = ProductionMainViewActionManifest.rows
    #expect(ProductionMainViewActionManifest.sourceCommandRows.count == 75)
    #expect(ProductionMainViewActionManifest.sourceHelperRows.count == 1)
    #expect(ProductionMainViewActionManifest.canvasRows.count == 12)
    #expect(ProductionMainViewActionManifest.patternArrayRows.count == 3)
    #expect(ProductionMainViewActionManifest.snapshotRows.count == 17)
    #expect(ProductionMainViewActionManifest.selectionRows.count == 5)
    #expect(ProductionMainViewActionManifest.navigationRows.count == 1)
    #expect(ProductionMainViewActionManifest.workspaceRows.count == 8)
    #expect(ProductionMainViewActionManifest.transientRows.count == 21)
    #expect(ProductionMainViewActionManifest.domainRows.count == 5)
    #expect(rows.count == 148)
}

@Test(.timeLimit(.minutes(1)))
func productionMainViewActionManifestUsesOneFinalRoutePerRow() {
    let validRoutes = Set(ProductionMainViewActionManifest.Route.allCases)
    let validCategories = Set(ProductionMainViewActionManifest.Category.allCases)
    for row in ProductionMainViewActionManifest.rows {
        #expect(validRoutes.contains(row.route))
        #expect(validCategories.contains(row.category))
        if row.category == .snapshot || row.category == .canvas && row.route == .snapshotRead {
            #expect(row.route == .snapshotRead)
        }
        if row.category == .sourceCommand || row.category == .sourceHelper || row.category == .patternArray {
            #expect(row.route == .sourceTransaction)
        }
    }
}

@Test(.timeLimit(.minutes(1)))
func productionMainViewActionManifestCoversEveryReachableSessionIdentifier() throws {
    let observed = try ProductionMainViewActionManifest.observedSessionIdentifiers()
    let manifest = Set(
        ProductionMainViewActionManifest.rows
            .flatMap(\.coveredSessionIdentifiers)
    )

    #expect(observed.count == ProductionMainViewActionManifest.expectedSessionIdentifierCount)
    #expect(manifest == observed)
}

@Test(.timeLimit(.minutes(1)))
func productionMainViewActionManifestCoversEveryDirectCommandCase() throws {
    let observed = try ProductionMainViewActionManifest.observedDirectCommandNames()
    #expect(observed == ProductionMainViewActionManifest.directCommandNames)

    let directRows = ProductionMainViewActionManifest.sourceCommandRows.filter {
        $0.coveredSessionIdentifiers.contains("execute")
            || $0.coveredSessionIdentifiers.contains("perform")
    }
    let directOperations = Set(
        directRows.compactMap { row -> String? in
            guard row.finalOperation.hasPrefix("EditorCommand.") else {
                return nil
            }
            return String(row.finalOperation.dropFirst("EditorCommand.".count))
        }
    )
    #expect(directOperations == observed)
}

@Test(.timeLimit(.minutes(1)))
func productionMainViewActionManifestMarkersMatchProductionSource() throws {
    let missingMarkers = try ProductionMainViewActionManifest.missingMarkers()
    #expect(missingMarkers.isEmpty, "Missing production markers: \(missingMarkers)")
}

@Test(.timeLimit(.minutes(1)))
func productionMainViewActionManifestAllowsEffectSpecificRouteRows() {
    let rows = ProductionMainViewActionManifest.rows
    let canvasActivationRoutes = Set(
        rows
            .filter { $0.coveredSessionIdentifiers.contains("activateSelectedToolFromCanvas") }
            .map(\.route)
    )
    #expect(canvasActivationRoutes.contains(.mainActorTransient))
    #expect(canvasActivationRoutes.contains(.sourceTransaction))
    #expect(canvasActivationRoutes.contains(.interactionTransaction))
    #expect(canvasActivationRoutes.contains(.snapshotRead))
}
