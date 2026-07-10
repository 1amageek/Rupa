import RupaCore
import RupaDomainFoundation

struct ManufacturingPrintabilityQuery: DomainCommandQuery {
    var options: ManufacturingPrintabilityOptions
    var processProfile: ManufacturingProcessProfile

    init(
        options: ManufacturingPrintabilityOptions,
        processProfile: ManufacturingProcessProfile
    ) {
        self.options = options
        self.processProfile = processProfile
    }

    func execute(
        _ request: DomainCommandRequest,
        in context: DomainQueryContext
    ) throws -> DomainQueryResult {
        let baseInputIdentity = try Self.makeInputIdentity(
            document: context.document,
            options: options,
            processProfile: processProfile,
            meshArtifact: nil
        )
        let report: ManufacturingPrintabilityReport
        do {
            let meshSummary = try MeshSnapshotService().snapshot(
                document: context.document,
                objectRegistry: context.objectRegistry,
                currentEvaluation: context.currentEvaluation,
                currentGeneration: context.generation
            )
            let meshAnalysis: ManufacturingMeshAnalysisResult
            if meshSummary.bodyCount > 0 {
                let evaluatedDocument = try DocumentEvaluationContextResolver().evaluatedDocument(
                    document: context.document,
                    objectRegistry: context.objectRegistry,
                    currentEvaluation: context.currentEvaluation,
                    currentGeneration: context.generation,
                    failurePrefix: "Document must evaluate successfully before manufacturing printability analysis"
                )
                meshAnalysis = try ManufacturingMeshAnalyzer().analyze(
                    evaluatedDocument: evaluatedDocument,
                    overhangLimitDegrees: options.overhangLimitDegrees
                )
            } else {
                meshAnalysis = ManufacturingMeshAnalysisResult.empty
            }
            report = Self.makeReport(
                options: options,
                processProfile: processProfile,
                meshSummary: meshSummary,
                meshAnalysis: meshAnalysis,
                inputIdentity: try Self.makeInputIdentity(
                    document: context.document,
                    options: options,
                    processProfile: processProfile,
                    meshArtifact: meshAnalysis.meshArtifact
                )
            )
        } catch {
            report = Self.failureReport(
                options: options,
                processProfile: processProfile,
                inputIdentity: baseInputIdentity,
                message: "Manufacturing printability requires a valid evaluated document: \(error.localizedDescription)"
            )
        }

        return DomainQueryResult(
            message: Self.message(for: report),
            diagnostics: report.diagnostics,
            validationFindings: report.validationFindings,
            validationRegions: report.validationRegions,
            payload: report.payload
        )
    }

    static func makeReport(
        options: ManufacturingPrintabilityOptions,
        processProfile: ManufacturingProcessProfile,
        meshSummary: MeshSnapshot,
        meshAnalysis: ManufacturingMeshAnalysisResult,
        inputIdentity: ValidationInputIdentity
    ) -> ManufacturingPrintabilityReport {
        var checks: [ManufacturingPrintabilityReport.Check] = []

        checks.append(processSelectionCheck(processProfile))

        if meshSummary.bodyCount == 0 {
            checks.append(
                ManufacturingPrintabilityReport.Check(
                    id: "manufacturing.bodyPresence",
                    outcome: .failed,
                    severity: .error,
                    message: "Manufacturing printability requires at least one generated body mesh."
                )
            )
        } else {
            checks.append(
                ManufacturingPrintabilityReport.Check(
                    id: "manufacturing.bodyPresence",
                    outcome: .passed,
                    severity: .info,
                    message: "Manufacturing printability found \(meshSummary.bodyCount) generated body mesh(es).",
                    measurements: [
                        countMeasurement("bodyCount", meshSummary.bodyCount),
                    ],
                    references: meshSummary.bodies.map(\.bodyID)
                )
            )
        }

        checks.append(meshTriangleCheck(meshSummary))
        checks.append(buildVolumeCheck(options: options, meshSummary: meshSummary))
        if options.requireExportReadyMesh {
            checks.append(meshExportReadinessCheck(meshAnalysis))
        }
        if let minimumWallThicknessMeters = options.minimumWallThicknessMeters {
            checks.append(wallThicknessCheck(
                minimumWallThicknessMeters: minimumWallThicknessMeters,
                meshAnalysis: meshAnalysis
            ))
        }
        if let minimumClearanceMeters = options.minimumClearanceMeters {
            checks.append(clearanceCheck(
                minimumClearanceMeters: minimumClearanceMeters,
                meshAnalysis: meshAnalysis
            ))
        }
        checks.append(supportabilityCheck(
            options: options,
            processProfile: processProfile,
            meshAnalysis: meshAnalysis
        ))
        checks.append(processAssignmentCheck(
            processProfile: processProfile,
            meshSummary: meshSummary
        ))

        if options.requireMaterialAssignment {
            checks.append(materialAssignmentCheck(meshSummary))
        }

        let outcome = aggregateOutcome(checks)
        return ManufacturingPrintabilityReport(
            inputIdentity: inputIdentity,
            subjects: [.document(inputIdentity.documentID)],
            processProfile: processProfile,
            outcome: outcome,
            bodyCount: meshSummary.bodyCount,
            triangleCount: meshSummary.triangleCount,
            bounds: meshSummary.bounds,
            buildVolume: options.buildVolume,
            meshAnalysis: meshAnalysis,
            checks: checks
        )
    }

