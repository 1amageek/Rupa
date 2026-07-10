import RupaCore

struct ManufacturingExportValidationPolicy: Sendable {
    func policy(
        options: ManufacturingPrintabilityOptions
    ) -> ValidationPolicy {
        var requirements = [
            requirement("manufacturing.processProfile", fidelities: [.exact]),
            requirement("manufacturing.bodyPresence", fidelities: [.exact]),
            requirement("manufacturing.meshTriangles", fidelities: [.exact]),
            requirement("manufacturing.buildVolume", fidelities: [.sampledApproximation]),
            requirement(
                "manufacturing.supportability",
                fidelities: [.sampledApproximation, .heuristic],
                completeness: [.complete, .representative, .summaryOnly]
            ),
            requirement("manufacturing.processAssignment", fidelities: [.exact]),
        ]
        if options.requireExportReadyMesh {
            requirements.append(
                requirement("manufacturing.meshExportReadiness", fidelities: [.exact])
            )
        }
        if options.minimumWallThicknessMeters != nil {
            requirements.append(
                requirement(
                    "manufacturing.wallThickness",
                    fidelities: [.sampledApproximation],
                    completeness: [.representative, .summaryOnly]
                )
            )
        }
        if options.minimumClearanceMeters != nil {
            requirements.append(
                requirement(
                    "manufacturing.clearance",
                    fidelities: [.sampledApproximation, .exact],
                    completeness: [.representative, .summaryOnly]
                )
            )
        }
        if options.requireMaterialAssignment {
            requirements.append(
                requirement("manufacturing.materialAssignment", fidelities: [.exact])
            )
        }
        return ValidationPolicy(
            id: "manufacturing.export.required.v1",
            requirements: requirements
        )
    }

    private func requirement(
        _ ruleID: String,
        fidelities: Set<ValidationFidelity>,
        completeness: Set<ValidationRegionCompleteness>? = nil
    ) -> ValidationRuleRequirement {
        ValidationRuleRequirement(
            ruleID: ruleID,
            acceptedFidelities: fidelities,
            acceptedRegionCompleteness: completeness,
            requiresCurrentInput: true,
            allowsOverride: false
        )
    }
}
