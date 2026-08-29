import Foundation

/// The compound cases prepared for the later serial authority activation.
enum CADCompoundActivatedCase: String, CaseIterable, Equatable, Hashable, Sendable {
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

    init(caseID: CADBenchmarkCaseID) throws {
        guard let value = Self(rawValue: caseID.rawValue) else {
            throw CADBenchmarkError.invalidCaseID(caseID.rawValue)
        }
        self = value
    }

    init(caseID: String) throws {
        guard let value = Self(rawValue: caseID) else {
            throw CADBenchmarkError.invalidCaseID(caseID)
        }
        self = value
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