    private static func failureReport(
        options: ManufacturingPrintabilityOptions,
        processProfile: ManufacturingProcessProfile,
        inputIdentity: ValidationInputIdentity,
        message: String
    ) -> ManufacturingPrintabilityReport {
        let check = ManufacturingPrintabilityReport.Check(
            id: "manufacturing.documentEvaluation",
            outcome: .failed,
            severity: .error,
            message: message
        )
        return ManufacturingPrintabilityReport(
            inputIdentity: inputIdentity,
            subjects: [.document(inputIdentity.documentID)],
            processProfile: processProfile,
            outcome: .failed,
            bodyCount: 0,
            triangleCount: 0,
            bounds: nil,
            buildVolume: options.buildVolume,
            meshAnalysis: nil,
            checks: [check]
        )
    }

    static func makeInputIdentity(
        document: DesignDocument,
        options: ManufacturingPrintabilityOptions,
        processProfile: ManufacturingProcessProfile,
        meshArtifact: MeshArtifactReference?
    ) throws -> ValidationInputIdentity {
        let configuration = try ArtifactConfigurationIdentity(
            schemaID: "rupa.manufacturing.printability-configuration",
            schemaVersion: "1.0.0",
            value: .object([
                "options": options.payload,
                "processProfile": .object([
                    "id": .string(processProfile.id.rawValue),
                    "name": .string(processProfile.name),
                    "summary": .string(processProfile.summary),
                    "family": .string(processProfile.family.rawValue),
                    "supportStrategy": .string(processProfile.supportStrategy.rawValue),
                ]),
            ])
        )
        let sourceFingerprint = try document.cadDocument.sourceFingerprint()
        let sourceDependencies = try SourceDependencySetIdentity(
            dependencies: [
                SourceDependencyIdentity(
                    subject: .cadDocument(document.id),
                    contentFingerprint: .init(
                        algorithm: sourceFingerprint.algorithm,
                        value: sourceFingerprint.value
                    )
                ),
            ]
        )
        return try ValidationInputIdentity(
            documentID: document.id,
            sourceDependencies: sourceDependencies,
            configuration: configuration,
            artifacts: meshArtifact.map { [$0.artifact] } ?? []
        )
    }

