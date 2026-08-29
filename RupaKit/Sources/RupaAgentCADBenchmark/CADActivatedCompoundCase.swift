import Foundation

/// Compound cases that have completed their individual activation gate.
enum CADActivatedCompoundCase: String, CaseIterable, Equatable, Hashable, Sendable {
    case compound001 = "CMP-001"

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

    var preparedCase: CADCompoundPreparedCase {
        get throws {
            guard let prepared = CADCompoundPreparedCase(rawValue: rawValue) else {
                throw CADBenchmarkError.invalidCaseID(rawValue)
            }
            return prepared
        }
    }

    var catalogEntry: CADCatalogEntry {
        get throws {
            try preparedCase.catalogEntry
        }
    }
}
