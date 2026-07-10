import RupaCore

public struct ManufacturingPrintabilityReport: Equatable, Sendable {
    public var inputIdentity: ValidationInputIdentity
    public var subjects: [ValidationSubjectReference]
    public var processProfile: ManufacturingProcessProfile
    public var outcome: ValidationOutcome
    public var bodyCount: Int
    public var triangleCount: Int
    public var bounds: MeasurementResult.Bounds?
    public var buildVolume: ManufacturingPrintabilityOptions.BuildVolume
    public var meshAnalysis: ManufacturingMeshAnalysisResult?
    public var checks: [Check]

    public init(
        inputIdentity: ValidationInputIdentity,
        subjects: [ValidationSubjectReference],
        processProfile: ManufacturingProcessProfile,
        outcome: ValidationOutcome,
        bodyCount: Int,
        triangleCount: Int,
        bounds: MeasurementResult.Bounds?,
        buildVolume: ManufacturingPrintabilityOptions.BuildVolume,
        meshAnalysis: ManufacturingMeshAnalysisResult? = nil,
        checks: [Check]
    ) {
        self.inputIdentity = inputIdentity
        self.subjects = subjects
        self.processProfile = processProfile
        self.outcome = outcome
        self.bodyCount = bodyCount
        self.triangleCount = triangleCount
        self.bounds = bounds
        self.buildVolume = buildVolume
        self.meshAnalysis = meshAnalysis
        self.checks = checks
    }

    public struct Check: Equatable, Sendable {
        public var id: String
        public var ruleVersion: String
        public var providerID: String
        public var providerVersion: String
        public var outcome: ValidationOutcome
        public var severity: EditorDiagnostic.Severity
        public var fidelity: ValidationFidelity
        public var message: String
        public var measurements: [ValidationMeasurement]
        public var references: [String]
        public var regions: [ValidationRegionReference]
        public var regionCompleteness: ValidationRegionCompleteness

        public init(
            id: String,
            ruleVersion: String = "1.0.0",
            providerID: String = "rupa.manufacturing",
            providerVersion: String = "0.1.0",
            outcome: ValidationOutcome,
            severity: EditorDiagnostic.Severity,
            fidelity: ValidationFidelity = .exact,
            message: String,
            measurements: [ValidationMeasurement] = [],
            references: [String] = [],
            regions: [ValidationRegionReference] = [],
            regionCompleteness: ValidationRegionCompleteness = .summaryOnly
        ) {
            self.id = id
            self.ruleVersion = ruleVersion
            self.providerID = providerID
            self.providerVersion = providerVersion
            self.outcome = outcome
            self.severity = severity
            self.fidelity = fidelity
            self.message = message
            self.measurements = measurements
            self.references = references
            self.regions = regions
            self.regionCompleteness = regionCompleteness
        }
    }

    public var diagnostics: [EditorDiagnostic] {
        checks.map { check in
            EditorDiagnostic(
                severity: check.severity,
                message: check.message
            )
        }
    }

    public var validationRegions: [ValidationRegionReference] {
        var seenIDs: Set<String> = []
        return checks.flatMap(\.regions).filter { region in
            seenIDs.insert(region.id).inserted
        }
    }

    public var validationFindings: [ValidationFinding] {
        checks.map {
            $0.validationFinding(
                subjects: subjects,
                inputIdentity: inputIdentity
            )
        }
    }

    public var payload: SemanticJSONValue {
        var object: [String: SemanticJSONValue] = [
            "process": .object([
                "id": .string(processProfile.id.rawValue),
                "name": .string(processProfile.name),
                "family": .string(processProfile.family.rawValue),
                "supportStrategy": .string(processProfile.supportStrategy.rawValue),
            ]),
            "outcome": .string(outcome.rawValue),
            "bodyCount": .number(Double(bodyCount)),
            "triangleCount": .number(Double(triangleCount)),
            "buildVolume": buildVolume.payload,
            "checks": .array(checks.map(\.payload)),
        ]
        if let bounds {
            object["bounds"] = bounds.payload
        }
        if let meshAnalysis {
            object["meshAnalysis"] = meshAnalysis.payload
        }
        return .object(object)
    }
}

private extension ManufacturingPrintabilityReport.Check {
    func validationFinding(
        subjects: [ValidationSubjectReference],
        inputIdentity: ValidationInputIdentity
    ) -> ValidationFinding {
        ValidationFinding(
            id: id,
            ruleVersion: ruleVersion,
            providerID: providerID,
            providerVersion: providerVersion,
            outcome: outcome,
            severity: severity,
            fidelity: fidelity,
            subjects: subjects,
            inputIdentity: inputIdentity,
            message: message,
            measurements: measurements,
            regions: regions,
            regionCompleteness: regionCompleteness
        )
    }

    var payload: SemanticJSONValue {
        .object([
            "id": .string(id),
            "ruleVersion": .string(ruleVersion),
            "providerID": .string(providerID),
            "providerVersion": .string(providerVersion),
            "outcome": .string(outcome.rawValue),
            "severity": .string(severity.rawValue),
            "fidelity": .string(fidelity.rawValue),
            "message": .string(message),
            "measurements": .array(measurements.map(\.payload)),
            "references": .array(references.map { .string($0) }),
            "regions": .array(regions.map(\.semanticJSONValue)),
            "regionCompleteness": .string(regionCompleteness.rawValue),
        ])
    }
}

private extension ValidationMeasurement {
    var payload: SemanticJSONValue {
        var object: [String: SemanticJSONValue] = [
            "id": .string(id),
            "value": .number(value.value),
            "dimension": .string(value.dimension.rawValue),
            "unit": .string(value.unit.rawValue),
        ]
        if let requirement {
            var requirementObject: [String: SemanticJSONValue] = [
                "comparison": .string(requirement.comparison.rawValue),
                "target": requirement.target.payload,
            ]
            if let upperBound = requirement.upperBound {
                requirementObject["upperBound"] = upperBound.payload
            }
            if let tolerance = requirement.tolerance {
                requirementObject["tolerance"] = tolerance.payload
            }
            object["requirement"] = .object(requirementObject)
        }
        return .object(object)
    }
}

private extension ValidationQuantity {
    var payload: SemanticJSONValue {
        .object([
            "value": .number(value),
            "dimension": .string(dimension.rawValue),
            "unit": .string(unit.rawValue),
        ])
    }
}

private extension MeasurementResult.Bounds {
    var payload: SemanticJSONValue {
        .object([
            "minX": .number(minX),
            "minY": .number(minY),
            "minZ": .number(minZ),
            "maxX": .number(maxX),
            "maxY": .number(maxY),
            "maxZ": .number(maxZ),
            "sizeX": .number(sizeX),
            "sizeY": .number(sizeY),
            "sizeZ": .number(sizeZ),
        ])
    }
}
