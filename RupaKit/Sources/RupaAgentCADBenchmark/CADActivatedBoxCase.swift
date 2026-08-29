import Foundation

/// The box cases whose solid production route has been independently activated.
enum CADActivatedBoxCase: String, CaseIterable, Equatable, Hashable, Sendable {
    case box001 = "BOX-001"
    case box002 = "BOX-002"
    case box003 = "BOX-003"
    case box004 = "BOX-004"
    case box005 = "BOX-005"
    case box006 = "BOX-006"
    case box007 = "BOX-007"
    case box008 = "BOX-008"
    case box009 = "BOX-009"

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
