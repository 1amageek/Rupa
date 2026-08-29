import Foundation

/// The transform cases whose production route has been independently activated.
///
/// Transform catalog entries remain prepared until their own vertical gate is
/// complete.  TRN-001 through TRN-007 are part of the measured authority in this sprint.
enum CADActivatedTransformCase: String, CaseIterable, Equatable, Hashable, Sendable {
    case trn001 = "TRN-001"
    case trn002 = "TRN-002"
    case trn003 = "TRN-003"
    case trn004 = "TRN-004"
    case trn005 = "TRN-005"
    case trn006 = "TRN-006"
    case trn007 = "TRN-007"

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
        case .trn004:
            .transform004
        case .trn005:
            .transform005
        case .trn006:
            .transform006
        case .trn007:
            .transform007
        }
    }

    var catalogEntry: CADCatalogEntry {
        get throws {
            try preparedCase.catalogEntry
        }
    }
}
