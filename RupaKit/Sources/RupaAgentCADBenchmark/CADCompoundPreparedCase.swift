import Foundation

/// Compound cases present in the private catalog and prepared for later gates.
enum CADCompoundPreparedCase: String, CaseIterable, Equatable, Hashable, Sendable {
    case compound001 = "CMP-001"
    case compound002 = "CMP-002"
    case compound003 = "CMP-003"
    case compound004 = "CMP-004"
    case compound005 = "CMP-005"
    case compound006 = "CMP-006"
    case compound007 = "CMP-007"

    var caseID: CADBenchmarkCaseID {
        CADBenchmarkCaseID(rawValue: rawValue)
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
