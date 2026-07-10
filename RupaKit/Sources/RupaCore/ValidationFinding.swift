import Foundation

public struct ValidationFinding: Codable, Equatable, Sendable {
    public var id: String
    public var ruleVersion: String
    public var providerID: String
    public var providerVersion: String
    public var outcome: ValidationOutcome
    public var severity: EditorDiagnostic.Severity
    public var fidelity: ValidationFidelity
    public var subjects: [ValidationSubjectReference]
    public var inputIdentity: ValidationInputIdentity
    public var diagnosticCode: String
    public var message: String
    public var recoveryAction: String?
    public var measurements: [ValidationMeasurement]
    public var regions: [ValidationRegionReference]
    public var regionCompleteness: ValidationRegionCompleteness

    public init(
        id: String,
        ruleVersion: String = "1.0.0",
        providerID: String,
        providerVersion: String,
        outcome: ValidationOutcome,
        severity: EditorDiagnostic.Severity,
        fidelity: ValidationFidelity = .exact,
        subjects: [ValidationSubjectReference],
        inputIdentity: ValidationInputIdentity,
        diagnosticCode: String? = nil,
        message: String,
        recoveryAction: String? = nil,
        measurements: [ValidationMeasurement] = [],
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
        self.subjects = subjects
        self.inputIdentity = inputIdentity
        self.diagnosticCode = diagnosticCode ?? id
        self.message = message
        self.recoveryAction = recoveryAction
        self.measurements = measurements
        self.regions = regions
        self.regionCompleteness = regionCompleteness
    }

    public var identity: ValidationFindingIdentity {
        ValidationFindingIdentity(
            ruleID: id,
            ruleVersion: ruleVersion,
            providerID: providerID,
            providerVersion: providerVersion,
            outcome: outcome,
            diagnosticCode: diagnosticCode,
            subjects: subjects
        )
    }

    public func validate() throws {
        let identityValues = [id, ruleVersion, providerID, providerVersion, diagnosticCode, message]
        guard identityValues.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ReferenceValidationError(
                code: .invalidIdentity,
                message: "Validation findings require rule, provider, diagnostic, and message identities."
            )
        }
        if let recoveryAction,
           recoveryAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ReferenceValidationError(
                code: .invalidIdentity,
                message: "Validation recovery actions must not be empty when present."
            )
        }
        guard !subjects.isEmpty,
              Set(subjects).count == subjects.count else {
            throw ReferenceValidationError(
                code: .invalidShape,
                message: "Validation findings must contain unique typed subjects."
            )
        }
        for subject in subjects {
            try subject.validate()
            guard subject.documentID == inputIdentity.documentID else {
                throw ReferenceValidationError(
                    code: .documentMismatch,
                    message: "Validation subjects and input identities must reference one document."
                )
            }
        }
        try inputIdentity.validate()
        guard Set(measurements.map(\.id)).count == measurements.count else {
            throw ReferenceValidationError(
                code: .invalidShape,
                message: "Validation measurement IDs must be unique per finding."
            )
        }
        for measurement in measurements {
            try measurement.validate()
        }
        guard Set(regions.map(\.id)).count == regions.count else {
            throw ReferenceValidationError(
                code: .invalidShape,
                message: "Validation region IDs must be unique per finding."
            )
        }
        for region in regions {
            try region.validate()
            guard region.documentID == inputIdentity.documentID else {
                throw ReferenceValidationError(
                    code: .documentMismatch,
                    message: "Validation regions and input identities must reference one document."
                )
            }
        }
        switch regionCompleteness {
        case .complete, .representative:
            guard !regions.isEmpty else {
                throw ReferenceValidationError(
                    code: .invalidShape,
                    message: "Complete or representative validation evidence requires regions."
                )
            }
        case .summaryOnly, .unavailable:
            guard regions.isEmpty else {
                throw ReferenceValidationError(
                    code: .invalidShape,
                    message: "Summary-only or unavailable validation evidence cannot contain regions."
                )
            }
        }
    }
}