    private static func wallThicknessCheck(
        minimumWallThicknessMeters: Double,
        meshAnalysis: ManufacturingMeshAnalysisResult
    ) -> ManufacturingPrintabilityReport.Check {
        guard !meshAnalysis.bodyAnalyses.isEmpty else {
            return ManufacturingPrintabilityReport.Check(
                id: "manufacturing.wallThickness",
                outcome: .failed,
                severity: .error,
                message: "Manufacturing wall-thickness validation requires at least one generated body mesh.",
                measurements: [
                    lengthMeasurement(
                        "minimumRequiredWallThicknessMeters",
                        minimumWallThicknessMeters
                    ),
                ]
            )
        }

        let solidBodies = meshAnalysis.bodyAnalyses.filter { $0.bodyKind == "solid" }
        guard !solidBodies.isEmpty else {
            return ManufacturingPrintabilityReport.Check(
                id: "manufacturing.wallThickness",
                outcome: .failed,
                severity: .error,
                message: "Manufacturing wall-thickness validation requires solid body meshes.",
                measurements: [
                    lengthMeasurement(
                        "minimumRequiredWallThicknessMeters",
                        minimumWallThicknessMeters
                    ),
                ],
                references: meshAnalysis.bodyAnalyses.map { $0.bodyID.description }
            )
        }

        let failedBodies = solidBodies.filter {
            guard let thickness = $0.minimumWallThicknessMeters else {
                return true
            }
            return thickness < minimumWallThicknessMeters
        }
        guard failedBodies.isEmpty else {
            let regions = failedBodies.compactMap(\.minimumWallThicknessRegion)
            return ManufacturingPrintabilityReport.Check(
                id: "manufacturing.wallThickness",
                outcome: .failed,
                severity: .error,
                fidelity: .sampledApproximation,
                message: "Manufacturing wall-thickness validation found solid body regions below the configured minimum.",
                measurements: [
                    lengthMeasurement(
                        "minimumRequiredWallThicknessMeters",
                        minimumWallThicknessMeters
                    ),
                    lengthMeasurement(
                        "minimumMeasuredWallThicknessMeters",
                        meshAnalysis.minimumWallThicknessMeters ?? 0.0,
                        requirement: ValidationMeasurementRequirement(
                            comparison: .atLeast,
                            target: .lengthMeters(minimumWallThicknessMeters)
                        )
                    ),
                    countMeasurement("failedBodyCount", failedBodies.count),
                ],
                references: failedBodies.map { $0.bodyID.description },
                regions: regions,
                regionCompleteness: regions.isEmpty ? .unavailable : .representative
            )
        }

        return ManufacturingPrintabilityReport.Check(
            id: "manufacturing.wallThickness",
            outcome: .passed,
            severity: .info,
            fidelity: .sampledApproximation,
            message: "Manufacturing wall-thickness validation found no solid body regions below the configured minimum.",
            measurements: [
                lengthMeasurement(
                    "minimumRequiredWallThicknessMeters",
                    minimumWallThicknessMeters
                ),
                lengthMeasurement(
                    "minimumMeasuredWallThicknessMeters",
                    meshAnalysis.minimumWallThicknessMeters ?? minimumWallThicknessMeters,
                    requirement: ValidationMeasurementRequirement(
                        comparison: .atLeast,
                        target: .lengthMeters(minimumWallThicknessMeters)
                    )
                ),
            ],
            references: solidBodies.map { $0.bodyID.description }
        )
    }

