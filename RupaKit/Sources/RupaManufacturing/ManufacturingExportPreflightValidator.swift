import RupaCore

public struct ManufacturingExportPreflightValidator: DocumentExportPreflightValidator {
    private var options: ManufacturingPrintabilityOptions
    private var processCatalog: any ManufacturingProcessCatalog

    public init(
        options: ManufacturingPrintabilityOptions = ManufacturingPrintabilityOptions(),
        processCatalog: any ManufacturingProcessCatalog = StandardManufacturingProcessCatalog()
    ) {
        self.options = options
        self.processCatalog = processCatalog
    }

    public func validateExport(
        context: DocumentExportPreflightContext
    ) throws -> DocumentExportPreflightResult {
        guard requiresManufacturingGate(context: context) else {
            let evaluation = try ValidationPolicy(
                id: "manufacturing.export.not-required"
            ).evaluate([])
            return DocumentExportPreflightResult(
                policyEvaluation: evaluation,
                diagnostics: [],
                findings: [],
                blockingReasons: []
            )
        }
        try processCatalog.validate()
        guard let processProfile = processCatalog.profile(for: options.processID) else {
            throw ManufacturingProcessCatalogError(
                code: .unsupportedProcess,
                message: "Manufacturing process \(options.processID.rawValue) is not registered for export preflight."
            )
        }

        let meshSummary = try MeshSnapshotService().snapshot(
            document: context.document
        )
        let meshAnalysis = meshSummary.bodyCount > 0
            ? try ManufacturingMeshAnalyzer().analyze(
                evaluatedDocument: context.evaluatedDocument,
                overhangLimitDegrees: options.overhangLimitDegrees
            )
            : ManufacturingMeshAnalysisResult.empty
        let report = ManufacturingPrintabilityQuery.makeReport(
            options: options,
            processProfile: processProfile,
            meshSummary: meshSummary,
            meshAnalysis: meshAnalysis,
            inputIdentity: try ManufacturingPrintabilityQuery.makeInputIdentity(
                document: context.document,
                options: options,
                processProfile: processProfile,
                meshArtifact: meshAnalysis.meshArtifact
            )
        )
        let findings = report.validationFindings
        let policyEvaluation = try ManufacturingExportValidationPolicy()
            .policy(options: options)
            .evaluate(
                findings,
                currentInputIdentity: report.inputIdentity
            )
        let diagnostics = report.diagnostics.map { diagnostic in
            EditorDiagnostic(
                severity: diagnostic.severity,
                message: "Manufacturing export gate for \(context.format.displayName): \(diagnostic.message)"
            )
        }
        let blockingReasons = policyEvaluation.blockingRuleIDs.compactMap { ruleID in
            guard let finding = findings.first(where: { $0.id == ruleID }) else {
                return nil
            }
            return "Manufacturing rule \(ruleID) returned \(finding.outcome.rawValue): \(finding.message)"
        } + policyEvaluation.missingRuleIDs.map { ruleID in
            "Manufacturing rule \(ruleID) is required but missing."
        }
        return DocumentExportPreflightResult(
            policyEvaluation: policyEvaluation,
            diagnostics: diagnostics,
            findings: findings,
            blockingReasons: blockingReasons
        )
    }

    private func requiresManufacturingGate(context: DocumentExportPreflightContext) -> Bool {
        switch context.format {
        case .stl, .threeMF, .step:
            true
        case .swiftCAD, .iges, .obj, .dxf, .svg, .glb, .usd, .usda, .usdc, .usdz, .pdf:
            false
        }
    }
}
