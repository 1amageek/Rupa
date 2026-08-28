import Foundation

/// The circle cases whose production route has been independently activated.
enum CADActivatedCircleCase: String, CaseIterable, Equatable, Hashable, Sendable {
    case cir001 = "CIR-001"
    case cir002 = "CIR-002"
    case cir003 = "CIR-003"
    case cir004 = "CIR-004"
    case cir005 = "CIR-005"
    case cir006 = "CIR-006"
    case cir007 = "CIR-007"
    case cir008 = "CIR-008"
    case cir009 = "CIR-009"
    case cir010 = "CIR-010"

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
