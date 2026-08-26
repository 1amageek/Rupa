import Testing

@Test(.timeLimit(.minutes(1)))
func productionMainViewActionManifestHasDurableRows() {
    let rows = ProductionMainViewActionManifest.rows
    let actionIDs = rows.map(\.actionID)
    let coverageKeys = rows.map { "\($0.actionID)|\($0.productionEntry)|\($0.finalOperation)" }

    #expect(Set(actionIDs).count == rows.count)
    #expect(Set(coverageKeys).count == rows.count)
    #expect(rows.allSatisfy {
        !$0.actionID.isEmpty
            && !$0.productionEntry.isEmpty
            && !$0.inputOwner.isEmpty
            && !$0.finalOperation.isEmpty
            && !$0.expectedSuccessEvidence.isEmpty
            && !$0.expectedFailureEvidence.isEmpty
            && !$0.transientSideEffect.isEmpty
            && !$0.markers.isEmpty
    })
}

@Test(.timeLimit(.minutes(1)))
func productionMainViewActionManifestCountsAreFixed() {
    let rows = ProductionMainViewActionManifest.rows
    #expect(ProductionMainViewActionManifest.sourceCommandRows.count == 76)
    #expect(ProductionMainViewActionManifest.canvasRows.count == 17)
    #expect(ProductionMainViewActionManifest.patternArrayRows.count == 3)
    #expect(ProductionMainViewActionManifest.snapshotRows.count == 9)
    #expect(ProductionMainViewActionManifest.selectionRows.count == 3)
    #expect(ProductionMainViewActionManifest.navigationRows.count == 1)
    #expect(ProductionMainViewActionManifest.workspaceRows.count == 2)
    #expect(ProductionMainViewActionManifest.transientRows.count == 5)
    #expect(ProductionMainViewActionManifest.domainRows.count == 2)
    #expect(rows.count == 118)
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
        if row.category == .sourceCommand || row.category == .patternArray {
            #expect(row.route == .sourceTransaction)
        }
    }
}

@Test(.timeLimit(.minutes(1)))
func productionMainViewGraphHasNoLegacySessionAuthority() throws {
    let matches = try ProductionMainViewActionManifest.forbiddenReferenceMatches()
    #expect(matches.isEmpty, "Forbidden production references: \(matches)")
}

@Test(.timeLimit(.minutes(1)))
func productionMainViewGraphAuditIncludesEveryNonLegacyUIAndPresentationSource() throws {
    let audited = try ProductionMainViewActionManifest.auditedProductionSourceFiles()
    #expect(audited.contains("Sources/RupaUI/MainView.swift"))
    #expect(audited.contains("Sources/RupaKit/ProjectWorkspace.swift"))
    #expect(audited.contains("Sources/RupaRendering/MeshSourcePresentationRenderer.swift"))
    #expect(audited.contains("Sources/RupaRendering/MeshSourcePresentationSectionGeometryCache.swift"))
    #expect(audited.contains("Sources/RupaRendering/ViewportSectionMeshClipper.swift"))
    #expect(audited.contains("Sources/RupaViewportScene/UniversalViewportScene.swift"))
    #expect(Set(audited).isDisjoint(with: ProductionMainViewActionManifest.legacyExcludedSourceFiles))
}

@Test(.timeLimit(.minutes(1)))
func productionMainViewActionManifestSourceCommandSetIsUniqueAndFixed() {
    let names = ProductionMainViewActionManifest.sourceCommandNames
    #expect(names.count == 76)
    #expect(Set(names).count == names.count)
    #expect(Set(ProductionMainViewActionManifest.sourceCommandRows.map(\.actionID)).count == 76)
}

@Test(.timeLimit(.minutes(1)))
func productionMainViewActionManifestMatchesDetectedEditorCommandSetInBothDirections() throws {
    let declared = ProductionMainViewActionManifest.declaredProductionEditorCommandNames
    let detected = try ProductionMainViewActionManifest.detectedProductionEditorCommandNames()

    #expect(declared.subtracting(detected).isEmpty, "Declared commands absent from production: \(declared.subtracting(detected).sorted())")
    #expect(detected.subtracting(declared).isEmpty, "Production commands absent from the manifest: \(detected.subtracting(declared).sorted())")
}

@Test(.timeLimit(.minutes(1)))
func productionMainViewActionManifestMarkersMatchProductionSource() throws {
    let missingMarkers = try ProductionMainViewActionManifest.missingMarkers()
    #expect(missingMarkers.isEmpty, "Missing production markers: \(missingMarkers)")
}
