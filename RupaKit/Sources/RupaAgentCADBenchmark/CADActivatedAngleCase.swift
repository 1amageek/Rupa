import Foundation

/// The angle cases whose production route has been independently activated.
enum CADActivatedAngleCase: String, CaseIterable, Equatable, Hashable, Sendable {
    case ang001 = "ANG-001"
    case ang002 = "ANG-002"
    case ang003 = "ANG-003"
    case ang004 = "ANG-004"
    case ang005 = "ANG-005"

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