    private static func clearanceCheck(
        minimumClearanceMeters: Double,
        meshAnalysis: ManufacturingMeshAnalysisResult
    ) -> ManufacturingPrintabilityReport.Check {
        guard !meshAnalysis.bodyAnalyses.isEmpty else {
            return ManufacturingPrintabilityReport.Check(
                id: "manufacturing.clearance",
                outcome: .failed,
                severity: .error,
                message: "Manufacturing clearance validation requires at least one generated body mesh.",
                measurements: [
                    lengthMeasurement("minimumRequiredClearanceMeters", minimumClearanceMeters),
                ]
            )
        }
        guard meshAnalysis.bodyAnalyses.count > 1 else {
            return ManufacturingPrintabilityReport.Check(
                id: "manufacturing.clearance",
                outcome: .passed,
                severity: .info,
                message: "Manufacturing clearance validation is not constrained for a single generated body mesh.",
                measurements: [
                    lengthMeasurement("minimumRequiredClearanceMeters", minimumClearanceMeters),
                ],
                references: meshAnalysis.bodyAnalyses.map { $0.bodyID.description }
            )
        }
        guard let measuredClearance = meshAnalysis.minimumBodyClearanceMeters else {
            return ManufacturingPrintabilityReport.Check(
                id: "manufacturing.clearance",
                outcome: .inconclusive,
                severity: .warning,
                fidelity: .sampledApproximation,
                message: "Manufacturing clearance validation could not measure body-to-body clearance.",
                measurements: [
                    lengthMeasurement("minimumRequiredClearanceMeters", minimumClearanceMeters),
                ],
                references: meshAnalysis.bodyAnalyses.map { $0.bodyID.description },
                regionCompleteness: .unavailable
            )
        }
        if measuredClearance < minimumClearanceMeters {
            let regions = [meshAnalysis.minimumBodyClearanceRegion].compactMap { $0 }
            return ManufacturingPrintabilityReport.Check(
                id: "manufacturing.clearance",
                outcome: .failed,
                severity: .error,
                fidelity: .sampledApproximation,
                message: "Manufacturing clearance validation found bodies closer than the configured minimum.",
                measurements: [
                    lengthMeasurement("minimumRequiredClearanceMeters", minimumClearanceMeters),
                    lengthMeasurement(
                        "minimumMeasuredClearanceMeters",
                        measuredClearance,
                        requirement: ValidationMeasurementRequirement(
                            comparison: .atLeast,
                            target: .lengthMeters(minimumClearanceMeters)
                        )
                    ),
                ],
                references: meshAnalysis.bodyAnalyses.map { $0.bodyID.description },
                regions: regions,
                regionCompleteness: regions.isEmpty ? .unavailable : .representative
            )
        }
        return ManufacturingPrintabilityReport.Check(
            id: "manufacturing.clearance",
            outcome: .passed,
            severity: .info,
            fidelity: .sampledApproximation,
            message: "Manufacturing clearance validation found no bodies closer than the configured minimum.",
            measurements: [
                lengthMeasurement("minimumRequiredClearanceMeters", minimumClearanceMeters),
                lengthMeasurement(
                    "minimumMeasuredClearanceMeters",
                    measuredClearance,
                    requirement: ValidationMeasurementRequirement(
                        comparison: .atLeast,
                        target: .lengthMeters(minimumClearanceMeters)
                    )
                ),
            ],
            references: meshAnalysis.bodyAnalyses.map { $0.bodyID.description }
        )
    }

    private static func meshTriangleCheck(
        _ meshSummary: MeshSnapshot
    ) -> ManufacturingPrintabilityReport.Check {
        guard meshSummary.bodyCount > 0 else {
            return ManufacturingPrintabilityReport.Check(
                id: "manufacturing.meshTriangles",
                outcome: .failed,
                severity: .error,
                message: "Manufacturing printability cannot inspect triangles because no body meshes were generated."
            )
        }
        guard meshSummary.triangleCount > 0 else {
            return ManufacturingPrintabilityReport.Check(
                id: "manufacturing.meshTriangles",
                outcome: .failed,
                severity: .error,
                message: "Manufacturing printability requires at least one generated mesh triangle."
            )
        }
        return ManufacturingPrintabilityReport.Check(
            id: "manufacturing.meshTriangles",
            outcome: .passed,
            severity: .info,
            message: "Manufacturing printability found \(meshSummary.triangleCount) generated mesh triangles.",
            measurements: [
                countMeasurement("triangleCount", meshSummary.triangleCount),
            ],
            references: meshSummary.bodies.map(\.bodyID)
        )
    }

