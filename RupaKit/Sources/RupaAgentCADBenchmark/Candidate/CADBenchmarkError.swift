import Foundation

/// Typed failures for benchmark catalog and candidate-contract validation.
public enum CADBenchmarkError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidCaseID(String)
    case invalidDimension(caseID: String, field: String, value: Double)
    case invalidDirection(caseID: String, field: String)
    case invalidInput(caseID: String, reason: String)
    case invalidCapability(caseID: String, capabilityID: String)
    case duplicateCaseID(String)
    case missingCaseID(String)
    case invalidCategoryCount(category: String, expected: Int, actual: Int)
    case duplicateRole(caseID: String, role: String)
    case invalidBinding(caseID: String, role: String, reason: String)
    case unsupportedCapabilityMismatch(caseID: String, capabilityID: String, reason: String)
    case invalidTolerance(String)
    case catalogDrift(expected: String, actual: String)
    case invalidBudget(String)
    case malformedManifest(String)

    public var description: String {
        switch self {
        case let .invalidCaseID(value):
            "Invalid benchmark case ID: \(value)."
        case let .invalidDimension(caseID, field, value):
            "Invalid dimension \(field)=\(value) for \(caseID)."
        case let .invalidDirection(caseID, field):
            "Invalid direction \(field) for \(caseID)."
        case let .invalidInput(caseID, reason):
            "Invalid input for \(caseID): \(reason)"
        case let .invalidCapability(caseID, capabilityID):
            "Invalid capability \(capabilityID) for \(caseID)."
        case let .duplicateCaseID(value):
            "Duplicate benchmark case ID: \(value)."
        case let .missingCaseID(value):
            "Missing benchmark case ID: \(value)."
        case let .invalidCategoryCount(category, expected, actual):
            "Invalid \(category) count: expected \(expected), got \(actual)."
        case let .duplicateRole(caseID, role):
            "Duplicate output role \(role) for \(caseID)."
        case let .invalidBinding(caseID, role, reason):
            "Invalid output binding \(role) for \(caseID): \(reason)"
        case let .unsupportedCapabilityMismatch(caseID, capabilityID, reason):
            "Unsupported capability \(capabilityID) is invalid for \(caseID): \(reason)"
        case let .invalidTolerance(reason):
            "Invalid benchmark tolerance: \(reason)"
        case let .catalogDrift(expected, actual):
            "Catalog digest drift: expected \(expected), got \(actual)."
        case let .invalidBudget(reason):
            "Invalid candidate budget: \(reason)"
        case let .malformedManifest(reason):
            "Malformed benchmark manifest: \(reason)"
        }
    }
}
