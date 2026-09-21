import Foundation

/// The cylinder cases whose solid production route has been independently activated.
enum CADActivatedCylinderCase: String, CaseIterable, Equatable, Hashable, Sendable {
    case cylinder001 = "CYL-001"
    case cylinder002 = "CYL-002"
    case cylinder003 = "CYL-003"
    case cylinder004 = "CYL-004"
    case cylinder005 = "CYL-005"
    case cylinder006 = "CYL-006"
    case cylinder007 = "CYL-007"
    case cylinder008 = "CYL-008"

    var caseID: CADBenchmarkCaseID {
        CADBenchmarkCaseID(rawValue: rawValue)
    }

    init(caseID: CADBenchmarkCaseID) throws {
        guard let activated = Self(rawValue: caseID.rawValue) else {
            throw CADBenchmarkError.invalidCaseID(caseID.rawValue)
        }
        self = activated
    }

    init(caseID: String) throws {
        guard let activated = Self(rawValue: caseID) else {
            throw CADBenchmarkError.invalidCaseID(caseID)
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
