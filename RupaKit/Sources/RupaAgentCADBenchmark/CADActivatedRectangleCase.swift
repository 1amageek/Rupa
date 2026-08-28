import Foundation

/// Rectangle cases whose production route has been independently activated.
/// Catalog membership alone never makes a case executable.
enum CADActivatedRectangleCase: String, CaseIterable, Equatable, Hashable, Sendable {
    case rec001 = "REC-001"
    case rec002 = "REC-002"
    case rec003 = "REC-003"
    case rec004 = "REC-004"
    case rec005 = "REC-005"
    case rec006 = "REC-006"

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
