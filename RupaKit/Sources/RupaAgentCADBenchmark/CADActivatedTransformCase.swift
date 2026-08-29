import Foundation

/// The transform cases whose production route has been independently activated.
///
/// Transform catalog entries remain prepared until their own vertical gate is
/// complete.  TRN-001 through TRN-003 are part of the measured authority in this sprint.
enum CADActivatedTransformCase: String, CaseIterable, Equatable, Hashable, Sendable {
    case trn001 = "TRN-001"
    case trn002 = "TRN-002"
    case trn003 = "TRN-003"

    var caseID: CADBenchmarkCaseID {
        CADBenchmarkCaseID(rawValue: rawValue)
    }

    init(caseID: CADBenchmarkCaseID) throws {
        guard let activated = Self(rawValue: caseID.rawValue) else {
            throw CADBenchmarkError.invalidCaseID(caseID.rawValue)
        }
        self = activated
    }

    var preparedCase: CADTransformPreparedCase {
        switch self {
        case .trn001:
            .transform001
        case .trn002:
            .transform002
        case .trn003:
            .transform003
        }
    }

    var catalogEntry: CADCatalogEntry {
        get throws {
            try preparedCase.catalogEntry
        }
    }
}
