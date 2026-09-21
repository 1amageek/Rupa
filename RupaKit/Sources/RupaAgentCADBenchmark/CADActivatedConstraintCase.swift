import Foundation

/// Constraint cases whose production source-relation route has been reviewed.
enum CADActivatedConstraintCase: String, CaseIterable, Equatable, Hashable, Sendable {
    case constraint001 = "CON-001"
    case constraint002 = "CON-002"
    case constraint003 = "CON-003"
    case constraint004 = "CON-004"
    case constraint005 = "CON-005"
    case constraint006 = "CON-006"
    case constraint007 = "CON-007"
    case constraint008 = "CON-008"

    var caseID: CADBenchmarkCaseID {
        CADBenchmarkCaseID(rawValue: rawValue)
    }

    init(caseID: CADBenchmarkCaseID) throws {
        guard let activated = Self(rawValue: caseID.rawValue) else {
            throw CADBenchmarkError.invalidCaseID(caseID.rawValue)
        }
        self = activated
    }

    var catalogEntry: CADCatalogEntry {
        get throws {
            guard let entry = try CADInternalCatalogStore.entries().first(where: {
                $0.challenge.id == caseID
            }) else {
                throw CADBenchmarkError.missingCaseID(caseID.rawValue)
            }
            return entry
        }
    }
}