    private static func meshExportReadinessCheck(
        _ meshAnalysis: ManufacturingMeshAnalysisResult
    ) -> ManufacturingPrintabilityReport.Check {
        guard !meshAnalysis.bodyAnalyses.isEmpty else {
            return ManufacturingPrintabilityReport.Check(
                id: "manufacturing.meshExportReadiness",
                outcome: .failed,
                severity: .error,
                message: "Manufacturing export readiness requires at least one generated body mesh."
            )
        }
        let failingBodies = meshAnalysis.bodyAnalyses.filter { !$0.isExportReady }
        if !failingBodies.isEmpty {
            return ManufacturingPrintabilityReport.Check(
                id: "manufacturing.meshExportReadiness",
                outcome: .failed,
                severity: .error,
                message: "Manufacturing export readiness requires solid, watertight, non-degenerate body meshes.",
                measurements: [
                    countMeasurement("failedBodyCount", failingBodies.count),
                    countMeasurement(
                        "boundaryEdgeCount",
                        failingBodies.reduce(0) { $0 + $1.boundaryEdgeCount }
                    ),
                    countMeasurement(
                        "nonManifoldEdgeCount",
                        failingBodies.reduce(0) { $0 + $1.nonManifoldEdgeCount }
                    ),
                    countMeasurement(
                        "degenerateTriangleCount",
                        failingBodies.reduce(0) { $0 + $1.degenerateTriangleCount }
                    ),
                    countMeasurement(
                        "invalidIndexCount",
                        failingBodies.reduce(0) { $0 + $1.invalidIndexCount }
                    ),
                ],
                references: failingBodies.map { $0.bodyID.description }
            )
        }
        return ManufacturingPrintabilityReport.Check(
            id: "manufacturing.meshExportReadiness",
            outcome: .passed,
            severity: .info,
            message: "Manufacturing export readiness found solid, watertight, non-degenerate meshes.",
            measurements: [
                countMeasurement("checkedBodyCount", meshAnalysis.bodyAnalyses.count),
            ],
            references: meshAnalysis.bodyAnalyses.map { $0.bodyID.description }
        )
    }

    private static func supportabilityCheck(
        options: ManufacturingPrintabilityOptions,
        processProfile: ManufacturingProcessProfile,
        meshAnalysis: ManufacturingMeshAnalysisResult
    ) -> ManufacturingPrintabilityReport.Check {
        guard !meshAnalysis.bodyAnalyses.isEmpty else {
            return ManufacturingPrintabilityReport.Check(
                id: "manufacturing.supportability",
                outcome: .failed,
                severity: .error,
                message: "Manufacturing supportability analysis requires at least one generated body mesh."
            )
        }
        switch processProfile.supportStrategy {
        case .surroundingPowder:
            let regions = meshAnalysis.bodyAnalyses.compactMap(\.overhangRegion)
            return ManufacturingPrintabilityReport.Check(
                id: "manufacturing.supportability",
                outcome: .unsupported,
                severity: .warning,
                fidelity: .heuristic,
                message: "Surrounding powder supports geometric overhangs, but trapped-powder volume and escape-path analysis are not implemented.",
                measurements: [
                    areaMeasurement(
                        "overhangAreaSquareMeters",
                        meshAnalysis.totalOverhangAreaSquareMeters
                    ),
                ],
                references: meshAnalysis.bodyAnalyses.map { $0.bodyID.description },
                regions: regions,
                regionCompleteness: regions.isEmpty ? .unavailable : .representative
            )
        case .overhangLimited:
            break
        }

        let failingBodies = meshAnalysis.bodyAnalyses.filter { $0.overhangAreaSquareMeters > 0.0 }
        if !failingBodies.isEmpty {
            let regions = failingBodies.compactMap(\.overhangRegion)
            return ManufacturingPrintabilityReport.Check(
                id: "manufacturing.supportability",
                outcome: .failed,
                severity: .warning,
                fidelity: .sampledApproximation,
                message: "Manufacturing supportability found downward-facing overhang area beyond the configured limit.",
                measurements: [
                    angleMeasurement("overhangLimitDegrees", options.overhangLimitDegrees),
                    areaMeasurement(
                        "overhangAreaSquareMeters",
                        meshAnalysis.totalOverhangAreaSquareMeters
                    ),
                    areaMeasurement(
                        "supportContactAreaSquareMeters",
                        meshAnalysis.totalSupportContactAreaSquareMeters
                    ),
                    countMeasurement("affectedBodyCount", failingBodies.count),
                ],
                references: failingBodies.map { $0.bodyID.description },
                regions: regions,
                regionCompleteness: regions.isEmpty ? .unavailable : .complete
            )
        }
        return ManufacturingPrintabilityReport.Check(
            id: "manufacturing.supportability",
            outcome: .passed,
            severity: .info,
            fidelity: .sampledApproximation,
            message: "Manufacturing supportability found no unsupported overhang area beyond the configured limit.",
            measurements: [
                angleMeasurement("overhangLimitDegrees", options.overhangLimitDegrees),
                areaMeasurement(
                    "supportContactAreaSquareMeters",
                    meshAnalysis.totalSupportContactAreaSquareMeters
                ),
            ],
            references: meshAnalysis.bodyAnalyses.map { $0.bodyID.description }
        )
    }

