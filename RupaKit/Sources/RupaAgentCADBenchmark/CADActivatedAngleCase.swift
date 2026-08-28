import Foundation

/// The angle cases whose production route has been independently activated.
enum CADActivatedAngleCase: String, CaseIterable, Equatable, Hashable, Sendable {
    case ang001 = "ANG-001"
    case ang002 = "ANG-002"
    case ang003 = "ANG-003"
    case ang004 = "ANG-004"
    case ang005 = "ANG-005"
    case ang006 = "ANG-006"
    case ang007 = "ANG-007"
    case ang008 = "ANG-008"
    case ang009 = "ANG-009"
    case ang010 = "ANG-010"
    case ang011 = "ANG-011"
    case ang012 = "ANG-012"
    case ang013 = "ANG-013"
    case ang014 = "ANG-014"

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