    private static func processSelectionCheck(
        _ processProfile: ManufacturingProcessProfile
    ) -> ManufacturingPrintabilityReport.Check {
        ManufacturingPrintabilityReport.Check(
            id: "manufacturing.processProfile",
            outcome: .passed,
            severity: .info,
            message: "Manufacturing printability uses the registered \(processProfile.name) process profile."
        )
    }

    private static func processAssignmentCheck(
        processProfile: ManufacturingProcessProfile,
        meshSummary: MeshSnapshot
    ) -> ManufacturingPrintabilityReport.Check {
        let manufacturingBindings = meshSummary.bodies.flatMap { body in
            body.faceMaterialBindings ?? []
        }.filter { binding in
            binding.processNamespace == ManufacturingDomain.namespace.rawValue
        }
        guard !manufacturingBindings.isEmpty else {
            return ManufacturingPrintabilityReport.Check(
                id: "manufacturing.processAssignment",
                outcome: .passed,
                severity: .info,
                message: "No face-level manufacturing process override conflicts with the selected process profile."
            )
        }
        let conflicts = manufacturingBindings.filter {
            $0.processID != processProfile.id.rawValue
        }
        guard conflicts.isEmpty else {
            return ManufacturingPrintabilityReport.Check(
                id: "manufacturing.processAssignment",
                outcome: .failed,
                severity: .error,
                message: "Face-level manufacturing process overrides conflict with the selected process profile.",
                measurements: [
                    countMeasurement("conflictingFaceCount", conflicts.count),
                ],
                references: conflicts.map(\.persistentName)
            )
        }
        return ManufacturingPrintabilityReport.Check(
            id: "manufacturing.processAssignment",
            outcome: .passed,
            severity: .info,
            message: "Face-level manufacturing process overrides match the selected process profile.",
            measurements: [
                countMeasurement("matchedFaceCount", manufacturingBindings.count),
            ],
            references: manufacturingBindings.map(\.persistentName)
        )
    }

    private static func materialAssignmentCheck(
        _ meshSummary: MeshSnapshot
    ) -> ManufacturingPrintabilityReport.Check {
        let incompleteCoverage = meshSummary.bodies.filter { body in
            body.materialCoverage == nil
                || body.materialCoverage == .missing
                || body.materialCoverage == .partialFace
        }
        let mixedFaceCoverage = meshSummary.bodies.filter {
            $0.materialCoverage == .mixedFace
        }
        if !incompleteCoverage.isEmpty {
            return ManufacturingPrintabilityReport.Check(
                id: "manufacturing.materialAssignment",
                outcome: .failed,
                severity: .error,
                message: "One or more generated body meshes have no material assignment or incomplete face material coverage.",
                measurements: [
                    countMeasurement("incompleteBodyCount", incompleteCoverage.count),
                ],
                references: incompleteCoverage.map { $0.bodyID.description }
            )
        }
        if !mixedFaceCoverage.isEmpty {
            return ManufacturingPrintabilityReport.Check(
                id: "manufacturing.materialAssignment",
                outcome: .unsupported,
                severity: .warning,
                message: "Manufacturing material coverage is complete, but the selected export path does not yet declare a mixed face-material mapping policy.",
                measurements: [
                    countMeasurement("mixedMaterialBodyCount", mixedFaceCoverage.count),
                ],
                references: mixedFaceCoverage.map { $0.bodyID.description }
            )
        }
        return ManufacturingPrintabilityReport.Check(
            id: "manufacturing.materialAssignment",
            outcome: .passed,
            severity: .info,
            message: "All generated body meshes have material assignments.",
            measurements: [
                countMeasurement("coveredBodyCount", meshSummary.bodies.count),
            ],
            references: meshSummary.bodies.map(\.bodyID)
        )
    }

    private static func buildVolumeCheck(
        options: ManufacturingPrintabilityOptions,
        meshSummary: MeshSnapshot
    ) -> ManufacturingPrintabilityReport.Check {
        guard let bounds = meshSummary.bounds else {
            return ManufacturingPrintabilityReport.Check(
                id: "manufacturing.buildVolume",
                outcome: .failed,
                severity: .error,
                message: "Manufacturing build-volume validation requires generated model bounds."
            )
        }
        let measurements: [ValidationMeasurement] = [
            lengthMeasurement(
                "modelWidthMeters",
                bounds.sizeX,
                requirement: ValidationMeasurementRequirement(
                    comparison: .atMost,
                    target: .lengthMeters(options.buildVolume.widthMeters)
                )
            ),
            lengthMeasurement(
                "modelHeightMeters",
                bounds.sizeY,
                requirement: ValidationMeasurementRequirement(
                    comparison: .atMost,
                    target: .lengthMeters(options.buildVolume.heightMeters)
                )
            ),
            lengthMeasurement(
                "modelDepthMeters",
                bounds.sizeZ,
                requirement: ValidationMeasurementRequirement(
                    comparison: .atMost,
                    target: .lengthMeters(options.buildVolume.depthMeters)
                )
            ),
            lengthMeasurement("buildWidthMeters", options.buildVolume.widthMeters),
            lengthMeasurement("buildHeightMeters", options.buildVolume.heightMeters),
            lengthMeasurement("buildDepthMeters", options.buildVolume.depthMeters),
        ]
        if options.buildVolume.contains(bounds) {
            return ManufacturingPrintabilityReport.Check(
                id: "manufacturing.buildVolume",
                outcome: .passed,
                severity: .info,
                fidelity: .sampledApproximation,
                message: "Model bounds fit inside the configured manufacturing build volume.",
                measurements: measurements
            )
        }
        return ManufacturingPrintabilityReport.Check(
            id: "manufacturing.buildVolume",
            outcome: .failed,
            severity: .error,
            fidelity: .sampledApproximation,
            message: "Model bounds exceed the configured manufacturing build volume.",
            measurements: measurements
        )
    }

    private static func countMeasurement(
        _ id: String,
        _ value: Int
    ) -> ValidationMeasurement {
        ValidationMeasurement(id: id, value: .count(value))
    }

    private static func lengthMeasurement(
        _ id: String,
        _ value: Double,
        requirement: ValidationMeasurementRequirement? = nil
    ) -> ValidationMeasurement {
        ValidationMeasurement(
            id: id,
            value: .lengthMeters(value),
            requirement: requirement
        )
    }

    private static func areaMeasurement(
        _ id: String,
        _ value: Double
    ) -> ValidationMeasurement {
        ValidationMeasurement(id: id, value: .areaSquareMeters(value))
    }

    private static func angleMeasurement(
        _ id: String,
        _ value: Double
    ) -> ValidationMeasurement {
        ValidationMeasurement(id: id, value: .angleDegrees(value))
    }

    private static func aggregateOutcome(
        _ checks: [ManufacturingPrintabilityReport.Check]
    ) -> ValidationOutcome {
        if checks.contains(where: { $0.outcome == .failed }) {
            return .failed
        }
        if checks.contains(where: { $0.outcome == .unsupported }) {
            return .unsupported
        }
        if checks.contains(where: { $0.outcome == .inconclusive }) {
            return .inconclusive
        }
        return .passed
    }

    private static func message(
        for report: ManufacturingPrintabilityReport
    ) -> String {
        switch report.outcome {
        case .passed:
            return "Manufacturing printability validation passed."
        case .failed:
            return "Manufacturing printability validation failed."
        case .inconclusive:
            return "Manufacturing printability validation was inconclusive."
        case .unsupported:
            return "Manufacturing printability validation is unsupported for one or more required checks."
        }
    }
}
